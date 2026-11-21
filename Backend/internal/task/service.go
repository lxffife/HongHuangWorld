package task

import (
 "context"
 "encoding/base64"
 "database/sql"
 "encoding/hex"
 "encoding/json"
 "errors"
 "fmt"
 "math"
 "sort"
 "strings"
 "time"
 "unicode/utf8"

 "github.com/liflife/HongHuangWorld/Backend/internal/faction"
)

var (
 ErrInvalid = errors.New("invalid bounty task request")
 ErrNotFound = errors.New("bounty task not found")
 ErrForbidden = errors.New("bounty task permission denied")
 ErrInsufficientTreasury = errors.New("insufficient available balance")
 ErrAlreadyJoined = errors.New("account already joined this task")
 ErrIdempotencyConflict = errors.New("idempotency key conflict")
 ErrTaskFull = errors.New("bounty task is full")
 ErrTaskNotReady = errors.New("bounty task is not ready for this operation")
 ErrCharacterNotEligible = errors.New("current character does not meet bounty requirements")
 ErrNotParticipant = errors.New("account is not an active bounty participant")
 ErrInvalidWorldEvent = errors.New("invalid world bounty event")
 ErrWorldEventSession = errors.New("world event session is not valid for this node and task")
 ErrWorldEventObjective = errors.New("world event does not match a configured bounty objective")
)

type Service struct { db *sql.DB; factions *faction.Service }
func NewService(db *sql.DB, factions *faction.Service) *Service { return &Service{db:db,factions:factions} }

type Task struct {
 ID string `json:"id"`
 WorldID string `json:"world_id"`
 PublisherType string `json:"publisher_type"`
 PublisherID string `json:"publisher_id"`
 PublisherName string `json:"publisher_name"`
 Title string `json:"title"`
 Description string `json:"description"`
 CurrencyID string `json:"currency_id"`
 RewardAmount int64 `json:"reward_amount"`
 EscrowAmount int64 `json:"escrow_amount"`
 DifficultyTier int `json:"difficulty_tier"`
 RequiredRealmLevel int `json:"required_realm_level"`
 RequiredCharacterLevel int `json:"required_character_level"`
 MaxAssignees int `json:"max_assignees"`
 ParticipantCount int `json:"participant_count"`
 Status string `json:"status"`
 ExpiresAt *string `json:"expires_at,omitempty"`
 CreatedAt string `json:"created_at"`
}

type PublishRequest struct {
 EventKey string
 FactionID string
 Title string
 Description string
 CurrencyID string
 RewardAmount int64
 MaxAssignees int
 DifficultyTier int
 RequiredRealmLevel int
 RequiredCharacterLevel int
 Objectives []ObjectiveRequest
 ExpiresAt *string
}


type ObjectiveRequest struct {
 Key string `json:"key"`
 EventType string `json:"event_type"`
 TargetCount int `json:"target_count"`
}

type WorldEvent struct {
 EventID string `json:"event_id"`
 TaskID string `json:"task_id"`
 SessionID string `json:"session_id"`
 CharacterID string `json:"character_id"`
 ObjectiveKey string `json:"objective_key"`
 EventType string `json:"event_type"`
}

type WorldEventResult struct {
 Applied bool `json:"applied"`
 TaskID string `json:"task_id"`
 ObjectiveKey string `json:"objective_key"`
 Progress int `json:"progress"`
 Target int `json:"target"`
 Completed bool `json:"completed"`
}

func validUUID(value string) bool {
 if len(value)!=36 || value[8]!='-' || value[13]!='-' || value[18]!='-' || value[23]!='-' { return false }
 compact:=strings.ReplaceAll(value,"-","")
 if len(compact)!=32 { return false }
 _,err:=hex.DecodeString(compact)
 return err==nil
}

func validateObjectives(items []ObjectiveRequest) error {
 if len(items)>10 { return ErrInvalid }
 seen:=make(map[string]struct{},len(items))
 for _,item:=range items {
  if item.Key=="" || len(item.Key)>64 || item.TargetCount<1 || item.TargetCount>100000 { return ErrInvalid }
  for _,r:=range item.Key {
   if !(r>='a'&&r<='z') && !(r>='A'&&r<='Z') && !(r>='0'&&r<='9') && r!='_' && r!='-' && r!='.' { return ErrInvalid }
  }
  switch item.EventType {
  case "monster_killed","exploration_discovered","escort_checkpoint","item_collected":
  default: return ErrInvalid
  }
  if _,ok:=seen[item.Key];ok { return ErrInvalid }
  seen[item.Key]=struct{}{}
 }
 return nil
}

func (s *Service) PublishFaction(ctx context.Context, accountID string, req PublishRequest) (Task,error) {
 req.Title=strings.TrimSpace(req.Title); req.Description=strings.TrimSpace(req.Description)
 if validateObjectives(req.Objectives)!=nil { return Task{},ErrInvalid }
 if accountID=="" || req.FactionID=="" || req.EventKey=="" || len(req.EventKey)>128 || utf8.RuneCountInString(req.Title)<2 || utf8.RuneCountInString(req.Title)>96 ||
  utf8.RuneCountInString(req.Description)>2000 || len(req.CurrencyID)==0 || len(req.CurrencyID)>64 ||
  req.RewardAmount<=0 || req.MaxAssignees<1 || req.MaxAssignees>20 ||
  req.DifficultyTier<1 || req.DifficultyTier>10 || req.RequiredRealmLevel<0 || req.RequiredRealmLevel>1000 || req.RequiredCharacterLevel<1 || req.RequiredCharacterLevel>10000 ||
  req.RewardAmount>math.MaxInt64/int64(req.MaxAssignees) { return Task{},ErrInvalid }
 // First authorization gives a clear domain error; membership and role are rechecked
 // under the faction row lock in the publishing transaction below.
 if err:=s.factions.AuthorizeTaskPublisher(ctx,accountID,req.FactionID); err!=nil { return Task{},ErrForbidden }
 if req.ExpiresAt!=nil { expiry,parseErr:=time.Parse(time.RFC3339,*req.ExpiresAt); if parseErr!=nil || !expiry.After(time.Now()) { return Task{},ErrInvalid } }
 total:=req.RewardAmount*int64(req.MaxAssignees)
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil{return Task{},fmt.Errorf("begin bounty publication: %w",err)}
 defer tx.Rollback()
 var worldID,name,treasuryID,role string
 err=tx.QueryRowContext(ctx,`SELECT f.world_id,f.name,f.treasury_account_id::text,m.role
  FROM factions f JOIN faction_members m ON m.faction_id=f.id
  WHERE f.id=$1 AND f.status='active' AND m.account_id=$2 FOR UPDATE OF f,m`,req.FactionID,accountID).Scan(&worldID,&name,&treasuryID,&role)
 if errors.Is(err,sql.ErrNoRows){return Task{},ErrForbidden}; if err!=nil{return Task{},fmt.Errorf("lock faction publisher: %w",err)}
 if role!="leader" && role!="officer" {return Task{},ErrForbidden}
 var currencyOK bool
 if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(
  SELECT 1 FROM currency_definitions c JOIN currency_world_rules w ON w.currency_id=c.id
  WHERE c.id=$1 AND c.enabled AND w.world_id=$2
 )`,req.CurrencyID,worldID).Scan(&currencyOK);err!=nil{return Task{},fmt.Errorf("validate bounty currency: %w",err)}
 if !currencyOK{return Task{},ErrInvalid}
 var priorTaskID string
 err=tx.QueryRowContext(ctx,`SELECT id::text FROM bounty_tasks WHERE created_by=$1 AND request_key=$2`,accountID,req.EventKey).Scan(&priorTaskID)
 if err==nil{return Task{},ErrIdempotencyConflict}
 if !errors.Is(err,sql.ErrNoRows){return Task{},fmt.Errorf("check bounty publication idempotency: %w",err)}
 var available,frozen int64
 err=tx.QueryRowContext(ctx,`SELECT available_amount,frozen_amount FROM economy_treasury_balances
  WHERE treasury_account_id=$1 AND currency_id=$2 FOR UPDATE`,treasuryID,req.CurrencyID).Scan(&available,&frozen)
 if errors.Is(err,sql.ErrNoRows){return Task{},ErrInsufficientTreasury}; if err!=nil{return Task{},fmt.Errorf("lock faction treasury: %w",err)}
 if available<total{return Task{},ErrInsufficientTreasury}
 if frozen>math.MaxInt64-total{return Task{},ErrInvalid}
 if _,err=tx.ExecContext(ctx,`UPDATE economy_treasury_balances SET available_amount=available_amount-$3,
  frozen_amount=frozen_amount+$3,updated_at=now() WHERE treasury_account_id=$1 AND currency_id=$2`,treasuryID,req.CurrencyID,total);err!=nil{return Task{},fmt.Errorf("freeze faction bounty budget: %w",err)}
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_treasury_ledger_entries
  (treasury_account_id,currency_id,event_key,entry_type,delta,balance_after,frozen_delta,frozen_after,source_type,note)
  VALUES ($1,$2,concat('bounty-lock:',gen_random_uuid()::text),'bounty_lock',$3,$4,$5,$6,'bounty_task','宗门悬赏预算托管')`,treasuryID,req.CurrencyID,-total,available-total,total,frozen+total);err!=nil{return Task{},fmt.Errorf("record bounty treasury lock: %w",err)}
 var result Task
 err=tx.QueryRowContext(ctx,`INSERT INTO bounty_tasks
  (world_id,publisher_type,publisher_id,title,description,currency_id,reward_amount,escrow_amount,
   difficulty_tier,required_realm_level,required_character_level,max_assignees,expires_at,created_by,request_key)
  VALUES ($1,'faction',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
  RETURNING id::text,world_id,publisher_type,publisher_id::text,title,description,currency_id,
   reward_amount,escrow_amount,difficulty_tier,required_realm_level,required_character_level,max_assignees,status,expires_at::text,created_at::text`,
  worldID,req.FactionID,req.Title,req.Description,req.CurrencyID,req.RewardAmount,total,req.DifficultyTier,
  req.RequiredRealmLevel,req.RequiredCharacterLevel,req.MaxAssignees,req.ExpiresAt,accountID,req.EventKey).
  Scan(&result.ID,&result.WorldID,&result.PublisherType,&result.PublisherID,&result.Title,
   &result.Description,&result.CurrencyID,&result.RewardAmount,&result.EscrowAmount,&result.DifficultyTier,
   &result.RequiredRealmLevel,&result.RequiredCharacterLevel,&result.MaxAssignees,&result.Status,&result.ExpiresAt,&result.CreatedAt)
 if err!=nil{return Task{},fmt.Errorf("insert bounty task: %w",err)}
 result.PublisherName=name
 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_escrows(task_id,treasury_account_id,currency_id,amount)
  VALUES ($1,$2,$3,$4)`,result.ID,treasuryID,req.CurrencyID,total);err!=nil{return Task{},fmt.Errorf("create bounty escrow: %w",err)}
 for _,objective:=range req.Objectives {
  if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_objectives(task_id,objective_key,event_type,target_count)
   VALUES($1,$2,$3,$4)`,result.ID,objective.Key,objective.EventType,objective.TargetCount);err!=nil {
   return Task{},fmt.Errorf("create bounty objective: %w",err)
  }
 }
 if err=tx.Commit();err!=nil{return Task{},fmt.Errorf("commit bounty publication: %w",err)}
 return result,nil
}


func (s *Service) Contribute(ctx context.Context,accountID,factionID,currencyID,eventKey string,amount int64) error {
 if accountID==""||factionID==""||currencyID==""||len(currencyID)>64||eventKey==""||len(eventKey)>128||amount<=0{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin faction contribution: %w",err)};defer tx.Rollback()
 var worldID,treasuryID string
 err=tx.QueryRowContext(ctx,`SELECT f.world_id,f.treasury_account_id::text FROM factions f
  JOIN faction_members m ON m.faction_id=f.id WHERE f.id=$1 AND f.status='active' AND m.account_id=$2
  FOR UPDATE OF f`,factionID,accountID).Scan(&worldID,&treasuryID)
 if errors.Is(err,sql.ErrNoRows){return ErrForbidden};if err!=nil{return fmt.Errorf("authorize faction contribution: %w",err)}
 var valid bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM currency_definitions c JOIN currency_world_rules w ON w.currency_id=c.id
  WHERE c.id=$1 AND c.enabled AND w.world_id=$2)`,currencyID,worldID).Scan(&valid);err!=nil{return fmt.Errorf("validate contribution currency: %w",err)}
 if !valid{return ErrInvalid}
 var oldCurrency,oldSource string
 var oldDelta int64
 err=tx.QueryRowContext(ctx,`SELECT currency_id,delta,source_id FROM economy_ledger_entries WHERE account_id=$1 AND event_key=$2`,accountID,eventKey).Scan(&oldCurrency,&oldDelta,&oldSource)
 if err==nil { if oldCurrency!=currencyID||oldDelta!=-amount||oldSource!=factionID{return ErrIdempotencyConflict}; if err=tx.Commit();err!=nil{return fmt.Errorf("commit recovered faction contribution: %w",err)};return nil }
 if !errors.Is(err,sql.ErrNoRows){return fmt.Errorf("check faction contribution idempotency: %w",err)}
 var treasuryEventExists bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM economy_treasury_ledger_entries WHERE treasury_account_id=$1 AND event_key=$2)`,treasuryID,eventKey).Scan(&treasuryEventExists);err!=nil{return fmt.Errorf("check treasury contribution idempotency: %w",err)}
 if treasuryEventExists{return ErrIdempotencyConflict}
 if _,err=tx.ExecContext(ctx,`INSERT INTO currency_balances(account_id,currency_id) VALUES($1,$2)
  ON CONFLICT(account_id,currency_id) DO NOTHING`,accountID,currencyID);err!=nil{return fmt.Errorf("initialize contributor wallet: %w",err)}
 var available,frozen int64
 if err=tx.QueryRowContext(ctx,`SELECT available_amount,frozen_amount FROM currency_balances
  WHERE account_id=$1 AND currency_id=$2 FOR UPDATE`,accountID,currencyID).Scan(&available,&frozen);err!=nil{return fmt.Errorf("lock contributor wallet: %w",err)}
 if available<amount{return ErrInsufficientTreasury}
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_treasury_balances(treasury_account_id,currency_id)
  VALUES($1,$2) ON CONFLICT(treasury_account_id,currency_id) DO NOTHING`,treasuryID,currencyID);err!=nil{return fmt.Errorf("initialize faction treasury balance: %w",err)}
 var treasuryAvailable int64
 if err=tx.QueryRowContext(ctx,`SELECT available_amount FROM economy_treasury_balances
  WHERE treasury_account_id=$1 AND currency_id=$2 FOR UPDATE`,treasuryID,currencyID).Scan(&treasuryAvailable);err!=nil{return fmt.Errorf("lock faction treasury balance: %w",err)}
 if treasuryAvailable>math.MaxInt64-amount{return ErrInvalid}
 if _,err=tx.ExecContext(ctx,`UPDATE currency_balances SET available_amount=available_amount-$3,updated_at=now()
  WHERE account_id=$1 AND currency_id=$2`,accountID,currencyID,amount);err!=nil{return fmt.Errorf("debit contributor wallet: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE economy_treasury_balances SET available_amount=available_amount+$3,updated_at=now()
  WHERE treasury_account_id=$1 AND currency_id=$2`,treasuryID,currencyID,amount);err!=nil{return fmt.Errorf("credit faction treasury: %w",err)}
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_ledger_entries
  (account_id,currency_id,event_key,entry_type,delta,available_after,frozen_delta,frozen_after,source_type,source_id,note)
  VALUES($1,$2,$3,'spend',$4,$5,0,$6,'faction_contribution',$7,'宗门成员捐献')`,
  accountID,currencyID,eventKey,-amount,available-amount,frozen,factionID);err!=nil{return fmt.Errorf("record contributor ledger: %w",err)}
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_treasury_ledger_entries
  (treasury_account_id,currency_id,event_key,entry_type,delta,balance_after,source_type,source_id,note)
  VALUES($1,$2,$3,'contribution',$4,$5,'faction_contribution',$6,'成员向宗门财政捐献')`,
  treasuryID,currencyID,eventKey,amount,treasuryAvailable+amount,factionID);err!=nil{return fmt.Errorf("record faction treasury contribution: %w",err)}
 if err=tx.Commit();err!=nil{return fmt.Errorf("commit faction contribution: %w",err)}
 return nil
}

func (s *Service) ListOpen(ctx context.Context,worldID string)([]Task,error){
 if strings.TrimSpace(worldID)=="" || len(worldID)>64{return nil,ErrInvalid}
 rows,err:=s.db.QueryContext(ctx,`SELECT t.id::text,t.world_id,t.publisher_type,t.publisher_id::text,f.name,
  t.title,t.description,t.currency_id,t.reward_amount,t.escrow_amount,t.difficulty_tier,t.required_realm_level,t.required_character_level,
  t.max_assignees,(SELECT count(*) FROM bounty_task_participants p WHERE p.task_id=t.id AND p.status='accepted'),
  t.status,t.expires_at::text,t.created_at::text
  FROM bounty_tasks t JOIN factions f ON f.id=t.publisher_id
  WHERE t.world_id=$1 AND f.status='active' AND t.status IN ('open','in_progress')
   AND (t.expires_at IS NULL OR t.expires_at>now()) ORDER BY t.created_at DESC LIMIT 100`,worldID)
 if err!=nil{return nil,fmt.Errorf("list open bounty tasks: %w",err)}; defer rows.Close()
 result:=make([]Task,0)
 for rows.Next(){var item Task;if err:=rows.Scan(&item.ID,&item.WorldID,&item.PublisherType,&item.PublisherID,&item.PublisherName,
  &item.Title,&item.Description,&item.CurrencyID,&item.RewardAmount,&item.EscrowAmount,&item.DifficultyTier,
  &item.RequiredRealmLevel,&item.RequiredCharacterLevel,&item.MaxAssignees,&item.ParticipantCount,&item.Status,&item.ExpiresAt,&item.CreatedAt);err!=nil{return nil,fmt.Errorf("scan bounty task: %w",err)}
  result=append(result,item)}
 if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate bounty tasks: %w",err)}
 return result,nil
}


// validateJoinParticipation preserves stable domain errors for retries and
// enforces capacity after excluding an existing accepted participant.
func validateJoinParticipation(exists bool, participantStatus string, joined, max int) error {
 if exists {
  if participantStatus=="accepted" { return ErrAlreadyJoined }
  if participantStatus!="withdrawn" { return ErrTaskNotReady }
 }
 if max<1 || joined<0 { return ErrInvalid }
 if joined>=max { return ErrTaskFull }
 return nil
}

// Join validates the server-owned current character and locks its progression rows.
func (s *Service) Join(ctx context.Context,accountID,taskID string)error{
 if accountID==""||taskID==""{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin bounty join: %w",err)};defer tx.Rollback()
 var max,requiredRealm,requiredLevel int
 var status,worldID string
 var expires sql.NullTime
 err=tx.QueryRowContext(ctx,`SELECT max_assignees,status,expires_at,world_id,required_realm_level,required_character_level FROM bounty_tasks WHERE id=$1 FOR UPDATE`,taskID).Scan(&max,&status,&expires,&worldID,&requiredRealm,&requiredLevel)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock bounty task: %w",err)}
 if expires.Valid&&!expires.Time.After(time.Now()){return ErrTaskNotReady}
 if status!="open"&&status!="in_progress"&&status!="full"{return ErrTaskNotReady}
 // Check the caller's existing participation before capacity. Otherwise a member
 // retrying Join on a full task receives "task full" instead of "already joined".
 var priorStatus string
 priorErr:=tx.QueryRowContext(ctx,`SELECT status FROM bounty_task_participants WHERE task_id=$1 AND account_id=$2 FOR UPDATE`,taskID,accountID).Scan(&priorStatus)
 priorExists:=priorErr==nil
 if priorErr!=nil&&!errors.Is(priorErr,sql.ErrNoRows){return fmt.Errorf("check existing bounty participation: %w",priorErr)}
 if err:=validateJoinParticipation(priorExists,priorStatus,0,max);err!=nil{return err}
 if status=="full"{return ErrTaskFull}
 var characterID string
 err=tx.QueryRowContext(ctx,`SELECT c.id::text FROM souls s JOIN characters c ON c.id=s.current_character_id AND c.soul_id=s.id JOIN character_progression p ON p.character_id=c.id JOIN cultivation_realms realm ON realm.id=p.realm_id AND realm.system_id=p.system_id WHERE s.account_id=$1 AND c.status='alive' AND c.world_id=$2 AND c.level >= $3 AND realm.realm_order >= $4 FOR SHARE OF s,c,p`,accountID,worldID,requiredLevel,requiredRealm).Scan(&characterID)
 if errors.Is(err,sql.ErrNoRows){return ErrCharacterNotEligible};if err!=nil{return fmt.Errorf("validate current character bounty eligibility: %w",err)}
 var joined int
 if err=tx.QueryRowContext(ctx,`SELECT count(*) FROM bounty_task_participants WHERE task_id=$1 AND status='accepted'`,taskID).Scan(&joined);err!=nil{return fmt.Errorf("count bounty participants: %w",err)}
 if err:=validateJoinParticipation(priorExists,priorStatus,joined,max);err!=nil{return err}
 insertResult,insertErr:=tx.ExecContext(ctx,`INSERT INTO bounty_task_participants(task_id,account_id) VALUES($1,$2) ON CONFLICT(task_id,account_id) DO UPDATE SET status='accepted',joined_at=now() WHERE bounty_task_participants.status='withdrawn'`,taskID,accountID)
 if insertErr!=nil{return fmt.Errorf("join bounty task: %w",insertErr)}
 inserted,rowsErr:=insertResult.RowsAffected();if rowsErr!=nil{return fmt.Errorf("read bounty participant insert result: %w",rowsErr)}
 if inserted==0{return ErrAlreadyJoined}
 next:="in_progress";if joined+1>=max{next="full"}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_tasks SET status=$2,updated_at=now() WHERE id=$1`,taskID,next);err!=nil{return fmt.Errorf("update bounty task capacity: %w",err)}
 if err=tx.Commit();err!=nil{return fmt.Errorf("commit bounty join: %w",err)}
 return nil
}

// Leave atomically withdraws an accepted participant and releases their slot.
func (s *Service) Leave(ctx context.Context,accountID,taskID string)error{
 if accountID==""||taskID==""{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin bounty leave: %w",err)};defer tx.Rollback()
 var status string;var expires sql.NullTime
 err=tx.QueryRowContext(ctx,`SELECT status,expires_at FROM bounty_tasks WHERE id=$1 FOR UPDATE`,taskID).Scan(&status,&expires)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock bounty task for leave: %w",err)}
 if status!="open"&&status!="in_progress"&&status!="full"{return ErrTaskNotReady}
 if expires.Valid&&!expires.Time.After(time.Now()){return ErrTaskNotReady}
 result,err:=tx.ExecContext(ctx,`UPDATE bounty_task_participants SET status='withdrawn' WHERE task_id=$1 AND account_id=$2 AND status='accepted'`,taskID,accountID)
 if err!=nil{return fmt.Errorf("withdraw bounty participant: %w",err)}
 changed,err:=result.RowsAffected();if err!=nil{return fmt.Errorf("read bounty withdrawal result: %w",err)}
 if changed==0{return ErrNotParticipant}
 var remaining int
 if err=tx.QueryRowContext(ctx,`SELECT count(*) FROM bounty_task_participants WHERE task_id=$1 AND status='accepted'`,taskID).Scan(&remaining);err!=nil{return fmt.Errorf("count remaining bounty participants: %w",err)}
 next:="open";if remaining>0{next="in_progress"}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_tasks SET status=$2,updated_at=now() WHERE id=$1`,taskID,next);err!=nil{return fmt.Errorf("release bounty task capacity: %w",err)}
 if err=tx.Commit();err!=nil{return fmt.Errorf("commit bounty leave: %w",err)}
 return nil
}

type Settlement struct {
 TaskID string `json:"task_id"`
 EventKey string `json:"event_key"`
 ParticipantCount int `json:"participant_count"`
 PaidAmount int64 `json:"paid_amount"`
 RefundedAmount int64 `json:"refunded_amount"`
 CurrencyID string `json:"currency_id"`
}

// Settle approves all currently accepted participants for the fixed per-person
// reward. Treasury release, participant credits, immutable ledgers and terminal
// task state are committed together.
func (s *Service) Settle(ctx context.Context,accountID,taskID,eventKey string)(Settlement,error){
 if accountID==""||taskID==""||eventKey==""||len(eventKey)>128{return Settlement{},ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return Settlement{},fmt.Errorf("begin bounty settlement: %w",err)};defer tx.Rollback()
 // Serialize reuse of the same caller key across different tasks before checking
 // the global unique receipt constraint.
 var advisoryLockResult any
 if err=tx.QueryRowContext(ctx,`SELECT pg_advisory_xact_lock(hashtextextended($1,0))`,eventKey).Scan(&advisoryLockResult);err!=nil{return Settlement{},fmt.Errorf("lock bounty settlement idempotency key: %w",err)}
 var publisherID,treasuryID,currencyID,status,escrowStatus string
 var reward,escrowAmount int64
 var isExpired bool
 err=tx.QueryRowContext(ctx,`SELECT t.publisher_id::text,e.treasury_account_id::text,t.currency_id,t.status,
  t.reward_amount,e.amount,e.status,(t.expires_at IS NOT NULL AND t.expires_at<=now())
  FROM bounty_tasks t JOIN bounty_task_escrows e ON e.task_id=t.id
  WHERE t.id=$1 FOR UPDATE OF t,e`,taskID).Scan(&publisherID,&treasuryID,&currencyID,&status,&reward,&escrowAmount,&escrowStatus,&isExpired)
 if errors.Is(err,sql.ErrNoRows){return Settlement{},ErrNotFound};if err!=nil{return Settlement{},fmt.Errorf("lock bounty and escrow: %w",err)}
 var role string
 err=tx.QueryRowContext(ctx,`SELECT m.role FROM factions f JOIN faction_members m ON m.faction_id=f.id
  WHERE f.id=$1 AND f.status='active' AND m.account_id=$2 FOR UPDATE OF f,m`,publisherID,accountID).Scan(&role)
 if errors.Is(err,sql.ErrNoRows){return Settlement{},ErrForbidden};if err!=nil{return Settlement{},fmt.Errorf("authorize bounty settlement: %w",err)}
 if role!="leader"&&role!="officer"{return Settlement{},ErrForbidden}
 var prior Settlement
 var priorEvent string
 err=tx.QueryRowContext(ctx,`SELECT event_key,participant_count,paid_amount,refunded_amount
  FROM bounty_task_settlements WHERE task_id=$1`,taskID).Scan(&priorEvent,&prior.ParticipantCount,&prior.PaidAmount,&prior.RefundedAmount)
 if err==nil{
  if priorEvent!=eventKey{return Settlement{},ErrIdempotencyConflict}
  prior.TaskID=taskID;prior.EventKey=priorEvent;prior.CurrencyID=currencyID
  if err=tx.Commit();err!=nil{return Settlement{},fmt.Errorf("commit idempotent bounty settlement: %w",err)}
  return prior,nil
 }
 if !errors.Is(err,sql.ErrNoRows){return Settlement{},fmt.Errorf("read bounty settlement receipt: %w",err)}
 var eventKeyUsed bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM bounty_task_settlements WHERE event_key=$1 UNION ALL SELECT 1 FROM bounty_task_refunds WHERE event_key=$1)`,eventKey).Scan(&eventKeyUsed);err!=nil{return Settlement{},fmt.Errorf("check bounty settlement idempotency key: %w",err)}
 if eventKeyUsed{return Settlement{},ErrIdempotencyConflict}
 if isExpired || (status!="full"&&status!="in_progress"){return Settlement{},ErrTaskNotReady}
 if escrowStatus!="locked"{return Settlement{},ErrTaskNotReady}
 rows,err:=tx.QueryContext(ctx,`SELECT account_id::text FROM bounty_task_participants
  WHERE task_id=$1 AND status='accepted' ORDER BY account_id FOR UPDATE`,taskID)
 if err!=nil{return Settlement{},fmt.Errorf("lock bounty participants: %w",err)}
 participantIDs:=make([]string,0,20)
 for rows.Next(){var id string;if err=rows.Scan(&id);err!=nil{rows.Close();return Settlement{},fmt.Errorf("scan bounty participant: %w",err)};participantIDs=append(participantIDs,id)}
 if err=rows.Err();err!=nil{rows.Close();return Settlement{},fmt.Errorf("iterate bounty participants: %w",err)}
 if err=rows.Close();err!=nil{return Settlement{},fmt.Errorf("close bounty participant rows: %w",err)}
 if len(participantIDs)==0{return Settlement{},ErrTaskNotReady}
 if int64(len(participantIDs))>math.MaxInt64/reward{return Settlement{},ErrInvalid}
 paid:=reward*int64(len(participantIDs))
 if paid>escrowAmount{return Settlement{},fmt.Errorf("bounty escrow invariant violated: payout exceeds escrow")}
 refunded:=escrowAmount-paid
 var treasuryAvailable,treasuryFrozen int64
 err=tx.QueryRowContext(ctx,`SELECT available_amount,frozen_amount FROM economy_treasury_balances
  WHERE treasury_account_id=$1 AND currency_id=$2 FOR UPDATE`,treasuryID,currencyID).Scan(&treasuryAvailable,&treasuryFrozen)
 if err!=nil{return Settlement{},fmt.Errorf("lock bounty treasury balance: %w",err)}
 if treasuryFrozen<escrowAmount{return Settlement{},fmt.Errorf("bounty treasury frozen balance invariant violated")}
 if refunded>math.MaxInt64-treasuryAvailable{return Settlement{},fmt.Errorf("bounty treasury available balance overflow")}
 for _,participantID:=range participantIDs{
  if _,err=tx.ExecContext(ctx,`INSERT INTO currency_balances(account_id,currency_id)
   VALUES($1,$2) ON CONFLICT(account_id,currency_id) DO NOTHING`,participantID,currencyID);err!=nil{return Settlement{},fmt.Errorf("initialize bounty recipient wallet: %w",err)}
  var available,frozen int64
  if err=tx.QueryRowContext(ctx,`SELECT available_amount,frozen_amount FROM currency_balances
   WHERE account_id=$1 AND currency_id=$2 FOR UPDATE`,participantID,currencyID).Scan(&available,&frozen);err!=nil{return Settlement{},fmt.Errorf("lock bounty recipient wallet: %w",err)}
  if available>math.MaxInt64-reward{return Settlement{},fmt.Errorf("bounty recipient wallet overflow")}
  if _,err=tx.ExecContext(ctx,`UPDATE currency_balances SET available_amount=available_amount+$3,updated_at=now()
   WHERE account_id=$1 AND currency_id=$2`,participantID,currencyID,reward);err!=nil{return Settlement{},fmt.Errorf("credit bounty recipient: %w",err)}
  ledgerKey:="bounty-settle:"+taskID+":"+participantID
  if _,err=tx.ExecContext(ctx,`INSERT INTO economy_ledger_entries
   (account_id,currency_id,event_key,entry_type,delta,available_after,frozen_delta,frozen_after,source_type,source_id,note)
   VALUES($1,$2,$3,'escrow_release',$4,$5,0,$6,'bounty_task',$7,'宗门悬赏完成奖励')`,
   participantID,currencyID,ledgerKey,reward,available+reward,frozen,taskID);err!=nil{return Settlement{},fmt.Errorf("record bounty recipient ledger: %w",err)}
 }
 if _,err=tx.ExecContext(ctx,`UPDATE economy_treasury_balances SET available_amount=available_amount+$3,
  frozen_amount=frozen_amount-$4,updated_at=now() WHERE treasury_account_id=$1 AND currency_id=$2`,
  treasuryID,currencyID,refunded,escrowAmount);err!=nil{return Settlement{},fmt.Errorf("release bounty treasury escrow: %w",err)}
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_treasury_ledger_entries
  (treasury_account_id,currency_id,event_key,entry_type,delta,balance_after,frozen_delta,frozen_after,source_type,source_id,note)
  VALUES($1,$2,$3,'bounty_payout',$4,$5,$6,$7,'bounty_task',$8,'宗门悬赏结算：支付奖励并退回未使用预算')`,
  treasuryID,currencyID,"bounty-settle:"+taskID,refunded,treasuryAvailable+refunded,-escrowAmount,treasuryFrozen-escrowAmount,taskID);err!=nil{return Settlement{},fmt.Errorf("record bounty treasury settlement: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_task_participants SET status='completed'
  WHERE task_id=$1 AND status='accepted'`,taskID);err!=nil{return Settlement{},fmt.Errorf("complete bounty participants: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_task_escrows SET status='paid',updated_at=now()
  WHERE task_id=$1 AND status='locked'`,taskID);err!=nil{return Settlement{},fmt.Errorf("mark bounty escrow paid: %w",err)}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_tasks SET status='completed',updated_at=now() WHERE id=$1`,taskID);err!=nil{return Settlement{},fmt.Errorf("complete bounty task: %w",err)}
 result:=Settlement{TaskID:taskID,EventKey:eventKey,ParticipantCount:len(participantIDs),PaidAmount:paid,RefundedAmount:refunded,CurrencyID:currencyID}
 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_settlements(task_id,event_key,settled_by,participant_count,paid_amount,refunded_amount)
  VALUES($1,$2,$3,$4,$5,$6)`,taskID,eventKey,accountID,len(participantIDs),paid,refunded);err!=nil{return Settlement{},fmt.Errorf("write bounty settlement receipt: %w",err)}
 if err=tx.Commit();err!=nil{return Settlement{},fmt.Errorf("commit bounty settlement: %w",err)}
 return result,nil
}


type RefundReceipt struct {
 TaskID string `json:"task_id"`
 EventKey string `json:"event_key"`
 RefundedAmount int64 `json:"refunded_amount"`
 CurrencyID string `json:"currency_id"`
 Status string `json:"status"`
}

// Cancel refunds the complete escrow. The publisher may cancel even after members
// joined; accepted participants are marked cancelled in the same transaction.
func (s *Service) Cancel(ctx context.Context, accountID, taskID, eventKey string) (RefundReceipt, error) {
 if accountID == "" { return RefundReceipt{}, ErrInvalid }
 return s.refund(ctx, accountID, taskID, eventKey, false)
}

// ExpireDue refunds due tasks in bounded batches. It is intended for a trusted
// scheduler/worker authenticated by the World Server API key, not the game client.
func (s *Service) ExpireDue(ctx context.Context, limit int) (int, error) {
 if limit < 1 || limit > 100 { return 0, ErrInvalid }
 rows, err := s.db.QueryContext(ctx, `SELECT t.id::text FROM bounty_tasks t
  JOIN bounty_task_escrows e ON e.task_id=t.id
  WHERE t.status IN ('open','in_progress','full') AND e.status='locked'
   AND t.expires_at IS NOT NULL AND t.expires_at<=now()
  ORDER BY t.expires_at,t.id LIMIT $1`, limit)
 if err != nil { return 0, fmt.Errorf("list expired bounty tasks: %w", err) }
 ids := make([]string,0,limit)
 for rows.Next() { var id string; if err=rows.Scan(&id); err!=nil { rows.Close(); return 0, fmt.Errorf("scan expired bounty task: %w",err) }; ids=append(ids,id) }
 if err=rows.Err(); err!=nil { rows.Close(); return 0, fmt.Errorf("iterate expired bounty tasks: %w",err) }
 if err=rows.Close(); err!=nil { return 0, fmt.Errorf("close expired bounty tasks: %w",err) }
 refunded := 0
 for _, id := range ids {
  _, err = s.refund(ctx, "", id, "bounty-expire:"+id, true)
  if errors.Is(err, ErrTaskNotReady) { continue } // Another worker settled/cancelled it first.
  if err != nil { return refunded, err }
  refunded++
 }
 return refunded,nil
}

func (s *Service) refund(ctx context.Context, accountID, taskID, eventKey string, expired bool) (RefundReceipt,error) {
 if taskID=="" || eventKey=="" || len(eventKey)>128 { return RefundReceipt{},ErrInvalid }
 tx,err:=s.db.BeginTx(ctx,nil); if err!=nil { return RefundReceipt{},fmt.Errorf("begin bounty refund: %w",err) }; defer tx.Rollback()
 var lockResult any
 if err=tx.QueryRowContext(ctx,`SELECT pg_advisory_xact_lock(hashtextextended($1,0))`,eventKey).Scan(&lockResult); err!=nil { return RefundReceipt{},fmt.Errorf("lock bounty refund idempotency key: %w",err) }
 var publisherID,treasuryID,currencyID,status,escrowStatus string
 var amount int64
 err=tx.QueryRowContext(ctx,`SELECT t.publisher_id::text,e.treasury_account_id::text,t.currency_id,t.status,e.amount,e.status
  FROM bounty_tasks t JOIN bounty_task_escrows e ON e.task_id=t.id
  WHERE t.id=$1 FOR UPDATE OF t,e`,taskID).Scan(&publisherID,&treasuryID,&currencyID,&status,&amount,&escrowStatus)
 if errors.Is(err,sql.ErrNoRows) { return RefundReceipt{},ErrNotFound }
 if err!=nil { return RefundReceipt{},fmt.Errorf("lock bounty and escrow for refund: %w",err) }

 if !expired {
  var role string
  err=tx.QueryRowContext(ctx,`SELECT m.role FROM factions f JOIN faction_members m ON m.faction_id=f.id
   WHERE f.id=$1 AND f.status='active' AND m.account_id=$2 FOR UPDATE OF f,m`,publisherID,accountID).Scan(&role)
  if errors.Is(err,sql.ErrNoRows) { return RefundReceipt{},ErrForbidden }
  if err!=nil { return RefundReceipt{},fmt.Errorf("authorize bounty cancellation: %w",err) }
  if role!="leader" && role!="officer" { return RefundReceipt{},ErrForbidden }
 } else {
  var due bool
  if err=tx.QueryRowContext(ctx,`SELECT expires_at IS NOT NULL AND expires_at<=now() FROM bounty_tasks WHERE id=$1`,taskID).Scan(&due);err!=nil { return RefundReceipt{},fmt.Errorf("verify bounty expiry: %w",err) }
  if !due { return RefundReceipt{},ErrTaskNotReady }
 }

 var prior RefundReceipt
 var priorKey string
 err=tx.QueryRowContext(ctx,`SELECT event_key,refunded_amount FROM bounty_task_refunds WHERE task_id=$1`,taskID).Scan(&priorKey,&prior.RefundedAmount)
 if err==nil {
  if priorKey!=eventKey { return RefundReceipt{},ErrIdempotencyConflict }
  prior.TaskID=taskID; prior.EventKey=priorKey; prior.CurrencyID=currencyID
  prior.Status=status
  if err=tx.Commit();err!=nil { return RefundReceipt{},fmt.Errorf("commit idempotent bounty refund: %w",err) }
  return prior,nil
 }
 if !errors.Is(err,sql.ErrNoRows) { return RefundReceipt{},fmt.Errorf("read bounty refund receipt: %w",err) }
 var keyUsed bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(
   SELECT 1 FROM bounty_task_refunds WHERE event_key=$1
   UNION ALL SELECT 1 FROM bounty_task_settlements WHERE event_key=$1
  )`,eventKey).Scan(&keyUsed);err!=nil { return RefundReceipt{},fmt.Errorf("check bounty refund idempotency key: %w",err) }
 if keyUsed { return RefundReceipt{},ErrIdempotencyConflict }
 var settled bool
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM bounty_task_settlements WHERE task_id=$1)`,taskID).Scan(&settled);err!=nil { return RefundReceipt{},fmt.Errorf("check bounty settlement before refund: %w",err) }
 if settled || escrowStatus!="locked" || (status!="open" && status!="in_progress" && status!="full") { return RefundReceipt{},ErrTaskNotReady }

 var treasuryAvailable,treasuryFrozen int64
 err=tx.QueryRowContext(ctx,`SELECT available_amount,frozen_amount FROM economy_treasury_balances
  WHERE treasury_account_id=$1 AND currency_id=$2 FOR UPDATE`,treasuryID,currencyID).Scan(&treasuryAvailable,&treasuryFrozen)
 if err!=nil { return RefundReceipt{},fmt.Errorf("lock bounty treasury for refund: %w",err) }
 if treasuryFrozen<amount { return RefundReceipt{},fmt.Errorf("bounty treasury frozen balance invariant violated") }
 if treasuryAvailable>math.MaxInt64-amount { return RefundReceipt{},fmt.Errorf("bounty treasury available balance overflow") }
 if _,err=tx.ExecContext(ctx,`UPDATE economy_treasury_balances
  SET available_amount=available_amount+$3,frozen_amount=frozen_amount-$4,updated_at=now()
  WHERE treasury_account_id=$1 AND currency_id=$2`,treasuryID,currencyID,amount,amount);err!=nil { return RefundReceipt{},fmt.Errorf("release bounty escrow refund: %w",err) }

 nextStatus:="cancelled"; ledgerType:="bounty_refund"; note:="宗门主动取消悬赏，全额退回托管预算"
 if expired { nextStatus="expired"; note="悬赏到期，全额退回托管预算" }
 var refundedBy any
 if accountID!="" { refundedBy=accountID }
 if _,err=tx.ExecContext(ctx,`INSERT INTO economy_treasury_ledger_entries
  (treasury_account_id,currency_id,event_key,entry_type,delta,balance_after,frozen_delta,frozen_after,source_type,source_id,note)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,'bounty_task',$9,$10)`,
  treasuryID,currencyID,"bounty-refund:"+taskID,ledgerType,amount,treasuryAvailable+amount,-amount,treasuryFrozen-amount,taskID,note);err!=nil {
  return RefundReceipt{},fmt.Errorf("record bounty treasury refund: %w",err)
 }
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_task_participants SET status='cancelled'
  WHERE task_id=$1 AND status='accepted'`,taskID);err!=nil { return RefundReceipt{},fmt.Errorf("cancel bounty participants: %w",err) }
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_task_escrows SET status='refunded',updated_at=now()
  WHERE task_id=$1 AND status='locked'`,taskID);err!=nil { return RefundReceipt{},fmt.Errorf("mark bounty escrow refunded: %w",err) }
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_tasks SET status=$2,updated_at=now() WHERE id=$1`,taskID,nextStatus);err!=nil { return RefundReceipt{},fmt.Errorf("update refunded bounty task: %w",err) }
 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_refunds(task_id,event_key,refunded_by,refunded_amount,reason)
  VALUES($1,$2,$3,$4,$5)`,taskID,eventKey,refundedBy,amount,nextStatus);err!=nil { return RefundReceipt{},fmt.Errorf("write bounty refund receipt: %w",err) }
 result:=RefundReceipt{TaskID:taskID,EventKey:eventKey,RefundedAmount:amount,CurrencyID:currencyID,Status:nextStatus}
 if err=tx.Commit();err!=nil { return RefundReceipt{},fmt.Errorf("commit bounty refund: %w",err) }
 return result,nil
}
 
type ObjectiveProgress struct {
 Key string `json:"key"`
 EventType string `json:"event_type"`
 Progress int `json:"progress"`
 Target int `json:"target"`
 Completed bool `json:"completed"`
}

type ParticipantProgress struct {
 TaskID string `json:"task_id"`
 Objectives []ObjectiveProgress `json:"objectives"`
}

// GetProgress returns objective counters only for the requesting participant.
func (s *Service) GetProgress(ctx context.Context,accountID,taskID string)(ParticipantProgress,error) {
 if accountID=="" || !validUUID(taskID) { return ParticipantProgress{},ErrInvalid }
 taskID=strings.ToLower(taskID)
 var exists bool
 if err:=s.db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM bounty_task_participants WHERE task_id=$1::uuid AND account_id=$2::uuid)`,taskID,accountID).Scan(&exists);err!=nil {
  return ParticipantProgress{},fmt.Errorf("verify bounty progress participant: %w",err)
 }
 if !exists { return ParticipantProgress{},ErrNotParticipant }
 rows,err:=s.db.QueryContext(ctx,`SELECT o.objective_key,o.event_type,COALESCE(p.progress_count,0),o.target_count,(p.completed_at IS NOT NULL)
  FROM bounty_task_objectives o LEFT JOIN bounty_task_objective_progress p
   ON p.task_id=o.task_id AND p.objective_key=o.objective_key AND p.account_id=$2::uuid
  WHERE o.task_id=$1::uuid ORDER BY o.objective_key`,taskID,accountID)
 if err!=nil { return ParticipantProgress{},fmt.Errorf("list bounty objective progress: %w",err) }
 defer rows.Close()
 result:=ParticipantProgress{TaskID:taskID,Objectives:make([]ObjectiveProgress,0)}
 for rows.Next() {
  var item ObjectiveProgress
  if err:=rows.Scan(&item.Key,&item.EventType,&item.Progress,&item.Target,&item.Completed);err!=nil { return ParticipantProgress{},fmt.Errorf("scan bounty objective progress: %w",err) }
  result.Objectives=append(result.Objectives,item)
 }
 if err:=rows.Err();err!=nil { return ParticipantProgress{},fmt.Errorf("iterate bounty objective progress: %w",err) }
 return result,nil
}

type ObjectiveSubscription struct {
 TaskID string `json:"task_id"`
 ObjectiveKey string `json:"objective_key"`
 EventType string `json:"event_type"`
}

// ListActiveObjectives returns only objectives belonging to the authenticated
// character's accepted, active bounty tasks on the node that hosts its session.
func (s *Service) ListActiveObjectives(ctx context.Context, nodeKey, sessionID, characterID string) ([]ObjectiveSubscription, error) {
 if strings.TrimSpace(nodeKey)=="" || len(nodeKey)>96 || !validUUID(sessionID) || !validUUID(characterID) {
  return nil, ErrInvalidWorldEvent
 }
 sessionID=strings.ToLower(sessionID)
 characterID=strings.ToLower(characterID)
 tx,err:=s.db.BeginTx(ctx,nil)
 if err!=nil { return nil,fmt.Errorf("begin active bounty objective lookup: %w",err) }
 defer tx.Rollback()
 var accountID, worldID string
 err=tx.QueryRowContext(ctx,`SELECT soul.account_id::text,c.world_id
  FROM world_sessions ws
  JOIN server_registry node ON node.id=ws.server_id
  JOIN world_instances instance ON instance.id=ws.instance_id
  JOIN characters c ON c.id=ws.character_id
  JOIN souls soul ON soul.id=c.soul_id
  WHERE ws.id=$1::uuid AND ws.character_id=$2::uuid AND node.node_key=$3
   AND ws.session_state='active' AND node.admin_state='normal'
   AND c.status='alive' AND soul.current_character_id=c.id
   AND c.world_id=instance.world_id
  FOR SHARE OF ws,c,soul`,sessionID,characterID,nodeKey).Scan(&accountID,&worldID)
 if errors.Is(err,sql.ErrNoRows) { return nil,ErrWorldEventSession }
 if err!=nil { return nil,fmt.Errorf("resolve active bounty objective session: %w",err) }
 rows,err:=tx.QueryContext(ctx,`SELECT t.id::text,o.objective_key,o.event_type
  FROM bounty_tasks t
  JOIN bounty_task_participants p ON p.task_id=t.id
  JOIN bounty_task_objectives o ON o.task_id=t.id
  WHERE p.account_id=$1::uuid AND p.status='accepted'
   AND t.world_id=$2 AND t.status IN ('in_progress','full')
   AND (t.expires_at IS NULL OR t.expires_at>now())
  ORDER BY t.id,o.objective_key`,accountID,worldID)
 if err!=nil { return nil,fmt.Errorf("list active bounty objectives: %w",err) }
 defer rows.Close()
 result:=make([]ObjectiveSubscription,0)
 for rows.Next() {
  var item ObjectiveSubscription
  if err:=rows.Scan(&item.TaskID,&item.ObjectiveKey,&item.EventType);err!=nil { return nil,fmt.Errorf("scan active bounty objective: %w",err) }
  result=append(result,item)
 }
 if err:=rows.Err();err!=nil { return nil,fmt.Errorf("iterate active bounty objectives: %w",err) }
 if err:=tx.Commit();err!=nil { return nil,fmt.Errorf("commit active bounty objective lookup: %w",err) }
 return result,nil
}

// ApplyWorldEvent accepts one unit of progress from the authenticated node that
// currently hosts the character. Account identity and progress increments are
// derived by the center service; callers cannot submit either value.
func (s *Service) ApplyWorldEvent(ctx context.Context,nodeKey string,event WorldEvent)(WorldEventResult,error) {
 if strings.TrimSpace(nodeKey)=="" || len(nodeKey)>96 || !validUUID(event.EventID) ||
  !validUUID(event.TaskID) || !validUUID(event.SessionID) || !validUUID(event.CharacterID) ||
  event.ObjectiveKey=="" || len(event.ObjectiveKey)>64 {
  return WorldEventResult{},ErrInvalidWorldEvent
 }
 event.EventID=strings.ToLower(event.EventID); event.TaskID=strings.ToLower(event.TaskID)
 event.SessionID=strings.ToLower(event.SessionID); event.CharacterID=strings.ToLower(event.CharacterID)
 tx,err:=s.db.BeginTx(ctx,nil)
 if err!=nil { return WorldEventResult{},fmt.Errorf("begin verified bounty event: %w",err) }
 defer tx.Rollback()
 var lock any
 if err=tx.QueryRowContext(ctx,`SELECT pg_advisory_xact_lock(hashtextextended($1,0))`,event.EventID).Scan(&lock);err!=nil {
  return WorldEventResult{},fmt.Errorf("lock bounty event idempotency key: %w",err)
 }
 var oldTask,oldAccount,oldCharacter,oldSession,oldNode,oldObjective,oldType string
 err=tx.QueryRowContext(ctx,`SELECT task_id::text,account_id::text,character_id::text,session_id::text,node_key,objective_key,event_type
  FROM bounty_task_events WHERE event_id=$1::uuid`,event.EventID).
  Scan(&oldTask,&oldAccount,&oldCharacter,&oldSession,&oldNode,&oldObjective,&oldType)
 if err==nil {
  if oldTask!=event.TaskID || oldCharacter!=event.CharacterID || oldSession!=event.SessionID ||
   oldNode!=nodeKey || oldObjective!=event.ObjectiveKey || oldType!=event.EventType {
   return WorldEventResult{},ErrIdempotencyConflict
  }
  var result WorldEventResult
  result.TaskID=event.TaskID
  result.ObjectiveKey=event.ObjectiveKey
  err=tx.QueryRowContext(ctx,`SELECT p.progress_count,o.target_count,(p.completed_at IS NOT NULL)
   FROM bounty_task_objective_progress p JOIN bounty_task_objectives o
    ON o.task_id=p.task_id AND o.objective_key=p.objective_key
   WHERE p.task_id=$1::uuid AND p.account_id=$2::uuid AND p.objective_key=$3`,
   event.TaskID,oldAccount,event.ObjectiveKey).Scan(&result.Progress,&result.Target,&result.Completed)
  if err!=nil { return WorldEventResult{},fmt.Errorf("read idempotent bounty progress: %w",err) }
  if err=tx.Commit();err!=nil { return WorldEventResult{},fmt.Errorf("commit duplicate bounty event: %w",err) }
  result.Applied=false
  return result,nil
 }
 if !errors.Is(err,sql.ErrNoRows) { return WorldEventResult{},fmt.Errorf("check bounty event idempotency: %w",err) }

 var worldID,status string
 var expired bool
 err=tx.QueryRowContext(ctx,`SELECT world_id,status,(expires_at IS NOT NULL AND expires_at<=now())
  FROM bounty_tasks WHERE id=$1::uuid FOR SHARE`,event.TaskID).Scan(&worldID,&status,&expired)
 if errors.Is(err,sql.ErrNoRows) { return WorldEventResult{},ErrNotFound }
 if err!=nil { return WorldEventResult{},fmt.Errorf("verify bounty task state: %w",err) }
 if expired || (status!="in_progress" && status!="full") { return WorldEventResult{},ErrTaskNotReady }

 var accountID string
 err=tx.QueryRowContext(ctx,`SELECT soul.account_id::text
  FROM world_sessions ws
  JOIN server_registry node ON node.id=ws.server_id
  JOIN world_instances instance ON instance.id=ws.instance_id
  JOIN characters c ON c.id=ws.character_id
  JOIN souls soul ON soul.id=c.soul_id
  WHERE ws.id=$1::uuid AND ws.character_id=$2::uuid AND node.node_key=$3
   AND ws.session_state='active' AND node.admin_state='normal'
   AND c.status='alive' AND soul.current_character_id=c.id
   AND c.world_id=$4 AND instance.world_id=$4
  FOR SHARE OF ws,c,soul`,event.SessionID,event.CharacterID,nodeKey,worldID).Scan(&accountID)
 if errors.Is(err,sql.ErrNoRows) { return WorldEventResult{},ErrWorldEventSession }
 if err!=nil { return WorldEventResult{},fmt.Errorf("verify bounty world session: %w",err) }

 var participantStatus string
 err=tx.QueryRowContext(ctx,`SELECT status FROM bounty_task_participants
  WHERE task_id=$1::uuid AND account_id=$2::uuid FOR SHARE`,event.TaskID,accountID).Scan(&participantStatus)
 if errors.Is(err,sql.ErrNoRows) { return WorldEventResult{},ErrNotParticipant }
 if err!=nil { return WorldEventResult{},fmt.Errorf("verify bounty participant: %w",err) }
 if participantStatus!="accepted" { return WorldEventResult{},ErrNotParticipant }

 var configuredType string
 var target int
 err=tx.QueryRowContext(ctx,`SELECT event_type,target_count FROM bounty_task_objectives
  WHERE task_id=$1::uuid AND objective_key=$2 FOR SHARE`,event.TaskID,event.ObjectiveKey).Scan(&configuredType,&target)
 if errors.Is(err,sql.ErrNoRows) { return WorldEventResult{},ErrWorldEventObjective }
 if err!=nil { return WorldEventResult{},fmt.Errorf("load bounty objective: %w",err) }
 if configuredType!=event.EventType { return WorldEventResult{},ErrWorldEventObjective }

 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_events
  (event_id,task_id,account_id,character_id,session_id,node_key,objective_key,event_type)
  VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8)`,
  event.EventID,event.TaskID,accountID,event.CharacterID,event.SessionID,nodeKey,event.ObjectiveKey,event.EventType);err!=nil {
  return WorldEventResult{},fmt.Errorf("record immutable bounty event: %w",err)
 }
 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_objective_progress
  (task_id,account_id,objective_key,progress_count,completed_at)
  VALUES($1::uuid,$2::uuid,$3,1,CASE WHEN $4=1 THEN now() ELSE NULL END)
  ON CONFLICT(task_id,account_id,objective_key) DO UPDATE SET
   progress_count=LEAST(bounty_task_objective_progress.progress_count+1,$4),
   completed_at=CASE WHEN bounty_task_objective_progress.progress_count+1 >= $4
    THEN COALESCE(bounty_task_objective_progress.completed_at,now())
    ELSE bounty_task_objective_progress.completed_at END,
   updated_at=now()`,event.TaskID,accountID,event.ObjectiveKey,target);err!=nil {
  return WorldEventResult{},fmt.Errorf("advance bounty objective progress: %w",err)
 }
 result:=WorldEventResult{Applied:true,TaskID:event.TaskID,ObjectiveKey:event.ObjectiveKey}
 err=tx.QueryRowContext(ctx,`SELECT p.progress_count,o.target_count,(p.completed_at IS NOT NULL)
  FROM bounty_task_objective_progress p JOIN bounty_task_objectives o
   ON o.task_id=p.task_id AND o.objective_key=p.objective_key
  WHERE p.task_id=$1::uuid AND p.account_id=$2::uuid AND p.objective_key=$3`,
  event.TaskID,accountID,event.ObjectiveKey).Scan(&result.Progress,&result.Target,&result.Completed)
 if err!=nil { return WorldEventResult{},fmt.Errorf("read updated bounty progress: %w",err) }
 if err=tx.Commit();err!=nil { return WorldEventResult{},fmt.Errorf("commit verified bounty event: %w",err) }
 return result,nil
}



// MonsterContribution is server-measured effective damage from one authenticated
// character session. It is audit data only; it does not change objective progress
// or settlement until the team-contribution rules are explicitly defined.
type MonsterContribution struct {
 SessionID string `json:"session_id"`
 CharacterID string `json:"character_id"`
 Damage int64 `json:"damage"`
 HitCount int64 `json:"hit_count"`
}

type MonsterContributionEvent struct {
 EventID string `json:"event_id"`
 TaskID string `json:"task_id"`
 MonsterInstanceID string `json:"monster_instance_id"`
 MonsterDefinitionID string `json:"monster_definition_id"`
 Contributors []MonsterContribution `json:"contributors"`
}

// RecordMonsterContributions stores an immutable, idempotent contribution
// snapshot. Historical sessions are accepted so a contributor need not remain
// online when the death event is delivered from the durable WorldServer outbox.
func (s *Service) RecordMonsterContributions(ctx context.Context, nodeKey string, event MonsterContributionEvent) error {
 if strings.TrimSpace(nodeKey)=="" || len(nodeKey)>96 || !validUUID(event.EventID) ||
  !validUUID(event.TaskID) || event.MonsterInstanceID=="" || len(event.MonsterInstanceID)>96 ||
  event.MonsterDefinitionID=="" || len(event.MonsterDefinitionID)>64 ||
  len(event.Contributors)<1 || len(event.Contributors)>256 {
  return ErrInvalidWorldEvent
 }
 event.EventID=strings.ToLower(event.EventID)
 event.TaskID=strings.ToLower(event.TaskID)
 seen:=make(map[string]struct{},len(event.Contributors))
 var totalDamage int64
 for i:=range event.Contributors {
  item:=&event.Contributors[i]
  if !validUUID(item.SessionID) || !validUUID(item.CharacterID) || item.Damage<=0 || item.HitCount<=0 ||
   totalDamage>math.MaxInt64-item.Damage { return ErrInvalidWorldEvent }
  item.SessionID=strings.ToLower(item.SessionID)
  item.CharacterID=strings.ToLower(item.CharacterID)
  key:=item.SessionID+":"+item.CharacterID
  if _,ok:=seen[key];ok { return ErrInvalidWorldEvent }
  seen[key]=struct{}{}
  totalDamage+=item.Damage
 }
 sort.Slice(event.Contributors,func(i,j int)bool {
  if event.Contributors[i].SessionID!=event.Contributors[j].SessionID { return event.Contributors[i].SessionID<event.Contributors[j].SessionID }
  return event.Contributors[i].CharacterID<event.Contributors[j].CharacterID
 })
 payload,err:=json.Marshal(event)
 if err!=nil { return fmt.Errorf("encode monster contribution snapshot: %w",err) }
 tx,err:=s.db.BeginTx(ctx,nil)
 if err!=nil { return fmt.Errorf("begin monster contribution event: %w",err) }
 defer tx.Rollback()
 var lock any
 if err=tx.QueryRowContext(ctx,`SELECT pg_advisory_xact_lock(hashtextextended($1,0))`,event.EventID).Scan(&lock);err!=nil {
  return fmt.Errorf("lock monster contribution event id: %w",err)
 }
 var existingNodeKey string
 err=tx.QueryRowContext(ctx,`SELECT node_key FROM bounty_monster_contribution_events WHERE event_id=$1::uuid`,event.EventID).Scan(&existingNodeKey)
 if err==nil {
  if existingNodeKey!=nodeKey { return ErrIdempotencyConflict }
  var same bool
  if err=tx.QueryRowContext(ctx,`SELECT payload=$2::jsonb FROM bounty_monster_contribution_events WHERE event_id=$1::uuid`,event.EventID,string(payload)).Scan(&same);err!=nil {
   return fmt.Errorf("compare duplicate monster contribution event: %w",err)
  }
  if !same { return ErrIdempotencyConflict }
  return tx.Commit()
 }
 if !errors.Is(err,sql.ErrNoRows) { return fmt.Errorf("check monster contribution event: %w",err) }

 var worldID,status string
 var expired bool
 err=tx.QueryRowContext(ctx,`SELECT world_id,status,(expires_at IS NOT NULL AND expires_at<=now())
  FROM bounty_tasks WHERE id=$1::uuid FOR SHARE`,event.TaskID).Scan(&worldID,&status,&expired)
 if errors.Is(err,sql.ErrNoRows) { return ErrNotFound }
 if err!=nil { return fmt.Errorf("verify contribution bounty task: %w",err) }
 if expired || (status!="in_progress" && status!="full") { return ErrTaskNotReady }
 var objectiveType string
 err=tx.QueryRowContext(ctx,`SELECT event_type FROM bounty_task_objectives
  WHERE task_id=$1::uuid AND objective_key=$2 FOR SHARE`,event.TaskID,event.MonsterDefinitionID).Scan(&objectiveType)
 if errors.Is(err,sql.ErrNoRows) || (err==nil && objectiveType!="monster_killed") { return ErrWorldEventObjective }
 if err!=nil { return fmt.Errorf("verify monster contribution objective: %w",err) }

 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_monster_contribution_events
  (event_id,task_id,node_key,monster_instance_id,monster_definition_id,payload)
  VALUES($1::uuid,$2::uuid,$3,$4,$5,$6::jsonb)`,
  event.EventID,event.TaskID,nodeKey,event.MonsterInstanceID,event.MonsterDefinitionID,string(payload));err!=nil {
  return fmt.Errorf("insert monster contribution event: %w",err)
 }
 acceptedContributors:=0
 for _,item:=range event.Contributors {
  var accountID string
  err=tx.QueryRowContext(ctx,`SELECT soul.account_id::text
   FROM world_sessions ws
   JOIN server_registry node ON node.id=ws.server_id
   JOIN world_instances instance ON instance.id=ws.instance_id
   JOIN characters c ON c.id=ws.character_id
   JOIN souls soul ON soul.id=c.soul_id
   WHERE ws.id=$1::uuid AND ws.character_id=$2::uuid AND node.node_key=$3
    AND node.admin_state='normal' AND ws.session_state IN ('active','saving','closed')
    AND c.world_id=$4 AND instance.world_id=$4
   FOR SHARE OF ws,c,soul`,item.SessionID,item.CharacterID,nodeKey,worldID).Scan(&accountID)
  if errors.Is(err,sql.ErrNoRows) { return ErrWorldEventSession }
  if err!=nil { return fmt.Errorf("verify historical monster contributor session: %w",err) }
  var participantStatus string
  err=tx.QueryRowContext(ctx,`SELECT status FROM bounty_task_participants
   WHERE task_id=$1::uuid AND account_id=$2::uuid FOR SHARE`,event.TaskID,accountID).Scan(&participantStatus)
  if errors.Is(err,sql.ErrNoRows) { continue }
  if err!=nil { return fmt.Errorf("verify monster contributor participation: %w",err) }
  // Non-participants may have helped kill the same monster; retain only accepted
  // bounty members instead of rejecting the entire team's valid contribution.
  if participantStatus!="accepted" { continue }
  if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_monster_contributors
   (event_id,session_id,character_id,account_id,damage,hit_count)
   VALUES($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6)`,
   event.EventID,item.SessionID,item.CharacterID,accountID,item.Damage,item.HitCount);err!=nil {
   return fmt.Errorf("persist monster contributor: %w",err)
  }
  acceptedContributors++
 }
 if acceptedContributors==0 { return ErrNotParticipant }
 if err=tx.Commit();err!=nil { return fmt.Errorf("commit monster contribution snapshot: %w",err) }
 return nil
}

type MonsterContributionDetail struct {
 CharacterID string `json:"character_id"`
 Damage int64 `json:"damage"`
 HitCount int64 `json:"hit_count"`
}

type MonsterContributionSnapshot struct {
 EventID string `json:"event_id"`
 MonsterInstanceID string `json:"monster_instance_id"`
 MonsterDefinitionID string `json:"monster_definition_id"`
 CreatedAt time.Time `json:"created_at"`
 Contributors []MonsterContributionDetail `json:"contributors"`
}

type BountyContributionAuditCharacter struct {
 CharacterID string `json:"character_id"`
 Damage int64 `json:"damage"`
 HitCount int64 `json:"hit_count"`
 MonsterCount int64 `json:"monster_count"`
 DamageSharePercent float64 `json:"damage_share_percent"`
}

type BountyContributionAudit struct {
 TaskID string `json:"task_id"`
 FactionID string `json:"faction_id"`
 TotalDamage int64 `json:"total_damage"`
 Characters []BountyContributionAuditCharacter `json:"characters"`
 Events []MonsterContributionSnapshot `json:"events"`

 NextCursor string `json:"next_cursor,omitempty"`
}

type bountyAuditCursor struct {
 CreatedAt time.Time `json:"created_at"`
 EventID string `json:"event_id"`
}

func decodeBountyAuditCursor(value string) (*bountyAuditCursor,error) {
 if value=="" { return nil,nil }
 raw,err:=base64.RawURLEncoding.DecodeString(value)
 if err!=nil { return nil,ErrInvalid }
 var cursor bountyAuditCursor
 if err=json.Unmarshal(raw,&cursor);err!=nil || cursor.CreatedAt.IsZero() || !validUUID(cursor.EventID) { return nil,ErrInvalid }
 cursor.EventID=strings.ToLower(cursor.EventID)
 return &cursor,nil
}

func encodeBountyAuditCursor(cursor bountyAuditCursor) string {
 raw,_:=json.Marshal(cursor)
 return base64.RawURLEncoding.EncodeToString(raw)
}

type BountyContributionHistory struct {
 TaskID string `json:"task_id"`
 Events []MonsterContributionSnapshot `json:"events"`
}

// ListPublisherContributionAudit exposes task-wide contribution evidence only
// to an active publisher faction leader or officer. Authorization and reads
// share one transaction so membership revocation cannot race the audit query.
func (s *Service) ListPublisherContributionAudit(ctx context.Context, accountID, factionID, taskID string, limit int, cursorValue string) (BountyContributionAudit, error) {
 if accountID=="" || !validUUID(factionID) || !validUUID(taskID) || limit<0 || limit>100 {
  return BountyContributionAudit{}, ErrInvalid
 }
 if limit==0 { limit=50 }
 cursor,err:=decodeBountyAuditCursor(cursorValue)
 if err!=nil { return BountyContributionAudit{},err }
 factionID=strings.ToLower(factionID)
 taskID=strings.ToLower(taskID)
 tx,err:=s.db.BeginTx(ctx,nil)
 if err!=nil { return BountyContributionAudit{},fmt.Errorf("begin bounty contribution audit: %w",err) }
 defer tx.Rollback()

 var role string
 err=tx.QueryRowContext(ctx,`SELECT m.role
  FROM bounty_tasks t
  JOIN factions f ON f.id=t.publisher_id
  JOIN faction_members m ON m.faction_id=f.id
  WHERE t.id=$1::uuid AND t.publisher_type='faction'
   AND t.publisher_id=$2::uuid AND f.status='active' AND m.account_id=$3::uuid
  FOR SHARE OF t,f,m`,taskID,factionID,accountID).Scan(&role)
 if errors.Is(err,sql.ErrNoRows) { return BountyContributionAudit{},ErrForbidden }
 if err!=nil { return BountyContributionAudit{},fmt.Errorf("authorize bounty contribution audit: %w",err) }
 if role!="leader" && role!="officer" { return BountyContributionAudit{},ErrForbidden }

 result:=BountyContributionAudit{
  TaskID:taskID,FactionID:factionID,Characters:make([]BountyContributionAuditCharacter,0),
  Events:make([]MonsterContributionSnapshot,0),
 }
 if err=tx.QueryRowContext(ctx,`SELECT COALESCE(SUM(damage),0)
  FROM bounty_monster_contributors c
  JOIN bounty_monster_contribution_events e ON e.event_id=c.event_id
  WHERE e.task_id=$1::uuid`,taskID).Scan(&result.TotalDamage);err!=nil {
  return BountyContributionAudit{},fmt.Errorf("sum bounty contribution damage: %w",err)
 }

 rows,err:=tx.QueryContext(ctx,`SELECT c.character_id::text,SUM(c.damage),SUM(c.hit_count),
  COUNT(DISTINCT c.event_id)
  FROM bounty_monster_contributors c
  JOIN bounty_monster_contribution_events e ON e.event_id=c.event_id
  WHERE e.task_id=$1::uuid
  GROUP BY c.character_id
  ORDER BY SUM(c.damage) DESC,c.character_id`,taskID)
 if err!=nil { return BountyContributionAudit{},fmt.Errorf("list bounty contribution character totals: %w",err) }
 for rows.Next() {
  var item BountyContributionAuditCharacter
  if err=rows.Scan(&item.CharacterID,&item.Damage,&item.HitCount,&item.MonsterCount);err!=nil {
   rows.Close()
   return BountyContributionAudit{},fmt.Errorf("scan bounty contribution character total: %w",err)
  }
  if result.TotalDamage>0 { item.DamageSharePercent=float64(item.Damage)*100/float64(result.TotalDamage) }
  result.Characters=append(result.Characters,item)
 }
 if err=rows.Err();err!=nil { rows.Close();return BountyContributionAudit{},fmt.Errorf("iterate bounty contribution character totals: %w",err) }
 if err=rows.Close();err!=nil { return BountyContributionAudit{},fmt.Errorf("close bounty contribution character totals: %w",err) }

 var cursorTime any
 var cursorID any
 if cursor!=nil { cursorTime=cursor.CreatedAt;cursorID=cursor.EventID }
 eventRows,err:=tx.QueryContext(ctx,`WITH visible_events AS (
  SELECT event_id,monster_instance_id,monster_definition_id,created_at
  FROM bounty_monster_contribution_events
  WHERE task_id=$1::uuid
   AND ($2::timestamptz IS NULL OR (created_at,event_id)<($2::timestamptz,$3::uuid))
  ORDER BY created_at DESC,event_id DESC
  LIMIT $4
 )
 SELECT e.event_id::text,e.monster_instance_id,e.monster_definition_id,e.created_at,
  c.character_id::text,c.damage,c.hit_count
 FROM visible_events e
 JOIN bounty_monster_contributors c ON c.event_id=e.event_id
 ORDER BY e.created_at DESC,e.event_id DESC,c.damage DESC,c.character_id`,taskID,cursorTime,cursorID,limit+1)
 if err!=nil { return BountyContributionAudit{},fmt.Errorf("list bounty contribution audit events: %w",err) }
 indexByEvent:=make(map[string]int)
 hasMore:=false
 var lastIncluded bountyAuditCursor
 for eventRows.Next() {
  var eventID,instanceID,definitionID,characterID string
  var createdAt time.Time
  var damage,hitCount int64
  if err=eventRows.Scan(&eventID,&instanceID,&definitionID,&createdAt,&characterID,&damage,&hitCount);err!=nil {
   eventRows.Close()
   return BountyContributionAudit{},fmt.Errorf("scan bounty contribution audit event: %w",err)
  }
  idx,ok:=indexByEvent[eventID]
  if !ok {
   if len(result.Events)>=limit { hasMore=true;continue }
   idx=len(result.Events)
   indexByEvent[eventID]=idx
   lastIncluded=bountyAuditCursor{CreatedAt:createdAt,EventID:eventID}
   result.Events=append(result.Events,MonsterContributionSnapshot{
    EventID:eventID,MonsterInstanceID:instanceID,MonsterDefinitionID:definitionID,
    CreatedAt:createdAt,Contributors:make([]MonsterContributionDetail,0),
   })
  }
  result.Events[idx].Contributors=append(result.Events[idx].Contributors,MonsterContributionDetail{
   CharacterID:characterID,Damage:damage,HitCount:hitCount,
  })
 }
 if err=eventRows.Err();err!=nil { eventRows.Close();return BountyContributionAudit{},fmt.Errorf("iterate bounty contribution audit events: %w",err) }
 if err=eventRows.Close();err!=nil { return BountyContributionAudit{},fmt.Errorf("close bounty contribution audit events: %w",err) }
 if hasMore && len(result.Events)>0 { result.NextCursor=encodeBountyAuditCursor(lastIncluded) }
 if err=tx.Commit();err!=nil { return BountyContributionAudit{},fmt.Errorf("commit bounty contribution audit: %w",err) }
 return result,nil
}

// ListContributions returns recent immutable damage snapshots to any account that participated in the bounty.
// Internal session IDs and account IDs are intentionally not exposed in the player-facing response.
func (s *Service) ListContributions(ctx context.Context, accountID, taskID string) (BountyContributionHistory, error) {
 if accountID=="" || !validUUID(taskID) { return BountyContributionHistory{},ErrInvalid }
 taskID=strings.ToLower(taskID)
 var exists bool
 if err:=s.db.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM bounty_task_participants WHERE task_id=$1::uuid AND account_id=$2::uuid)`,taskID,accountID).Scan(&exists);err!=nil {
  return BountyContributionHistory{},fmt.Errorf("verify bounty contribution viewer: %w",err)
 }
 if !exists { return BountyContributionHistory{},ErrNotParticipant }
 rows,err:=s.db.QueryContext(ctx,`WITH visible_events AS (
  SELECT event_id,monster_instance_id,monster_definition_id,created_at
  FROM bounty_monster_contribution_events
  WHERE task_id=$1::uuid
  ORDER BY created_at DESC,event_id DESC
  LIMIT 200
 )
 SELECT e.event_id::text,e.monster_instance_id,e.monster_definition_id,e.created_at,
  c.character_id::text,c.damage,c.hit_count
 FROM visible_events e
 JOIN bounty_monster_contributors c ON c.event_id=e.event_id
 ORDER BY e.created_at DESC,e.event_id DESC,c.damage DESC,c.character_id`,taskID)
 if err!=nil { return BountyContributionHistory{},fmt.Errorf("list bounty contribution snapshots: %w",err) }
 defer rows.Close()
 result:=BountyContributionHistory{TaskID:taskID,Events:make([]MonsterContributionSnapshot,0)}
 indexByEvent:=make(map[string]int)
 for rows.Next() {
  var eventID,instanceID,definitionID,characterID string
  var createdAt time.Time
  var damage,hitCount int64
  if err:=rows.Scan(&eventID,&instanceID,&definitionID,&createdAt,&characterID,&damage,&hitCount);err!=nil {
   return BountyContributionHistory{},fmt.Errorf("scan bounty contribution snapshot: %w",err)
  }
  idx,ok:=indexByEvent[eventID]
  if !ok {
   idx=len(result.Events)
   indexByEvent[eventID]=idx
   result.Events=append(result.Events,MonsterContributionSnapshot{
    EventID:eventID,MonsterInstanceID:instanceID,MonsterDefinitionID:definitionID,
    CreatedAt:createdAt,Contributors:make([]MonsterContributionDetail,0),
   })
  }
  result.Events[idx].Contributors=append(result.Events[idx].Contributors,MonsterContributionDetail{
   CharacterID:characterID,Damage:damage,HitCount:hitCount,
  })
 }
 if err:=rows.Err();err!=nil { return BountyContributionHistory{},fmt.Errorf("iterate bounty contribution snapshots: %w",err) }
 return result,nil
}
