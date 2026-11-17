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
	Quantity int `json:"quantity,omitempty"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
	Description string `json:"description"`
}


type LootEntry struct {
	MonsterID string `json:"monster_id"`
	ItemID string `json:"item_id"`
	ItemName string `json:"item_name"`
	Quality int `json:"quality"`
	DropChanceBP int `json:"drop_chance_bp"`
	MinQuantity int `json:"min_quantity"`
	MaxQuantity int `json:"max_quantity"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
}

type GroundDrop struct {
	ID string `json:"id"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
	ExpiresAt string `json:"expires_at"`
}


type GroundDropSnapshot struct {
	ID string `json:"id"`
	SessionID string `json:"session_id"`
	OwnerCharacterID string `json:"owner_character_id"`
	ItemID string `json:"item_id"`
	ItemName string `json:"item_name"`
	Quality int `json:"quality"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
	RemainingSeconds int `json:"remaining_seconds"`
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


func (s *Service) ListLootTable(ctx context.Context) ([]LootEntry, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT ml.monster_id, i.id, i.name, i.quality,
		ml.drop_chance_bp, ml.min_quantity, ml.max_quantity, i.max_stack, i.icon_key
		FROM monster_loot_entries ml
		JOIN item_definitions i ON i.id = ml.item_id
		WHERE i.enabled
		ORDER BY ml.monster_id, i.quality DESC, i.id`)
	if err != nil { return nil, fmt.Errorf("list monster loot table: %w", err) }
	defer rows.Close()
	entries := make([]LootEntry, 0)
	for rows.Next() {
		var entry LootEntry
		if err := rows.Scan(&entry.MonsterID, &entry.ItemID, &entry.ItemName, &entry.Quality,
			&entry.DropChanceBP, &entry.MinQuantity, &entry.MaxQuantity, &entry.MaxStack, &entry.IconKey); err != nil {
			return nil, fmt.Errorf("scan monster loot entry: %w", err)
		}
		entries = append(entries, entry)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate monster loot table: %w", err) }
	return entries, nil
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

func (s *Service) ListGroundDrops(ctx context.Context, nodeKey string) ([]GroundDropSnapshot, error) {
	if strings.TrimSpace(nodeKey) == "" { return nil, ErrInvalidRequest }
	rows, err := s.db.QueryContext(ctx, `SELECT d.id::text, d.session_id::text, d.owner_character_id::text,
		d.item_id, i.name, i.quality, d.quantity, d.position_x, d.position_z,
		GREATEST(0, CEIL(EXTRACT(EPOCH FROM (d.expires_at - now()))))::integer
		FROM ground_drops d
		JOIN server_registry s ON s.id = d.server_id
		JOIN item_definitions i ON i.id = d.item_id
		WHERE s.node_key = $1 AND d.status = 'available' AND d.expires_at > now()
		ORDER BY d.created_at`, nodeKey)
	if err != nil { return nil, fmt.Errorf("list persisted ground drops: %w", err) }
	defer rows.Close()
	drops := make([]GroundDropSnapshot, 0)
	for rows.Next() {
		var drop GroundDropSnapshot
		if err := rows.Scan(&drop.ID, &drop.SessionID, &drop.OwnerCharacterID, &drop.ItemID,
			&drop.ItemName, &drop.Quality, &drop.Quantity, &drop.PositionX, &drop.PositionZ,
			&drop.RemainingSeconds); err != nil {
			return nil, fmt.Errorf("scan persisted ground drop: %w", err)
		}
		drops = append(drops, drop)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate persisted ground drops: %w", err) }
	return drops, nil
}

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
	if errors.Is(err, sql.ErrNoRows) {
		// A retry after a lost HTTP response must return the same persisted drop,
		// but reusing an ID with different contents must never mutate it.
		err = tx.QueryRowContext(ctx, `SELECT id::text, item_id, quantity, position_x, position_z, expires_at::text
			FROM ground_drops
			WHERE id = $1::uuid AND server_id = $2 AND session_id = $3::uuid
			  AND owner_character_id = $4::uuid AND item_id = $5 AND quantity = $6
			  AND position_x = $7 AND position_z = $8 AND status = 'available' AND expires_at > now()`,
			request.DropID, serverID, request.SessionID, request.CharacterID, request.ItemID,
			request.Quantity, request.PositionX, request.PositionZ).
			Scan(&result.ID, &result.ItemID, &result.Quantity, &result.PositionX, &result.PositionZ, &result.ExpiresAt)
		if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrDropUnavailable }
	}
	if err != nil { return GroundDrop{}, fmt.Errorf("create or recover ground drop: %w", err) }
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
		WHERE id = $1::uuid AND server_id = $2
		  AND owner_character_id = $3::uuid AND status = 'available' AND expires_at > now()
		FOR UPDATE`, request.DropID, serverID, request.CharacterID).Scan(&itemID, &quantity)
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
