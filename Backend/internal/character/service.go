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
	ErrInvalidAllocation = errors.New("invalid attribute allocation")
	ErrInsufficientPoints = errors.New("insufficient unspent attribute points")
	ErrInvalidReward = errors.New("invalid character reward")
	ErrRewardSession = errors.New("character has no active session on this server")
	ErrInvalidRace = errors.New("race has no configured default cultivation system")
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
	SystemID               string `json:"system_id"`
	SystemName             string `json:"system_name"`
	RealmID                string `json:"realm_id"`
	RealmName              string `json:"realm_name"`
	RealmOrder             int    `json:"realm_order"`
	RealmStage             int    `json:"realm_stage"`
	RealmStageName         string `json:"realm_stage_name"`
	MaxRealmStage          int    `json:"max_realm_stage"`
	RequiredForNextRealm   *int64 `json:"required_for_next_realm,omitempty"`
	PowerTierID            string `json:"power_tier_id,omitempty"`
	PowerTierName          string `json:"power_tier_name,omitempty"`
	PowerTierOrder         int    `json:"power_tier_order,omitempty"`
	PowerComparisonNote    string `json:"power_comparison_note,omitempty"`
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
	if raceID == "" {
		raceID = "human"
	}
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

	var systemID, firstRealmID string
	err = tx.QueryRowContext(ctx,
		`SELECT mapping.system_id, realm.id
		 FROM race_cultivation_systems mapping
		 JOIN cultivation_realms realm ON realm.system_id = mapping.system_id AND realm.realm_order = 1
		 WHERE mapping.race_id = $1 AND mapping.is_default`, raceID,
	).Scan(&systemID, &firstRealmID)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, ErrInvalidRace
	}
	if err != nil {
		return Character{}, fmt.Errorf("resolve race cultivation system: %w", err)
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
	if _, err := tx.ExecContext(ctx, `INSERT INTO character_progression (character_id, system_id, realm_id) VALUES ($1, $2, $3)`, result.ID, systemID, firstRealmID); err != nil {
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

type Reward struct {
	EventID        string `json:"event_id"`
	CharacterID    string `json:"character_id"`
	Experience     int64  `json:"experience"`
	Cultivation    int64  `json:"cultivation"`
	AttributePoints int   `json:"attribute_points"`
}

type RewardResult struct {
	Applied bool `json:"applied"`
}

// ApplyServerReward accepts rewards only from the node hosting the character's
// active session. A per-node event ID makes retries safe and prevents double grants.
func (s *Service) ApplyServerReward(ctx context.Context, nodeKey string, reward Reward) (RewardResult, error) {
	if !validReward(nodeKey, reward) {
		return RewardResult{}, ErrInvalidReward
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return RewardResult{}, fmt.Errorf("begin character reward: %w", err)
	}
	defer tx.Rollback()

	var serverID string
	err = tx.QueryRowContext(ctx,
		`SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey,
	).Scan(&serverID)
	if errors.Is(err, sql.ErrNoRows) {
		return RewardResult{}, ErrRewardSession
	}
	if err != nil {
		return RewardResult{}, fmt.Errorf("resolve world server for reward: %w", err)
	}

	// A previously committed event remains idempotent even if the player has
	// disconnected before the node could retry after a lost response.
	var alreadyApplied bool
	if err := tx.QueryRowContext(ctx,
		`SELECT EXISTS (
			SELECT 1 FROM character_reward_events WHERE server_id = $1 AND event_id = $2::uuid
		)`, serverID, reward.EventID,
	).Scan(&alreadyApplied); err != nil {
		return RewardResult{}, fmt.Errorf("check duplicate character reward: %w", err)
	}
	if alreadyApplied {
		if err := tx.Commit(); err != nil {
			return RewardResult{}, fmt.Errorf("commit duplicate character reward: %w", err)
		}
		return RewardResult{Applied: false}, nil
	}

	var activeCharacterID string
	err = tx.QueryRowContext(ctx,
		`SELECT c.id::text
		 FROM world_sessions ws
		 JOIN characters c ON c.id = ws.character_id
		 WHERE ws.server_id = $1 AND c.id = $2::uuid
		   AND c.status = 'alive' AND ws.session_state = 'active'
		 FOR UPDATE OF ws, c`, serverID, reward.CharacterID,
	).Scan(&activeCharacterID)
	if errors.Is(err, sql.ErrNoRows) {
		return RewardResult{}, ErrRewardSession
	}
	if err != nil {
		return RewardResult{}, fmt.Errorf("verify active character session for reward: %w", err)
	}

	var eventRecordID string
	err = tx.QueryRowContext(ctx,
		`INSERT INTO character_reward_events
		 (server_id, character_id, event_id, experience, cultivation, attribute_points)
		 VALUES ($1, $2, $3::uuid, $4, $5, $6)
		 ON CONFLICT (server_id, event_id) DO NOTHING
		 RETURNING id::text`,
		serverID, reward.CharacterID, reward.EventID,
		reward.Experience, reward.Cultivation, reward.AttributePoints,
	).Scan(&eventRecordID)
	if errors.Is(err, sql.ErrNoRows) {
		if err := tx.Commit(); err != nil {
			return RewardResult{}, fmt.Errorf("commit duplicate character reward: %w", err)
		}
		return RewardResult{Applied: false}, nil
	}
	if err != nil {
		return RewardResult{}, fmt.Errorf("record character reward event: %w", err)
	}

	updated, err := tx.ExecContext(ctx,
		`UPDATE character_progression
		 SET experience = experience + $1,
		     cultivation = cultivation + $2,
		     unspent_attribute_points = unspent_attribute_points + $3,
		     updated_at = now()
		 WHERE character_id = $4`,
		reward.Experience, reward.Cultivation, reward.AttributePoints, reward.CharacterID,
	)
	if err != nil {
		return RewardResult{}, fmt.Errorf("apply character reward values: %w", err)
	}
	if rows, err := updated.RowsAffected(); err != nil || rows != 1 {
		return RewardResult{}, fmt.Errorf("apply character reward values: expected one progression row, updated %d: %v", rows, err)
	}
	if err := tx.Commit(); err != nil {
		return RewardResult{}, fmt.Errorf("commit character reward: %w", err)
	}
	return RewardResult{Applied: true}, nil
}

func validReward(nodeKey string, reward Reward) bool {
	return nodeKey != "" && validUUID(reward.EventID) && validUUID(reward.CharacterID) &&
		reward.Experience >= 0 && reward.Experience <= 1000000 &&
		reward.Cultivation >= 0 && reward.Cultivation <= 1000000000 &&
		reward.AttributePoints >= 0 && reward.AttributePoints <= 1000 &&
		(reward.Experience > 0 || reward.Cultivation > 0 || reward.AttributePoints > 0)
}

func validUUID(value string) bool {
	if len(value) != 36 {
		return false
	}
	for i, char := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if char != '-' {
				return false
			}
			continue
		}
		if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')) {
			return false
		}
	}
	return true
}

// AllocateAttributePoints atomically spends server-issued points on one primary attribute.
func (s *Service) AllocateAttributePoints(ctx context.Context, accountID, attribute string, points int) error {
	if points < 1 || points > 100 {
		return ErrInvalidAllocation
	}

	var updateSQL string
	switch attribute {
	case "strength":
		updateSQL = `UPDATE character_attributes SET strength = strength + $1, attack = attack + ($1 * 2), updated_at = now() WHERE character_id = $2`
	case "constitution":
		updateSQL = `UPDATE character_attributes SET constitution = constitution + $1, max_health = max_health + ($1 * 10), health = LEAST(health + ($1 * 10), max_health + ($1 * 10)), updated_at = now() WHERE character_id = $2`
	case "agility":
		updateSQL = `UPDATE character_attributes SET agility = agility + $1, movement_speed = movement_speed + ($1::real * 0.05::real), updated_at = now() WHERE character_id = $2`
	case "spirit":
		updateSQL = `UPDATE character_attributes SET spirit = spirit + $1, max_mana = max_mana + ($1 * 10), mana = LEAST(mana + ($1 * 10), max_mana + ($1 * 10)), updated_at = now() WHERE character_id = $2`
	case "vitality":
		updateSQL = `UPDATE character_attributes SET vitality = vitality + $1, defense = defense + $1, updated_at = now() WHERE character_id = $2`
	default:
		return ErrInvalidAllocation
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin attribute allocation: %w", err)
	}
	defer tx.Rollback()

	var characterID string
	var available int
	err = tx.QueryRowContext(ctx,
		`SELECT c.id::text, p.unspent_attribute_points
		 FROM souls s
		 JOIN characters c ON c.id = s.current_character_id
		 JOIN character_progression p ON p.character_id = c.id
		 WHERE s.account_id = $1 AND c.status = 'alive'
		 FOR UPDATE OF c, p`, accountID,
	).Scan(&characterID, &available)
	if errors.Is(err, sql.ErrNoRows) {
		return sql.ErrNoRows
	}
	if err != nil {
		return fmt.Errorf("load character attribute points: %w", err)
	}
	if available < points {
		return ErrInsufficientPoints
	}
	updated, err := tx.ExecContext(ctx, updateSQL, points, characterID)
	if err != nil {
		return fmt.Errorf("apply character attribute allocation: %w", err)
	}
	if rows, err := updated.RowsAffected(); err != nil || rows != 1 {
		return fmt.Errorf("apply character attribute allocation: expected one attribute row, updated %d: %v", rows, err)
	}
	spent, err := tx.ExecContext(ctx,
		`UPDATE character_progression
		 SET unspent_attribute_points = unspent_attribute_points - $1, updated_at = now()
		 WHERE character_id = $2`, points, characterID,
	)
	if err != nil {
		return fmt.Errorf("spend character attribute points: %w", err)
	}
	if rows, err := spent.RowsAffected(); err != nil || rows != 1 {
		return fmt.Errorf("spend character attribute points: expected one progression row, updated %d: %v", rows, err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit character attribute allocation: %w", err)
	}
	return nil
}

type CultivationRealmOption struct {
	ID                    string `json:"id"`
	Name                  string `json:"name"`
	Order                 int    `json:"order"`
	MaxStage              int    `json:"max_stage"`
	RequiredCultivation   int64  `json:"required_cultivation"`
	PowerTierID           string `json:"power_tier_id"`
	PowerTierName         string `json:"power_tier_name"`
	PowerTierOrder        int    `json:"power_tier_order"`
	PowerComparisonNote  string `json:"power_comparison_note"`
}

type CultivationOption struct {
	RaceID    string                  `json:"race_id"`
	RaceName  string                  `json:"race_name"`
	SystemID  string                  `json:"system_id"`
	SystemName string                 `json:"system_name"`
	Realms    []CultivationRealmOption `json:"realms"`
}

func (s *Service) CultivationCatalog(ctx context.Context) ([]CultivationOption, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT race.id, race.name, system.id, system.name,
			realm.id, realm.name, realm.realm_order, realm.max_stage, realm.required_cultivation,
			tier.id, tier.name, tier.tier_order, mapping.comparison_note
		 FROM race_cultivation_systems race_system
		 JOIN race_definitions race ON race.id = race_system.race_id
		 JOIN cultivation_systems system ON system.id = race_system.system_id
		 JOIN cultivation_realms realm ON realm.system_id = system.id
		 JOIN realm_power_mappings mapping ON mapping.realm_id = realm.id
		 JOIN power_tiers tier ON tier.id = mapping.power_tier_id
		 WHERE race_system.is_default
		 ORDER BY race.id, realm.realm_order`)
	if err != nil {
		return nil, fmt.Errorf("query cultivation catalog: %w", err)
	}
	defer rows.Close()

	catalog := make([]CultivationOption, 0, 4)
	byRace := make(map[string]int)
	for rows.Next() {
		var raceID, raceName, systemID, systemName string
		var realm CultivationRealmOption
		if err := rows.Scan(
			&raceID, &raceName, &systemID, &systemName,
			&realm.ID, &realm.Name, &realm.Order, &realm.MaxStage, &realm.RequiredCultivation,
			&realm.PowerTierID, &realm.PowerTierName, &realm.PowerTierOrder, &realm.PowerComparisonNote,
		); err != nil {
			return nil, fmt.Errorf("scan cultivation catalog: %w", err)
		}
		index, exists := byRace[raceID]
		if !exists {
			index = len(catalog)
			byRace[raceID] = index
			catalog = append(catalog, CultivationOption{
				RaceID: raceID, RaceName: raceName, SystemID: systemID,
				SystemName: systemName, Realms: make([]CultivationRealmOption, 0, 9),
			})
		}
		catalog[index].Realms = append(catalog[index].Realms, realm)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate cultivation catalog: %w", err)
	}
	return catalog, nil
}

func (s *Service) CurrentStatus(ctx context.Context, accountID string) (Status, error) {
	var result Status
	var race sql.NullString
	var required sql.NullInt64
	var stageName, powerTierID, powerTierName, comparisonNote sql.NullString
	var powerTierOrder sql.NullInt64
	err := s.db.QueryRowContext(ctx,
		`SELECT
			c.id::text, c.soul_id::text, c.life_index, c.world_id, c.name, c.race_id, c.level, c.status,
			a.strength, a.constitution, a.agility, a.spirit, a.vitality,
			a.health, a.max_health, a.mana, a.max_mana, a.attack, a.defense, a.movement_speed,
			p.experience, p.cultivation, p.system_id, cs.name, p.realm_id, rd.name, rd.realm_order,
			p.realm_stage, current_stage.name, rd.max_stage, next_realm.required_cultivation,
			pt.id, pt.name, pt.tier_order, rpm.comparison_note, p.unspent_attribute_points
		 FROM souls s
		 JOIN characters c ON c.id = s.current_character_id
		 JOIN character_attributes a ON a.character_id = c.id
		 JOIN character_progression p ON p.character_id = c.id
		 JOIN cultivation_systems cs ON cs.id = p.system_id
		 JOIN cultivation_realms rd ON rd.id = p.realm_id AND rd.system_id = p.system_id
		 LEFT JOIN cultivation_stages current_stage ON current_stage.realm_id = rd.id AND current_stage.stage_order = p.realm_stage
		 LEFT JOIN cultivation_realms next_realm ON next_realm.system_id = p.system_id AND next_realm.realm_order = rd.realm_order + 1
		 LEFT JOIN realm_power_mappings rpm ON rpm.realm_id = rd.id
		 LEFT JOIN power_tiers pt ON pt.id = rpm.power_tier_id
		 WHERE s.account_id = $1`, accountID,
	).Scan(
		&result.Character.ID, &result.Character.SoulID, &result.Character.LifeIndex,
		&result.Character.WorldID, &result.Character.Name, &race, &result.Character.Level, &result.Character.Status,
		&result.Attributes.Strength, &result.Attributes.Constitution, &result.Attributes.Agility,
		&result.Attributes.Spirit, &result.Attributes.Vitality, &result.Attributes.Health,
		&result.Attributes.MaxHealth, &result.Attributes.Mana, &result.Attributes.MaxMana,
		&result.Attributes.Attack, &result.Attributes.Defense, &result.Attributes.MovementSpeed,
		&result.Progression.Experience, &result.Progression.Cultivation,
		&result.Progression.SystemID, &result.Progression.SystemName,
		&result.Progression.RealmID, &result.Progression.RealmName, &result.Progression.RealmOrder,
		&result.Progression.RealmStage, &stageName, &result.Progression.MaxRealmStage, &required,
		&powerTierID, &powerTierName, &powerTierOrder, &comparisonNote,
		&result.Progression.UnspentAttributePoints,
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
	if stageName.Valid {
		result.Progression.RealmStageName = stageName.String
	}
	if required.Valid {
		result.Progression.RequiredForNextRealm = &required.Int64
	}
	if powerTierID.Valid {
		result.Progression.PowerTierID = powerTierID.String
	}
	if powerTierName.Valid {
		result.Progression.PowerTierName = powerTierName.String
	}
	if powerTierOrder.Valid {
		result.Progression.PowerTierOrder = int(powerTierOrder.Int64)
	}
	if comparisonNote.Valid {
		result.Progression.PowerComparisonNote = comparisonNote.String
	}
	return result, nil
}
