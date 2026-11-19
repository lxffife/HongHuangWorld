package chat

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"
)

var (
	ErrAlreadyFriend = errors.New("characters are already friends")
	ErrFriendRequestExists = errors.New("friend request already pending")
	ErrFriendRequestNotFound = errors.New("friend request not found")
	ErrFriendRequestsDisabled = errors.New("recipient does not accept friend requests")
	ErrBlocked = errors.New("chat relationship is blocked")
	ErrFriendRequired = errors.New("accepted friendship required")
)

type CharacterSearchResult struct {
	CharacterID string `json:"character_id"`
	Name string `json:"name"`
	WorldID string `json:"world_id"`
	Level int `json:"level"`
	IsFriend bool `json:"is_friend"`
}

type Friend struct {
	CharacterID string `json:"character_id"`
	Name string `json:"name"`
	WorldID string `json:"world_id"`
	Level int `json:"level"`
	ChatOnline bool `json:"chat_online"`
	InGame bool `json:"in_game"`
}

type FriendRequest struct {
	ID string `json:"id"`
	CharacterID string `json:"character_id"`
	Name string `json:"name"`
	WorldID string `json:"world_id"`
	Message string `json:"message"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Service) currentCharacterID(ctx context.Context, accountID string) (string, error) {
	if !isUUID(accountID) {
		return "", ErrInvalidInput
	}
	var characterID string
	err := s.db.QueryRowContext(ctx, `SELECT current_character_id::text FROM chat_accounts WHERE account_id=$1::uuid AND current_character_id IS NOT NULL`, accountID).Scan(&characterID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNoCharacter
	}
	if err != nil {
		return "", fmt.Errorf("resolve current character for social action: %w", err)
	}
	return characterID, nil
}

func (s *Service) SearchCharacters(ctx context.Context, accountID, query string, limit int) ([]CharacterSearchResult, error) {
	query = strings.TrimSpace(query)
	if utf8.RuneCountInString(query) < 2 || utf8.RuneCountInString(query) > 48 {
		return nil, ErrInvalidInput
	}
	if limit < 1 || limit > 30 {
		limit = 20
	}
	characterID, err := s.currentCharacterID(ctx, accountID)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT c.character_id::text,c.name,c.world_id,c.level,
			EXISTS(SELECT 1 FROM chat_friendships f
				WHERE (f.requester_character_id=$1::uuid AND f.addressee_character_id=c.character_id)
				   OR (f.addressee_character_id=$1::uuid AND f.requester_character_id=c.character_id))
		FROM chat_characters c
		WHERE c.status='alive' AND c.character_id<>$1::uuid
			AND c.name ILIKE '%' || $2 || '%'
			AND NOT EXISTS(SELECT 1 FROM chat_blocks b
				WHERE (b.blocker_character_id=$1::uuid AND b.blocked_character_id=c.character_id)
				   OR (b.blocker_character_id=c.character_id AND b.blocked_character_id=$1::uuid))
		ORDER BY c.name,c.character_id
		LIMIT $3`, characterID, query, limit)
	if err != nil {
		return nil, fmt.Errorf("search chat characters: %w", err)
	}
	defer rows.Close()
	items := make([]CharacterSearchResult, 0)
	for rows.Next() {
		var item CharacterSearchResult
		if err := rows.Scan(&item.CharacterID,&item.Name,&item.WorldID,&item.Level,&item.IsFriend); err != nil {
			return nil, fmt.Errorf("scan character search result: %w", err)
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Service) ListFriends(ctx context.Context, accountID string) ([]Friend, error) {
	characterID, err := s.currentCharacterID(ctx, accountID)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx, `
		WITH friend_characters AS (
			SELECT f.addressee_character_id AS character_id FROM chat_friendships f WHERE f.requester_character_id=$1::uuid
			UNION
			SELECT f.requester_character_id AS character_id FROM chat_friendships f WHERE f.addressee_character_id=$1::uuid
		)
		SELECT c.character_id::text,c.name,c.world_id,c.level,
			EXISTS(SELECT 1 FROM chat_presence_sessions p WHERE p.character_id=c.character_id AND p.expires_at>now()),
			EXISTS(SELECT 1 FROM chat_world_sessions ws WHERE ws.character_id=c.character_id AND ws.session_state='active')
		FROM friend_characters f
		JOIN chat_characters c ON c.character_id=f.character_id AND c.status='alive'
		ORDER BY c.name,c.character_id`, characterID)
	if err != nil {
		return nil, fmt.Errorf("list chat friends: %w", err)
	}
	defer rows.Close()
	items := make([]Friend, 0)
	for rows.Next() {
		var item Friend
		if err := rows.Scan(&item.CharacterID,&item.Name,&item.WorldID,&item.Level,&item.ChatOnline,&item.InGame); err != nil {
			return nil, fmt.Errorf("scan chat friend: %w", err)
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Service) ListIncomingFriendRequests(ctx context.Context, accountID string) ([]FriendRequest, error) {
	characterID, err := s.currentCharacterID(ctx, accountID)
	if err != nil {
		return nil, err
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT r.id::text,c.character_id::text,c.name,c.world_id,r.message,r.created_at
		FROM chat_friend_requests r
		JOIN chat_characters c ON c.character_id=r.requester_character_id
		WHERE r.addressee_character_id=$1::uuid AND r.status='pending'
		ORDER BY r.created_at ASC,r.id ASC
		LIMIT 100`, characterID)
	if err != nil {
		return nil, fmt.Errorf("list incoming friend requests: %w", err)
	}
	defer rows.Close()
	items := make([]FriendRequest, 0)
	for rows.Next() {
		var item FriendRequest
		if err := rows.Scan(&item.ID,&item.CharacterID,&item.Name,&item.WorldID,&item.Message,&item.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan incoming friend request: %w", err)
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Service) SendFriendRequest(ctx context.Context, accountID, targetCharacterID, message string) (FriendRequest, error) {
	message = strings.TrimSpace(message)
	if !isUUID(targetCharacterID) || utf8.RuneCountInString(message) > 200 {
		return FriendRequest{}, ErrInvalidInput
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return FriendRequest{}, fmt.Errorf("begin friend request: %w", err)
	}
	defer tx.Rollback()
	var senderID string
	if err := tx.QueryRowContext(ctx, `SELECT current_character_id::text FROM chat_accounts WHERE account_id=$1::uuid AND current_character_id IS NOT NULL FOR UPDATE`, accountID).Scan(&senderID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return FriendRequest{}, ErrNoCharacter }
		return FriendRequest{}, fmt.Errorf("resolve friend requester: %w", err)
	}
	if senderID == targetCharacterID { return FriendRequest{}, ErrInvalidInput }
	var targetName, targetWorld string
	err = tx.QueryRowContext(ctx, `SELECT name,world_id FROM chat_characters WHERE character_id=$1::uuid AND status='alive'`, targetCharacterID).Scan(&targetName,&targetWorld)
	if errors.Is(err, sql.ErrNoRows) { return FriendRequest{}, ErrInvalidInput }
	if err != nil { return FriendRequest{}, fmt.Errorf("resolve friend request target: %w", err) }
	var blocked bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_blocks WHERE (blocker_character_id=$1::uuid AND blocked_character_id=$2::uuid) OR (blocker_character_id=$2::uuid AND blocked_character_id=$1::uuid))`, senderID,targetCharacterID).Scan(&blocked); err != nil {
		return FriendRequest{}, fmt.Errorf("check friend request block: %w", err)
	}
	if blocked { return FriendRequest{}, ErrBlocked }
	var friends bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_friendships WHERE (requester_character_id=$1::uuid AND addressee_character_id=$2::uuid) OR (requester_character_id=$2::uuid AND addressee_character_id=$1::uuid))`, senderID,targetCharacterID).Scan(&friends); err != nil {
		return FriendRequest{}, fmt.Errorf("check existing friendship: %w", err)
	}
	if friends { return FriendRequest{}, ErrAlreadyFriend }
	var allowed bool
	err = tx.QueryRowContext(ctx, `SELECT COALESCE((SELECT allow_stranger_requests FROM chat_preferences WHERE character_id=$1::uuid),true)`, targetCharacterID).Scan(&allowed)
	if err != nil { return FriendRequest{}, fmt.Errorf("check friend request preference: %w", err) }
	if !allowed { return FriendRequest{}, ErrFriendRequestsDisabled }
	var item FriendRequest
	err = tx.QueryRowContext(ctx, `
		INSERT INTO chat_friend_requests(requester_character_id,addressee_character_id,message)
		VALUES($1::uuid,$2::uuid,$3)
		RETURNING id::text,created_at`, senderID,targetCharacterID,message).Scan(&item.ID,&item.CreatedAt)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "uq_chat_friend_requests_pending") { return FriendRequest{}, ErrFriendRequestExists }
		return FriendRequest{}, fmt.Errorf("create friend request: %w", err)
	}
	item.CharacterID=senderID
	item.Message=message
	if err := tx.Commit(); err != nil { return FriendRequest{}, fmt.Errorf("commit friend request: %w", err) }
	return item,nil
}

func (s *Service) RespondFriendRequest(ctx context.Context, accountID, requestID string, accept bool) error {
	if !isUUID(requestID) { return ErrInvalidInput }
	tx, err := s.db.BeginTx(ctx,nil)
	if err != nil { return fmt.Errorf("begin friend request response: %w",err) }
	defer tx.Rollback()
	var currentID, requesterID string
	err=tx.QueryRowContext(ctx,`
		SELECT a.current_character_id::text,r.requester_character_id::text
		FROM chat_accounts a JOIN chat_friend_requests r ON r.addressee_character_id=a.current_character_id
		WHERE a.account_id=$1::uuid AND a.current_character_id IS NOT NULL
		  AND r.id=$2::uuid AND r.status='pending'
		FOR UPDATE OF r`,accountID,requestID).Scan(&currentID,&requesterID)
	if errors.Is(err,sql.ErrNoRows){return ErrFriendRequestNotFound}
	if err!=nil{return fmt.Errorf("load friend request response: %w",err)}
	var blocked bool
	if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM chat_blocks WHERE (blocker_character_id=$1::uuid AND blocked_character_id=$2::uuid) OR (blocker_character_id=$2::uuid AND blocked_character_id=$1::uuid))`,currentID,requesterID).Scan(&blocked);err!=nil{return fmt.Errorf("check block before accepting friend: %w",err)}
	if blocked{return ErrBlocked}
	status:="rejected"
	if accept{status="accepted"}
	if _,err:=tx.ExecContext(ctx,`UPDATE chat_friend_requests SET status=$2,responded_at=now() WHERE id=$1::uuid`,requestID,status);err!=nil{return fmt.Errorf("update friend request: %w",err)}
	if accept{
		if _,err:=tx.ExecContext(ctx,`
			INSERT INTO chat_friendships(requester_character_id,addressee_character_id)
			VALUES($1::uuid,$2::uuid),($2::uuid,$1::uuid)
			ON CONFLICT DO NOTHING`,currentID,requesterID);err!=nil{return fmt.Errorf("create accepted friendship: %w",err)}
	}
	if err:=tx.Commit();err!=nil{return fmt.Errorf("commit friend request response: %w",err)}
	return nil
}

func (s *Service) RemoveFriend(ctx context.Context, accountID, friendCharacterID string) error {
	if !isUUID(friendCharacterID) { return ErrInvalidInput }
	characterID,err:=s.currentCharacterID(ctx,accountID)
	if err!=nil{return err}
	result,err:=s.db.ExecContext(ctx,`
		DELETE FROM chat_friendships
		WHERE (requester_character_id=$1::uuid AND addressee_character_id=$2::uuid)
		   OR (requester_character_id=$2::uuid AND addressee_character_id=$1::uuid)`,characterID,friendCharacterID)
	if err!=nil{return fmt.Errorf("remove friendship: %w",err)}
	count,err:=result.RowsAffected()
	if err!=nil{return err}
	if count==0{return ErrFriendRequestNotFound}
	return nil
}

func (s *Service) ListConversation(ctx context.Context, accountID, peerCharacterID, before string, limit int) ([]Message, error) {
	if !isUUID(peerCharacterID) { return nil, ErrInvalidInput }
	if limit < 1 || limit > 100 { limit = 50 }
	currentID, err := s.currentCharacterID(ctx, accountID)
	if err != nil { return nil, err }
	if currentID == peerCharacterID { return nil, ErrInvalidInput }
	var friends, blocked bool
	if err := s.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_friendships WHERE requester_character_id=$1::uuid AND addressee_character_id=$2::uuid)`, currentID, peerCharacterID).Scan(&friends); err != nil {
		return nil, fmt.Errorf("check direct conversation friendship: %w", err)
	}
	if !friends { return nil, ErrFriendRequired }
	if err := s.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_blocks WHERE (blocker_character_id=$1::uuid AND blocked_character_id=$2::uuid) OR (blocker_character_id=$2::uuid AND blocked_character_id=$1::uuid))`, currentID, peerCharacterID).Scan(&blocked); err != nil {
		return nil, fmt.Errorf("check direct conversation block: %w", err)
	}
	if blocked { return nil, ErrBlocked }
	query := `SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),COALESCE(m.recipient_character_id::text,''),COALESCE(m.conversation_id::text,''),m.sender_character_id::text,m.sender_name,m.sender_race,m.sender_level,m.content,m.created_at
		FROM chat_messages m
		JOIN chat_conversations c ON c.id=m.conversation_id
		WHERE m.channel_type='whisper'
		  AND c.participant_low=LEAST($1::uuid,$2::uuid)
		  AND c.participant_high=GREATEST($1::uuid,$2::uuid)
		  AND m.created_at>now()-interval '30 days'`
	args := []any{currentID, peerCharacterID}
	if before != "" {
		query += ` AND m.created_at < $3`
		args = append(args, before)
	}
	query += fmt.Sprintf(` ORDER BY m.created_at DESC,m.id DESC LIMIT $%d`, len(args)+1)
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil { return nil, fmt.Errorf("query direct conversation: %w", err) }
	defer rows.Close()
	items := make([]Message, 0)
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID,&m.ClientMessageID,&m.Channel,&m.WorldID,&m.RecipientCharacterID,&m.ConversationID,&m.SenderCharacterID,&m.SenderName,&m.SenderRace,&m.SenderLevel,&m.Content,&m.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan direct conversation message: %w", err)
		}
		items = append(items,m)
	}
	if err := rows.Err(); err != nil { return nil, err }
	for left,right:=0,len(items)-1;left<right;left,right=left+1,right-1 { items[left],items[right]=items[right],items[left] }
	return items,nil
}

func (s *Service) GetAllowStrangerFriendRequests(ctx context.Context, accountID string) (bool, error) {
	characterID, err := s.currentCharacterID(ctx, accountID)
	if err != nil { return false, err }
	var allowed bool
	if err := s.db.QueryRowContext(ctx, `SELECT COALESCE((SELECT allow_stranger_requests FROM chat_preferences WHERE character_id=$1::uuid),true)`, characterID).Scan(&allowed); err != nil {
		return false, fmt.Errorf("read friend request preference: %w", err)
	}
	return allowed,nil
}

func (s *Service) SetAllowStrangerFriendRequests(ctx context.Context, accountID string, allowed bool) error {
	characterID, err := s.currentCharacterID(ctx, accountID)
	if err != nil { return err }
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO chat_preferences(character_id,allow_stranger_requests,updated_at)
		VALUES($1::uuid,$2,now())
		ON CONFLICT(character_id) DO UPDATE SET allow_stranger_requests=EXCLUDED.allow_stranger_requests,updated_at=now()`, characterID, allowed)
	if err != nil { return fmt.Errorf("update friend request preference: %w", err) }
	return nil
}
