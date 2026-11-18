package soul

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrNotFound = errors.New("soul not found")
	ErrConflict = errors.New("soul already exists")
	ErrInvalid  = errors.New("invalid soul name")
	ErrInvalidReward = errors.New("invalid soul reward")
	ErrRewardSession = errors.New("soul reward session is not valid for this node")
	ErrInvalidAbsorption = errors.New("invalid soul absorption")
	ErrAbsorptionSession = errors.New("soul absorption session is not valid for this node")
	ErrAbsorptionCapacity = errors.New("soul absorption capacity is full")
	ErrAbsorptionChoiceUsed = errors.New("rare soul essence choice is unavailable or already used")
	ErrInsufficientExperience = errors.New("not enough soul experience for breakthrough")
	ErrMaxRealm = errors.New("soul has reached the highest configured realm")
)

type Soul struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Origin     string `json:"origin,omitempty"`
	Karma      int64  `json:"karma"`
	Merit      int64  `json:"merit"`
	CreatedAt  string `json:"created_at"`
}

type Progression struct {
 Experience int64 `json:"experience"`
 RealmID string `json:"realm_id"`
 RealmName string `json:"realm_name"`
 RealmOrder int `json:"realm_order"`
 NextRealmName string `json:"next_realm_name,omitempty"`
 NextRequiredExperience *int64 `json:"next_required_experience,omitempty"`
}

type Service struct {
	db *sql.DB
}

func NewService(db *sql.DB) *Service {
	return &Service{db: db}
}

func (s *Service) Create(ctx context.Context, accountID, name, origin string) (Soul, error) {
	name = strings.TrimSpace(name)
	origin = strings.TrimSpace(origin)
	if len([]rune(name)) < 2 || len([]rune(name)) > 48 || len(origin) > 64 {
		return Soul{}, ErrInvalid
	}
	var result Soul
	var createdAt sql.NullTime
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Soul{}, fmt.Errorf("begin soul creation: %w", err) }
	defer tx.Rollback()
	err = tx.QueryRowContext(ctx,
		`INSERT INTO souls (account_id, soul_name, soul_origin) VALUES ($1, $2, NULLIF($3, ''))
		 RETURNING id::text, soul_name, COALESCE(soul_origin, ''), karma, merit, created_at`,
		accountID, name, origin,
	).Scan(&result.ID, &result.Name, &result.Origin, &result.Karma, &result.Merit, &createdAt)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return Soul{}, ErrConflict
		}
		return Soul{}, fmt.Errorf("create soul: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO soul_progression (soul_id) VALUES ($1)`, result.ID); err != nil {
		return Soul{}, fmt.Errorf("initialize soul progression: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO soul_essence_attributes (soul_id) VALUES ($1)`, result.ID); err != nil {
		return Soul{}, fmt.Errorf("initialize soul essence: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO soul_inheritance_attributes (soul_id) VALUES ($1)`, result.ID); err != nil {
		return Soul{}, fmt.Errorf("initialize soul inheritance attributes: %w", err)
	}
	if err := tx.Commit(); err != nil { return Soul{}, fmt.Errorf("commit soul creation: %w", err) }
	if createdAt.Valid {
		result.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05Z07:00")
	}
	return result, nil
}

func (s *Service) Current(ctx context.Context, accountID string) (Soul, error) {
	var result Soul
	var createdAt sql.NullTime
	err := s.db.QueryRowContext(ctx,
		`SELECT id::text, soul_name, COALESCE(soul_origin, ''), karma, merit, created_at
		 FROM souls WHERE account_id = $1`, accountID,
	).Scan(&result.ID, &result.Name, &result.Origin, &result.Karma, &result.Merit, &createdAt)
	if errors.Is(err, sql.ErrNoRows) {
		return Soul{}, ErrNotFound
	}
	if err != nil {
		return Soul{}, fmt.Errorf("load current soul: %w", err)
	}
	if createdAt.Valid {
		result.CreatedAt = createdAt.Time.UTC().Format("2006-01-02T15:04:05Z07:00")
	}
	return result, nil
}

 
// CurrentProgression returns permanent soul growth, independent of the active body.
func (s *Service) CurrentProgression(ctx context.Context, accountID string) (Progression, error) {
 var result Progression
 var nextName sql.NullString
 var nextRequired sql.NullInt64
 err := s.db.QueryRowContext(ctx,
  `SELECT p.experience, realm.id, realm.name, realm.realm_order,
          next_realm.name, next_realm.required_experience
   FROM souls soul
   JOIN soul_progression p ON p.soul_id = soul.id
   JOIN soul_realm_definitions realm ON realm.id = p.realm_id
   LEFT JOIN soul_realm_definitions next_realm ON next_realm.realm_order = realm.realm_order + 1
   WHERE soul.account_id = $1`, accountID,
 ).Scan(&result.Experience, &result.RealmID, &result.RealmName, &result.RealmOrder, &nextName, &nextRequired)
 if errors.Is(err, sql.ErrNoRows) { return Progression{}, ErrNotFound }
 if err != nil { return Progression{}, fmt.Errorf("load soul progression: %w", err) }
 if nextName.Valid { result.NextRealmName = nextName.String }
 if nextRequired.Valid { value := nextRequired.Int64; result.NextRequiredExperience = &value }
 return result, nil
}

type FateEvent struct {
 Source string `json:"source"`
 WorldID string `json:"world_id"`
 KarmaDelta int64 `json:"karma_delta"`
 MeritDelta int64 `json:"merit_delta"`
 CreatedAt time.Time `json:"created_at"`
}
type FateSummary struct {
 Karma int64 `json:"karma"`
 Merit int64 `json:"merit"`
 RecentEvents []FateEvent `json:"recent_events"`
}

// CurrentFate returns soul-level karma, merit, and a short immutable event history.
func (s *Service) CurrentFate(ctx context.Context, accountID string) (FateSummary, error) {
 var result FateSummary
 err := s.db.QueryRowContext(ctx,
  `SELECT karma,merit FROM souls WHERE account_id=$1`,accountID).Scan(&result.Karma,&result.Merit)
 if errors.Is(err,sql.ErrNoRows) { return FateSummary{},ErrNotFound }
 if err != nil { return FateSummary{},fmt.Errorf("load soul fate totals: %w",err) }
 rows,err:=s.db.QueryContext(ctx,
  `SELECT source,world_id,karma_delta,merit_delta,created_at
   FROM soul_fate_events
   WHERE soul_id=(SELECT id FROM souls WHERE account_id=$1)
   ORDER BY created_at DESC LIMIT 20`,accountID)
 if err != nil { return FateSummary{},fmt.Errorf("load soul fate events: %w",err) }
 defer rows.Close()
 result.RecentEvents=make([]FateEvent,0)
 for rows.Next() {
  var item FateEvent
  if err:=rows.Scan(&item.Source,&item.WorldID,&item.KarmaDelta,&item.MeritDelta,&item.CreatedAt);err!=nil {
   return FateSummary{},fmt.Errorf("scan soul fate event: %w",err)
  }
  result.RecentEvents=append(result.RecentEvents,item)
 }
 if err:=rows.Err();err!=nil{return FateSummary{},fmt.Errorf("iterate soul fate events: %w",err)}
 return result,nil
}

type Reward struct {
 EventID string `json:"event_id"`
 SessionID string `json:"session_id"`
 CharacterID string `json:"character_id"`
 Experience int64 `json:"experience"`
 Source string `json:"source"`
}
type RewardResult struct {
 Applied bool `json:"applied"`
 Experience int64 `json:"experience"`
 RealmID string `json:"realm_id"`
 RealmName string `json:"realm_name"`
 TrialProgress int `json:"trial_progress,omitempty"`
 TrialTarget int `json:"trial_target,omitempty"`
 TrialCompleted bool `json:"trial_completed,omitempty"`
 TrialBonusExperience int64 `json:"trial_bonus_experience,omitempty"`
}

// ApplyServerReward only accepts rewards from the node that hosted the character session.
func (s *Service) ApplyServerReward(ctx context.Context, nodeKey string, reward Reward) (RewardResult, error) {
 if nodeKey == "" || !validUUID(reward.EventID) || !validUUID(reward.SessionID) || !validUUID(reward.CharacterID) ||
    reward.Experience < 1 || reward.Experience > 100000 || !validSource(reward.Source) {
  return RewardResult{}, ErrInvalidReward
 }
 tx, err := s.db.BeginTx(ctx, nil)
 if err != nil { return RewardResult{}, fmt.Errorf("begin soul reward: %w", err) }
 defer tx.Rollback()
 var serverID string
 err = tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey).Scan(&serverID)
 if errors.Is(err, sql.ErrNoRows) { return RewardResult{}, ErrRewardSession }
 if err != nil { return RewardResult{}, fmt.Errorf("resolve soul reward node: %w", err) }
 var soulID string
 var currentExperience int64
 var worldID string
 err = tx.QueryRowContext(ctx,
  `SELECT soul.id::text, progression.experience, world.id
   FROM world_sessions ws
   JOIN world_instances instance ON instance.id = ws.instance_id
   JOIN world_definitions world ON world.id = instance.world_id
   JOIN characters character ON character.id = ws.character_id
   JOIN souls soul ON soul.id = character.soul_id
   JOIN soul_progression progression ON progression.soul_id = soul.id
   WHERE ws.id = $1::uuid AND ws.server_id = $2 AND character.id = $3::uuid
     AND character.status = 'alive'
     AND (ws.session_state = 'active' OR (ws.session_state = 'closed' AND ws.updated_at >= now() - INTERVAL '10 minutes'))
   FOR UPDATE OF ws, soul, progression`, reward.SessionID, serverID, reward.CharacterID,
 ).Scan(&soulID, &currentExperience, &worldID)
 if errors.Is(err, sql.ErrNoRows) {
  var duplicate bool
  checkErr := tx.QueryRowContext(ctx,
   `SELECT EXISTS (SELECT 1 FROM soul_reward_events WHERE soul_id =
      (SELECT soul_id FROM characters WHERE id = $1::uuid) AND event_id = $2::uuid)`,
   reward.CharacterID, reward.EventID).Scan(&duplicate)
  if checkErr != nil { return RewardResult{}, fmt.Errorf("check duplicate soul reward: %w", checkErr) }
  if duplicate {
   if err := tx.Commit(); err != nil { return RewardResult{}, fmt.Errorf("commit duplicate soul reward: %w", err) }
   return RewardResult{Applied:false}, nil
  }
  return RewardResult{}, ErrRewardSession
 }
 if err != nil { return RewardResult{}, fmt.Errorf("verify soul reward session: %w", err) }
 inserted, err := tx.ExecContext(ctx,
  `INSERT INTO soul_reward_events (soul_id,event_id,experience,source)
   VALUES ($1,$2::uuid,$3,$4) ON CONFLICT (soul_id,event_id) DO NOTHING`,
  soulID, reward.EventID, reward.Experience, reward.Source)
 if err != nil { return RewardResult{}, fmt.Errorf("record soul reward: %w", err) }
 rows, err := inserted.RowsAffected()
 if err != nil { return RewardResult{}, fmt.Errorf("read soul reward insert result: %w", err) }
 if rows == 0 {
  if err := tx.Commit(); err != nil { return RewardResult{}, fmt.Errorf("commit duplicate soul reward: %w", err) }
  return RewardResult{Applied:false}, nil
 }
 // Moral outcomes are derived from the verified world session and trusted event source.
 // A successful exorcism in Fengdu grants one merit point; clients cannot submit deltas.
 if reward.Source == "underworld_trial:monster_hunt" && worldID == "underworld_fengdu" {
  fateInsert, fateErr := tx.ExecContext(ctx,
   `INSERT INTO soul_fate_events (soul_id,event_id,source,world_id,karma_delta,merit_delta)
    VALUES ($1,$2::uuid,$3,$4,0,1)
    ON CONFLICT (soul_id,event_id) DO NOTHING`,
   soulID,reward.EventID,reward.Source,worldID)
  if fateErr != nil { return RewardResult{}, fmt.Errorf("record soul fate event: %w",fateErr) }
  fateRows, fateErr := fateInsert.RowsAffected()
  if fateErr != nil { return RewardResult{}, fmt.Errorf("read soul fate event result: %w",fateErr) }
  if fateRows > 0 {
   if _, fateErr = tx.ExecContext(ctx,
    `UPDATE souls SET merit=merit+1,updated_at=now() WHERE id=$1`,soulID); fateErr != nil {
    return RewardResult{}, fmt.Errorf("grant exorcism merit: %w",fateErr)
   }
  }
 }
 if currentExperience > 9223372036854775807-reward.Experience { return RewardResult{}, ErrInvalidReward }
 newExperience := currentExperience + reward.Experience
 var realmID, realmName string
 err = tx.QueryRowContext(ctx,
  `UPDATE soul_progression SET experience = $1, updated_at = now()
   WHERE soul_id = $2 RETURNING realm_id`, newExperience, soulID).Scan(&realmID)
 if err != nil { return RewardResult{}, fmt.Errorf("apply soul experience: %w", err) }
 result := RewardResult{Applied:true, Experience:newExperience, RealmID:realmID}
 if reward.Source == "underworld_trial:monster_hunt" {
  if _, err := tx.ExecContext(ctx,
   `INSERT INTO soul_trial_progress (soul_id,trial_id)
    SELECT $1,id FROM soul_trial_definitions WHERE id='fengdu_first_exorcism' AND enabled
    ON CONFLICT (soul_id,trial_id) DO NOTHING`, soulID); err != nil {
   return RewardResult{}, fmt.Errorf("initialize underworld trial progress: %w", err)
  }
  var completed bool
  var progress, target int
  var bonus int64
  trialErr := tx.QueryRowContext(ctx,
   `UPDATE soul_trial_progress p
    SET progress_count = LEAST(p.progress_count + 1, definition.target_count),
        completed_at = CASE WHEN p.progress_count + 1 >= definition.target_count THEN now() ELSE NULL END,
        updated_at = now()
    FROM soul_trial_definitions definition
    WHERE p.soul_id=$1 AND p.trial_id=definition.id
      AND definition.id='fengdu_first_exorcism' AND definition.enabled
      AND p.completed_at IS NULL
    RETURNING p.progress_count, definition.target_count, definition.reward_experience,
              (p.completed_at IS NOT NULL)`, soulID,
  ).Scan(&progress,&target,&bonus,&completed)
  if trialErr != nil && !errors.Is(trialErr,sql.ErrNoRows) {
   return RewardResult{}, fmt.Errorf("advance underworld trial: %w",trialErr)
  }
  if trialErr == nil {
   result.TrialProgress=progress
   result.TrialTarget=target
   result.TrialCompleted=completed
   if completed {
    if newExperience > 9223372036854775807-bonus { return RewardResult{}, ErrInvalidReward }
    if _,err:=tx.ExecContext(ctx,
     `INSERT INTO soul_reward_events (soul_id,event_id,experience,source)
      VALUES ($1,gen_random_uuid(),$2,'trial_completion')`,soulID,bonus); err!=nil {
     return RewardResult{},fmt.Errorf("record soul trial bonus: %w",err)
    }
    if _,err:=tx.ExecContext(ctx,
     `UPDATE soul_progression SET experience=experience+$1,updated_at=now() WHERE soul_id=$2`,bonus,soulID);err!=nil{
     return RewardResult{},fmt.Errorf("grant soul trial bonus: %w",err)
    }
    if _,err:=tx.ExecContext(ctx,
     `UPDATE soul_trial_progress SET reward_granted_at=now(),updated_at=now()
      WHERE soul_id=$1 AND trial_id='fengdu_first_exorcism' AND reward_granted_at IS NULL`,soulID);err!=nil{
     return RewardResult{},fmt.Errorf("mark soul trial reward: %w",err)
    }
    newExperience += bonus
    result.Experience = newExperience
    result.TrialBonusExperience = bonus
   }
  }
 }
 if err := tx.QueryRowContext(ctx, `SELECT name FROM soul_realm_definitions WHERE id=$1`, realmID).Scan(&realmName); err != nil {
  return RewardResult{}, fmt.Errorf("load soul realm after reward: %w", err)
 }
 if err := tx.Commit(); err != nil { return RewardResult{}, fmt.Errorf("commit soul reward: %w", err) }
 result.RealmName = realmName
 return result, nil
}
func validSource(source string) bool {
 if len(source) < 2 || len(source) > 48 { return false }
 for _, r := range source {
  if !((r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' || r == ':') { return false }
 }
 return true
}
func validUUID(value string) bool {
 if len(value) != 36 { return false }
 for i, r := range value {
  if i == 8 || i == 13 || i == 18 || i == 23 { if r != '-' { return false }; continue }
  if !((r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')) { return false }
 }
 return true
}

 
type BreakthroughResult struct {
 RealmID string `json:"realm_id"`
 RealmName string `json:"realm_name"`
 RealmOrder int `json:"realm_order"`
}
func (s *Service) Breakthrough(ctx context.Context, accountID string) (BreakthroughResult, error) {
 tx, err := s.db.BeginTx(ctx, nil)
 if err != nil { return BreakthroughResult{}, fmt.Errorf("begin soul breakthrough: %w", err) }
 defer tx.Rollback()
 var currentID string
 var currentOrder int
 var experience int64
 var nextID, nextName sql.NullString
 var nextRequired sql.NullInt64
 err = tx.QueryRowContext(ctx,
  `SELECT current_realm.id, current_realm.realm_order, progression.experience,
          next_realm.id, next_realm.name, next_realm.required_experience
   FROM souls soul
   JOIN soul_progression progression ON progression.soul_id = soul.id
   JOIN soul_realm_definitions current_realm ON current_realm.id = progression.realm_id
   LEFT JOIN soul_realm_definitions next_realm ON next_realm.realm_order = current_realm.realm_order + 1
   WHERE soul.account_id = $1
   FOR UPDATE OF soul, progression`, accountID,
 ).Scan(&currentID, &currentOrder, &experience, &nextID, &nextName, &nextRequired)
 if errors.Is(err, sql.ErrNoRows) { return BreakthroughResult{}, ErrNotFound }
 if err != nil { return BreakthroughResult{}, fmt.Errorf("load soul breakthrough state: %w", err) }
 if !nextID.Valid || !nextRequired.Valid { return BreakthroughResult{}, ErrMaxRealm }
 if experience < nextRequired.Int64 { return BreakthroughResult{}, ErrInsufficientExperience }
 if _, err := tx.ExecContext(ctx, `UPDATE soul_progression SET realm_id=$1, updated_at=now() WHERE soul_id=(SELECT id FROM souls WHERE account_id=$2)`, nextID.String, accountID); err != nil {
  return BreakthroughResult{}, fmt.Errorf("advance soul realm: %w", err)
 }
 if err := tx.Commit(); err != nil { return BreakthroughResult{}, fmt.Errorf("commit soul breakthrough: %w", err) }
 return BreakthroughResult{RealmID:nextID.String, RealmName:nextName.String, RealmOrder:currentOrder+1}, nil
}

 
type Trial struct {
 ID string `json:"id"`
 Name string `json:"name"`
 Description string `json:"description"`
 Progress int `json:"progress"`
 Target int `json:"target"`
 RewardExperience int64 `json:"reward_experience"`
 Completed bool `json:"completed"`
 RewardGranted bool `json:"reward_granted"`
}
func (s *Service) Trials(ctx context.Context, accountID string) ([]Trial,error) {
 rows,err:=s.db.QueryContext(ctx,
  `SELECT definition.id,definition.name,definition.description,
          COALESCE(progress.progress_count,0),definition.target_count,
          definition.reward_experience,
          COALESCE(progress.completed_at IS NOT NULL,FALSE),
          COALESCE(progress.reward_granted_at IS NOT NULL,FALSE)
   FROM souls soul CROSS JOIN soul_trial_definitions definition
   LEFT JOIN soul_trial_progress progress
     ON progress.soul_id=soul.id AND progress.trial_id=definition.id
   WHERE soul.account_id=$1 AND definition.enabled
   ORDER BY definition.id`,accountID)
 if err!=nil{return nil,fmt.Errorf("query soul trials: %w",err)}
 defer rows.Close()
 result:=make([]Trial,0)
 for rows.Next(){
  var item Trial
  if err:=rows.Scan(&item.ID,&item.Name,&item.Description,&item.Progress,&item.Target,
    &item.RewardExperience,&item.Completed,&item.RewardGranted);err!=nil{
   return nil,fmt.Errorf("scan soul trial: %w",err)
  }
  result=append(result,item)
 }
 if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate soul trials: %w",err)}
 if len(result)==0 {
  var exists bool
  if err:=s.db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM souls WHERE account_id=$1)`,accountID).Scan(&exists);err!=nil{
   return nil,fmt.Errorf("check soul for trials: %w",err)
  }
  if !exists{return nil,ErrNotFound}
 }
 return result,nil
}

 
type ReincarnationEligibility struct {
 Eligible bool `json:"eligible"`
 CurrentRealmID string `json:"current_realm_id"`
 CurrentRealmName string `json:"current_realm_name"`
 CurrentRealmOrder int `json:"current_realm_order"`
 RequiredRealmID string `json:"required_realm_id"`
 RequiredRealmName string `json:"required_realm_name"`
 RequiredRealmOrder int `json:"required_realm_order"`
 TrialID string `json:"trial_id"`
 TrialName string `json:"trial_name"`
 TrialCompleted bool `json:"trial_completed"`
 Reasons []string `json:"reasons"`
}

// ReincarnationEligibility is a preview only; the character transaction repeats
// these checks while holding the soul lock before creating a new body.
func (s *Service) ReincarnationEligibility(ctx context.Context, accountID string) (ReincarnationEligibility,error) {
 var result ReincarnationEligibility
 err:=s.db.QueryRowContext(ctx,
  `SELECT current_realm.id,current_realm.name,current_realm.realm_order,
          required_realm.id,required_realm.name,required_realm.realm_order,
          trial.id,trial.name,
          COALESCE(progress.completed_at IS NOT NULL,FALSE)
   FROM souls soul
   JOIN soul_progression progression ON progression.soul_id=soul.id
   JOIN soul_realm_definitions current_realm ON current_realm.id=progression.realm_id
   JOIN soul_realm_definitions required_realm ON required_realm.realm_order=3
   JOIN soul_trial_definitions trial ON trial.id='fengdu_first_exorcism'
   LEFT JOIN soul_trial_progress progress ON progress.soul_id=soul.id AND progress.trial_id=trial.id
   WHERE soul.account_id=$1`,accountID).Scan(
  &result.CurrentRealmID,&result.CurrentRealmName,&result.CurrentRealmOrder,
  &result.RequiredRealmID,&result.RequiredRealmName,&result.RequiredRealmOrder,
  &result.TrialID,&result.TrialName,&result.TrialCompleted)
 if errors.Is(err,sql.ErrNoRows) { return ReincarnationEligibility{},ErrNotFound }
 if err!=nil { return ReincarnationEligibility{},fmt.Errorf("load reincarnation eligibility: %w",err) }
 result.Reasons=make([]string,0,2)
 if result.CurrentRealmOrder<result.RequiredRealmOrder { result.Reasons=append(result.Reasons,"soul_realm_required") }
 if !result.TrialCompleted { result.Reasons=append(result.Reasons,"fengdu_trial_required") }
 result.Eligible=len(result.Reasons)==0
 return result,nil
}


// EssenceProfile describes the persistent soul body. Physical character attributes
// are deliberately excluded: they are generated separately at reincarnation.
type EssenceProfile struct {
	SoulPower int64 `json:"soul_power"`
	SoulWisdom int64 `json:"soul_wisdom"`
	SoulResilience int64 `json:"soul_resilience"`
	SoulPerception int64 `json:"soul_perception"`
	InheritanceAttributes InheritanceAttributes `json:"inheritance_attributes"`
	PendingRareChoices []PendingRareChoice `json:"pending_rare_choices"`
	AbsorptionCapacity int64 `json:"absorption_capacity"`
	AbsorbedEnergy int64 `json:"absorbed_energy"`
	AbsorbedCount int64 `json:"absorbed_count"`
	RealmID string `json:"realm_id"`
	RealmName string `json:"realm_name"`
	RealmOrder int `json:"realm_order"`
	FormStage int `json:"form_stage"`
	FormName string `json:"form_name"`
	VisualScale float64 `json:"visual_scale"`
	AbsorptionKinds []AbsorptionKindProgress `json:"absorption_kinds"`
}

type InheritanceAttributes struct {
 Strength int64 `json:"strength"`
 Constitution int64 `json:"constitution"`
 Agility int64 `json:"agility"`
 Spirit int64 `json:"spirit"`
 Vitality int64 `json:"vitality"`
}

type PendingRareChoice struct {
 RecordID string `json:"record_id"`
 KindID string `json:"kind_id"`
 KindName string `json:"kind_name"`
 CreatedAt string `json:"created_at"`
}

type AbsorptionKindProgress struct {
	KindID string `json:"kind_id"`
	Name string `json:"name"`
	Description string `json:"description"`
	BaseEnergy int64 `json:"base_energy"`
	TraitKey string `json:"trait_key"`
	Rarity string `json:"rarity"`
	InheritanceAttribute string `json:"inheritance_attribute,omitempty"`
	AbsorbedCount int64 `json:"absorbed_count"`
}

// CurrentEssence returns soul-owned essence and authored absorption categories.
// It is read-only; rewards must later be applied by trusted combat/server events.
func (s *Service) CurrentEssence(ctx context.Context, accountID string) (EssenceProfile, error) {
	var result EssenceProfile
	err := s.db.QueryRowContext(ctx,
		`SELECT a.soul_power,a.soul_wisdom,a.soul_resilience,a.soul_perception,
		       inheritance.strength,inheritance.constitution,inheritance.agility,inheritance.spirit,inheritance.vitality,
		       a.absorption_capacity,a.absorbed_energy,a.absorbed_count,
			       realm.id,realm.name,realm.realm_order
		 FROM souls soul
		 JOIN soul_essence_attributes a ON a.soul_id=soul.id
		 JOIN soul_inheritance_attributes inheritance ON inheritance.soul_id=soul.id
		 JOIN soul_progression progression ON progression.soul_id=soul.id
		 JOIN soul_realm_definitions realm ON realm.id=progression.realm_id
		 WHERE soul.account_id=$1`, accountID).Scan(
		&result.SoulPower,&result.SoulWisdom,&result.SoulResilience,&result.SoulPerception,
		&result.InheritanceAttributes.Strength,&result.InheritanceAttributes.Constitution,&result.InheritanceAttributes.Agility,&result.InheritanceAttributes.Spirit,&result.InheritanceAttributes.Vitality,
		&result.AbsorptionCapacity,&result.AbsorbedEnergy,&result.AbsorbedCount,
		&result.RealmID,&result.RealmName,&result.RealmOrder)
	if errors.Is(err,sql.ErrNoRows) { return EssenceProfile{},ErrNotFound }
	if err!=nil { return EssenceProfile{},fmt.Errorf("load soul essence: %w",err) }

	switch {
	case result.RealmOrder <= 1:
		result.FormStage,result.FormName,result.VisualScale=1,"初生魂光",0.35
	case result.RealmOrder == 2:
		result.FormStage,result.FormName,result.VisualScale=2,"凝魂",0.55
	case result.RealmOrder == 3:
		result.FormStage,result.FormName,result.VisualScale=3,"聚魄",0.8
	case result.RealmOrder <= 5:
		result.FormStage,result.FormName,result.VisualScale=4,"灵体",1.1
	default:
		result.FormStage,result.FormName,result.VisualScale=5,"魂魄圆满",1.4
	}

	rows,err:=s.db.QueryContext(ctx,
		`SELECT kinds.id,kinds.name,kinds.description,kinds.base_energy,kinds.trait_key,kinds.rarity,COALESCE(kinds.inheritance_attribute,''),
			       COUNT(records.id)
		 FROM soul_absorption_kinds kinds
		 LEFT JOIN soul_absorption_records records
		   ON records.absorption_kind_id=kinds.id
		  AND records.soul_id=(SELECT id FROM souls WHERE account_id=$1)
		 WHERE kinds.enabled=TRUE
		 GROUP BY kinds.id,kinds.name,kinds.description,kinds.base_energy,kinds.trait_key,kinds.rarity,kinds.inheritance_attribute
		 ORDER BY kinds.id`,accountID)
	if err!=nil { return EssenceProfile{},fmt.Errorf("load soul absorption kinds: %w",err) }
	defer rows.Close()
	result.AbsorptionKinds=make([]AbsorptionKindProgress,0)
	for rows.Next() {
		var item AbsorptionKindProgress
		if err:=rows.Scan(&item.KindID,&item.Name,&item.Description,&item.BaseEnergy,&item.TraitKey,&item.Rarity,&item.InheritanceAttribute,&item.AbsorbedCount);err!=nil {
			return EssenceProfile{},fmt.Errorf("scan soul absorption kind: %w",err)
		}
		result.AbsorptionKinds=append(result.AbsorptionKinds,item)
	}
	if err:=rows.Err();err!=nil { return EssenceProfile{},fmt.Errorf("iterate soul absorption kinds: %w",err) }
	pendingRows,pendingErr:=s.db.QueryContext(ctx, `SELECT records.id::text,kinds.id,kinds.name,records.created_at::text FROM soul_absorption_records records JOIN soul_absorption_kinds kinds ON kinds.id=records.absorption_kind_id WHERE records.soul_id=(SELECT id FROM souls WHERE account_id=$1) AND records.absorption_kind_id='faceless_essence' AND records.selected_at IS NULL ORDER BY records.created_at`,accountID)
	if pendingErr!=nil{return EssenceProfile{},fmt.Errorf("load pending rare soul choices: %w",pendingErr)}
	defer pendingRows.Close()
	result.PendingRareChoices=make([]PendingRareChoice,0)
	for pendingRows.Next(){var choice PendingRareChoice;if err:=pendingRows.Scan(&choice.RecordID,&choice.KindID,&choice.KindName,&choice.CreatedAt);err!=nil{return EssenceProfile{},fmt.Errorf("scan pending rare soul choice: %w",err)};result.PendingRareChoices=append(result.PendingRareChoices,choice)}
	if err:=pendingRows.Err();err!=nil{return EssenceProfile{},fmt.Errorf("iterate pending rare soul choices: %w",err)}
	return result,nil
}


type Absorption struct {
 EventID string `json:"event_id"`
 SessionID string `json:"session_id"`
 CharacterID string `json:"character_id"`
 SourceEntityID string `json:"source_entity_id"`
 SourceEntityKind string `json:"source_entity_kind"`
}
type AbsorptionResult struct {
 Applied bool `json:"applied"`
 KindID string `json:"kind_id,omitempty"`
 KindName string `json:"kind_name,omitempty"`
 EnergyGained int64 `json:"energy_gained,omitempty"`
 AbsorbedEnergy int64 `json:"absorbed_energy"`
 AbsorptionCapacity int64 `json:"absorption_capacity"`
 AbsorbedCount int64 `json:"absorbed_count"`
 SoulPower int64 `json:"soul_power"`
}

// ApplyServerAbsorption accepts only a trusted world-server event. The entity kind
// is mapped through the server-owned catalogue; clients never submit energy or traits.
func (s *Service) ApplyServerAbsorption(ctx context.Context, nodeKey string, event Absorption) (AbsorptionResult, error) {
 if nodeKey == "" || !validUUID(event.EventID) || !validUUID(event.SessionID) ||
    !validUUID(event.CharacterID) || strings.TrimSpace(event.SourceEntityID) == "" ||
    len(event.SourceEntityID) > 96 || len(event.SourceEntityKind) > 48 {
  return AbsorptionResult{}, ErrInvalidAbsorption
 }
 kindID := ""
 switch event.SourceEntityKind {
 case "wandering_wraith":
  kindID = "ordinary_wraith"
 default:
  return AbsorptionResult{}, ErrInvalidAbsorption
 }
 tx, err := s.db.BeginTx(ctx, nil)
 if err != nil { return AbsorptionResult{}, fmt.Errorf("begin soul absorption: %w", err) }
 defer tx.Rollback()
 var serverID string
 err = tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key=$1`, nodeKey).Scan(&serverID)
 if errors.Is(err, sql.ErrNoRows) { return AbsorptionResult{}, ErrAbsorptionSession }
 if err != nil { return AbsorptionResult{}, fmt.Errorf("resolve absorption node: %w", err) }

 var soulID string
 err = tx.QueryRowContext(ctx,
  `SELECT soul.id::text
   FROM world_sessions ws
   JOIN world_instances instance ON instance.id=ws.instance_id
   JOIN world_definitions world ON world.id=instance.world_id
   JOIN characters character ON character.id=ws.character_id
   JOIN souls soul ON soul.id=character.soul_id
   WHERE ws.id=$1::uuid AND ws.server_id=$2 AND character.id=$3::uuid
     AND character.status='alive' AND world.id='underworld_fengdu'
     AND (ws.session_state='active' OR (ws.session_state='closed' AND ws.updated_at>=now()-INTERVAL '10 minutes'))
   FOR UPDATE OF ws,soul`, event.SessionID, serverID, event.CharacterID).Scan(&soulID)
 if errors.Is(err, sql.ErrNoRows) {
  var duplicate bool
  checkErr := tx.QueryRowContext(ctx,
   `SELECT EXISTS (SELECT 1 FROM soul_absorption_records
      WHERE soul_id=(SELECT soul_id FROM characters WHERE id=$1::uuid) AND event_id=$2::uuid)`,
   event.CharacterID,event.EventID).Scan(&duplicate)
  if checkErr != nil { return AbsorptionResult{}, fmt.Errorf("check duplicate absorption: %w",checkErr) }
  if duplicate {
   if err:=tx.Commit();err!=nil{return AbsorptionResult{},fmt.Errorf("commit duplicate absorption: %w",err)}
   return AbsorptionResult{Applied:false},nil
  }
  return AbsorptionResult{},ErrAbsorptionSession
 }
 if err != nil { return AbsorptionResult{},fmt.Errorf("verify absorption session: %w",err) }

 var result AbsorptionResult
 var traitKey string
 err=tx.QueryRowContext(ctx,
  `SELECT id,name,base_energy,trait_key FROM soul_absorption_kinds WHERE id=$1 AND enabled=true`,
  kindID).Scan(&result.KindID,&result.KindName,&result.EnergyGained,&traitKey)
 if err!=nil{return AbsorptionResult{},fmt.Errorf("load absorption kind: %w",err)}
 var capacity, absorbed int64
 err=tx.QueryRowContext(ctx,
  `SELECT absorption_capacity,absorbed_energy FROM soul_essence_attributes WHERE soul_id=$1 FOR UPDATE`,
  soulID).Scan(&capacity,&absorbed)
 if err!=nil{return AbsorptionResult{},fmt.Errorf("lock soul essence: %w",err)}
 if capacity<=absorbed{return AbsorptionResult{},ErrAbsorptionCapacity}
 remaining:=capacity-absorbed
 if result.EnergyGained>remaining { result.EnergyGained=remaining }
 inserted,err:=tx.ExecContext(ctx,
  `INSERT INTO soul_absorption_records
    (soul_id,event_id,source_entity_id,absorption_kind_id,energy_gained,trait_key,trait_value)
   VALUES ($1,$2::uuid,$3,$4,$5,$6,1) ON CONFLICT (soul_id,event_id) DO NOTHING`,
  soulID,event.EventID,event.SourceEntityID,result.KindID,result.EnergyGained,traitKey)
 if err!=nil{return AbsorptionResult{},fmt.Errorf("record soul absorption: %w",err)}
 rows,err:=inserted.RowsAffected()
 if err!=nil{return AbsorptionResult{},fmt.Errorf("read absorption insert result: %w",err)}
 if rows==0 {
  if err:=tx.Commit();err!=nil{return AbsorptionResult{},fmt.Errorf("commit duplicate absorption: %w",err)}
  return AbsorptionResult{Applied:false},nil
 }
 err=tx.QueryRowContext(ctx,
  `UPDATE soul_essence_attributes
   SET absorbed_energy=absorbed_energy+$1,absorbed_count=absorbed_count+1,
       soul_power=soul_power+$1,updated_at=now()
   WHERE soul_id=$2
   RETURNING absorbed_energy,absorption_capacity,absorbed_count,soul_power`,
  result.EnergyGained,soulID).Scan(&result.AbsorbedEnergy,&result.AbsorptionCapacity,&result.AbsorbedCount,&result.SoulPower)
 if err!=nil{return AbsorptionResult{},fmt.Errorf("apply soul essence absorption: %w",err)}
 result.Applied=true
 if err:=tx.Commit();err!=nil{return AbsorptionResult{},fmt.Errorf("commit soul absorption: %w",err)}
 return result,nil
}
