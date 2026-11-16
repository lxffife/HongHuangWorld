package inventory

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math"
	"strings"
)

var (
	ErrInvalidRequest = errors.New("invalid inventory request")
	ErrSessionInvalid = errors.New("world session is not active on this server")
	ErrDropUnavailable = errors.New("drop is unavailable")
	ErrInventoryFull = errors.New("inventory stack is full")
)

type ItemStack struct {
	ItemID string `json:"item_id"`
	Name string `json:"name"`
	Category string `json:"category"`
	Quality int `json:"quality"`
	Quantity int `json:"quantity"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
	Description string `json:"description"`
}

type GroundDrop struct {
	ID string `json:"id"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
	ExpiresAt string `json:"expires_at"`
}

type DropRequest struct {
	DropID string
	SessionID string
	CharacterID string
	ItemID string
	Quantity int
	PositionX float64
	PositionZ float64
}

type PickupRequest struct {
	EventID string
	DropID string
	SessionID string
	CharacterID string
}

type Result struct { Applied bool `json:"applied"` }

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

func (s *Service) ListItems(ctx context.Context) ([]ItemStack, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id, name, category, quality, max_stack, icon_key, description
		FROM item_definitions WHERE enabled ORDER BY quality DESC, category, id`)
	if err != nil { return nil, fmt.Errorf("list item definitions: %w", err) }
	defer rows.Close()
	items := make([]ItemStack, 0)
	for rows.Next() {
		var item ItemStack
		if err := rows.Scan(&item.ItemID, &item.Name, &item.Category, &item.Quality, &item.MaxStack, &item.IconKey, &item.Description); err != nil {
			return nil, fmt.Errorf("scan item definition: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate item definitions: %w", err) }
	return items, nil
}

func (s *Service) CurrentInventory(ctx context.Context, accountID string) ([]ItemStack, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT i.id, i.name, i.category, i.quality, ci.quantity, i.max_stack, i.icon_key, i.description
		FROM souls soul
		JOIN characters c ON c.id = soul.current_character_id
		JOIN character_inventory ci ON ci.character_id = c.id
		JOIN item_definitions i ON i.id = ci.item_id
		WHERE soul.account_id = $1 AND c.status = 'alive'
		ORDER BY i.quality DESC, i.name`, accountID)
	if err != nil { return nil, fmt.Errorf("load current character inventory: %w", err) }
	defer rows.Close()
	items := make([]ItemStack, 0)
	for rows.Next() {
		var item ItemStack
		if err := rows.Scan(&item.ItemID, &item.Name, &item.Category, &item.Quality, &item.Quantity, &item.MaxStack, &item.IconKey, &item.Description); err != nil {
			return nil, fmt.Errorf("scan inventory stack: %w", err)
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate inventory: %w", err) }
	return items, nil
}

// CreateDrop is called only by an authenticated world server after its own
// authoritative loot roll. The server supplies the item and quantity.
func (s *Service) CreateDrop(ctx context.Context, nodeKey string, request DropRequest) (GroundDrop, error) {
	if strings.TrimSpace(nodeKey) == "" || !validUUID(request.DropID) || !validUUID(request.SessionID) ||
		!validUUID(request.CharacterID) || strings.TrimSpace(request.ItemID) == "" ||
		request.Quantity < 1 || request.Quantity > 9999 ||
		math.IsNaN(request.PositionX) || math.IsInf(request.PositionX, 0) ||
		math.IsNaN(request.PositionZ) || math.IsInf(request.PositionZ, 0) {
		return GroundDrop{}, ErrInvalidRequest
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return GroundDrop{}, fmt.Errorf("begin ground drop: %w", err) }
	defer tx.Rollback()
	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrSessionInvalid }
		return GroundDrop{}, fmt.Errorf("resolve drop server: %w", err)
	}
	var maxStack int
	if err := tx.QueryRowContext(ctx, `SELECT max_stack FROM item_definitions WHERE id = $1 AND enabled`, request.ItemID).Scan(&maxStack); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrInvalidRequest }
		return GroundDrop{}, fmt.Errorf("load drop item: %w", err)
	}
	if request.Quantity > maxStack { return GroundDrop{}, ErrInvalidRequest }
	var valid bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM world_sessions WHERE id = $1::uuid AND server_id = $2 AND character_id = $3::uuid AND session_state = 'active'
	)`, request.SessionID, serverID, request.CharacterID).Scan(&valid); err != nil {
		return GroundDrop{}, fmt.Errorf("verify drop session: %w", err)
	}
	if !valid { return GroundDrop{}, ErrSessionInvalid }
	var result GroundDrop
	err = tx.QueryRowContext(ctx, `INSERT INTO ground_drops
		(id, server_id, session_id, owner_character_id, item_id, quantity, position_x, position_z, expires_at)
		VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5, $6, $7, $8, now() + INTERVAL '15 minutes')
		ON CONFLICT (server_id, id) DO NOTHING
		RETURNING id::text, item_id, quantity, position_x, position_z, expires_at::text`,
		request.DropID, serverID, request.SessionID, request.CharacterID, request.ItemID, request.Quantity, request.PositionX, request.PositionZ).
		Scan(&result.ID, &result.ItemID, &result.Quantity, &result.PositionX, &result.PositionZ, &result.ExpiresAt)
	if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrDropUnavailable }
	if err != nil { return GroundDrop{}, fmt.Errorf("create ground drop: %w", err) }
	if err := tx.Commit(); err != nil { return GroundDrop{}, fmt.Errorf("commit ground drop: %w", err) }
	return result, nil
}

// PickupDrop is called after the WorldServer has validated range and pickup
// permissions. The DB transaction consumes one drop and adds one inventory stack.
func (s *Service) PickupDrop(ctx context.Context, nodeKey string, request PickupRequest) (Result, error) {
	if strings.TrimSpace(nodeKey) == "" || !validUUID(request.EventID) || !validUUID(request.DropID) ||
		!validUUID(request.SessionID) || !validUUID(request.CharacterID) {
		return Result{}, ErrInvalidRequest
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Result{}, fmt.Errorf("begin item pickup: %w", err) }
	defer tx.Rollback()
	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return Result{}, ErrSessionInvalid }
		return Result{}, fmt.Errorf("resolve pickup server: %w", err)
	}
	var duplicate bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM item_pickup_events WHERE server_id = $1 AND event_id = $2::uuid)`, serverID, request.EventID).Scan(&duplicate); err != nil {
		return Result{}, fmt.Errorf("check pickup idempotency: %w", err)
	}
	if duplicate {
		if err := tx.Commit(); err != nil { return Result{}, fmt.Errorf("commit duplicate pickup: %w", err) }
		return Result{Applied: false}, nil
	}
	var validSession bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM world_sessions WHERE id = $1::uuid AND server_id = $2 AND character_id = $3::uuid AND session_state = 'active'
	)`, request.SessionID, serverID, request.CharacterID).Scan(&validSession); err != nil {
		return Result{}, fmt.Errorf("verify pickup session: %w", err)
	}
	if !validSession { return Result{}, ErrSessionInvalid }
	var itemID string
	var quantity int
	err = tx.QueryRowContext(ctx, `SELECT item_id, quantity FROM ground_drops
		WHERE id = $1::uuid AND server_id = $2 AND session_id = $3::uuid
		  AND owner_character_id = $4::uuid AND status = 'available' AND expires_at > now()
		FOR UPDATE`, request.DropID, serverID, request.SessionID, request.CharacterID).Scan(&itemID, &quantity)
	if errors.Is(err, sql.ErrNoRows) { return Result{}, ErrDropUnavailable }
	if err != nil { return Result{}, fmt.Errorf("lock ground drop: %w", err) }
	var maxStack int
	if err := tx.QueryRowContext(ctx, `SELECT max_stack FROM item_definitions WHERE id = $1 AND enabled`, itemID).Scan(&maxStack); err != nil {
		return Result{}, fmt.Errorf("load pickup item definition: %w", err)
	}
	var current int
	err = tx.QueryRowContext(ctx, `SELECT quantity FROM character_inventory WHERE character_id = $1::uuid AND item_id = $2 FOR UPDATE`, request.CharacterID, itemID).Scan(&current)
	if err != nil && !errors.Is(err, sql.ErrNoRows) { return Result{}, fmt.Errorf("lock inventory stack: %w", err) }
	if current + quantity > maxStack { return Result{}, ErrInventoryFull }
	if _, err := tx.ExecContext(ctx, `INSERT INTO character_inventory (character_id, item_id, quantity)
		VALUES ($1::uuid, $2, $3)
		ON CONFLICT (character_id, item_id) DO UPDATE SET quantity = character_inventory.quantity + EXCLUDED.quantity, updated_at = now()`,
		request.CharacterID, itemID, quantity); err != nil {
		return Result{}, fmt.Errorf("apply inventory stack: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `UPDATE ground_drops SET status = 'picked', picked_by_character_id = $1::uuid, picked_at = now(), updated_at = now()
		WHERE id = $2::uuid AND server_id = $3 AND status = 'available'`, request.CharacterID, request.DropID, serverID); err != nil {
		return Result{}, fmt.Errorf("consume ground drop: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO item_pickup_events (server_id, event_id, drop_id, character_id, item_id, quantity)
		VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, $6)`, serverID, request.EventID, request.DropID, request.CharacterID, itemID, quantity); err != nil {
		return Result{}, fmt.Errorf("record pickup event: %w", err)
	}
	if err := tx.Commit(); err != nil { return Result{}, fmt.Errorf("commit item pickup: %w", err) }
	return Result{Applied: true}, nil
}

func validUUID(value string) bool {
	if len(value) != 36 { return false }
	for i, char := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 { if char != '-' { return false }; continue }
		if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')) { return false }
	}
	return true
}
