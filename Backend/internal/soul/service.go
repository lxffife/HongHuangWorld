package soul

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
)

var (
	ErrNotFound = errors.New("soul not found")
	ErrConflict = errors.New("soul already exists")
	ErrInvalid  = errors.New("invalid soul name")
	ErrInvalidReward = errors.New("invalid soul reward")
	ErrRewardSession = errors.New("soul reward session is not valid for this node")
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
 err = tx.QueryRowContext(ctx,
  `SELECT soul.id::text, progression.experience
   FROM world_sessions ws
   JOIN characters character ON character.id = ws.character_id
   JOIN souls soul ON soul.id = character.soul_id
   JOIN soul_progression progression ON progression.soul_id = soul.id
   WHERE ws.id = $1::uuid AND ws.server_id = $2 AND character.id = $3::uuid
     AND character.status = 'alive'
     AND (ws.session_state = 'active' OR (ws.session_state = 'closed' AND ws.updated_at >= now() - INTERVAL '10 minutes'))
   FOR UPDATE OF ws, soul, progression`, reward.SessionID, serverID, reward.CharacterID,
 ).Scan(&soulID, &currentExperience)
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
