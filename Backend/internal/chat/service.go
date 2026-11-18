package chat

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

var (
	ErrInvalidInput = errors.New("invalid chat input")
	ErrNoCharacter = errors.New("no active character")
	ErrRateLimited = errors.New("chat rate limit exceeded")
	ErrUnsupportedChannel = errors.New("chat channel is not available in this phase")
)

type Service struct { db *sql.DB }

type Message struct {
	ID string `json:"id"`
	ClientMessageID string `json:"client_message_id"`
	Channel string `json:"channel"`
	WorldID string `json:"world_id,omitempty"`
	SenderCharacterID string `json:"sender_character_id"`
	SenderName string `json:"sender_name"`
	SenderRace string `json:"sender_race,omitempty"`
	SenderLevel int `json:"sender_level"`
	Content string `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

type SendRequest struct {
	ClientMessageID string `json:"client_message_id"`
	Channel string `json:"channel"`
	Content string `json:"content"`
}

func NewService(db *sql.DB) *Service { return &Service{db: db} }

func (s *Service) Send(ctx context.Context, accountID string, req SendRequest) (Message, error) {
	req.Channel = strings.TrimSpace(req.Channel)
	req.Content = strings.TrimSpace(req.Content)
	if accountID == "" || req.ClientMessageID == "" || len(req.ClientMessageID) > 36 || !isUUID(req.ClientMessageID) || utf8.RuneCountInString(req.Content) == 0 || utf8.RuneCountInString(req.Content) > 200 {
		return Message{}, ErrInvalidInput
	}
	for _, r := range req.Content {
		if unicode.IsControl(r) && r != '\n' && r != '\t' { return Message{}, ErrInvalidInput }
	}
	if req.Channel != "world" && req.Channel != "cross_world" {
		return Message{}, ErrUnsupportedChannel
	}
	var characterID, characterName, raceID, worldID string
	var level int
	err := s.db.QueryRowContext(ctx, `SELECT c.id::text,c.name,COALESCE(c.race_id,''),c.world_id,c.level
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive'`, accountID).Scan(&characterID,&characterName,&raceID,&worldID,&level)
	if errors.Is(err,sql.ErrNoRows) { return Message{},ErrNoCharacter }
	if err != nil { return Message{},fmt.Errorf("resolve chat character: %w",err) }

	var worldScope any
	if req.Channel == "world" { worldScope = worldID }
	var allowed bool
	if req.Channel == "world" {
		err=s.db.QueryRowContext(ctx,`SELECT NOT EXISTS(SELECT 1 FROM chat_blocks b WHERE b.blocker_character_id<>$1::uuid AND b.blocked_character_id=$1::uuid)`,characterID).Scan(&allowed)
		if err!=nil{return Message{},fmt.Errorf("check chat block state: %w",err)}
		if !allowed{return Message{},ErrInvalidInput}
	}
	window:=3*time.Second
	if req.Channel=="cross_world" { window=5*time.Second }
	var recent int
	if err:=s.db.QueryRowContext(ctx,`SELECT count(*) FROM chat_messages WHERE sender_character_id=$1::uuid AND created_at>now()-$2::interval AND channel_type=$3`,characterID,window.String(),req.Channel).Scan(&recent);err!=nil{return Message{},fmt.Errorf("check chat rate limit: %w",err)}
	if recent>0 { return Message{},ErrRateLimited }

	_,err=s.db.ExecContext(ctx,`DELETE FROM chat_messages WHERE created_at<now()-interval '30 days'`)
	if err!=nil{return Message{},fmt.Errorf("prune expired chat history: %w",err)}
	var worldValue any
	if req.Channel=="world" { worldValue=worldScope }
	_,err=s.db.ExecContext(ctx,`INSERT INTO chat_messages(channel_type,world_id,sender_character_id,client_message_id,content)
		VALUES($1,$2,$3::uuid,$4::uuid,$5) ON CONFLICT(sender_character_id,client_message_id) DO NOTHING`,
		req.Channel,worldValue,characterID,req.ClientMessageID,req.Content)
	if err!=nil{return Message{},fmt.Errorf("store chat message: %w",err)}
	return s.getByClientID(ctx,characterID,req.ClientMessageID)
}

func (s *Service) List(ctx context.Context, accountID, channel, before string, limit int) ([]Message,error) {
	if accountID=="" { return nil,ErrInvalidInput }
	if channel!="world" && channel!="cross_world" { return nil,ErrUnsupportedChannel }
	if limit<1 || limit>100 { limit=50 }
	var characterID,worldID string
	err:=s.db.QueryRowContext(ctx,`SELECT c.id::text,c.world_id FROM souls soul JOIN characters c ON c.id=soul.current_character_id WHERE soul.account_id=$1 AND c.status='alive'`,accountID).Scan(&characterID,&worldID)
	if errors.Is(err,sql.ErrNoRows){return nil,ErrNoCharacter}
	if err!=nil{return nil,fmt.Errorf("resolve chat history character: %w",err)}
	_,err=s.db.ExecContext(ctx,`DELETE FROM chat_messages WHERE created_at<now()-interval '30 days'`)
	if err!=nil{return nil,fmt.Errorf("prune expired chat history: %w",err)}
	var rows *sql.Rows
	if channel=="world" {
		if before!="" {
			rows,err=s.db.QueryContext(ctx,`SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
				FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
				WHERE m.channel_type='world' AND m.world_id=$1 AND m.created_at<$2 ORDER BY m.created_at DESC,m.id DESC LIMIT $3`,worldID,before,limit)
		}else{
			rows,err=s.db.QueryContext(ctx,`SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
				FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
				WHERE m.channel_type='world' AND m.world_id=$1 ORDER BY m.created_at DESC,m.id DESC LIMIT $2`,worldID,limit)
		}
	}else{
		if before!="" {
			rows,err=s.db.QueryContext(ctx,`SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
				FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
				WHERE m.channel_type='cross_world' AND m.created_at<$1 ORDER BY m.created_at DESC,m.id DESC LIMIT $2`,before,limit)
		}else{
			rows,err=s.db.QueryContext(ctx,`SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
				FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
				WHERE m.channel_type='cross_world' ORDER BY m.created_at DESC,m.id DESC LIMIT $1`,limit)
		}
	}
	if err!=nil{return nil,fmt.Errorf("query chat history: %w",err)}
	defer rows.Close()
	items:=make([]Message,0)
	for rows.Next(){
		var m Message
		if err:=rows.Scan(&m.ID,&m.ClientMessageID,&m.Channel,&m.WorldID,&m.SenderCharacterID,&m.SenderName,&m.SenderRace,&m.SenderLevel,&m.Content,&m.CreatedAt);err!=nil{return nil,fmt.Errorf("scan chat message: %w",err)}
		items=append(items,m)
	}
	if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate chat history: %w",err)}
	for i,j:=0,len(items)-1;i<j;i,j=i+1,j-1{items[i],items[j]=items[j],items[i]}
	return items,nil
}

func (s *Service) getByClientID(ctx context.Context, characterID, clientID string)(Message,error){
	var m Message
	err:=s.db.QueryRowContext(ctx,`SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
		FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$2::uuid`,characterID,clientID).
		Scan(&m.ID,&m.ClientMessageID,&m.Channel,&m.WorldID,&m.SenderCharacterID,&m.SenderName,&m.SenderRace,&m.SenderLevel,&m.Content,&m.CreatedAt)
	if err!=nil{return Message{},fmt.Errorf("load stored chat message: %w",err)}
	return m,nil
}

func isUUID(value string) bool {
	if len(value)!=36{return false}
	for i,r:=range value{
		if i==8||i==13||i==18||i==23{if r!='-'{return false};continue}
		if !((r>='0'&&r<='9')||(r>='a'&&r<='f')||(r>='A'&&r<='F')){return false}
	}
	return true
}
