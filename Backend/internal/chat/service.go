package chat

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
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
	WorldInstanceID string `json:"world_instance_id,omitempty"`
	RecipientCharacterIDs []string `json:"recipient_character_ids,omitempty"`
	RecipientCharacterID string `json:"recipient_character_id,omitempty"`
	ConversationID string `json:"conversation_id,omitempty"`
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
	RecipientCharacterIDs []string `json:"recipient_character_ids,omitempty"`
	RecipientCharacterID string `json:"recipient_character_id,omitempty"`
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
	if req.Channel != "world" && req.Channel != "cross_world" && req.Channel != "whisper" {
		return Message{}, ErrUnsupportedChannel
	}
	if req.Channel == "whisper" {
		if !isUUID(req.RecipientCharacterID) { return Message{}, ErrInvalidInput }
	} else if req.RecipientCharacterID != "" {
		return Message{}, ErrInvalidInput
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
	characterQuery := `SELECT c.character_id::text,c.name,COALESCE(c.race_id,''),c.world_id,c.level FROM chat_accounts account JOIN chat_characters c ON c.character_id=account.current_character_id WHERE account.account_id=$1::uuid AND c.status='alive' FOR UPDATE OF account,c`
	err = tx.QueryRowContext(ctx, characterQuery, accountID).Scan(&characterID, &characterName, &raceID, &worldID, &level)
	if errors.Is(err, sql.ErrNoRows) {
		return Message{}, ErrNoCharacter
	}
	if err != nil {
		return Message{}, fmt.Errorf("resolve and lock chat character: %w", err)
	}

	existing, existingErr := getChatMessageByClientID(ctx, tx, characterID, req.ClientMessageID)
	if existingErr == nil {
		if existing.Channel != req.Channel || existing.Content != req.Content || existing.RecipientCharacterID != req.RecipientCharacterID {
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
	if req.Channel == "cross_world" { window = 5 * time.Second }
	if req.Channel == "whisper" { window = time.Second }
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
	if req.Channel == "world" { worldValue = worldID }
	var recipientValue any
	var conversationValue any
	if req.Channel == "whisper" {
		var recipientName string
		if err := tx.QueryRowContext(ctx, `SELECT name FROM chat_characters WHERE character_id=$1::uuid AND status='alive'`, req.RecipientCharacterID).Scan(&recipientName); err != nil {
			if errors.Is(err, sql.ErrNoRows) { return Message{}, ErrInvalidInput }
			return Message{}, fmt.Errorf("resolve whisper recipient: %w", err)
		}
		var friends bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_friendships WHERE (requester_character_id=$1::uuid AND addressee_character_id=$2::uuid) OR (requester_character_id=$2::uuid AND addressee_character_id=$1::uuid))`, characterID, req.RecipientCharacterID).Scan(&friends); err != nil {
			return Message{}, fmt.Errorf("check whisper friendship: %w", err)
		}
		if !friends { return Message{}, ErrFriendRequired }
		var blocked bool
		if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM chat_blocks WHERE (blocker_character_id=$1::uuid AND blocked_character_id=$2::uuid) OR (blocker_character_id=$2::uuid AND blocked_character_id=$1::uuid))`, characterID, req.RecipientCharacterID).Scan(&blocked); err != nil {
			return Message{}, fmt.Errorf("check whisper block: %w", err)
		}
		if blocked { return Message{}, ErrBlocked }
		if err := tx.QueryRowContext(ctx, `
			INSERT INTO chat_conversations(participant_low,participant_high)
			VALUES(LEAST($1::uuid,$2::uuid),GREATEST($1::uuid,$2::uuid))
			ON CONFLICT(participant_low,participant_high) DO UPDATE SET updated_at=now()
			RETURNING id::text`, characterID, req.RecipientCharacterID).Scan(&conversationValue); err != nil {
			return Message{}, fmt.Errorf("resolve direct conversation: %w", err)
		}
		recipientValue = req.RecipientCharacterID
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO chat_messages(channel_type,world_id,sender_character_id,recipient_character_id,conversation_id,client_message_id,sender_name,sender_race,sender_level,content) VALUES($1,$2,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,$9,$10)`, req.Channel, worldValue, characterID, recipientValue, conversationValue, req.ClientMessageID, characterName, raceID, level, req.Content)
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

func (s *Service) List(ctx context.Context, accountID, channel, before string, limit int) ([]Message, error) {
	if strings.TrimSpace(accountID) == "" {
		return nil, ErrInvalidInput
	}
	if channel != "world" && channel != "cross_world" && channel != "nearby" {
		return nil, ErrUnsupportedChannel
	}
	if limit < 1 || limit > 100 {
		limit = 50
	}
	var characterID, worldID, instanceID string
	resolveQuery := `SELECT c.character_id::text,c.world_id,COALESCE(ws.instance_id::text,'') FROM chat_accounts account JOIN chat_characters c ON c.character_id=account.current_character_id LEFT JOIN chat_world_sessions ws ON ws.character_id=c.character_id AND ws.session_state='active' WHERE account.account_id=$1::uuid AND c.status='alive'`
	err := s.db.QueryRowContext(ctx, resolveQuery, accountID).Scan(&characterID, &worldID, &instanceID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNoCharacter
	}
	if err != nil {
		return nil, fmt.Errorf("resolve chat history character: %w", err)
	}
	if channel == "nearby" && instanceID == "" {
		return []Message{}, nil
	}

	query := `SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,m.sender_name,m.sender_race,m.sender_level,m.content,m.created_at FROM chat_messages m WHERE m.created_at > now()-interval '30 days' AND `
	args := []any{}
	switch channel {
	case "world":
		query += "m.channel_type='world' AND m.world_id=$1"
		args = append(args, worldID)
	case "cross_world":
		query += "m.channel_type='cross_world'"
	case "nearby":
		query += "m.channel_type='nearby' AND m.world_instance_id=$1::uuid AND m.nearby_recipient_character_ids @> jsonb_build_array($2::text)"
		args = append(args, instanceID, characterID)
	}
	if before != "" {
		query += fmt.Sprintf(" AND m.created_at < $%d", len(args)+1)
		args = append(args, before)
	}
	query += " ORDER BY m.created_at DESC,m.id DESC"
	query += fmt.Sprintf(" LIMIT $%d", len(args)+1)
	args = append(args, limit)

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query chat history: %w", err)
	}
	defer rows.Close()
	items := make([]Message, 0)
	for rows.Next() {
		var message Message
		if err := rows.Scan(&message.ID,&message.ClientMessageID,&message.Channel,&message.WorldID,
			&message.SenderCharacterID,&message.SenderName,&message.SenderRace,&message.SenderLevel,
			&message.Content,&message.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan chat message: %w", err)
		}
		items = append(items, message)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate chat history: %w", err)
	}
	for left, right := 0, len(items)-1; left < right; left, right = left+1, right-1 {
		items[left], items[right] = items[right], items[left]
	}
	return items, nil
}

type chatRowQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func getChatMessageByClientID(ctx context.Context, queryer chatRowQueryer, characterID, clientID string) (Message, error) {
	var m Message
	err := queryer.QueryRowContext(ctx, `SELECT id::text,client_message_id::text,channel_type,COALESCE(world_id,''),COALESCE(recipient_character_id::text,''),COALESCE(conversation_id::text,''),sender_character_id::text,sender_name,sender_race,sender_level,content,created_at FROM chat_messages WHERE sender_character_id=$1::uuid AND client_message_id=$2::uuid`, characterID, clientID).Scan(&m.ID,&m.ClientMessageID,&m.Channel,&m.WorldID,&m.RecipientCharacterID,&m.ConversationID,&m.SenderCharacterID,&m.SenderName,&m.SenderRace,&m.SenderLevel,&m.Content,&m.CreatedAt)
	if err != nil { return Message{}, fmt.Errorf("load stored chat message: %w", err) }
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
	if _, err := tx.ExecContext(ctx, `INSERT INTO chat_event_outbox(message_id,payload) VALUES($1::uuid,$2::jsonb) ON CONFLICT(message_id) DO NOTHING`, message.ID, string(payload)); err != nil {
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
	serverQuery := `SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),m.sender_character_id::text,m.sender_name,m.sender_race,m.sender_level,m.content,m.created_at FROM chat_messages m WHERE m.channel_type IN ('world','cross_world') AND (m.channel_type='cross_world' OR m.world_id IN (SELECT DISTINCT wi.world_id FROM chat_world_instances wi JOIN chat_server_nodes sr ON sr.node_key=wi.node_key WHERE sr.node_key=$1 AND sr.status='ready' AND wi.status='ready')) AND (m.created_at > $2 OR (m.created_at = $2 AND m.id > $3::uuid)) ORDER BY m.created_at ASC,m.id ASC LIMIT $4`
	rows, err := s.db.QueryContext(ctx, serverQuery, nodeKey, after, afterID, limit)
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
	if req.Channel != "nearby" && req.Channel != "world" && req.Channel != "cross_world" {
		return Message{}, ErrUnsupportedChannel
	}
	for _, r := range req.Content {
		if unicode.IsControl(r) && r != '\n' && r != '\t' {
			return Message{}, ErrInvalidInput
		}
	}

	recipientSet := make(map[string]struct{}, len(req.RecipientCharacterIDs))
	for _, recipientID := range req.RecipientCharacterIDs {
		recipientID = strings.TrimSpace(recipientID)
		if !isUUID(recipientID) {
			return Message{}, ErrInvalidInput
		}
		recipientSet[recipientID] = struct{}{}
	}
	if req.Channel == "nearby" {
		if len(recipientSet) == 0 || len(recipientSet) > 512 {
			return Message{}, ErrInvalidInput
		}
		if _, includesSender := recipientSet[characterID]; !includesSender {
			return Message{}, ErrInvalidInput
		}
	} else if len(recipientSet) != 0 {
		return Message{}, ErrInvalidInput
	}
	req.RecipientCharacterIDs = req.RecipientCharacterIDs[:0]
	for recipientID := range recipientSet {
		req.RecipientCharacterIDs = append(req.RecipientCharacterIDs, recipientID)
	}
	sort.Strings(req.RecipientCharacterIDs)
	recipientsJSON, err := json.Marshal(req.RecipientCharacterIDs)
	if err != nil {
		return Message{}, fmt.Errorf("encode nearby chat recipients: %w", err)
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Message{}, fmt.Errorf("begin world server chat send: %w", err)
	}
	defer tx.Rollback()

	var name, raceID, worldID, instanceID string
	var level int
	sessionQuery := `SELECT c.name,c.race_id,c.world_id,wi.instance_id::text,c.level FROM chat_world_sessions ws JOIN chat_server_nodes sr ON sr.node_key=ws.node_key JOIN chat_world_instances wi ON wi.instance_id=ws.instance_id AND wi.node_key=sr.node_key JOIN chat_characters c ON c.character_id=ws.character_id WHERE ws.session_id=$1::uuid AND ws.character_id=$2::uuid AND sr.node_key=$3 AND sr.status='ready' AND sr.last_heartbeat_at > now()-interval '30 seconds' AND wi.status='ready' AND (ws.session_state='active' OR (ws.session_state IN ('saving','closed') AND COALESCE(ws.disconnected_at,ws.updated_at) > now()-interval '30 days')) AND c.status='alive' FOR UPDATE OF ws,c`
	err = tx.QueryRowContext(ctx, sessionQuery, sessionID, characterID, nodeKey).
		Scan(&name, &raceID, &worldID, &instanceID, &level)
	if errors.Is(err, sql.ErrNoRows) {
		return Message{}, ErrNoCharacter
	}
	if err != nil {
		return Message{}, fmt.Errorf("verify world server chat session: %w", err)
	}

	// Retries with the same client ID return the original result and do not
	// consume another rate-limit slot.
	var existing Message
	var existingRecipients []byte
	err = tx.QueryRowContext(ctx, `
		SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),
		       m.sender_character_id::text,$2::text,$3::text,$4::int,m.content,m.created_at,
		       COALESCE(m.world_instance_id::text,''),m.nearby_recipient_character_ids
		FROM chat_messages m
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$5::uuid`,
		characterID, name, raceID, level, req.ClientMessageID).
		Scan(&existing.ID,&existing.ClientMessageID,&existing.Channel,&existing.WorldID,
			&existing.SenderCharacterID,&existing.SenderName,&existing.SenderRace,&existing.SenderLevel,
			&existing.Content,&existing.CreatedAt,&existing.WorldInstanceID,&existingRecipients)
	if err == nil {
		if existing.Channel != req.Channel || existing.Content != req.Content ||
			(req.Channel == "nearby" && (existing.WorldInstanceID != instanceID || existing.WorldID != worldID)) {
			return Message{}, ErrIdempotencyConflict
		}
		if err := json.Unmarshal(existingRecipients, &existing.RecipientCharacterIDs); err != nil {
			return Message{}, fmt.Errorf("decode existing nearby chat recipients: %w", err)
		}
		if len(existing.RecipientCharacterIDs) != len(req.RecipientCharacterIDs) {
			return Message{}, ErrIdempotencyConflict
		}
		for index := range existing.RecipientCharacterIDs {
			if existing.RecipientCharacterIDs[index] != req.RecipientCharacterIDs[index] {
				return Message{}, ErrIdempotencyConflict
			}
		}
		if err := tx.Commit(); err != nil {
			return Message{}, fmt.Errorf("commit idempotent chat lookup: %w", err)
		}
		return existing, nil
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return Message{}, fmt.Errorf("check duplicate world server chat message: %w", err)
	}

	if req.Channel == "nearby" {
		var validRecipients int
		recipientQuery := `SELECT count(DISTINCT ws.character_id) FROM jsonb_array_elements_text($2::jsonb) AS requested(character_id) JOIN chat_world_sessions ws ON ws.character_id=requested.character_id::uuid JOIN chat_characters c ON c.character_id=ws.character_id WHERE ws.instance_id=$1::uuid AND ws.node_key=$3 AND (ws.session_state='active' OR (ws.session_state IN ('saving','closed') AND COALESCE(ws.disconnected_at,ws.updated_at) > now()-interval '30 days')) AND c.status='alive'`
		err = tx.QueryRowContext(ctx, recipientQuery, instanceID, string(recipientsJSON), nodeKey).Scan(&validRecipients)
		if err != nil {
			return Message{}, fmt.Errorf("validate nearby chat AOI recipients: %w", err)
		}
		if validRecipients != len(req.RecipientCharacterIDs) {
			return Message{}, ErrInvalidInput
		}
	}

	window := 3 * time.Second
	switch req.Channel {
	case "nearby":
		window = time.Second
	case "cross_world":
		window = 5 * time.Second
	}
	var recent int
	if err := tx.QueryRowContext(ctx, `
		SELECT count(*) FROM chat_messages
		WHERE sender_character_id=$1::uuid AND channel_type=$2
		  AND created_at > now()-$3::interval`, characterID, req.Channel, window.String()).Scan(&recent); err != nil {
		return Message{}, fmt.Errorf("check world server chat rate limit: %w", err)
	}
	if recent > 0 {
		return Message{}, ErrRateLimited
	}

	var worldValue, instanceValue any
	if req.Channel == "world" || req.Channel == "nearby" {
		worldValue = worldID
	}
	if req.Channel == "nearby" {
		instanceValue = instanceID
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO chat_messages(channel_type,world_id,world_instance_id,nearby_recipient_character_ids,sender_character_id,client_message_id,sender_name,sender_race,sender_level,content) VALUES($1,$2,$3::uuid,$4::jsonb,$5::uuid,$6::uuid,$7,$8,$9,$10) ON CONFLICT(sender_character_id,client_message_id) DO NOTHING`, req.Channel, worldValue, instanceValue, string(recipientsJSON), characterID, req.ClientMessageID, name, raceID, level, req.Content)
	if err != nil {
		return Message{}, fmt.Errorf("persist world server chat message: %w", err)
	}

	var item Message
	var storedRecipients []byte
	err = tx.QueryRowContext(ctx, `
		SELECT m.id::text,m.client_message_id::text,m.channel_type,COALESCE(m.world_id,''),
		       m.sender_character_id::text,$2::text,$3::text,$4::int,m.content,m.created_at,
		       COALESCE(m.world_instance_id::text,''),m.nearby_recipient_character_ids
		FROM chat_messages m
		WHERE m.sender_character_id=$1::uuid AND m.client_message_id=$5::uuid`,
		characterID, name, raceID, level, req.ClientMessageID).
		Scan(&item.ID,&item.ClientMessageID,&item.Channel,&item.WorldID,&item.SenderCharacterID,
			&item.SenderName,&item.SenderRace,&item.SenderLevel,&item.Content,&item.CreatedAt,
			&item.WorldInstanceID,&storedRecipients)
	if err != nil {
		return Message{}, fmt.Errorf("load persisted world server chat message: %w", err)
	}
	if err := json.Unmarshal(storedRecipients, &item.RecipientCharacterIDs); err != nil {
		return Message{}, fmt.Errorf("decode persisted nearby chat recipients: %w", err)
	}
	if item.Channel != req.Channel || item.Content != req.Content {
		return Message{}, ErrIdempotencyConflict
	}
	if err := insertChatEventOutbox(ctx, tx, item); err != nil {
		return Message{}, err
	}
	if err := tx.Commit(); err != nil {
		return Message{}, fmt.Errorf("commit world server chat message and outbox: %w", err)
	}
	return item, nil
}


type OutboxItem struct {
	Message Message
	Attempts int
}

// ClaimChatEventOutbox atomically leases pending rows to one publisher worker.
// SKIP LOCKED allows multiple ChatServer processes to share the same database.
func (s *Service) ClaimChatEventOutbox(ctx context.Context, workerID string, limit int, lease time.Duration) ([]OutboxItem, error) {
	workerID = strings.TrimSpace(workerID)
	if workerID == "" || len(workerID) > 96 {
		return nil, ErrInvalidInput
	}
	if limit < 1 || limit > 100 {
		limit = 32
	}
	if lease < 5*time.Second || lease > 5*time.Minute {
		lease = time.Minute
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin chat outbox claim: %w", err)
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `
		WITH picked AS (
			SELECT message_id
			FROM chat_event_outbox
			WHERE published_at IS NULL
			  AND next_attempt_at <= now()
			  AND (locked_until IS NULL OR locked_until < now())
			ORDER BY created_at, message_id
			FOR UPDATE SKIP LOCKED
			LIMIT $1
		)
		UPDATE chat_event_outbox o
		SET locked_until = now() + make_interval(secs => $2::double precision),
		    locked_by = $3,
		    attempts = o.attempts + 1
		FROM picked
		WHERE o.message_id = picked.message_id
		RETURNING o.payload, o.attempts`, limit, lease.Seconds(), workerID)
	if err != nil {
		return nil, fmt.Errorf("claim chat event outbox: %w", err)
	}
	items := make([]OutboxItem, 0)
	for rows.Next() {
		var payload []byte
		var item OutboxItem
		if err := rows.Scan(&payload, &item.Attempts); err != nil {
			rows.Close()
			return nil, fmt.Errorf("scan claimed chat outbox event: %w", err)
		}
		if err := json.Unmarshal(payload, &item.Message); err != nil {
			rows.Close()
			return nil, fmt.Errorf("decode claimed chat outbox event: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		rows.Close()
		return nil, fmt.Errorf("iterate claimed chat outbox events: %w", err)
	}
	rows.Close()
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit chat outbox claim: %w", err)
	}
	return items, nil
}

// MarkChatEventOutboxPublished acknowledges a successful JetStream PubAck.
func (s *Service) MarkChatEventOutboxPublished(ctx context.Context, workerID, messageID string) error {
	result, err := s.db.ExecContext(ctx, `
		UPDATE chat_event_outbox
		SET published_at = now(), locked_until = NULL, locked_by = NULL, last_error = NULL
		WHERE message_id = $1::uuid AND locked_by = $2 AND published_at IS NULL`, messageID, workerID)
	if err != nil {
		return fmt.Errorf("mark chat outbox event published: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read chat outbox publish result: %w", err)
	}
	if count != 1 {
		return fmt.Errorf("chat outbox lease lost for message %s", messageID)
	}
	return nil
}

// RetryChatEventOutbox releases a failed lease and schedules an asynchronous retry.
func (s *Service) RetryChatEventOutbox(ctx context.Context, workerID, messageID string, delay time.Duration, publishErr error) error {
	if delay < time.Second {
		delay = time.Second
	}
	if delay > 5*time.Minute {
		delay = 5 * time.Minute
	}
	reason := "unknown publish error"
	if publishErr != nil {
		reason = publishErr.Error()
	}
	if len(reason) > 1000 {
		reason = reason[:1000]
	}
	result, err := s.db.ExecContext(ctx, `
		UPDATE chat_event_outbox
		SET next_attempt_at = now() + make_interval(secs => $3::double precision),
		    locked_until = NULL, locked_by = NULL, last_error = $4
		WHERE message_id = $1::uuid AND locked_by = $2 AND published_at IS NULL`,
		messageID, workerID, delay.Seconds(), reason)
	if err != nil {
		return fmt.Errorf("schedule chat outbox retry: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("read chat outbox retry result: %w", err)
	}
	if count != 1 {
		return fmt.Errorf("chat outbox lease lost while retrying message %s", messageID)
	}
	return nil
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
type ChatScope struct {
	CharacterID string
	WorldID string
	WorldInstanceID string
}

func (s *Service) CurrentChatScope(ctx context.Context, accountID string) (ChatScope, error) {
	if strings.TrimSpace(accountID) == "" {
		return ChatScope{}, ErrInvalidInput
	}
	var scope ChatScope
	scopeQuery := `SELECT c.character_id::text,c.world_id,COALESCE(ws.instance_id::text,'') FROM chat_accounts account JOIN chat_characters c ON c.character_id=account.current_character_id LEFT JOIN chat_world_sessions ws ON ws.character_id=c.character_id AND ws.session_state='active' WHERE account.account_id=$1::uuid AND c.status='alive'`
	err := s.db.QueryRowContext(ctx, scopeQuery, accountID).Scan(&scope.CharacterID,&scope.WorldID,&scope.WorldInstanceID)
	if errors.Is(err, sql.ErrNoRows) {
		return ChatScope{}, ErrNoCharacter
	}
	if err != nil {
		return ChatScope{}, fmt.Errorf("resolve current chat scope: %w", err)
	}
	return scope, nil
}

func (s *Service) CurrentWorldID(ctx context.Context, accountID string) (string, error) {
	if strings.TrimSpace(accountID) == "" {
		return "", ErrInvalidInput
	}
	var worldID string
	worldQuery := `SELECT c.world_id FROM chat_accounts account JOIN chat_characters c ON c.character_id=account.current_character_id WHERE account.account_id=$1::uuid AND c.status='alive'`
	err := s.db.QueryRowContext(ctx, worldQuery, accountID).Scan(&worldID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", ErrNoCharacter
	}
	if err != nil {
		return "", fmt.Errorf("resolve chat world: %w", err)
	}
	return worldID, nil
}
