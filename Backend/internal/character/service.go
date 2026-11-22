package character

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
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
	ErrInvalidSpellMasteryReward = errors.New("invalid spell mastery reward")
	ErrInvalidRace = errors.New("race has no configured default cultivation system")
	ErrInsufficientCultivation = errors.New("not enough cultivation for breakthrough")
	ErrMaxRealm = errors.New("character has reached the highest configured realm")
	ErrReincarnationUnavailable = errors.New("reincarnation is not currently available")
	ErrReincarnationRequirements = errors.New("soul has not met reincarnation requirements")
	ErrInvalidBirthRoute = errors.New("selected reincarnation birth route is unavailable for this race or fate")
)

type ReincarnationRoute struct {
	ID string `json:"id"`
	WorldID string `json:"world_id"`
	WorldName string `json:"world_name"`
	RaceID *string `json:"race_id,omitempty"`
	FateTraitID *string `json:"fate_trait_id,omitempty"`
	Name string `json:"name"`
	Description string `json:"description"`
	RegionID string `json:"region_id"`
	RegionName string `json:"region_name"`
	RegionDescription string `json:"region_description"`
	DangerLevel int `json:"danger_level"`
	ResourceTags json.RawMessage `json:"resource_tags"`
	ExplorationPoints json.RawMessage `json:"exploration_points"`
	RaceAffinity json.RawMessage `json:"race_affinity"`
	SpawnX float64 `json:"-"`
	SpawnY float64 `json:"-"`
	SpawnZ float64 `json:"-"`
	InitialBoon json.RawMessage `json:"-"`
}

type BirthInheritance struct {
	SourceAbsorbedCount int64 `json:"source_absorbed_count"`
	SourceGrowthStage int `json:"source_growth_stage"`
	SourceGrowthName string `json:"source_growth_name"`
	SourceStrength int64 `json:"source_strength"`
	SourceConstitution int64 `json:"source_constitution"`
	SourceAgility int64 `json:"source_agility"`
	SourceSpirit int64 `json:"source_spirit"`
	SourceVitality int64 `json:"source_vitality"`
	AppliedStrength int `json:"applied_strength"`
	AppliedConstitution int `json:"applied_constitution"`
	AppliedAgility int `json:"applied_agility"`
	AppliedSpirit int `json:"applied_spirit"`
	AppliedVitality int `json:"applied_vitality"`
	DominantAttribute string `json:"dominant_attribute"`
	InitialStrength int `json:"initial_strength"`
	InitialConstitution int `json:"initial_constitution"`
	InitialAgility int `json:"initial_agility"`
	InitialSpirit int `json:"initial_spirit"`
	InitialVitality int `json:"initial_vitality"`
	InitialHealth int `json:"initial_health"`
	InitialMaxHealth int `json:"initial_max_health"`
	InitialMana int `json:"initial_mana"`
	InitialMaxMana int `json:"initial_max_mana"`
	InitialAttack int `json:"initial_attack"`
	InitialDefense int `json:"initial_defense"`
	InitialMovementSpeed float64 `json:"initial_movement_speed"`
}

type Character struct {
	BirthInheritance *BirthInheritance `json:"birth_inheritance,omitempty"`
	ID        string  `json:"id"`
	PositionX float64 `json:"-"`
	PositionY float64 `json:"-"`
	PositionZ float64 `json:"-"`
	BirthRouteName string `json:"birth_route_name,omitempty"`
	SoulID    string  `json:"soul_id"`
	LifeIndex int     `json:"life_index"`
	WorldID   string  `json:"world_id"`
	Name      string  `json:"name"`
	RaceID    *string `json:"race_id,omitempty"`
	Level     int     `json:"level"`
	Status    string  `json:"status"`
	FateAspect string `json:"fate_aspect,omitempty"`
	FateKarma int64 `json:"fate_karma,omitempty"`
	FateMerit int64 `json:"fate_merit,omitempty"`
	FateTraitID string `json:"fate_trait_id,omitempty"`
	FateTraitName string `json:"fate_trait_name,omitempty"`
	FateTraitDescription string `json:"fate_trait_description,omitempty"`
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

func growthStageForAbsorptions(count int64) (int, string) {
	switch {
	case count >= 40:
		return 5, "魂魄圆融"
	case count >= 20:
		return 4, "灵体初成"
	case count >= 8:
		return 3, "聚魄成形"
	case count >= 3:
		return 2, "魂光凝实"
	default:
		return 1, "初生魂团"
	}
}

func inheritanceBonus(potential int64, raceWeight int) int {
	bonus := 0
	if potential >= 9 { bonus = 3 } else { bonus = int(potential / 3) }
	// A race's strongest natural growth affinity can resonate with matching
	// soul potential, but the total inherited bonus remains capped at +3.
	if potential >= 6 && raceWeight >= 2600 && bonus < 3 {
		bonus++
	}
	return bonus
}

func dominantInheritanceAttribute(values [5]int64, weights [5]int) string {
	names := [5]string{"strength", "constitution", "agility", "spirit", "vitality"}
	best := int64(0)
	index := -1
	for i, value := range values {
		if value > best || (value == best && value > 0 && index >= 0 && weights[i] > weights[index]) {
			best, index = value, i
		}
	}
	if index < 0 { return "" }
	return names[index]
}

func (s *Service) loadBirthInheritance(ctx context.Context, tx *sql.Tx, soulID, raceID string) (BirthInheritance, [5]int, error) {
	var result BirthInheritance
	var weights [5]int
	err := tx.QueryRowContext(ctx,
		`SELECT COALESCE(inheritance.strength,0), COALESCE(inheritance.constitution,0),
		        COALESCE(inheritance.agility,0), COALESCE(inheritance.spirit,0),
		        COALESCE(inheritance.vitality,0), COALESCE(essence.absorbed_count,0),
		        COALESCE(growth.strength_weight,1800), COALESCE(growth.constitution_weight,1800),
		        COALESCE(growth.agility_weight,1800), COALESCE(growth.spirit_weight,2800),
		        COALESCE(growth.vitality_weight,1800)
		 FROM soul_inheritance_attributes inheritance
		 JOIN souls soul ON soul.id=inheritance.soul_id
		 LEFT JOIN soul_essence_attributes essence ON essence.soul_id=soul.id
		 LEFT JOIN race_attribute_growth_profiles growth ON growth.race_id=$2
		 WHERE inheritance.soul_id=$1`,
		soulID, raceID,
	).Scan(&result.SourceStrength, &result.SourceConstitution, &result.SourceAgility,
		&result.SourceSpirit, &result.SourceVitality, &result.SourceAbsorbedCount,
		&weights[0], &weights[1], &weights[2], &weights[3], &weights[4])
	if err != nil {
		return BirthInheritance{}, weights, fmt.Errorf("load soul inheritance for birth: %w", err)
	}
	result.SourceGrowthStage, result.SourceGrowthName = growthStageForAbsorptions(result.SourceAbsorbedCount)
	values := [5]int64{result.SourceStrength, result.SourceConstitution, result.SourceAgility, result.SourceSpirit, result.SourceVitality}
	bonuses := [5]int{
		inheritanceBonus(values[0], weights[0]),
		inheritanceBonus(values[1], weights[1]),
		inheritanceBonus(values[2], weights[2]),
		inheritanceBonus(values[3], weights[3]),
		inheritanceBonus(values[4], weights[4]),
	}
	result.DominantAttribute = dominantInheritanceAttribute(values, weights)
	// A mature soul concentrates its additional birth resonance into its
	// strongest inherited affinity rather than inflating every base stat.
	if result.DominantAttribute != "" && result.SourceGrowthStage >= 3 {
		stageBonus := 1
		if result.SourceGrowthStage >= 5 { stageBonus = 2 }
		for i, name := range [5]string{"strength", "constitution", "agility", "spirit", "vitality"} {
			if name == result.DominantAttribute {
				bonuses[i] += stageBonus
				if bonuses[i] > 3 { bonuses[i] = 3 }
				break
			}
		}
	}
	result.AppliedStrength, result.AppliedConstitution = bonuses[0], bonuses[1]
	result.AppliedAgility, result.AppliedSpirit, result.AppliedVitality = bonuses[2], bonuses[3], bonuses[4]
	result.InitialStrength, result.InitialConstitution = 5+bonuses[0], 5+bonuses[1]
	result.InitialAgility, result.InitialSpirit, result.InitialVitality = 5+bonuses[2], 5+bonuses[3], 5+bonuses[4]
	result.InitialHealth, result.InitialMaxHealth = 100+bonuses[1]*10+bonuses[4]*5, 100+bonuses[1]*10+bonuses[4]*5
	result.InitialMana, result.InitialMaxMana = 50+bonuses[3]*10, 50+bonuses[3]*10
	result.InitialAttack, result.InitialDefense = 10+bonuses[0]*2, 5+bonuses[1]+bonuses[4]
	result.InitialMovementSpeed = 5.0+float64(bonuses[2])*0.05
	return result, weights, nil
}

// ReincarnationPreview computes a read-only preview using the same server-side
// inheritance formula as Reincarnate. The client never submits stat values.
func (s *Service) ReincarnationPreview(ctx context.Context, accountID, raceID string) (BirthInheritance, error) {
	raceID = strings.TrimSpace(raceID)
	if raceID == "" || len(raceID) > 64 { return BirthInheritance{}, ErrInvalidRace }
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil { return BirthInheritance{}, fmt.Errorf("begin inheritance preview: %w", err) }
	defer tx.Rollback()
	var soulID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM souls WHERE account_id=$1`, accountID).Scan(&soulID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return BirthInheritance{}, ErrSoulRequired }
		return BirthInheritance{}, fmt.Errorf("load soul for inheritance preview: %w", err)
	}
	var exists bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM race_attribute_growth_profiles WHERE race_id=$1)`, raceID).Scan(&exists); err != nil {
		return BirthInheritance{}, fmt.Errorf("validate race for inheritance preview: %w", err)
	}
	if !exists { return BirthInheritance{}, ErrInvalidRace }
	preview, _, err := s.loadBirthInheritance(ctx, tx, soulID, raceID)
	if err != nil { return BirthInheritance{}, err }
	return preview, nil
}

func (s *Service) CreateFirstLife(ctx context.Context, accountID, name, worldID, raceID string) (Character, error) {
	name = strings.TrimSpace(name)
	// A soul's first physical form always awakens in Fengdu; the player
	// reaches other worlds through the reincarnation/entry flow, never by
	// selecting an arbitrary world during first-life creation.
	worldID = "underworld_fengdu"
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
	var sourceAbsorbedCount, sourceGrowthStage sql.NullInt64
	var sourceGrowthName, dominantAttribute sql.NullString
	var sourceStrength, sourceConstitution, sourceAgility, sourceSpirit, sourceVitality sql.NullInt64
	var appliedStrength, appliedConstitution, appliedAgility, appliedSpirit, appliedVitality sql.NullInt64
	err := s.db.QueryRowContext(ctx,
		`SELECT c.id::text, c.soul_id::text, c.life_index, c.world_id, c.name, c.race_id, c.level, c.status,
		        COALESCE(trait.trait_id, ''), COALESCE(trait.trait_name, ''), COALESCE(trait.description, ''),
		        birth.source_absorbed_count, birth.source_growth_stage, birth.source_growth_name,
		        birth.source_strength, birth.source_constitution, birth.source_agility, birth.source_spirit, birth.source_vitality,
		        birth.applied_strength, birth.applied_constitution, birth.applied_agility, birth.applied_spirit, birth.applied_vitality,
		        birth.dominant_attribute
		 FROM souls s JOIN characters c ON c.id = s.current_character_id
		 LEFT JOIN character_fate_traits trait ON trait.character_id = c.id
		 LEFT JOIN character_birth_inheritance birth ON birth.character_id = c.id
		 WHERE s.account_id = $1`, accountID,
	).Scan(&result.ID, &result.SoulID, &result.LifeIndex, &result.WorldID, &result.Name, &race, &result.Level, &result.Status,
		&result.FateTraitID, &result.FateTraitName, &result.FateTraitDescription,
		&sourceAbsorbedCount, &sourceGrowthStage, &sourceGrowthName,
		&sourceStrength, &sourceConstitution, &sourceAgility, &sourceSpirit, &sourceVitality,
		&appliedStrength, &appliedConstitution, &appliedAgility, &appliedSpirit, &appliedVitality, &dominantAttribute)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, sql.ErrNoRows
	}
	if err != nil {
		return Character{}, fmt.Errorf("load current character: %w", err)
	}
	if race.Valid {
		result.RaceID = &race.String
	}
	if sourceAbsorbedCount.Valid {
		birth := &BirthInheritance{
			SourceAbsorbedCount: sourceAbsorbedCount.Int64,
			SourceGrowthStage: int(sourceGrowthStage.Int64),
			SourceGrowthName: sourceGrowthName.String,
			SourceStrength: sourceStrength.Int64,
			SourceConstitution: sourceConstitution.Int64,
			SourceAgility: sourceAgility.Int64,
			SourceSpirit: sourceSpirit.Int64,
			SourceVitality: sourceVitality.Int64,
			AppliedStrength: int(appliedStrength.Int64),
			AppliedConstitution: int(appliedConstitution.Int64),
			AppliedAgility: int(appliedAgility.Int64),
			AppliedSpirit: int(appliedSpirit.Int64),
			AppliedVitality: int(appliedVitality.Int64),
			DominantAttribute: dominantAttribute.String,
		}
		birth.InitialStrength, birth.InitialConstitution = 5+birth.AppliedStrength, 5+birth.AppliedConstitution
		birth.InitialAgility, birth.InitialSpirit, birth.InitialVitality = 5+birth.AppliedAgility, 5+birth.AppliedSpirit, 5+birth.AppliedVitality
		birth.InitialHealth, birth.InitialMaxHealth = 100+birth.AppliedConstitution*10+birth.AppliedVitality*5, 100+birth.AppliedConstitution*10+birth.AppliedVitality*5
		birth.InitialMana, birth.InitialMaxMana = 50+birth.AppliedSpirit*10, 50+birth.AppliedSpirit*10
		birth.InitialAttack, birth.InitialDefense = 10+birth.AppliedStrength*2, 5+birth.AppliedConstitution+birth.AppliedVitality
		birth.InitialMovementSpeed = 5.0+float64(birth.AppliedAgility)*0.05
		result.BirthInheritance = birth
	}
	return result, nil
}

type LifeRecord struct {
	CharacterID string  `json:"character_id"`
	LifeIndex   int     `json:"life_index"`
	Name        string  `json:"name"`
	WorldID     string  `json:"world_id"`
	WorldName   string  `json:"world_name"`
	RaceID      *string `json:"race_id,omitempty"`
	RaceName    string  `json:"race_name"`
	Level       int     `json:"level"`
	Status      string  `json:"status"`
	RealmName   string  `json:"realm_name"`
	RealmStage  int     `json:"realm_stage"`
	IsCurrent   bool    `json:"is_current"`
	CreatedAt   time.Time `json:"created_at"`
	ReincarnatedAt *string `json:"reincarnated_at,omitempty"`
	PreviousWorldID string `json:"previous_world_id,omitempty"`
	NextWorldID string `json:"next_world_id,omitempty"`
	BirthRouteName string `json:"birth_route_name,omitempty"`
	FateAspect string `json:"fate_aspect,omitempty"`
	FateKarma int64 `json:"fate_karma,omitempty"`
	FateMerit int64 `json:"fate_merit,omitempty"`
	FateTraitID string `json:"fate_trait_id,omitempty"`
	FateTraitName string `json:"fate_trait_name,omitempty"`
	FateTraitDescription string `json:"fate_trait_description,omitempty"`
}

// History returns every physical life belonging to the authenticated soul.
// It deliberately reads immutable life records rather than inferring history
// from the current character pointer.
func (s *Service) History(ctx context.Context, accountID string) ([]LifeRecord, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT c.id::text, c.life_index, c.name, c.world_id, world.name,
		        c.race_id, COALESCE(race.name, '未知种族'), c.level, c.status,
		        COALESCE(realm.name, '尚未记录'), COALESCE(progression.realm_stage, 1),
		        (c.id = soul.current_character_id),
		        c.created_at,
		        reincarnation.reincarnated_at,
		        COALESCE(reincarnation.previous_world_id, ''),
		        COALESCE(reincarnation.new_world_id, ''),
		        COALESCE(reincarnation.birth_route_name, ''),
		        COALESCE(reincarnation.fate_aspect, '因果未定'),
		        COALESCE(reincarnation.fate_karma, 0), COALESCE(reincarnation.fate_merit, 0),
		 COALESCE(fate_trait.trait_id, 'unmarked_fate'), COALESCE(fate_trait.trait_name, '因果未定'),
		 COALESCE(fate_trait.description, '')
		 FROM souls soul
		 JOIN characters c ON c.soul_id = soul.id
		 JOIN world_definitions world ON world.id = c.world_id
		 LEFT JOIN race_definitions race ON race.id = c.race_id
		 LEFT JOIN character_progression progression ON progression.character_id = c.id
		 LEFT JOIN cultivation_realms realm ON realm.id = progression.realm_id
		 LEFT JOIN reincarnation_events reincarnation ON reincarnation.new_character_id = c.id
		 LEFT JOIN character_fate_traits fate_trait ON fate_trait.character_id = c.id
		 WHERE soul.account_id = $1
		 ORDER BY c.life_index DESC`, accountID)
	if err != nil {
		return nil, fmt.Errorf("query soul life history: %w", err)
	}
	defer rows.Close()

	history := make([]LifeRecord, 0)
	for rows.Next() {
		var item LifeRecord
		var raceID sql.NullString
		var reincarnatedAt sql.NullTime
		if err := rows.Scan(
			&item.CharacterID, &item.LifeIndex, &item.Name, &item.WorldID, &item.WorldName,
			&raceID, &item.RaceName, &item.Level, &item.Status, &item.RealmName,
			&item.RealmStage, &item.IsCurrent, &item.CreatedAt, &reincarnatedAt,
			&item.PreviousWorldID, &item.NextWorldID, &item.BirthRouteName, &item.FateAspect, &item.FateKarma, &item.FateMerit,
			&item.FateTraitID, &item.FateTraitName, &item.FateTraitDescription,
		); err != nil {
			return nil, fmt.Errorf("scan soul life history: %w", err)
		}
		if raceID.Valid {
			item.RaceID = &raceID.String
		}
		if reincarnatedAt.Valid {
			value := reincarnatedAt.Time.UTC().Format(time.RFC3339)
			item.ReincarnatedAt = &value
		}
		history = append(history, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate soul life history: %w", err)
	}
	return history, nil
}

type SoulMemory struct {
	ID string `json:"id"`
	SourceCharacterID string `json:"source_character_id"`
	LifeIndex int `json:"life_index"`
	MemoryType string `json:"memory_type"`
	Title string `json:"title"`
	Summary string `json:"summary,omitempty"`
	Details json.RawMessage `json:"details,omitempty"`
	MinRealmOrder int `json:"min_realm_order"`
	RequiredRealmName string `json:"required_realm_name"`
	Unlocked bool `json:"unlocked"`
	CreatedAt time.Time `json:"created_at"`
}

// Memories returns archive metadata for every previous life. The summary and
// detailed payload are only returned after the soul reaches the required realm.
func (s *Service) Memories(ctx context.Context, accountID string) ([]SoulMemory, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT memory.id::text, memory.source_character_id::text, life.life_index,
		        memory.memory_type, memory.title, memory.summary, memory.memory_data,
		        memory.min_realm_order, required.name,
		        (current_realm.realm_order >= memory.min_realm_order),
		        memory.created_at
		 FROM souls soul
		 JOIN soul_progression progression ON progression.soul_id = soul.id
		 JOIN soul_realm_definitions current_realm ON current_realm.id = progression.realm_id
		 JOIN soul_memory_entries memory ON memory.soul_id = soul.id
		 JOIN characters life ON life.id = memory.source_character_id
		 JOIN soul_realm_definitions required ON required.realm_order = memory.min_realm_order
		 WHERE soul.account_id = $1
		 ORDER BY life.life_index DESC, memory.created_at DESC`, accountID)
	if err != nil {
		return nil, fmt.Errorf("query soul memories: %w", err)
	}
	defer rows.Close()

	memories := make([]SoulMemory, 0)
	for rows.Next() {
		var item SoulMemory
		var summary string
		var details []byte
		if err := rows.Scan(
			&item.ID, &item.SourceCharacterID, &item.LifeIndex, &item.MemoryType,
			&item.Title, &summary, &details, &item.MinRealmOrder,
			&item.RequiredRealmName, &item.Unlocked, &item.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("scan soul memory: %w", err)
		}
		if item.Unlocked {
			item.Summary = summary
			item.Details = append(json.RawMessage(nil), details...)
		}
		memories = append(memories, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate soul memories: %w", err)
	}
	return memories, nil
}


// SpellMasteryReward is emitted by the authoritative world server after a
// projectile has dealt damage. Event IDs make retries safe across disconnects.
type SpellMasteryReward struct {
	EventID     string `json:"event_id"`
	SessionID   string `json:"session_id"`
	CharacterID string `json:"character_id"`
	SpellID     string `json:"spell_id"`
	Experience  int64  `json:"experience"`
}

type SpellMasteryResult struct {
	Applied     bool  `json:"applied"`
	Experience  int64 `json:"experience"`
	Level       int   `json:"level"`
}

// ApplySpellMasteryReward verifies the exact world session and stores both the
// idempotency record and progression update in one transaction.
func (s *Service) ApplySpellMasteryReward(ctx context.Context, nodeKey string, reward SpellMasteryReward) (SpellMasteryResult, error) {
	if !validSpellMasteryReward(nodeKey, reward) {
		return SpellMasteryResult{}, ErrInvalidSpellMasteryReward
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return SpellMasteryResult{}, fmt.Errorf("begin spell mastery reward: %w", err) }
	defer tx.Rollback()

	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key=$1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return SpellMasteryResult{}, ErrRewardSession }
		return SpellMasteryResult{}, fmt.Errorf("resolve server for spell mastery: %w", err)
	}
	var duplicate bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM character_spell_mastery_events WHERE server_id=$1 AND event_id=$2::uuid)`, serverID, reward.EventID).Scan(&duplicate); err != nil {
		return SpellMasteryResult{}, fmt.Errorf("check spell mastery event: %w", err)
	}
	if duplicate {
		var xp int64
		var level int
		if err := tx.QueryRowContext(ctx, `SELECT experience, level FROM character_spell_mastery WHERE character_id=$1::uuid AND spell_id=$2`, reward.CharacterID, reward.SpellID).Scan(&xp, &level); err != nil {
			if errors.Is(err, sql.ErrNoRows) { xp, level = 0, 1 } else { return SpellMasteryResult{}, err }
		}
		if err := tx.Commit(); err != nil { return SpellMasteryResult{}, fmt.Errorf("commit duplicate spell mastery: %w", err) }
		return SpellMasteryResult{Applied:false, Experience:xp, Level:level}, nil
	}
	var verified string
	err = tx.QueryRowContext(ctx, `SELECT c.id::text FROM world_sessions ws JOIN characters c ON c.id=ws.character_id
		WHERE ws.id=$1::uuid AND ws.server_id=$2 AND c.id=$3::uuid AND c.status='alive'
		AND ws.session_state IN ('active','closed') FOR UPDATE OF ws,c`,
		reward.SessionID, serverID, reward.CharacterID).Scan(&verified)
	if errors.Is(err, sql.ErrNoRows) { return SpellMasteryResult{}, ErrRewardSession }
	if err != nil { return SpellMasteryResult{}, fmt.Errorf("verify spell mastery session: %w", err) }

	if _, err := tx.ExecContext(ctx, `INSERT INTO character_spell_mastery_events(server_id,event_id,character_id,spell_id,experience_awarded)
		VALUES($1,$2::uuid,$3::uuid,$4,$5)`, serverID,reward.EventID,reward.CharacterID,reward.SpellID,reward.Experience); err != nil {
		return SpellMasteryResult{}, fmt.Errorf("record spell mastery event: %w", err)
	}
	var xp int64
	var level int
	err = tx.QueryRowContext(ctx, `INSERT INTO character_spell_mastery(character_id,spell_id,experience,level,updated_at)
		VALUES($1::uuid,$2,LEAST($3,4500),CASE WHEN $3>=4500 THEN 10 WHEN $3>=3600 THEN 9 WHEN $3>=2800 THEN 8 WHEN $3>=2100 THEN 7 WHEN $3>=1500 THEN 6 WHEN $3>=1000 THEN 5 WHEN $3>=600 THEN 4 WHEN $3>=300 THEN 3 WHEN $3>=100 THEN 2 ELSE 1 END,now())
		ON CONFLICT(character_id,spell_id) DO UPDATE SET
		experience=LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience),
		level=CASE WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=4500 THEN 10
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=3600 THEN 9
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=2800 THEN 8
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=2100 THEN 7
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=1500 THEN 6
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=1000 THEN 5
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=600 THEN 4
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=300 THEN 3
		WHEN LEAST(4500,character_spell_mastery.experience+EXCLUDED.experience)>=100 THEN 2 ELSE 1 END,updated_at=now()
		RETURNING experience,level`, reward.CharacterID,reward.SpellID,reward.Experience).Scan(&xp,&level)
	if err != nil { return SpellMasteryResult{}, fmt.Errorf("update spell mastery: %w", err) }
	if err := tx.Commit(); err != nil { return SpellMasteryResult{}, fmt.Errorf("commit spell mastery reward: %w", err) }
	return SpellMasteryResult{Applied:true,Experience:xp,Level:level}, nil
}

func validSpellMasteryReward(nodeKey string, reward SpellMasteryReward) bool {
	return nodeKey != "" && validUUID(reward.EventID) && validUUID(reward.SessionID) &&
		validUUID(reward.CharacterID) && (reward.SpellID=="fireball" || reward.SpellID=="ice_bolt") &&
		reward.Experience > 0 && reward.Experience <= 10
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
		   AND ws.session_state IN ('active', 'closed')
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
		// Vitality reinforces survivability: each point adds 5 max health and
		// 1 defense, matching the reincarnation baseline formula.
		updateSQL = `UPDATE character_attributes
			SET vitality = vitality + $1,
			    defense = defense + $1,
			    max_health = max_health + ($1 * 5),
			    health = LEAST(health + ($1 * 5), max_health + ($1 * 5)),
			    updated_at = now()
			WHERE character_id = $2`
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
	var sourceAbsorbedCount, sourceGrowthStage sql.NullInt64
	var sourceGrowthName, dominantAttribute sql.NullString
	var sourceStrength, sourceConstitution, sourceAgility, sourceSpirit, sourceVitality sql.NullInt64
	var appliedStrength, appliedConstitution, appliedAgility, appliedSpirit, appliedVitality sql.NullInt64
	birthErr := s.db.QueryRowContext(ctx,
		`SELECT source_absorbed_count, source_growth_stage, source_growth_name,
		        source_strength, source_constitution, source_agility, source_spirit, source_vitality,
		        applied_strength, applied_constitution, applied_agility, applied_spirit, applied_vitality,
		        dominant_attribute
		 FROM character_birth_inheritance WHERE character_id = $1`,
		result.Character.ID,
	).Scan(&sourceAbsorbedCount, &sourceGrowthStage, &sourceGrowthName,
		&sourceStrength, &sourceConstitution, &sourceAgility, &sourceSpirit, &sourceVitality,
		&appliedStrength, &appliedConstitution, &appliedAgility, &appliedSpirit, &appliedVitality, &dominantAttribute)
	if birthErr != nil && !errors.Is(birthErr, sql.ErrNoRows) {
		return Status{}, fmt.Errorf("load current character birth inheritance: %w", birthErr)
	}
	if sourceAbsorbedCount.Valid {
		birth := &BirthInheritance{
			SourceAbsorbedCount: sourceAbsorbedCount.Int64,
			SourceGrowthStage: int(sourceGrowthStage.Int64),
			SourceGrowthName: sourceGrowthName.String,
			SourceStrength: sourceStrength.Int64,
			SourceConstitution: sourceConstitution.Int64,
			SourceAgility: sourceAgility.Int64,
			SourceSpirit: sourceSpirit.Int64,
			SourceVitality: sourceVitality.Int64,
			AppliedStrength: int(appliedStrength.Int64),
			AppliedConstitution: int(appliedConstitution.Int64),
			AppliedAgility: int(appliedAgility.Int64),
			AppliedSpirit: int(appliedSpirit.Int64),
			AppliedVitality: int(appliedVitality.Int64),
			DominantAttribute: dominantAttribute.String,
		}
		birth.InitialStrength, birth.InitialConstitution = 5+birth.AppliedStrength, 5+birth.AppliedConstitution
		birth.InitialAgility, birth.InitialSpirit, birth.InitialVitality = 5+birth.AppliedAgility, 5+birth.AppliedSpirit, 5+birth.AppliedVitality
		birth.InitialHealth, birth.InitialMaxHealth = 100+birth.AppliedConstitution*10+birth.AppliedVitality*5, 100+birth.AppliedConstitution*10+birth.AppliedVitality*5
		birth.InitialMana, birth.InitialMaxMana = 50+birth.AppliedSpirit*10, 50+birth.AppliedSpirit*10
		birth.InitialAttack, birth.InitialDefense = 10+birth.AppliedStrength*2, 5+birth.AppliedConstitution+birth.AppliedVitality
		birth.InitialMovementSpeed = 5.0+float64(birth.AppliedAgility)*0.05
		result.Character.BirthInheritance = birth
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


// currentFateTraitID mirrors the server-side reincarnation imprint thresholds.
func currentFateTraitID(merit, karma int64) string {
	switch {
	case merit >= 5 && karma >= 5:
		return "entangled_fate"
	case merit >= 5:
		return "blessed_fate"
	case karma >= 5:
		return "karmic_shadow"
	default:
		return "unmarked_fate"
	}
}

// ReincarnationRoutes returns enabled routes compatible with the soul's
// predicted next-life fate. Reincarnate repeats the same check transactionally.
func (s *Service) ReincarnationRoutes(ctx context.Context, accountID string) ([]ReincarnationRoute, error) {
	var merit, karma int64
	if err := s.db.QueryRowContext(ctx,
		`SELECT merit, karma FROM souls WHERE account_id = $1`, accountID,
	).Scan(&merit, &karma); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrSoulRequired
		}
		return nil, fmt.Errorf("load soul fate for reincarnation routes: %w", err)
	}
	predictedTrait := currentFateTraitID(merit, karma)

	rows, err := s.db.QueryContext(ctx,
		`SELECT route.id, route.world_id, world.name, route.race_id, route.fate_trait_id,
		        route.name, route.description, route.region_id, route.region_name,
		        route.region_description, route.danger_level, route.resource_tags,
		        route.exploration_points, route.race_affinity, route.spawn_x, route.spawn_y,
		        route.spawn_z, route.initial_boon
	 FROM reincarnation_birth_routes route
	 JOIN world_definitions world ON world.id = route.world_id
	 WHERE route.enabled AND world.enabled
	   AND (route.fate_trait_id IS NULL OR route.fate_trait_id = $1)
	 ORDER BY world.world_level, route.sort_order, route.name`, predictedTrait)
	if err != nil {
		return nil, fmt.Errorf("query reincarnation birth routes: %w", err)
	}
	defer rows.Close()
	routes := make([]ReincarnationRoute, 0)
	for rows.Next() {
		var item ReincarnationRoute
		var raceID, fateTraitID sql.NullString
		var boon []byte
		if err := rows.Scan(&item.ID, &item.WorldID, &item.WorldName, &raceID, &fateTraitID,
			&item.Name, &item.Description, &item.RegionID, &item.RegionName, &item.RegionDescription,
			&item.DangerLevel, &item.ResourceTags, &item.ExplorationPoints, &item.RaceAffinity,
			&item.SpawnX, &item.SpawnY, &item.SpawnZ, &boon); err != nil {
			return nil, fmt.Errorf("scan reincarnation birth route: %w", err)
		}
		if raceID.Valid {
			item.RaceID = &raceID.String
		}
		if fateTraitID.Valid {
			item.FateTraitID = &fateTraitID.String
		}
		item.InitialBoon = append(json.RawMessage(nil), boon...)
		routes = append(routes, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate reincarnation birth routes: %w", err)
	}
	return routes, nil
}

// Reincarnate creates a new physical life while retaining the soul record.
// The old body is retired, never overwritten; all writes are atomic.
func (s *Service) Reincarnate(ctx context.Context, accountID, name, raceID, routeID string) (Character, error) {
	name = strings.TrimSpace(name)
	raceID = strings.TrimSpace(raceID)
	if len([]rune(name)) < 2 || len([]rune(name)) > 24 || len(raceID) == 0 || len(raceID) > 64 || strings.TrimSpace(routeID) == "" || len(routeID) > 96 {
		return Character{}, ErrInvalid
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Character{}, fmt.Errorf("begin reincarnation: %w", err)
	}
	defer tx.Rollback()

	var soulID, oldCharacterID, oldWorldID, oldRaceID string
	var oldLifeIndex int
	var fateKarma, fateMerit int64
	err = tx.QueryRowContext(ctx,
		`SELECT soul.id::text, c.id::text, c.world_id, c.race_id, c.life_index, soul.karma, soul.merit
		 FROM souls soul
		 JOIN characters c ON c.id = soul.current_character_id
		 WHERE soul.account_id = $1 AND c.status = 'alive'
		 FOR UPDATE OF soul, c`,
		accountID,
	).Scan(&soulID, &oldCharacterID, &oldWorldID, &oldRaceID, &oldLifeIndex, &fateKarma, &fateMerit)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, ErrReincarnationUnavailable
	}
	if err != nil {
		return Character{}, fmt.Errorf("load current life for reincarnation: %w", err)
	}

	// First reincarnation requires 聚灵境 and completion of the first Fengdu
	// soul trial. The check is repeated here inside the creation transaction;
	// the public eligibility endpoint is never trusted as authorization.
	var soulRealmOrder int
	var firstTrialCompleted bool
	err = tx.QueryRowContext(ctx,
		`SELECT realm.realm_order,
		        EXISTS (SELECT 1 FROM soul_trial_progress trial
		                WHERE trial.soul_id=progression.soul_id
		                  AND trial.trial_id='fengdu_first_exorcism'
		                  AND trial.completed_at IS NOT NULL)
		 FROM soul_progression progression
		 JOIN soul_realm_definitions realm ON realm.id=progression.realm_id
		 WHERE progression.soul_id=$1
		 FOR UPDATE OF progression`, soulID,
	).Scan(&soulRealmOrder,&firstTrialCompleted)
	if err != nil {
		return Character{}, fmt.Errorf("check soul reincarnation requirements: %w", err)
	}
	if soulRealmOrder < 3 || !firstTrialCompleted {
		return Character{}, ErrReincarnationRequirements
	}

	var activeSession bool
	if err := tx.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM world_sessions
		 WHERE character_id = $1 AND session_state IN ('connecting','active','saving'))`,
		oldCharacterID,
	).Scan(&activeSession); err != nil {
		return Character{}, fmt.Errorf("check current life session: %w", err)
	}
	if activeSession {
		return Character{}, ErrReincarnationUnavailable
	}

	var destinationWorld, routeName, routeDescription string
	var routeRaceID, routeFateTraitID sql.NullString
	var spawnX, spawnY, spawnZ float64
	var initialBoon []byte
	err = tx.QueryRowContext(ctx,
	 `SELECT route.world_id, route.name, route.description, route.race_id,
	         route.fate_trait_id, route.spawn_x, route.spawn_y, route.spawn_z, route.initial_boon
	  FROM reincarnation_birth_routes route
	  JOIN world_definitions world ON world.id = route.world_id
	  WHERE route.id = $1 AND route.enabled AND world.enabled`,
	 routeID,
	).Scan(&destinationWorld, &routeName, &routeDescription, &routeRaceID, &routeFateTraitID,
	 &spawnX, &spawnY, &spawnZ, &initialBoon)
	if errors.Is(err, sql.ErrNoRows) { return Character{}, ErrInvalidBirthRoute }
	if err != nil { return Character{}, fmt.Errorf("load selected reincarnation route: %w", err) }
	if routeRaceID.Valid && routeRaceID.String != raceID { return Character{}, ErrInvalidBirthRoute }


	var systemID, firstRealmID string
	err = tx.QueryRowContext(ctx,
		`SELECT mapping.system_id, realm.id
		 FROM race_cultivation_systems mapping
		 JOIN cultivation_realms realm ON realm.system_id = mapping.system_id AND realm.realm_order = 1
		 WHERE mapping.race_id = $1 AND mapping.is_default`,
		raceID,
	).Scan(&systemID, &firstRealmID)
	if errors.Is(err, sql.ErrNoRows) {
		return Character{}, ErrInvalidRace
	}
	if err != nil {
		return Character{}, fmt.Errorf("resolve reincarnated race cultivation: %w", err)
	}

	birthInheritance, raceWeights, err := s.loadBirthInheritance(ctx, tx, soulID, raceID)
	if err != nil {
		return Character{}, fmt.Errorf("calculate reincarnation inheritance: %w", err)
	}

	newLifeIndex := oldLifeIndex + 1
	fateAspect := "因果未定"
	switch {
	case fateMerit >= 5 && fateKarma >= 5:
		fateAspect = "福祸交织"
	case fateMerit >= 5:
		fateAspect = "福缘深厚"
	case fateKarma >= 5:
		fateAspect = "业障缠身"
	}
	var result Character
	result.BirthInheritance = &birthInheritance
	result.FateAspect, result.FateKarma, result.FateMerit = fateAspect, fateKarma, fateMerit
	result.BirthRouteName = routeName
	result.FateTraitID = currentFateTraitID(fateMerit, fateKarma)
	switch result.FateTraitID {
	case "entangled_fate":
		result.FateTraitName, result.FateTraitDescription = "福祸交织", "福缘与业障并存，可能触发更复杂的因果遭遇。"
	case "blessed_fate":
		result.FateTraitName, result.FateTraitDescription = "福缘深厚", "善缘随身，部分正道 NPC 可能给予额外信任与隐藏机缘。"
	case "karmic_shadow":
		result.FateTraitName, result.FateTraitDescription = "业障缠身", "业障随身，部分冥界 NPC 与特殊事件会对你作出不同反应。"
	default:
		result.FateTraitName, result.FateTraitDescription = "因果未定", "此世命格尚未显现，未来的善恶抉择仍可改变命运。"
	}
	if routeFateTraitID.Valid && routeFateTraitID.String != result.FateTraitID {
		return Character{}, ErrInvalidBirthRoute
	}
	var race sql.NullString
	err = tx.QueryRowContext(ctx,
		`INSERT INTO characters (soul_id, life_index, world_id, name, race_id, position_x, position_y, position_z)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		 RETURNING id::text, soul_id::text, life_index, world_id, name, race_id, level, status, position_x, position_y, position_z`,
		soulID, newLifeIndex, destinationWorld, name, raceID, spawnX, spawnY, spawnZ,
	).Scan(&result.ID, &result.SoulID, &result.LifeIndex, &result.WorldID, &result.Name, &race, &result.Level, &result.Status, &result.PositionX, &result.PositionY, &result.PositionZ)
	if err != nil {
		return Character{}, fmt.Errorf("create reincarnated body: %w", err)
	}
	if race.Valid {
		result.RaceID = &race.String
	}

	if _, err := tx.ExecContext(ctx, `INSERT INTO character_attributes (character_id) VALUES ($1)`, result.ID); err != nil {
		return Character{}, fmt.Errorf("initialize reincarnated attributes: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE character_attributes
		 SET strength=strength+$2, constitution=constitution+$3, agility=agility+$4,
		     spirit=spirit+$5, vitality=vitality+$6,
		     attack=attack+($2*2), defense=defense+$3+$6,
		     max_health=max_health+($3*10)+($6*5), health=max_health+($3*10)+($6*5),
		     max_mana=max_mana+($5*10), mana=max_mana+($5*10),
		     movement_speed=movement_speed+($4*0.05::real), updated_at=now()
		 WHERE character_id=$1`,
		result.ID, birthInheritance.AppliedStrength, birthInheritance.AppliedConstitution,
		birthInheritance.AppliedAgility, birthInheritance.AppliedSpirit, birthInheritance.AppliedVitality,
	); err != nil {
		return Character{}, fmt.Errorf("apply reincarnation birth attributes: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO character_birth_inheritance
		 (character_id,soul_id,life_index,source_absorbed_count,source_growth_stage,source_growth_name,
		  source_strength,source_constitution,source_agility,source_spirit,source_vitality,
		  race_strength_weight,race_constitution_weight,race_agility_weight,race_spirit_weight,race_vitality_weight,
		  applied_strength,applied_constitution,applied_agility,applied_spirit,applied_vitality,dominant_attribute)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22)`,
		result.ID,soulID,newLifeIndex,birthInheritance.SourceAbsorbedCount,birthInheritance.SourceGrowthStage,
		birthInheritance.SourceGrowthName,birthInheritance.SourceStrength,birthInheritance.SourceConstitution,
		birthInheritance.SourceAgility,birthInheritance.SourceSpirit,birthInheritance.SourceVitality,
		raceWeights[0],raceWeights[1],raceWeights[2],raceWeights[3],raceWeights[4],
		birthInheritance.AppliedStrength,birthInheritance.AppliedConstitution,birthInheritance.AppliedAgility,
		birthInheritance.AppliedSpirit,birthInheritance.AppliedVitality,birthInheritance.DominantAttribute,
	); err != nil {
		return Character{}, fmt.Errorf("record reincarnation birth inheritance: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO character_progression (character_id, system_id, realm_id) VALUES ($1, $2, $3)`,
		result.ID, systemID, firstRealmID,
	); err != nil {
		return Character{}, fmt.Errorf("initialize reincarnated cultivation: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO character_inventory (character_id, item_id, quantity)
		 VALUES ($1, 'starter_iron_sword', 1), ($1, 'starter_cloth_cap', 1),
		        ($1, 'starter_leather_vest', 1), ($1, 'starter_trousers', 1),
		        ($1, 'starter_travel_boots', 1), ($1, 'starter_wooden_charm', 1),
		        ($1, 'minor_health_pill', 3), ($1, 'minor_mana_pill', 3)`,
		result.ID,
	); err != nil {
		return Character{}, fmt.Errorf("grant reincarnated starter inventory: %w", err)
	}

	bloodlineResult, err := tx.ExecContext(ctx,
		`INSERT INTO character_bloodlines (character_id, bloodline_id, purity, awakening_stage, is_primary)
		 SELECT $1, id, base_purity, 0, TRUE FROM bloodline_definitions
		 WHERE race_id = $2 AND is_default`,
		result.ID, raceID,
	)
	if err != nil {
		return Character{}, fmt.Errorf("initialize reincarnated bloodline: %w", err)
	}
	if rows, rowsErr := bloodlineResult.RowsAffected(); rowsErr != nil || rows != 1 {
		return Character{}, fmt.Errorf("initialize reincarnated bloodline: expected one default, inserted %d: %v", rows, rowsErr)
	}
	techniqueResult, err := tx.ExecContext(ctx,
		`INSERT INTO character_techniques (character_id, technique_id, proficiency, is_equipped, is_starter)
		 SELECT $1, technique_id, 0, TRUE, TRUE FROM race_starter_techniques WHERE race_id = $2`,
		result.ID, raceID,
	)
	if err != nil {
		return Character{}, fmt.Errorf("initialize reincarnated starter technique: %w", err)
	}
	if rows, rowsErr := techniqueResult.RowsAffected(); rowsErr != nil || rows != 1 {
		return Character{}, fmt.Errorf("initialize reincarnated starter technique: expected one starter, inserted %d: %v", rows, rowsErr)
	}

	if _, err := tx.ExecContext(ctx,
		`UPDATE characters SET status = 'retired', updated_at = now() WHERE id = $1 AND status = 'alive'`,
		oldCharacterID,
	); err != nil {
		return Character{}, fmt.Errorf("retire previous physical life: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO soul_memory_entries
		 (soul_id, source_character_id, memory_type, title, summary, memory_data, min_realm_order)
		 SELECT $1, c.id, 'life_summary',
		        format('第 %s 世：%s', c.life_index, c.name),
		        format('%s曾在%s度过这一世，最终修炼至%s。', c.name, world.name, COALESCE(realm.name, '初始境界')),
		        jsonb_build_object(
		            'life_index', c.life_index,
		            'character_name', c.name,
		            'world_id', c.world_id,
		            'world_name', world.name,
		            'race_id', c.race_id,
		            'race_name', COALESCE(race.name, '未知种族'),
		            'level', c.level,
		            'character_status', c.status,
		            'cultivation_experience', COALESCE(progression.experience, 0),
		            'cultivation_value', COALESCE(progression.cultivation, 0),
		            'realm_id', progression.realm_id,
		            'realm_name', realm.name,
		            'realm_stage', COALESCE(progression.realm_stage, 1),
		            'archived_at', now()
		        ),
		        5
		 FROM characters c
		 JOIN world_definitions world ON world.id = c.world_id
		 LEFT JOIN race_definitions race ON race.id = c.race_id
		 LEFT JOIN character_progression progression ON progression.character_id = c.id
		 LEFT JOIN cultivation_realms realm ON realm.id = progression.realm_id
		 WHERE c.id = $2
		 ON CONFLICT (soul_id, source_character_id, memory_type) DO NOTHING`,
		soulID, oldCharacterID,
	); err != nil {
		return Character{}, fmt.Errorf("preserve previous life memory: %w", err)
	}

	if _, err := tx.ExecContext(ctx,
		`UPDATE souls SET current_character_id = $1, updated_at = now() WHERE id = $2`,
		result.ID, soulID,
	); err != nil {
		return Character{}, fmt.Errorf("switch soul to reincarnated body: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO reincarnation_events
		 (soul_id, previous_character_id, new_character_id, previous_world_id, new_world_id,
		  previous_race_id, new_race_id, life_index, merit_spent, fate_karma, fate_merit, fate_aspect,
		  birth_route_id, birth_route_name, birth_route_description, birth_route_snapshot)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,$9,$10,$11,$12,$13,$14,
		         jsonb_build_object('spawn_x',$15,'spawn_y',$16,'spawn_z',$17,'initial_boon',$18::jsonb))`,
		soulID, oldCharacterID, result.ID, oldWorldID, destinationWorld,
		oldRaceID, raceID, newLifeIndex, fateKarma, fateMerit, fateAspect,
		routeID, routeName, routeDescription, spawnX, spawnY, spawnZ, string(initialBoon),
	); err != nil {
		return Character{}, fmt.Errorf("record reincarnation history: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO character_fate_traits
		 (character_id, soul_id, life_index, trait_id, trait_name, description, effect_data)
		 VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb)`,
		result.ID, soulID, newLifeIndex, result.FateTraitID, result.FateTraitName,
		result.FateTraitDescription,
		`{"source":"server_reincarnation","merit_threshold":5,"karma_threshold":5}`,
	); err != nil {
		return Character{}, fmt.Errorf("record reincarnation fate trait: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Character{}, fmt.Errorf("commit reincarnation: %w", err)
	}
	return result, nil
}


// SpellMasteryProgress is the persistent proficiency state for one spell.
type SpellMasteryProgress struct {
	SpellID string `json:"spell_id"`
	Experience int64 `json:"experience"`
	Level int `json:"level"`
}

// SpellMasteryForSession exposes only the authenticated character's mastery to
// the world node currently hosting that exact session.
func (s *Service) SpellMasteryForSession(ctx context.Context, nodeKey, sessionID, characterID string) ([]SpellMasteryProgress, error) {
	if strings.TrimSpace(nodeKey) == "" || !validUUID(sessionID) || !validUUID(characterID) {
		return nil, ErrInvalidSpellMasteryReward
	}
	var serverID string
	if err := s.db.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key=$1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return nil, ErrRewardSession }
		return nil, fmt.Errorf("resolve server for spell mastery query: %w", err)
	}
	var verified string
	err := s.db.QueryRowContext(ctx, `SELECT ws.id::text FROM world_sessions ws
		JOIN characters c ON c.id=ws.character_id
		WHERE ws.id=$1::uuid AND ws.server_id=$2 AND c.id=$3::uuid
		AND c.status='alive' AND ws.session_state='active'`,
		sessionID, serverID, characterID).Scan(&verified)
	if errors.Is(err, sql.ErrNoRows) { return nil, ErrRewardSession }
	if err != nil { return nil, fmt.Errorf("verify spell mastery query session: %w", err) }

	rows, err := s.db.QueryContext(ctx, `SELECT spell_id, experience, level
		FROM character_spell_mastery WHERE character_id=$1::uuid ORDER BY spell_id`, characterID)
	if err != nil { return nil, fmt.Errorf("query character spell mastery: %w", err) }
	defer rows.Close()
	result := make([]SpellMasteryProgress, 0, 2)
	for rows.Next() {
		var item SpellMasteryProgress
		if err := rows.Scan(&item.SpellID, &item.Experience, &item.Level); err != nil {
			return nil, fmt.Errorf("scan character spell mastery: %w", err)
		}
		result = append(result, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate character spell mastery: %w", err) }
	return result, nil
}
