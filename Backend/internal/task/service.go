package task

import (
 "context"
 "database/sql"
 "errors"
 "fmt"
 "math"
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
 ErrIdempotencyConflict = errors.New("contribution idempotency key conflict")
 ErrTaskFull = errors.New("bounty task is full")
 ErrTaskNotReady = errors.New("bounty task is not ready for settlement")
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
 ExpiresAt *string
}

func (s *Service) PublishFaction(ctx context.Context, accountID string, req PublishRequest) (Task,error) {
 req.Title=strings.TrimSpace(req.Title); req.Description=strings.TrimSpace(req.Description)
 if accountID=="" || req.FactionID=="" || req.EventKey=="" || len(req.EventKey)>128 || utf8.RuneCountInString(req.Title)<2 || utf8.RuneCountInString(req.Title)>96 ||
  utf8.RuneCountInString(req.Description)>2000 || len(req.CurrencyID)==0 || len(req.CurrencyID)>64 ||
  req.RewardAmount<=0 || req.MaxAssignees<1 || req.MaxAssignees>20 ||
  req.DifficultyTier<1 || req.DifficultyTier>10 || req.RequiredRealmLevel<0 || req.RequiredRealmLevel>1000 ||
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
   difficulty_tier,required_realm_level,max_assignees,expires_at,created_by,request_key)
  VALUES ($1,'faction',$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
  RETURNING id::text,world_id,publisher_type,publisher_id::text,title,description,currency_id,
   reward_amount,escrow_amount,difficulty_tier,required_realm_level,max_assignees,status,expires_at::text,created_at::text`,
  worldID,req.FactionID,req.Title,req.Description,req.CurrencyID,req.RewardAmount,total,req.DifficultyTier,
  req.RequiredRealmLevel,req.MaxAssignees,req.ExpiresAt,accountID,req.EventKey).
  Scan(&result.ID,&result.WorldID,&result.PublisherType,&result.PublisherID,&result.Title,
   &result.Description,&result.CurrencyID,&result.RewardAmount,&result.EscrowAmount,&result.DifficultyTier,
   &result.RequiredRealmLevel,&result.MaxAssignees,&result.Status,&result.ExpiresAt,&result.CreatedAt)
 if err!=nil{return Task{},fmt.Errorf("insert bounty task: %w",err)}
 result.PublisherName=name
 if _,err=tx.ExecContext(ctx,`INSERT INTO bounty_task_escrows(task_id,treasury_account_id,currency_id,amount)
  VALUES ($1,$2,$3,$4)`,result.ID,treasuryID,req.CurrencyID,total);err!=nil{return Task{},fmt.Errorf("create bounty escrow: %w",err)}
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
  t.title,t.description,t.currency_id,t.reward_amount,t.escrow_amount,t.difficulty_tier,t.required_realm_level,
  t.max_assignees,(SELECT count(*) FROM bounty_task_participants p WHERE p.task_id=t.id AND p.status='accepted'),
  t.status,t.expires_at::text,t.created_at::text
  FROM bounty_tasks t JOIN factions f ON f.id=t.publisher_id
  WHERE t.world_id=$1 AND f.status='active' AND t.status IN ('open','in_progress')
   AND (t.expires_at IS NULL OR t.expires_at>now()) ORDER BY t.created_at DESC LIMIT 100`,worldID)
 if err!=nil{return nil,fmt.Errorf("list open bounty tasks: %w",err)}; defer rows.Close()
 result:=make([]Task,0)
 for rows.Next(){var item Task;if err:=rows.Scan(&item.ID,&item.WorldID,&item.PublisherType,&item.PublisherID,&item.PublisherName,
  &item.Title,&item.Description,&item.CurrencyID,&item.RewardAmount,&item.EscrowAmount,&item.DifficultyTier,
  &item.RequiredRealmLevel,&item.MaxAssignees,&item.ParticipantCount,&item.Status,&item.ExpiresAt,&item.CreatedAt);err!=nil{return nil,fmt.Errorf("scan bounty task: %w",err)}
  result=append(result,item)}
 if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate bounty tasks: %w",err)}
 return result,nil
}

// Join locks the task row before checking capacity, so concurrent joiners cannot
// overfill a party. Settlement is deliberately a separate, not-yet-exposed phase.
func (s *Service) Join(ctx context.Context,accountID,taskID string)error{
 if accountID==""||taskID==""{return ErrInvalid}
 tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin bounty join: %w",err)};defer tx.Rollback()
 var max int;var status string;var expires sql.NullTime
 err=tx.QueryRowContext(ctx,`SELECT max_assignees,status,expires_at FROM bounty_tasks WHERE id=$1 FOR UPDATE`,taskID).Scan(&max,&status,&expires)
 if errors.Is(err,sql.ErrNoRows){return ErrNotFound};if err!=nil{return fmt.Errorf("lock bounty task: %w",err)}
 if status=="full"{return ErrTaskFull};if status!="open"&&status!="in_progress"{return ErrNotFound}
 if expires.Valid && !expires.Time.After(time.Now()){return ErrNotFound}
 var joined int
 if err=tx.QueryRowContext(ctx,`SELECT count(*) FROM bounty_task_participants WHERE task_id=$1 AND status='accepted'`,taskID).Scan(&joined);err!=nil{return fmt.Errorf("count bounty participants: %w",err)}
 if joined>=max{return ErrTaskFull}
 insertResult,insertErr:=tx.ExecContext(ctx,`INSERT INTO bounty_task_participants(task_id,account_id) VALUES($1,$2)
  ON CONFLICT(task_id,account_id) DO NOTHING`,taskID,accountID)
 if insertErr!=nil{return fmt.Errorf("join bounty task: %w",insertErr)}
 inserted,rowsErr:=insertResult.RowsAffected();if rowsErr!=nil{return fmt.Errorf("read bounty participant insert result: %w",rowsErr)}
 if inserted==0{return ErrAlreadyJoined}
 next:="in_progress";if joined+1>=max{next="full"}
 if _,err=tx.ExecContext(ctx,`UPDATE bounty_tasks SET status=$2,updated_at=now() WHERE id=$1`,taskID,next);err!=nil{return fmt.Errorf("update bounty task capacity: %w",err)}
 if err=tx.Commit();err!=nil{return fmt.Errorf("commit bounty join: %w",err)}
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
 err=tx.QueryRowContext(ctx,`SELECT t.publisher_id::text,e.treasury_account_id::text,t.currency_id,t.status,
  t.reward_amount,e.amount,e.status
  FROM bounty_tasks t JOIN bounty_task_escrows e ON e.task_id=t.id
  WHERE t.id=$1 FOR UPDATE OF t,e`,taskID).Scan(&publisherID,&treasuryID,&currencyID,&status,&reward,&escrowAmount,&escrowStatus)
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
 if err=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM bounty_task_settlements WHERE event_key=$1)`,eventKey).Scan(&eventKeyUsed);err!=nil{return Settlement{},fmt.Errorf("check bounty settlement idempotency key: %w",err)}
 if eventKeyUsed{return Settlement{},ErrIdempotencyConflict}
 if status!="full"&&status!="in_progress"{return Settlement{},ErrTaskNotReady}
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
