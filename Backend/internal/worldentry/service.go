package worldentry

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"math"
	"time"
	"strings"
)

var (
	ErrNoAvailableServer = errors.New("no available world server")
	ErrInvalidTicket    = errors.New("invalid or expired world entry ticket")
	ErrInvalidSessionSnapshot = errors.New("invalid or unauthorized world session snapshot")
	ErrNoPendingDeath = errors.New("character has no pending death to respawn")
)

type Entry struct {
	WorldID   string    `json:"world_id"`
	Host      string    `json:"host"`
	UDPPort   int       `json:"udp_port"`
	Ticket    string    `json:"ticket"`
	ExpiresAt time.Time `json:"expires_at"`
}

type PlayerSnapshot struct {
	SessionID   string  `json:"session_id"`
	CharacterID string  `json:"character_id"`
	WorldID     string  `json:"world_id"`
	InstanceID  string  `json:"instance_id"`
	Name        string  `json:"name"`
	PositionX   float64 `json:"position_x"`
	PositionY   float64 `json:"position_y"`
	PositionZ   float64 `json:"position_z"`
	RotationY   float64 `json:"rotation_y"`
}

type SessionSnapshot struct {
	NodeKey     string
	SessionID   string
	CharacterID string
	PositionX   float64
	PositionY   float64
	PositionZ   float64
	RotationY   float64
	Health      *int
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
		   AND GREATEST(sr.current_players, (SELECT COUNT(*) FROM world_sessions ws WHERE ws.server_id = sr.id AND ws.session_state IN ('connecting', 'active', 'saving')))
		       + (SELECT COUNT(*) FROM world_entry_tickets pending WHERE pending.server_id = sr.id AND pending.expires_at > now() AND pending.consumed_at IS NULL) < sr.capacity
		   AND sr.last_heartbeat_at > now() - INTERVAL '30 seconds'
		 ORDER BY sr.current_players ASC, wi.created_at ASC
		 LIMIT 1 FOR UPDATE OF sr, c SKIP LOCKED`, accountID,
	).Scan(&characterID, &entry.WorldID, &instanceID, &serverID, &entry.Host, &entry.UDPPort)
	if errors.Is(err, sql.ErrNoRows) {
		return Entry{}, ErrNoAvailableServer
	}
	if err != nil {
		return Entry{}, fmt.Errorf("select world server: %w", err)
	}

	if _, err := tx.ExecContext(ctx, `UPDATE world_entry_tickets SET consumed_at = now() WHERE character_id = $1 AND consumed_at IS NULL`, characterID); err != nil {
		return Entry{}, fmt.Errorf("invalidate previous entry tickets: %w", err)
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
		 JOIN world_instances wi ON wi.id = t.instance_id AND wi.status = 'ready'
		 JOIN characters c ON c.id = t.character_id
		 WHERE t.token_hash = $1 AND t.expires_at > now() AND t.consumed_at IS NULL
		   AND sr.node_key = $2 AND sr.status = 'ready' AND sr.last_heartbeat_at > now() - INTERVAL '30 seconds'
		   AND c.status = 'alive'
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
	if err := tx.QueryRowContext(ctx,
		`INSERT INTO world_sessions (character_id, instance_id, server_id, session_state, connected_at)
		 VALUES ($1, $2, $3, 'active', now())
		 RETURNING id::text`, characterID, instanceID, serverID,
	).Scan(&snapshot.SessionID); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("create world session: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return PlayerSnapshot{}, fmt.Errorf("commit world ticket redemption: %w", err)
	}
	return snapshot, nil
}


// SavePosition periodically persists an authoritative position without ending the session.
// The node/session/character tuple is verified against the trusted server registry.
func (s *Service) SavePosition(ctx context.Context, input SessionSnapshot) error {
	if input.NodeKey == "" || len(input.NodeKey) > 96 ||
		input.SessionID == "" || input.CharacterID == "" ||
		math.IsNaN(input.PositionX) || math.IsInf(input.PositionX, 0) ||
		math.IsNaN(input.PositionY) || math.IsInf(input.PositionY, 0) ||
		math.IsNaN(input.PositionZ) || math.IsInf(input.PositionZ, 0) ||
		math.IsNaN(input.RotationY) || math.IsInf(input.RotationY, 0) ||
		input.PositionX < -100 || input.PositionX > 100 ||
		input.PositionZ < -100 || input.PositionZ > 100 ||
		input.PositionY < 0 || input.PositionY > 100 ||
		(input.Health != nil && (*input.Health < 0 || *input.Health > 100000)) {
		return ErrInvalidSessionSnapshot
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin periodic world snapshot: %w", err)
	}
	defer tx.Rollback()

	var state string
	err = tx.QueryRowContext(ctx,
		`SELECT ws.session_state
		 FROM world_sessions ws
		 JOIN server_registry sr ON sr.id = ws.server_id
		 WHERE ws.id = $1 AND ws.character_id = $2 AND sr.node_key = $3
		 FOR UPDATE OF ws`,
		input.SessionID, input.CharacterID, input.NodeKey,
	).Scan(&state)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInvalidSessionSnapshot
	}
	if err != nil {
		return fmt.Errorf("lock periodic world snapshot session: %w", err)
	}
	if state != "active" {
		return ErrInvalidSessionSnapshot
	}

	result, err := tx.ExecContext(ctx,
		`UPDATE characters
		 SET position_x = $2, position_y = $3, position_z = $4, rotation_y = $5, updated_at = now()
		 WHERE id = $1 AND status = 'alive'`,
		input.CharacterID, input.PositionX, input.PositionY, input.PositionZ, input.RotationY,
	)
	if err != nil {
		return fmt.Errorf("save periodic character position: %w", err)
	}
	if rows, rowsErr := result.RowsAffected(); rowsErr != nil {
		return fmt.Errorf("check periodic character rows: %w", rowsErr)
	} else if rows != 1 {
		return ErrInvalidSessionSnapshot
	}
	if input.Health != nil && *input.Health == 0 {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO character_death_events (character_id, session_id, world_id, death_reason)
			 SELECT ws.character_id, ws.id, c.world_id, 'combat'
			 FROM world_sessions ws
			 JOIN characters c ON c.id = ws.character_id
			 WHERE ws.id = $1 AND ws.character_id = $2
			 ON CONFLICT (session_id, character_id) DO NOTHING`,
			input.SessionID, input.CharacterID,
		); err != nil {
			return fmt.Errorf("record character death: %w", err)
		}
	}
	if input.Health != nil {
		result, err := tx.ExecContext(ctx,
			`UPDATE character_attributes SET health = LEAST($2, max_health), updated_at = now()
			 WHERE character_id = $1 AND max_health >= 1`,
			input.CharacterID, *input.Health,
		)
		if err != nil { return fmt.Errorf("save periodic character health: %w", err) }
		if rows, rowsErr := result.RowsAffected(); rowsErr != nil { return fmt.Errorf("check periodic health rows: %w", rowsErr) } else if rows != 1 { return ErrInvalidSessionSnapshot }
	}
	if _, err := tx.ExecContext(ctx, `UPDATE world_sessions SET updated_at = now() WHERE id = $1`, input.SessionID); err != nil {
		return fmt.Errorf("touch periodic world session: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit periodic world snapshot: %w", err)
	}
	return nil
}

// SaveAndClose persists the authoritative final position and closes the world session.
// The node/session/character tuple is verified against the trusted server registry.
func (s *Service) SaveAndClose(ctx context.Context, input SessionSnapshot) error {
	if input.NodeKey == "" || len(input.NodeKey) > 96 ||
		input.SessionID == "" || input.CharacterID == "" ||
		math.IsNaN(input.PositionX) || math.IsInf(input.PositionX, 0) ||
		math.IsNaN(input.PositionY) || math.IsInf(input.PositionY, 0) ||
		math.IsNaN(input.PositionZ) || math.IsInf(input.PositionZ, 0) ||
		math.IsNaN(input.RotationY) || math.IsInf(input.RotationY, 0) ||
		input.PositionX < -100 || input.PositionX > 100 ||
		input.PositionZ < -100 || input.PositionZ > 100 ||
		input.PositionY < 0 || input.PositionY > 100 ||
		(input.Health != nil && (*input.Health < 0 || *input.Health > 100000)) {
		return ErrInvalidSessionSnapshot
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin world session snapshot: %w", err)
	}
	defer tx.Rollback()

	var state string
	err = tx.QueryRowContext(ctx,
		`SELECT ws.session_state
		 FROM world_sessions ws
		 JOIN server_registry sr ON sr.id = ws.server_id
		 WHERE ws.id = $1 AND ws.character_id = $2 AND sr.node_key = $3
		 FOR UPDATE OF ws`,
		input.SessionID, input.CharacterID, input.NodeKey,
	).Scan(&state)
	if errors.Is(err, sql.ErrNoRows) {
		return ErrInvalidSessionSnapshot
	}
	if err != nil {
		return fmt.Errorf("lock world session snapshot: %w", err)
	}
	if state == "closed" {
		return tx.Commit()
	}
	if state != "active" && state != "saving" {
		return ErrInvalidSessionSnapshot
	}

	result, err := tx.ExecContext(ctx,
		`UPDATE characters
		 SET position_x = $2, position_y = $3, position_z = $4, rotation_y = $5, updated_at = now()
		 WHERE id = $1 AND status = 'alive'`,
		input.CharacterID, input.PositionX, input.PositionY, input.PositionZ, input.RotationY,
	)
	if err != nil {
		return fmt.Errorf("save character world position: %w", err)
	}
	if rows, rowsErr := result.RowsAffected(); rowsErr != nil {
		return fmt.Errorf("check saved character rows: %w", rowsErr)
	} else if rows != 1 {
		return ErrInvalidSessionSnapshot
	}

	if input.Health != nil && *input.Health == 0 {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO character_death_events (character_id, session_id, world_id, death_reason)
			 SELECT ws.character_id, ws.id, c.world_id, 'combat'
			 FROM world_sessions ws
			 JOIN characters c ON c.id = ws.character_id
			 WHERE ws.id = $1 AND ws.character_id = $2
			 ON CONFLICT (session_id, character_id) DO NOTHING`,
			input.SessionID, input.CharacterID,
		); err != nil {
			return fmt.Errorf("record final character death: %w", err)
		}
	}
	if input.Health != nil {
		result, err := tx.ExecContext(ctx,
			`UPDATE character_attributes SET health = LEAST($2, max_health), updated_at = now()
			 WHERE character_id = $1 AND max_health >= 1`,
			input.CharacterID, *input.Health,
		)
		if err != nil { return fmt.Errorf("save final character health: %w", err) }
		if rows, rowsErr := result.RowsAffected(); rowsErr != nil { return fmt.Errorf("check final health rows: %w", rowsErr) } else if rows != 1 { return ErrInvalidSessionSnapshot }
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE world_sessions
		 SET session_state = 'closed', disconnected_at = now(), updated_at = now()
		 WHERE id = $1`, input.SessionID,
	); err != nil {
		return fmt.Errorf("close world session: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit world session snapshot: %w", err)
	}
	return nil
}

// RespawnCurrent returns a dead current life to the underworld while preserving
// its soul, progression, inventory and equipment. Only a recorded death can be respawned.
func (s *Service) RespawnCurrent(ctx context.Context, accountID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return fmt.Errorf("begin character respawn: %w", err) }
	defer tx.Rollback()
	var characterID string
	var maxHealth int
	var deathID string
	err = tx.QueryRowContext(ctx,
		`SELECT c.id::text, a.max_health, d.id::text
		 FROM souls soul
		 JOIN characters c ON c.id = soul.current_character_id
		 JOIN character_attributes a ON a.character_id = c.id
		 JOIN LATERAL (
		   SELECT id FROM character_death_events
		   WHERE character_id = c.id AND respawned_at IS NULL
		   ORDER BY died_at DESC LIMIT 1 FOR UPDATE
		 ) d ON true
		 WHERE soul.account_id = $1 AND a.health = 0 AND c.status = 'alive'
		 FOR UPDATE OF c, a`,
		accountID,
	).Scan(&characterID, &maxHealth, &deathID)
	if errors.Is(err, sql.ErrNoRows) { return ErrNoPendingDeath }
	if err != nil { return fmt.Errorf("load pending character death: %w", err) }
	if maxHealth < 1 { return ErrInvalidSessionSnapshot }
	if _, err := tx.ExecContext(ctx,
		`UPDATE world_sessions SET session_state = 'closed', disconnected_at = COALESCE(disconnected_at, now()), updated_at = now()
		 WHERE id = (SELECT session_id FROM character_death_events WHERE id = $1)
		   AND session_state IN ('connecting', 'active', 'saving')`,
		deathID,
	); err != nil { return fmt.Errorf("close dead world session before respawn: %w", err) }
	if _, err := tx.ExecContext(ctx,
		`UPDATE characters SET world_id = 'underworld_fengdu',
		 position_x = 0, position_y = 0, position_z = 0, rotation_y = 0, updated_at = now()
		 WHERE id = $1`, characterID,
	); err != nil { return fmt.Errorf("move respawned character to Fengdu: %w", err) }
	if _, err := tx.ExecContext(ctx,
		`UPDATE character_attributes SET health = max_health, mana = max_mana, updated_at = now()
		 WHERE character_id = $1`, characterID,
	); err != nil { return fmt.Errorf("restore respawned character attributes: %w", err) }
	if _, err := tx.ExecContext(ctx,
		`UPDATE character_death_events SET respawned_at = now(), respawn_world_id = 'underworld_fengdu'
		 WHERE id = $1 AND respawned_at IS NULL`, deathID,
	); err != nil { return fmt.Errorf("complete character respawn record: %w", err) }
	if err := tx.Commit(); err != nil { return fmt.Errorf("commit character respawn: %w", err) }
	return nil
}


// RequestDisconnect marks all active world sessions for an account as saving.
// WorldServer's next authoritative snapshot receives HTTP 409, which causes it
// to disconnect the ENet peer and persist the final snapshot through SaveAndClose.
func (s *Service) RequestDisconnect(ctx context.Context, accountID string) (int64, error) {
	if strings.TrimSpace(accountID) == "" {
		return 0, ErrInvalidSessionSnapshot
	}
	result, err := s.db.ExecContext(ctx, `
		UPDATE world_sessions ws
		SET session_state = 'saving', updated_at = now()
		FROM characters c
		JOIN souls soul ON soul.id = c.soul_id
		WHERE ws.character_id = c.id
		  AND soul.account_id = $1::uuid
		  AND ws.session_state = 'active'
	`, accountID)
	if err != nil {
		return 0, fmt.Errorf("request player world disconnect: %w", err)
	}
	count, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("read requested player disconnect count: %w", err)
	}
	return count, nil
}
