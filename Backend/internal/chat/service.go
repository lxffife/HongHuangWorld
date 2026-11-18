package chat

import (
	"context"
	"database/sql"
	"encoding/json"
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
	ErrIdempotencyConflict = errors.New("chat client message id was reused with different content")
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
	if accountID == "" || !isUUID(req.ClientMessageID) || utf8.RuneCountInString(req.Content) == 0 || utf8.RuneCountInString(req.Content) > 200 {
		return Message{}, ErrInvalidInput
	}
	for _, r := range req.Content {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return Message{}, ErrInvalidInput
		}
	}
	if req.Channel != "world" && req.Channel != "cross_world" {
		return Message{}, ErrUnsupportedChannel
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Message{}, fmt.Errorf("begin chat send: %w", err)
	}
	defer tx.Rollback()

	// Serialize sends by active character so rate limiting and idempotency
	// remain correct when the same account submits concurrent requests.
	var characterID, characterName, raceID, worldID string
	var level int
	err = tx.QueryRowContext(ctx, `SELECT c.id::text,c.name,COALESCE(c.race_id,''),c.world_id,c.level
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive'
		FOR UPDATE OF c`, accountID).Scan(&characterID, &characterName, &raceID, &worldID, &level)
	if errors.Is(err, sql.ErrNoRows) {
		return Message{}, ErrNoCharacter
	}
	if err != nil {
		return Message{}, fmt.Errorf("resolve and lock chat character: %w", err)
	}

	existing, existingErr := getChatMessageByClientID(ctx, tx, characterID, req.ClientMessageID)
	if existingErr == nil {
		if existing.Channel != req.Channel || existing.Content != req.Content {
			return Message{}, ErrIdempotencyConflict
		}
		if err := tx.Commit(); err != nil {
			return Message{}, fmt.Errorf("commit idempotent chat retry: %w", err)
		}
		return existing, nil
	}
	if !errors.Is(existingErr, sql.ErrNoRows) {
		return Message{}, existingErr
	}

	window := 3 * time.Second
	if req.Channel == "cross_world" {
		window = 5 * time.Second
	}
	var recent int
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM chat_messages
		WHERE sender_character_id=$1::uuid AND created_at>now()-$2::interval AND channel_type=$3`,
		characterID, window.String(), req.Channel).Scan(&recent); err != nil {
		return Message{}, fmt.Errorf("check chat rate limit: %w", err)
	}
	if recent > 0 {
		return Message{}, ErrRateLimited
	}

	var worldValue any
	if req.Channel == "world" {
		worldValue = worldID
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO chat_messages(channel_type,world_id,sender_character_id,client_message_id,content)
		VALUES($1,$2,$3::uuid,$4::uuid,$5)`,
		req.Channel, worldValue, characterID, req.ClientMessageID, req.Content)
	if err != nil {
		return Message{}, fmt.Errorf("store chat message: %w", err)
	}
	item, err := getChatMessageByClientID(ctx, tx, characterID, req.ClientMessageID)
	if err != nil {
		return Message{}, err
	}
	if item.Channel != req.Channel || item.Content != req.Content {
		return Message{}, ErrIdempotencyConflict
	}
	if err := insertChatEventOutbox(ctx, tx, item); err != nil {
		return Message{}, err
	}
	if err := tx.Commit(); err != nil {
		return Message{}, fmt.Errorf("commit chat message and outbox: %w", err)
	}
	return item, nil
}

func (s *Service) List(ctx context.Context, accountID, channel, before string, limit int) ([]Message,error) {
	if accountID=="" { return nil,ErrInvalidInput }
	if channel!="world" && channel!="cross_world" { return nil,ErrUnsupportedChannel }
	if limit<1 || limit>100 { limit=50 }
	var characterID,worldID string
	err:=s.db.QueryRowContext(ctx,`SELECT c.id::text,c.world_id FROM souls soul JOIN characters c ON c.id=soul.current_character_id WHERE soul.account_id=$1 AND c.status='alive'`,accountID).Scan(&characterID,&worldID)
	if errors.Is(err,sql.ErrNoRows){return nil,ErrNoCharacter}
	if err!=nil{return nil,fmt.Errorf("resolve chat history character: %w",err)}
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

type chatRowQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func getChatMessageByClientID(ctx context.Context, queryer chatRowQueryer, characterID, clientID string) (Message, error) {
	var m Message
	err := queryer.QueryRowContext(ctx, `SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
		FROM chat_messages m JOIN characters c ON c.id=m.sender_character_id
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$2::uuid`, characterID, clientID).
		Scan(&m.ID,&m.ClientMessageID,&m.Channel,&m.WorldID,&m.SenderCharacterID,&m.SenderName,&m.SenderRace,&m.SenderLevel,&m.Content,&m.CreatedAt)
	if err != nil {
		return Message{}, fmt.Errorf("load stored chat message: %w", err)
	}
	return m, nil
}

func (s *Service) getByClientID(ctx context.Context, characterID, clientID string) (Message, error) {
	return getChatMessageByClientID(ctx, s.db, characterID, clientID)
}

func insertChatEventOutbox(ctx context.Context, tx *sql.Tx, message Message) error {
	payload, err := json.Marshal(message)
	if err != nil {
		return fmt.Errorf("encode chat outbox payload: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO chat_event_outbox(message_id,payload) VALUES($1::uuid,$2::jsonb)`, message.ID, string(payload)); err != nil {
		return fmt.Errorf("insert chat event outbox: %w", err)
	}
	return nil
}

func isUUID(value string) bool {
	if len(value)!=36{return false}
	for i,r:=range value{
		if i==8||i==13||i==18||i==23{if r!='-'{return false};continue}
		if !((r>='0'&&r<='9')||(r>='a'&&r<='f')||(r>='A'&&r<='F')){return false}
	}
	return true
}

// ServerBatch is a durable page of public messages visible to a WorldServer node.
// The cursor is the (created_at, id) pair, so messages sharing a timestamp are not skipped.
type ServerBatch struct {
	Items []Message
	NextCreatedAt time.Time
	NextID string
}

var ErrInvalidServerCursor = errors.New("invalid chat server cursor")

func (s *Service) ListForServer(ctx context.Context, nodeKey string, after time.Time, afterID string, limit int) (ServerBatch, error) {
	nodeKey = strings.TrimSpace(nodeKey)
	if nodeKey == "" {
		return ServerBatch{}, ErrInvalidInput
	}
	if limit < 1 || limit > 100 {
		limit = 50
	}
	if afterID == "" {
		afterID = "00000000-0000-0000-0000-000000000000"
	}
	if !isUUID(afterID) {
		return ServerBatch{}, ErrInvalidServerCursor
	}

	// A node may host multiple instances, but only messages for worlds it currently
	// serves are visible. cross_world deliberately has no world filter.
	rows, err := s.db.QueryContext(ctx, `
		SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),
		       m.sender_character_id::text,c.name,COALESCE(c.race_id,''),c.level,m.content,m.created_at
		FROM chat_messages m
		JOIN characters c ON c.id=m.sender_character_id
		WHERE m.channel_type IN ('world','cross_world')
		  AND (m.channel_type='cross_world' OR m.world_id IN (
			SELECT DISTINCT wi.world_id
			FROM world_instances wi
			JOIN server_registry sr ON sr.id=wi.server_id
			WHERE sr.node_key=$1 AND sr.status='ready' AND wi.status='ready'
		  ))
		  AND (m.created_at > $2 OR (m.created_at = $2 AND m.id > $3::uuid))
		ORDER BY m.created_at ASC,m.id ASC
		LIMIT $4`, nodeKey, after, afterID, limit)
	if err != nil {
		return ServerBatch{}, fmt.Errorf("query server chat messages: %w", err)
	}
	defer rows.Close()

	batch := ServerBatch{Items: make([]Message, 0)}
	for rows.Next() {
		var item Message
		if err := rows.Scan(&item.ID,&item.ClientMessageID,&item.Channel,&item.WorldID,
			&item.SenderCharacterID,&item.SenderName,&item.SenderRace,&item.SenderLevel,
			&item.Content,&item.CreatedAt); err != nil {
			return ServerBatch{}, fmt.Errorf("scan server chat message: %w", err)
		}
		batch.Items = append(batch.Items, item)
		batch.NextCreatedAt = item.CreatedAt
		batch.NextID = item.ID
	}
	if err := rows.Err(); err != nil {
		return ServerBatch{}, fmt.Errorf("iterate server chat messages: %w", err)
	}
	return batch, nil
}

// SendFromServer accepts a public-channel message only when the supplied active
// world session belongs to this registered node. Sender identity and world scope
// are always resolved from PostgreSQL, never from the request body.
func (s *Service) SendFromServer(ctx context.Context, nodeKey, sessionID, characterID string, req SendRequest) (Message, error) {
	nodeKey = strings.TrimSpace(nodeKey)
	sessionID = strings.TrimSpace(sessionID)
	characterID = strings.TrimSpace(characterID)
	req.Channel = strings.TrimSpace(req.Channel)
	req.Content = strings.TrimSpace(req.Content)
	if nodeKey == "" || len(nodeKey) > 96 || !isUUID(sessionID) || !isUUID(characterID) ||
		!isUUID(req.ClientMessageID) || utf8.RuneCountInString(req.Content) == 0 ||
		utf8.RuneCountInString(req.Content) > 200 {
		return Message{}, ErrInvalidInput
	}
	if req.Channel != "world" && req.Channel != "cross_world" {
		return Message{}, ErrUnsupportedChannel
	}
	for _, r := range req.Content {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return Message{}, ErrInvalidInput
		}
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Message{}, fmt.Errorf("begin world server chat send: %w", err)
	}
	defer tx.Rollback()

	var name, raceID, worldID string
	var level int
	err = tx.QueryRowContext(ctx, `
		SELECT c.name,COALESCE(c.race_id,''),c.world_id,c.level
		FROM world_sessions ws
		JOIN server_registry sr ON sr.id=ws.server_id
		JOIN characters c ON c.id=ws.character_id
		WHERE ws.id=$1::uuid AND ws.character_id=$2::uuid
		  AND sr.node_key=$3 AND sr.status='ready'
		  AND sr.last_heartbeat_at > now()-interval '30 seconds'
		  AND ws.session_state='active' AND c.status='alive'
		FOR UPDATE OF ws`, sessionID, characterID, nodeKey).
		Scan(&name,&raceID,&worldID,&level)
	if errors.Is(err, sql.ErrNoRows) {
		return Message{}, ErrNoCharacter
	}
	if err != nil {
		return Message{}, fmt.Errorf("verify world server chat session: %w", err)
	}

	// Retries with the same client ID return the original result and do not
	// consume another rate-limit slot.
	var existing Message
	err = tx.QueryRowContext(ctx, `
		SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),
		       m.sender_character_id::text,$2,$3,$4,m.content,m.created_at
		FROM chat_messages m
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$5::uuid`,
		characterID,name,raceID,level,req.ClientMessageID).
		Scan(&existing.ID,&existing.ClientMessageID,&existing.Channel,&existing.WorldID,
			&existing.SenderCharacterID,&existing.SenderName,&existing.SenderRace,&existing.SenderLevel,
			&existing.Content,&existing.CreatedAt)
	if err == nil {
		if existing.Channel != req.Channel || existing.Content != req.Content {
			return Message{}, ErrIdempotencyConflict
		}
		if err := tx.Commit(); err != nil { return Message{}, fmt.Errorf("commit idempotent chat lookup: %w", err) }
		return existing,nil
	}
	if !errors.Is(err,sql.ErrNoRows) {
		return Message{},fmt.Errorf("check duplicate world server chat message: %w",err)
	}

	window := 3*time.Second
	if req.Channel == "cross_world" { window = 5*time.Second }
	var recent int
	if err := tx.QueryRowContext(ctx,`
		SELECT count(*) FROM chat_messages
		WHERE sender_character_id=$1::uuid AND channel_type=$2
		  AND created_at > now()-$3::interval`, characterID,req.Channel,window.String()).Scan(&recent); err != nil {
		return Message{}, fmt.Errorf("check world server chat rate limit: %w", err)
	}
	if recent > 0 { return Message{}, ErrRateLimited }

	var worldValue any
	if req.Channel == "world" { worldValue = worldID }
	_, err = tx.ExecContext(ctx,`
		INSERT INTO chat_messages(channel_type,world_id,sender_character_id,client_message_id,content)
		VALUES($1,$2,$3::uuid,$4::uuid,$5)
		ON CONFLICT(sender_character_id,client_message_id) DO NOTHING`,
		req.Channel,worldValue,characterID,req.ClientMessageID,req.Content)
	if err != nil { return Message{}, fmt.Errorf("persist world server chat message: %w", err) }

	var item Message
	err = tx.QueryRowContext(ctx,`
		SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),
		       m.sender_character_id::text,$2,$3,$4,m.content,m.created_at
		FROM chat_messages m
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$5::uuid`,
		characterID,name,raceID,level,req.ClientMessageID).
		Scan(&item.ID,&item.ClientMessageID,&item.Channel,&item.WorldID,&item.SenderCharacterID,
			&item.SenderName,&item.SenderRace,&item.SenderLevel,&item.Content,&item.CreatedAt)
	if err != nil { return Message{}, fmt.Errorf("load persisted world server chat message: %w", err) }
	if err := insertChatEventOutbox(ctx, tx, item); err != nil {
		return Message{}, err
	}
	if err := tx.Commit(); err != nil { return Message{}, fmt.Errorf("commit world server chat message and outbox: %w", err) }
	return item,nil
}


// PruneExpiredMessages removes chat history beyond the configured 30-day retention.
// It is called by the standalone ChatServer scheduler, never from a player request.
func (s *Service) PruneExpiredMessages(ctx context.Context) (int64, error) {
	result, err := s.db.ExecContext(ctx, `DELETE FROM chat_messages WHERE created_at < now() - interval '30 days'`)
	if err != nil {
		return 0, fmt.Errorf("prune expired chat history: %w", err)
	}
	deleted, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("read expired chat deletion count: %w", err)
	}
	return deleted, nil
}

// CurrentWorldID resolves the active character's world for chat-only routing.
// It intentionally reads identity state but never mutates game state.
func (s *Service) CurrentWorldID(ctx context.Context, accountID string) (string, error) {
	if strings.TrimSpace(accountID) == "" {
		return "", ErrInvalidInput
	}
	var worldID string
	err := s.db.QueryRowContext(ctx, `
		SELECT c.world_id
		FROM souls soul
		JOIN characters c ON c.id = soul.current_character_id
		WHERE soul.account_id = $1 AND c.status = 'alive'`, accountID).Scan(&worldID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNoCharacter
	}
	if err != nil {
		return "", fmt.Errorf("resolve chat world: %w", err)
	}
	return worldID, nil
}
