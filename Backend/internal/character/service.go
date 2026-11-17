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
	ErrInsufficientCultivation = errors.New("not enough cultivation for breakthrough")
	ErrMaxRealm = errors.New("character has reached the highest configured realm")
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
	RequiredForNextStage   *int64 `json:"required_for_next_stage,omitempty"`
	RequiredForNextRealm   *int64 `json:"required_for_next_realm,omitempty"`
	PowerTierID            string `json:"power_tier_id,omitempty"`
	PowerTierName          string `json:"power_tier_name,omitempty"`
	PowerTierOrder         int    `json:"power_tier_order,omitempty"`
	PowerComparisonNote    string `json:"power_comparison_note,omitempty"`
	UnspentAttributePoints int    `json:"unspent_attribute_points"`
}

type CharacterBloodline struct {
	ID string `json:"id"`
	Name string `json:"name"`
	RaceID string `json:"race_id"`
	Grade int `json:"grade"`
	Purity int `json:"purity"`
	AwakeningStage int `json:"awakening_stage"`
	IsPrimary bool `json:"is_primary"`
}

type CharacterTechnique struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Type        string `json:"type"`
	Grade       int    `json:"grade"`
	Proficiency int64  `json:"proficiency"`
	IsEquipped  bool   `json:"is_equipped"`
}

type Status struct {
	Character   Character   `json:"character"`
	Attributes  Attributes  `json:"attributes"`
	Progression Progression `json:"progression"`
	Bloodlines  []CharacterBloodline `json:"bloodlines"`
	Techniques  []CharacterTechnique `json:"techniques"`
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

	// Every new life starts with a small, non-tradable-by-default starter kit.
	// Equipment is placed in inventory and must be equipped by the player.
	if _, err := tx.ExecContext(ctx, `INSERT INTO character_inventory (character_id, item_id, quantity)
		VALUES
			($1, 'starter_iron_sword', 1),
			($1, 'starter_cloth_cap', 1),
			($1, 'starter_leather_vest', 1),
			($1, 'starter_trousers', 1),
			($1, 'starter_travel_boots', 1),
			($1, 'starter_wooden_charm', 1),
			($1, 'minor_health_pill', 3),
			($1, 'minor_mana_pill', 3)`, result.ID); err != nil {
		return Character{}, fmt.Errorf("grant starter inventory: %w", err)
	}

	bloodlineResult, err := tx.ExecContext(ctx,
		`INSERT INTO character_bloodlines (character_id, bloodline_id, purity, awakening_stage, is_primary)
		 SELECT $1, id, base_purity, 0, TRUE
		 FROM bloodline_definitions
		 WHERE race_id = $2 AND is_default`, result.ID, raceID)
	if err != nil {
		return Character{}, fmt.Errorf("initialize character bloodline: %w", err)
	}
	if rows, err := bloodlineResult.RowsAffected(); err != nil || rows != 1 {
		return Character{}, fmt.Errorf("initialize character bloodline: expected one default bloodline, inserted %d: %v", rows, err)
	}
	starterResult, err := tx.ExecContext(ctx, `INSERT INTO character_techniques (character_id, technique_id, proficiency, is_equipped, is_starter)
		 SELECT $1, technique_id, 0, TRUE, TRUE FROM race_starter_techniques WHERE race_id=$2`, result.ID, raceID)
	if err != nil { return Character{}, fmt.Errorf("initialize starter technique: %w", err) }
	if rows, err := starterResult.RowsAffected(); err != nil || rows != 1 {
		return Character{}, fmt.Errorf("initialize starter technique: expected one starter technique, inserted %d: %v", rows, err)
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
	SessionID      string `json:"session_id"`
	CharacterID    string `json:"character_id"`
	Experience     int64  `json:"experience"`
	Cultivation    int64  `json:"cultivation"`
	AttributePoints int   `json:"attribute_points"`
}

type RewardResult struct {
	Applied bool `json:"applied"`
}

// ApplyServerReward accepts rewards from the node that hosted the exact session.
// A recently closed session is accepted so an asynchronous reward can finish
 // after a player disconnects. A per-node event ID prevents duplicate grants.
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
		 WHERE ws.id = $1::uuid AND ws.server_id = $2 AND c.id = $3::uuid
		   AND c.status = 'alive'
		   AND (ws.session_state = 'active' OR
		        (ws.session_state = 'closed' AND ws.updated_at >= now() - INTERVAL '10 minutes'))
		 FOR UPDATE OF ws, c`, reward.SessionID, serverID, reward.CharacterID,
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
	return nodeKey != "" && validUUID(reward.EventID) && validUUID(reward.SessionID) && validUUID(reward.CharacterID) &&
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

type BreakthroughResult struct {
	RealmID      string `json:"realm_id"`
	RealmStage   int    `json:"realm_stage"`
	AdvancedRealm bool  `json:"advanced_realm"`
}

// Breakthrough advances one stage, or enters the next realm after the final
// stage. Cultivation thresholds are cumulative and derived from adjacent
// realm thresholds, keeping the realm catalogue data-driven.
func (s *Service) Breakthrough(ctx context.Context, accountID string) (BreakthroughResult, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return BreakthroughResult{}, fmt.Errorf("begin breakthrough: %w", err)
	}
	defer tx.Rollback()

	var characterID, realmID string
	var stage, maxStage int
	var cultivation, currentRequired int64
	var nextRealmID sql.NullString
	var nextRequired sql.NullInt64
	err = tx.QueryRowContext(ctx,
		`SELECT c.id::text, p.realm_id, p.realm_stage, p.cultivation,
		        rd.max_stage, rd.required_cultivation,
		        next_realm.id, next_realm.required_cultivation
		 FROM souls s
		 JOIN characters c ON c.id = s.current_character_id
		 JOIN character_progression p ON p.character_id = c.id
		 JOIN cultivation_realms rd ON rd.id = p.realm_id AND rd.system_id = p.system_id
		 LEFT JOIN cultivation_realms next_realm
		   ON next_realm.system_id = p.system_id AND next_realm.realm_order = rd.realm_order + 1
		 WHERE s.account_id = $1 AND c.status = 'alive'
		 FOR UPDATE OF c, p`, accountID,
	).Scan(&characterID, &realmID, &stage, &cultivation, &maxStage, &currentRequired, &nextRealmID, &nextRequired)
	if errors.Is(err, sql.ErrNoRows) {
		return BreakthroughResult{}, sql.ErrNoRows
	}
	if err != nil {
		return BreakthroughResult{}, fmt.Errorf("load character breakthrough state: %w", err)
	}
	if !nextRealmID.Valid || !nextRequired.Valid {
		return BreakthroughResult{}, ErrMaxRealm
	}

	result := BreakthroughResult{RealmID: realmID, RealmStage: stage}
	if stage < maxStage {
		threshold := cultivationStageThreshold(currentRequired, nextRequired.Int64, stage+1, maxStage)
		if cultivation < threshold {
			return BreakthroughResult{}, ErrInsufficientCultivation
		}
		result.RealmStage = stage + 1
		_, err = tx.ExecContext(ctx,
			`UPDATE character_progression SET realm_stage = $1, updated_at = now() WHERE character_id = $2`,
			result.RealmStage, characterID)
	} else {
		if cultivation < nextRequired.Int64 {
			return BreakthroughResult{}, ErrInsufficientCultivation
		}
		result.RealmID = nextRealmID.String
		result.RealmStage = 1
		result.AdvancedRealm = true
		_, err = tx.ExecContext(ctx,
			`UPDATE character_progression SET realm_id = $1, realm_stage = 1, updated_at = now() WHERE character_id = $2`,
			result.RealmID, characterID)
	}
	if err != nil {
		return BreakthroughResult{}, fmt.Errorf("apply character breakthrough: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return BreakthroughResult{}, fmt.Errorf("commit character breakthrough: %w", err)
	}
	return result, nil
}

// Stage thresholds divide the cultivation gap to the next realm into
// maxStage+1 steps. The final step is the realm breakthrough itself.
func cultivationStageThreshold(currentRealmRequired, nextRealmRequired int64, targetStage, maxStage int) int64 {
	if maxStage < 1 || targetStage < 1 || targetStage > maxStage || nextRealmRequired <= currentRealmRequired {
		return currentRealmRequired
	}
	delta := nextRealmRequired - currentRealmRequired
	denominator := int64(maxStage + 1)
	numerator := delta * int64(targetStage)
	return currentRealmRequired + (numerator+denominator-1)/denominator
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


type RaceGrowthProfile struct {
	RaceID string `json:"race_id"`
	StrengthWeight int `json:"strength_weight"`
	ConstitutionWeight int `json:"constitution_weight"`
	AgilityWeight int `json:"agility_weight"`
	SpiritWeight int `json:"spirit_weight"`
	VitalityWeight int `json:"vitality_weight"`
}

type BloodlineModifier struct {
	Attribute string `json:"attribute"`
	ModifierBasisPoints int `json:"modifier_basis_points"`
}

type BloodlineOption struct {
	ID string `json:"id"`
	RaceID string `json:"race_id"`
	Name string `json:"name"`
	Grade int `json:"grade"`
	BasePurity int `json:"base_purity"`
	IsDefault bool `json:"is_default"`
	Description string `json:"description"`
	Modifiers []BloodlineModifier `json:"modifiers"`
}

type TechniqueCompatibility struct {
	RaceID string `json:"race_id"`
	Compatibility string `json:"compatibility"`
	EfficiencyBasisPoints int `json:"efficiency_basis_points"`
	UnlockCondition string `json:"unlock_condition"`
}

type TechniqueOption struct {
	ID string `json:"id"`
	SystemID string `json:"system_id"`
	SystemName string `json:"system_name"`
	Name string `json:"name"`
	Type string `json:"type"`
	Grade int `json:"grade"`
	MinRealmOrder int `json:"min_realm_order"`
	CrossRace bool `json:"cross_race"`
	Description string `json:"description"`
	Compatibility []TechniqueCompatibility `json:"compatibility"`
}

func (s *Service) RaceGrowthCatalog(ctx context.Context) ([]RaceGrowthProfile, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT race_id, strength_weight, constitution_weight, agility_weight, spirit_weight, vitality_weight
		 FROM race_attribute_growth_profiles ORDER BY race_id`)
	if err != nil { return nil, fmt.Errorf("query race growth profiles: %w", err) }
	defer rows.Close()
	result := make([]RaceGrowthProfile, 0, 4)
	for rows.Next() {
		var item RaceGrowthProfile
		if err := rows.Scan(&item.RaceID, &item.StrengthWeight, &item.ConstitutionWeight, &item.AgilityWeight, &item.SpiritWeight, &item.VitalityWeight); err != nil {
			return nil, fmt.Errorf("scan race growth profile: %w", err)
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate race growth profiles: %w", err) }
	return result, nil
}

func (s *Service) BloodlineCatalog(ctx context.Context) ([]BloodlineOption, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT bloodline.id, bloodline.race_id, bloodline.name, bloodline.grade,
		        bloodline.base_purity, bloodline.is_default, bloodline.description,
		        modifier.attribute_key, modifier.modifier_basis_points
		 FROM bloodline_definitions bloodline
		 LEFT JOIN bloodline_attribute_modifiers modifier ON modifier.bloodline_id = bloodline.id
		 ORDER BY bloodline.race_id, bloodline.grade, bloodline.id, modifier.attribute_key`)
	if err != nil { return nil, fmt.Errorf("query bloodline catalog: %w", err) }
	defer rows.Close()
	result := make([]BloodlineOption, 0, 4)
	indexes := make(map[string]int)
	for rows.Next() {
		var item BloodlineOption
		var attribute sql.NullString
		var modifier sql.NullInt64
		if err := rows.Scan(&item.ID, &item.RaceID, &item.Name, &item.Grade, &item.BasePurity, &item.IsDefault, &item.Description, &attribute, &modifier); err != nil {
			return nil, fmt.Errorf("scan bloodline catalog: %w", err)
		}
		index, exists := indexes[item.ID]
		if !exists {
			index = len(result)
			indexes[item.ID] = index
			item.Modifiers = make([]BloodlineModifier, 0, 3)
			result = append(result, item)
		}
		if attribute.Valid && modifier.Valid {
			result[index].Modifiers = append(result[index].Modifiers, BloodlineModifier{Attribute: attribute.String, ModifierBasisPoints: int(modifier.Int64)})
		}
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate bloodline catalog: %w", err) }
	return result, nil
}

func (s *Service) TechniqueCatalog(ctx context.Context) ([]TechniqueOption, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT technique.id, technique.system_id, system.name, technique.name,
		        technique.technique_type, technique.grade, technique.min_realm_order,
		        technique.is_cross_race, technique.description,
		        compatibility.race_id, compatibility.compatibility,
		        compatibility.efficiency_basis_points, compatibility.unlock_condition
		 FROM cultivation_techniques technique
		 JOIN cultivation_systems system ON system.id = technique.system_id
		 JOIN technique_race_compatibility compatibility ON compatibility.technique_id = technique.id
		 ORDER BY technique.system_id, technique.grade, technique.id, compatibility.race_id`)
	if err != nil { return nil, fmt.Errorf("query technique catalog: %w", err) }
	defer rows.Close()
	result := make([]TechniqueOption, 0, 12)
	indexes := make(map[string]int)
	for rows.Next() {
		var item TechniqueOption
		var compatibility TechniqueCompatibility
		if err := rows.Scan(&item.ID, &item.SystemID, &item.SystemName, &item.Name, &item.Type,
			&item.Grade, &item.MinRealmOrder, &item.CrossRace, &item.Description,
			&compatibility.RaceID, &compatibility.Compatibility, &compatibility.EfficiencyBasisPoints, &compatibility.UnlockCondition); err != nil {
			return nil, fmt.Errorf("scan technique catalog: %w", err)
		}
		index, exists := indexes[item.ID]
		if !exists {
			index = len(result)
			indexes[item.ID] = index
			item.Compatibility = make([]TechniqueCompatibility, 0, 4)
			result = append(result, item)
		}
		result[index].Compatibility = append(result[index].Compatibility, compatibility)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate technique catalog: %w", err) }
	return result, nil
}

func (s *Service) CurrentStatus(ctx context.Context, accountID string) (Status, error) {
	var result Status
	var race sql.NullString
	var required sql.NullInt64
	var currentRealmRequired int64
	var stageName, powerTierID, powerTierName, comparisonNote sql.NullString
	var powerTierOrder sql.NullInt64
	err := s.db.QueryRowContext(ctx,
		`SELECT
			c.id::text, c.soul_id::text, c.life_index, c.world_id, c.name, c.race_id, c.level, c.status,
			a.strength, a.constitution, a.agility, a.spirit, a.vitality,
			a.health, a.max_health, a.mana, a.max_mana, a.attack, a.defense, a.movement_speed,
			p.experience, p.cultivation, p.system_id, cs.name, p.realm_id, rd.name, rd.realm_order,
			p.realm_stage, current_stage.name, rd.max_stage, rd.required_cultivation, next_realm.required_cultivation,
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
		&result.Progression.RealmStage, &stageName, &result.Progression.MaxRealmStage, &currentRealmRequired, &required,
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
		if result.Progression.RealmStage < result.Progression.MaxRealmStage {
			threshold := cultivationStageThreshold(currentRealmRequired, required.Int64, result.Progression.RealmStage+1, result.Progression.MaxRealmStage)
			result.Progression.RequiredForNextStage = &threshold
		}
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
	bloodlineRows, err := s.db.QueryContext(ctx,
		`SELECT bloodline.id, bloodline.name, bloodline.race_id, bloodline.grade,
		        character_bloodline.purity, character_bloodline.awakening_stage, character_bloodline.is_primary
		 FROM character_bloodlines character_bloodline
		 JOIN bloodline_definitions bloodline ON bloodline.id = character_bloodline.bloodline_id
		 WHERE character_bloodline.character_id = $1
		 ORDER BY character_bloodline.is_primary DESC, bloodline.grade DESC, bloodline.id`,
		result.Character.ID)
	if err != nil {
		return Status{}, fmt.Errorf("load current character bloodlines: %w", err)
	}
	defer bloodlineRows.Close()
	result.Bloodlines = make([]CharacterBloodline, 0, 2)
	for bloodlineRows.Next() {
		var bloodline CharacterBloodline
		if err := bloodlineRows.Scan(&bloodline.ID, &bloodline.Name, &bloodline.RaceID, &bloodline.Grade,
			&bloodline.Purity, &bloodline.AwakeningStage, &bloodline.IsPrimary); err != nil {
			return Status{}, fmt.Errorf("scan current character bloodline: %w", err)
		}
		result.Bloodlines = append(result.Bloodlines, bloodline)
	}
	if err := bloodlineRows.Err(); err != nil {
		return Status{}, fmt.Errorf("iterate current character bloodlines: %w", err)
	}

	techniqueRows, err := s.db.QueryContext(ctx,
		`SELECT technique.id, technique.name, technique.technique_type, technique.grade,
		        character_technique.proficiency, character_technique.is_equipped
		 FROM character_techniques character_technique
		 JOIN cultivation_techniques technique ON technique.id = character_technique.technique_id
		 WHERE character_technique.character_id = $1
		 ORDER BY character_technique.is_equipped DESC, technique.grade, technique.id`,
		result.Character.ID)
	if err != nil {
		return Status{}, fmt.Errorf("load current character techniques: %w", err)
	}
	defer techniqueRows.Close()
	result.Techniques = make([]CharacterTechnique, 0, 4)
	for techniqueRows.Next() {
		var technique CharacterTechnique
		if err := techniqueRows.Scan(&technique.ID, &technique.Name, &technique.Type,
			&technique.Grade, &technique.Proficiency, &technique.IsEquipped); err != nil {
			return Status{}, fmt.Errorf("scan current character technique: %w", err)
		}
		result.Techniques = append(result.Techniques, technique)
	}
	if err := techniqueRows.Err(); err != nil {
		return Status{}, fmt.Errorf("iterate current character techniques: %w", err)
	}
	return result, nil
}

type BloodlineAwakeningResult struct {
	BloodlineID string `json:"bloodline_id"`
	AwakeningStage int `json:"awakening_stage"`
	Purity int `json:"purity"`
	CultivationRemaining int64 `json:"cultivation_remaining"`
}

var (
	ErrBloodlineNotOwned = errors.New("bloodline is not owned by current character")
	ErrBloodlineMaxAwakening = errors.New("bloodline has reached maximum awakening")
	ErrAwakeningRequirement = errors.New("bloodline awakening requirements are not met")
	ErrInvalidTechniqueTraining = errors.New("invalid technique training points")
	ErrTechniqueNotOwned = errors.New("technique is not owned by current character")
)

func (s *Service) AwakenBloodline(ctx context.Context, accountID, bloodlineID string) (BloodlineAwakeningResult, error) {
	bloodlineID = strings.TrimSpace(bloodlineID)
	if bloodlineID == "" || len(bloodlineID) > 96 {
		return BloodlineAwakeningResult{}, ErrBloodlineNotOwned
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("begin bloodline awakening: %w", err) }
	defer tx.Rollback()
	var characterID string
	var stage, purity, realmOrder int
	var cultivation int64
	err = tx.QueryRowContext(ctx, `SELECT c.id::text, cb.awakening_stage, cb.purity, p.realm_order, cp.cultivation
		FROM souls s JOIN characters c ON c.id=s.current_character_id
		JOIN character_bloodlines cb ON cb.character_id=c.id
		JOIN character_progression cp ON cp.character_id=c.id
		JOIN cultivation_realms p ON p.id=cp.realm_id AND p.system_id=cp.system_id
		WHERE s.account_id=$1 AND c.status='alive' AND cb.bloodline_id=$2
		FOR UPDATE OF c, cb, cp`, accountID, bloodlineID).Scan(&characterID, &stage, &purity, &realmOrder, &cultivation)
	if errors.Is(err, sql.ErrNoRows) { return BloodlineAwakeningResult{}, ErrBloodlineNotOwned }
	if err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("load bloodline awakening state: %w", err) }
	if stage >= 9 { return BloodlineAwakeningResult{}, ErrBloodlineMaxAwakening }
	var minRealm int
	var cost int64
	var gain int
	err = tx.QueryRowContext(ctx, `SELECT min_realm_order, cultivation_cost, purity_gain FROM bloodline_awakening_rules WHERE target_stage=$1`, stage+1).Scan(&minRealm, &cost, &gain)
	if err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("load bloodline awakening rule: %w", err) }
	if realmOrder < minRealm || cultivation < cost { return BloodlineAwakeningResult{}, ErrAwakeningRequirement }
	newPurity := purity + gain
	if newPurity > 10000 { newPurity = 10000 }
	_, err = tx.ExecContext(ctx, `UPDATE character_bloodlines SET awakening_stage=$1, purity=$2 WHERE character_id=$3 AND bloodline_id=$4`, stage+1, newPurity, characterID, bloodlineID)
	if err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("update bloodline awakening: %w", err) }
	remaining := cultivation - cost
	_, err = tx.ExecContext(ctx, `UPDATE character_progression SET cultivation=$1, updated_at=now() WHERE character_id=$2`, remaining, characterID)
	if err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("consume awakening cultivation: %w", err) }
	if err := tx.Commit(); err != nil { return BloodlineAwakeningResult{}, fmt.Errorf("commit bloodline awakening: %w", err) }
	return BloodlineAwakeningResult{BloodlineID:bloodlineID, AwakeningStage:stage+1, Purity:newPurity, CultivationRemaining:remaining}, nil
}

type TechniqueTrainingResult struct {
	TechniqueID string `json:"technique_id"`
	Proficiency int64 `json:"proficiency"`
	CultivationRemaining int64 `json:"cultivation_remaining"`
}

func (s *Service) TrainTechnique(ctx context.Context, accountID, techniqueID string, points int) (TechniqueTrainingResult, error) {
	techniqueID = strings.TrimSpace(techniqueID)
	if techniqueID == "" || len(techniqueID) > 96 || points < 1 || points > 100 {
		return TechniqueTrainingResult{}, ErrInvalidTechniqueTraining
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return TechniqueTrainingResult{}, fmt.Errorf("begin technique training: %w", err) }
	defer tx.Rollback()
	var characterID string
	var grade, minRealm, currentRealm int
	var proficiency, cultivation int64
	err = tx.QueryRowContext(ctx, `SELECT c.id::text, t.grade, t.min_realm_order, r.realm_order, ct.proficiency, p.cultivation
		FROM souls s JOIN characters c ON c.id=s.current_character_id
		JOIN character_progression p ON p.character_id=c.id
		JOIN cultivation_realms r ON r.id=p.realm_id AND r.system_id=p.system_id
		JOIN character_techniques ct ON ct.character_id=c.id AND ct.technique_id=$2
		JOIN cultivation_techniques t ON t.id=ct.technique_id
		WHERE s.account_id=$1 AND c.status='alive'
		FOR UPDATE OF c, p, ct`, accountID, techniqueID).Scan(&characterID, &grade, &minRealm, &currentRealm, &proficiency, &cultivation)
	if errors.Is(err, sql.ErrNoRows) { return TechniqueTrainingResult{}, ErrTechniqueNotOwned }
	if err != nil { return TechniqueTrainingResult{}, fmt.Errorf("load technique training state: %w", err) }
	if currentRealm < minRealm { return TechniqueTrainingResult{}, ErrAwakeningRequirement }
	cost := int64(points) * int64(grade) * 100
	if cultivation < cost { return TechniqueTrainingResult{}, ErrInsufficientCultivation }
	newProficiency := proficiency + int64(points)*100
	remaining := cultivation - cost
	if _, err := tx.ExecContext(ctx, `UPDATE character_techniques SET proficiency=$1 WHERE character_id=$2 AND technique_id=$3`, newProficiency, characterID, techniqueID); err != nil {
		return TechniqueTrainingResult{}, fmt.Errorf("update technique proficiency: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `UPDATE character_progression SET cultivation=$1, updated_at=now() WHERE character_id=$2`, remaining, characterID); err != nil {
		return TechniqueTrainingResult{}, fmt.Errorf("consume technique training cultivation: %w", err)
	}
	if err := tx.Commit(); err != nil { return TechniqueTrainingResult{}, fmt.Errorf("commit technique training: %w", err) }
	return TechniqueTrainingResult{TechniqueID:techniqueID, Proficiency:newProficiency, CultivationRemaining:remaining}, nil
}
