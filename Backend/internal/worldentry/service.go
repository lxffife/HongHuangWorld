package worldentry

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"time"
)

var (
	ErrNoAvailableServer = errors.New("no available world server")
	ErrInvalidTicket    = errors.New("invalid or expired world entry ticket")
)

type Entry struct {
	WorldID   string    `json:"world_id"`
	Host      string    `json:"host"`
	UDPPort   int       `json:"udp_port"`
	Ticket    string    `json:"ticket"`
	ExpiresAt time.Time `json:"expires_at"`
}

type PlayerSnapshot struct {
	CharacterID string  `json:"character_id"`
	WorldID     string  `json:"world_id"`
	InstanceID  string  `json:"instance_id"`
	Name        string  `json:"name"`
	PositionX   float64 `json:"position_x"`
	PositionY   float64 `json:"position_y"`
	PositionZ   float64 `json:"position_z"`
	RotationY   float64 `json:"rotation_y"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

func (s *Service) Issue(ctx context.Context, accountID string) (Entry, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Entry{}, fmt.Errorf("begin world entry: %w", err)
	}
	defer tx.Rollback()

	var entry Entry
	var characterID, instanceID, serverID string
	err = tx.QueryRowContext(ctx,
		`SELECT c.id::text, c.world_id, wi.id::text, sr.id::text, sr.host, sr.udp_port
		 FROM souls s
		 JOIN characters c ON c.id = s.current_character_id
		 JOIN world_instances wi ON wi.world_id = c.world_id AND wi.status = 'ready'
		 JOIN server_registry sr ON sr.id = wi.server_id
		 WHERE s.account_id = $1 AND c.status = 'alive' AND sr.status = 'ready'
		   AND sr.current_players < sr.capacity
		   AND sr.last_heartbeat_at > now() - INTERVAL '30 seconds'
		 ORDER BY sr.current_players ASC, wi.created_at ASC
		 LIMIT 1 FOR UPDATE OF sr SKIP LOCKED`, accountID,
	).Scan(&characterID, &entry.WorldID, &instanceID, &serverID, &entry.Host, &entry.UDPPort)
	if errors.Is(err, sql.ErrNoRows) {
		return Entry{}, ErrNoAvailableServer
	}
	if err != nil {
		return Entry{}, fmt.Errorf("select world server: %w", err)
	}

	var raw [32]byte
	if _, err := rand.Read(raw[:]); err != nil {
		return Entry{}, fmt.Errorf("generate world entry ticket: %w", err)
	}
	entry.Ticket = base64.RawURLEncoding.EncodeToString(raw[:])
	entry.ExpiresAt = time.Now().UTC().Add(60 * time.Second)
	tokenHash := sha256.Sum256([]byte(entry.Ticket))
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO world_entry_tickets (token_hash, character_id, instance_id, server_id, expires_at)
		 VALUES ($1, $2, $3, $4, $5)`, tokenHash[:], characterID, instanceID, serverID, entry.ExpiresAt,
	); err != nil {
		return Entry{}, fmt.Errorf("store world entry ticket: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Entry{}, fmt.Errorf("commit world entry ticket: %w", err)
	}
	return entry, nil
}

func (s *Service) Redeem(ctx context.Context, nodeKey, ticket string) (PlayerSnapshot, error) {
	if nodeKey == "" || ticket == "" || len(ticket) > 128 {
		return PlayerSnapshot{}, ErrInvalidTicket
	}
	tokenHash := sha256.Sum256([]byte(ticket))
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return PlayerSnapshot{}, fmt.Errorf("begin ticket redemption: %w", err)
	}
	defer tx.Rollback()

	var ticketID, characterID, instanceID, serverID string
	var snapshot PlayerSnapshot
	err = tx.QueryRowContext(ctx,
		`SELECT t.id::text, c.id::text, t.instance_id::text, t.server_id::text,
		        c.world_id, c.name, c.position_x, c.position_y, c.position_z, c.rotation_y
		 FROM world_entry_tickets t
		 JOIN server_registry sr ON sr.id = t.server_id
		 JOIN characters c ON c.id = t.character_id
		 WHERE t.token_hash = $1 AND t.expires_at > now() AND t.consumed_at IS NULL
		   AND sr.node_key = $2 AND sr.status = 'ready'
		 FOR UPDATE OF t`, tokenHash[:], nodeKey,
	).Scan(&ticketID, &characterID, &instanceID, &serverID, &snapshot.WorldID, &snapshot.Name,
		&snapshot.PositionX, &snapshot.PositionY, &snapshot.PositionZ, &snapshot.RotationY)
	if errors.Is(err, sql.ErrNoRows) {
		return PlayerSnapshot{}, ErrInvalidTicket
	}
	if err != nil {
		return PlayerSnapshot{}, fmt.Errorf("load world entry ticket: %w", err)
	}
	snapshot.CharacterID = characterID
	snapshot.InstanceID = instanceID

	if _, err := tx.ExecContext(ctx, `UPDATE world_entry_tickets SET consumed_at = now() WHERE id = $1`, ticketID); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("consume world entry ticket: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE world_sessions SET session_state = 'closed', disconnected_at = now(), updated_at = now()
		 WHERE character_id = $1 AND session_state IN ('connecting', 'active', 'saving')`, characterID,
	); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("close previous world session: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO world_sessions (character_id, instance_id, server_id, session_state, connected_at)
		 VALUES ($1, $2, $3, 'active', now())`, characterID, instanceID, serverID,
	); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("create world session: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("commit world ticket redemption: %w", err)
	}
	return snapshot, nil
}
