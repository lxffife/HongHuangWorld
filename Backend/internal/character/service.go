package character

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

var (
	ErrSoulRequired = errors.New("soul profile required")
	ErrWorldInvalid = errors.New("world is unavailable")
	ErrExists       = errors.New("first-life character already exists")
	ErrInvalid      = errors.New("invalid character name")
)

type Character struct {
	ID        string  `json:"id"`
	SoulID    string  `json:"soul_id"`
	LifeIndex int     `json:"life_index"`
	WorldID   string  `json:"world_id"`
	Name      string  `json:"name"`
	RaceID    *string `json:"race_id,omitempty"`
	Level     int     `json:"level"`
	Status    string  `json:"status"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

func (s *Service) CreateFirstLife(ctx context.Context, accountID, name, worldID, raceID string) (Character, error) {
	name = strings.TrimSpace(name)
	worldID = strings.TrimSpace(worldID)
	raceID = strings.TrimSpace(raceID)
	if len([]rune(name)) < 2 || len([]rune(name)) > 24 || worldID == "" || len(raceID) > 64 {
		return Character{}, ErrInvalid
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Character{}, fmt.Errorf("begin character creation: %w", err)
	}
	defer tx.Rollback()

	var soulID string
	var currentCharacter sql.NullString
	err = tx.QueryRowContext(ctx,
		`SELECT id::text, current_character_id::text FROM souls WHERE account_id = $1 FOR UPDATE`, accountID,
	).Scan(&soulID, &currentCharacter)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, ErrSoulRequired
	}
	if err != nil {
		return Character{}, fmt.Errorf("load soul for character creation: %w", err)
	}
	if currentCharacter.Valid {
		return Character{}, ErrExists
	}

	var enabled bool
	if err := tx.QueryRowContext(ctx, `SELECT enabled FROM world_definitions WHERE id = $1`, worldID).Scan(&enabled); err != nil || !enabled {
		return Character{}, ErrWorldInvalid
	}

	var result Character
	var race sql.NullString
	err = tx.QueryRowContext(ctx,
		`INSERT INTO characters (soul_id, life_index, world_id, name, race_id)
		 VALUES ($1, 1, $2, $3, NULLIF($4, ''))
		 RETURNING id::text, soul_id::text, life_index, world_id, name, race_id, level, status`,
		soulID, worldID, name, raceID,
	).Scan(&result.ID, &result.SoulID, &result.LifeIndex, &result.WorldID, &result.Name, &race, &result.Level, &result.Status)
	if err != nil {
		return Character{}, fmt.Errorf("insert first-life character: %w", err)
	}
	if race.Valid {
		result.RaceID = &race.String
	}
	if _, err := tx.ExecContext(ctx, `UPDATE souls SET current_character_id = $1, updated_at = now() WHERE id = $2`, result.ID, soulID); err != nil {
		return Character{}, fmt.Errorf("set current character: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Character{}, fmt.Errorf("commit character creation: %w", err)
	}
	return result, nil
}

func (s *Service) Current(ctx context.Context, accountID string) (Character, error) {
	var result Character
	var race sql.NullString
	err := s.db.QueryRowContext(ctx,
		`SELECT c.id::text, c.soul_id::text, c.life_index, c.world_id, c.name, c.race_id, c.level, c.status
		 FROM souls s JOIN characters c ON c.id = s.current_character_id
		 WHERE s.account_id = $1`, accountID,
	).Scan(&result.ID, &result.SoulID, &result.LifeIndex, &result.WorldID, &result.Name, &race, &result.Level, &result.Status)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, sql.ErrNoRows
	}
	if err != nil {
		return Character{}, fmt.Errorf("load current character: %w", err)
	}
	if race.Valid {
		result.RaceID = &race.String
	}
	return result, nil
}
