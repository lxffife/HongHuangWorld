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

type Attributes struct {
	Strength      int     `json:"strength"`
	Constitution  int     `json:"constitution"`
	Agility       int     `json:"agility"`
	Spirit        int     `json:"spirit"`
	Vitality      int     `json:"vitality"`
	Health        int     `json:"health"`
	MaxHealth     int     `json:"max_health"`
	Mana          int     `json:"mana"`
	MaxMana       int     `json:"max_mana"`
	Attack        int     `json:"attack"`
	Defense       int     `json:"defense"`
	MovementSpeed float64 `json:"movement_speed"`
}

type Progression struct {
	Experience             int64  `json:"experience"`
	Cultivation            int64  `json:"cultivation"`
	RealmID                string `json:"realm_id"`
	RealmName              string `json:"realm_name"`
	RealmOrder             int    `json:"realm_order"`
	RealmStage             int    `json:"realm_stage"`
	MaxRealmStage          int    `json:"max_realm_stage"`
	RequiredForNextRealm   *int64 `json:"required_for_next_realm,omitempty"`
	UnspentAttributePoints int    `json:"unspent_attribute_points"`
}

type Status struct {
	Character   Character   `json:"character"`
	Attributes  Attributes  `json:"attributes"`
	Progression Progression `json:"progression"`
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

	if _, err := tx.ExecContext(ctx, `INSERT INTO character_attributes (character_id) VALUES ($1)`, result.ID); err != nil {
		return Character{}, fmt.Errorf("initialize character attributes: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO character_progression (character_id) VALUES ($1)`, result.ID); err != nil {
		return Character{}, fmt.Errorf("initialize character progression: %w", err)
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

func (s *Service) CurrentStatus(ctx context.Context, accountID string) (Status, error) {
	var result Status
	var race sql.NullString
	var required sql.NullInt64
	err := s.db.QueryRowContext(ctx,
		`SELECT
			c.id::text, c.soul_id::text, c.life_index, c.world_id, c.name, c.race_id, c.level, c.status,
			a.strength, a.constitution, a.agility, a.spirit, a.vitality,
			a.health, a.max_health, a.mana, a.max_mana, a.attack, a.defense, a.movement_speed,
			p.experience, p.cultivation, p.realm_id, rd.name, rd.realm_order, p.realm_stage,
			rd.max_stage, next_realm.required_cultivation, p.unspent_attribute_points
		 FROM souls s
		 JOIN characters c ON c.id = s.current_character_id
		 JOIN character_attributes a ON a.character_id = c.id
		 JOIN character_progression p ON p.character_id = c.id
		 JOIN realm_definitions rd ON rd.id = p.realm_id
		 LEFT JOIN realm_definitions next_realm ON next_realm.realm_order = rd.realm_order + 1
		 WHERE s.account_id = $1`, accountID,
	).Scan(
		&result.Character.ID, &result.Character.SoulID, &result.Character.LifeIndex,
		&result.Character.WorldID, &result.Character.Name, &race, &result.Character.Level, &result.Character.Status,
		&result.Attributes.Strength, &result.Attributes.Constitution, &result.Attributes.Agility,
		&result.Attributes.Spirit, &result.Attributes.Vitality, &result.Attributes.Health,
		&result.Attributes.MaxHealth, &result.Attributes.Mana, &result.Attributes.MaxMana,
		&result.Attributes.Attack, &result.Attributes.Defense, &result.Attributes.MovementSpeed,
		&result.Progression.Experience, &result.Progression.Cultivation, &result.Progression.RealmID,
		&result.Progression.RealmName, &result.Progression.RealmOrder, &result.Progression.RealmStage,
		&result.Progression.MaxRealmStage, &required, &result.Progression.UnspentAttributePoints,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return Status{}, sql.ErrNoRows
	}
	if err != nil {
		return Status{}, fmt.Errorf("load current character status: %w", err)
	}
	if race.Valid {
		result.Character.RaceID = &race.String
	}
	if required.Valid {
		result.Progression.RequiredForNextRealm = &required.Int64
	}
	return result, nil
}
