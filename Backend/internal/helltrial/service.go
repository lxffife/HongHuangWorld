package helltrial

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

const FloorCount = 18

var (
	ErrNoActiveSession = errors.New("character has no active world session")
	ErrWrongWorld = errors.New("hell trials are only available in the underworld")
	ErrWrongInstance = errors.New("active world instance does not match the requested hell floor")
	ErrInvalid = errors.New("invalid hell trial request")
	ErrFloorLocked = errors.New("hell trial floor is locked")
	ErrObjectiveIncomplete = errors.New("hell trial objective is incomplete")
	ErrGuardianAlive = errors.New("hell trial guardian is alive")
	ErrAlreadyCompleted = errors.New("hell trial floor is already completed")
	ErrEntryIdempotencyConflict = errors.New("hell trial entry event ID was reused")
)

type Service struct { db *sql.DB }
func NewService(db *sql.DB) *Service { return &Service{db: db} }

type Floor struct {
	Floor int `json:"floor"`
	Status string `json:"status"`
	UnlockedAt time.Time `json:"unlocked_at"`
	FirstEnteredAt *time.Time `json:"first_entered_at,omitempty"`
	LastEnteredAt *time.Time `json:"last_entered_at,omitempty"`
	EntryCount int `json:"entry_count"`
	CompletedAt *time.Time `json:"completed_at,omitempty"`
}

type Progress struct {
	CharacterID string `json:"character_id"`
	WorldID string `json:"world_id"`
	HighestUnlockedFloor int `json:"highest_unlocked_floor"`
	FinalTrialCompleted bool `json:"final_trial_completed"`
	Floors []Floor `json:"floors"`
}

type EntryRequest struct {
	CharacterID string `json:"character_id"`
	Floor int `json:"floor"`
	EventID string `json:"event_id"`
}

type EntryResult struct {
	CharacterID string `json:"character_id"`
	Floor int `json:"floor"`
	EntryCount int `json:"entry_count"`
	AlreadyApplied bool `json:"already_applied"`
}

type CompletionRequest struct {
	CharacterID string `json:"character_id"`
	Floor int `json:"floor"`
	EventID string `json:"event_id"`
	ObjectiveComplete bool `json:"objective_complete"`
	GuardianDefeated bool `json:"guardian_defeated"`
	ObjectiveSnapshot json.RawMessage `json:"objective_snapshot"`
}

type CompletionResult struct {
	CharacterID string `json:"character_id"`
	Floor int `json:"floor"`
	Completed bool `json:"completed"`
	AlreadyApplied bool `json:"already_applied"`
	NextUnlockedFloor int `json:"next_unlocked_floor,omitempty"`
	FinalTrialCompleted bool `json:"final_trial_completed"`
}

func validUUID(value string) bool {
	if len(value) != 36 || value[8] != '-' || value[13] != '-' || value[18] != '-' || value[23] != '-' { return false }
	for i, r := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 { continue }
		if !((r >= '0' && r <= '9') || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')) { return false }
	}
	return true
}

func validateCompletion(req CompletionRequest) error {
	if !validUUID(req.CharacterID) || !validUUID(req.EventID) || req.Floor < 1 || req.Floor > FloorCount { return ErrInvalid }
	if len(req.ObjectiveSnapshot) == 0 || len(req.ObjectiveSnapshot) > 16*1024 || !json.Valid(req.ObjectiveSnapshot) { return ErrInvalid }
	var object map[string]json.RawMessage
	if err := json.Unmarshal(req.ObjectiveSnapshot, &object); err != nil || object == nil { return ErrInvalid }
	if !req.ObjectiveComplete { return ErrObjectiveIncomplete }
	if !req.GuardianDefeated { return ErrGuardianAlive }
	return nil
}

// Current resolves the active character and world session from the account.
func (s *Service) Current(ctx context.Context, accountID string) (Progress, error) {
	if strings.TrimSpace(accountID) == "" { return Progress{}, ErrInvalid }
	var result Progress
	err := s.db.QueryRowContext(ctx, `SELECT c.id::text,c.world_id
		FROM souls soul
		JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		WHERE soul.account_id=$1
		ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`, accountID).Scan(&result.CharacterID,&result.WorldID)
	if errors.Is(err,sql.ErrNoRows) { return Progress{},ErrNoActiveSession }
	if err != nil { return Progress{},fmt.Errorf("resolve active hell trial character: %w",err) }
	if result.WorldID != "underworld_fengdu" { return Progress{},ErrWrongWorld }

	if _,err=s.db.ExecContext(ctx,`INSERT INTO character_hell_trial_progress(character_id,floor_number,status)
		VALUES($1::uuid,1,'unlocked') ON CONFLICT(character_id,floor_number) DO NOTHING`,result.CharacterID);err!=nil {
		return Progress{},fmt.Errorf("initialize first hell floor: %w",err)
	}
	rows,err:=s.db.QueryContext(ctx,`SELECT floor_number,status,unlocked_at,first_entered_at,last_entered_at,entry_count,completed_at
		FROM character_hell_trial_progress WHERE character_id=$1::uuid ORDER BY floor_number`,result.CharacterID)
	if err!=nil{return Progress{},fmt.Errorf("query hell trial progress: %w",err)}
	defer rows.Close()
	result.Floors=make([]Floor,0,FloorCount)
	for rows.Next(){
		var item Floor
		if err:=rows.Scan(&item.Floor,&item.Status,&item.UnlockedAt,&item.FirstEnteredAt,&item.LastEnteredAt,&item.EntryCount,&item.CompletedAt);err!=nil{return Progress{},fmt.Errorf("scan hell trial progress: %w",err)}
		result.Floors=append(result.Floors,item)
		if item.Floor>result.HighestUnlockedFloor { result.HighestUnlockedFloor=item.Floor }
		if item.Floor==FloorCount && item.Status=="completed" { result.FinalTrialCompleted=true }
	}
	if err:=rows.Err();err!=nil{return Progress{},fmt.Errorf("iterate hell trial progress: %w",err)}
	return result,nil
}

// Complete accepts reports only from the WorldServer currently hosting this character.
// The event UUID makes retries safe; completion and next-floor unlock are atomic.
func (s *Service) Complete(ctx context.Context, nodeKey string, req CompletionRequest) (CompletionResult,error) {
	if strings.TrimSpace(nodeKey)=="" { return CompletionResult{},ErrInvalid }
	if err := validateCompletion(req); err != nil { return CompletionResult{},err }
	tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return CompletionResult{},fmt.Errorf("begin hell trial completion: %w",err)}
	defer tx.Rollback()

	var worldID string
	err=tx.QueryRowContext(ctx,`SELECT c.world_id
		FROM characters c
		JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		JOIN server_registry sr ON sr.id=ws.server_id AND sr.node_key=$2
		WHERE c.id=$1::uuid AND c.status='alive' AND wi.hell_floor=$3
		ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		FOR UPDATE OF c,ws`,req.CharacterID,nodeKey,req.Floor).Scan(&worldID)
	if errors.Is(err,sql.ErrNoRows) {
		var activeUnderworld bool
		checkErr := tx.QueryRowContext(ctx,`SELECT EXISTS(
			SELECT 1 FROM characters c
			JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
			JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
			JOIN server_registry sr ON sr.id=ws.server_id AND sr.node_key=$2
			WHERE c.id=$1::uuid AND c.status='alive' AND c.world_id='underworld_fengdu'
		)`,req.CharacterID,nodeKey).Scan(&activeUnderworld)
		if checkErr != nil { return CompletionResult{},fmt.Errorf("check active underworld instance: %w",checkErr) }
		if activeUnderworld { return CompletionResult{},ErrWrongInstance }
		return CompletionResult{},ErrNoActiveSession
	}
	if err!=nil{return CompletionResult{},fmt.Errorf("validate hell trial world session: %w",err)}
	if worldID!="underworld_fengdu"{return CompletionResult{},ErrWrongWorld}

	if _,err=tx.ExecContext(ctx,`INSERT INTO character_hell_trial_progress(character_id,floor_number,status)
		VALUES($1::uuid,1,'unlocked') ON CONFLICT(character_id,floor_number) DO NOTHING`,req.CharacterID);err!=nil{
		return CompletionResult{},fmt.Errorf("initialize hell trial progress: %w",err)
	}

	var status string
	var priorEvent sql.NullString
	err=tx.QueryRowContext(ctx,`SELECT status,completion_event_id::text FROM character_hell_trial_progress
		WHERE character_id=$1::uuid AND floor_number=$2 FOR UPDATE`,req.CharacterID,req.Floor).Scan(&status,&priorEvent)
	if errors.Is(err,sql.ErrNoRows){return CompletionResult{},ErrFloorLocked}
	if err!=nil{return CompletionResult{},fmt.Errorf("lock hell trial floor: %w",err)}
	if status=="completed" {
		if priorEvent.Valid && strings.EqualFold(priorEvent.String,req.EventID) {
			next := 0
			if req.Floor < FloorCount { next = req.Floor + 1 }
			return CompletionResult{CharacterID:req.CharacterID,Floor:req.Floor,Completed:true,AlreadyApplied:true,NextUnlockedFloor:next,FinalTrialCompleted:req.Floor==FloorCount},nil
		}
		return CompletionResult{},ErrAlreadyCompleted
	}

	_,err=tx.ExecContext(ctx,`UPDATE character_hell_trial_progress
		SET status='completed',completed_at=now(),completion_event_id=$3::uuid,
		    objective_snapshot=$4::jsonb,updated_at=now()
		WHERE character_id=$1::uuid AND floor_number=$2`,req.CharacterID,req.Floor,req.EventID,string(req.ObjectiveSnapshot))
	if err!=nil{return CompletionResult{},fmt.Errorf("complete hell trial floor: %w",err)}

	next:=0
	if req.Floor<FloorCount {
		next=req.Floor+1
		_,err=tx.ExecContext(ctx,`INSERT INTO character_hell_trial_progress(character_id,floor_number,status)
			VALUES($1::uuid,$2,'unlocked') ON CONFLICT(character_id,floor_number) DO NOTHING`,req.CharacterID,next)
		if err!=nil{return CompletionResult{},fmt.Errorf("unlock next hell trial floor: %w",err)}
	}
	if err=tx.Commit();err!=nil{return CompletionResult{},fmt.Errorf("commit hell trial completion: %w",err)}
	return CompletionResult{CharacterID:req.CharacterID,Floor:req.Floor,Completed:true,NextUnlockedFloor:next,FinalTrialCompleted:req.Floor==FloorCount},nil
}


// RecordEntry records a real entry reported by the WorldServer that owns the
// character's active session and the requested floor-specific instance.
func (s *Service) RecordEntry(ctx context.Context, nodeKey string, req EntryRequest) (EntryResult,error) {
	if strings.TrimSpace(nodeKey)=="" || !validUUID(req.CharacterID) || !validUUID(req.EventID) || req.Floor<1 || req.Floor>FloorCount {
		return EntryResult{},ErrInvalid
	}
	tx,err:=s.db.BeginTx(ctx,nil)
	if err!=nil{return EntryResult{},fmt.Errorf("begin hell trial entry: %w",err)}
	defer tx.Rollback()

	var worldID string
	err=tx.QueryRowContext(ctx,`SELECT c.world_id
		FROM characters c
		JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		JOIN server_registry sr ON sr.id=ws.server_id AND sr.node_key=$2
		WHERE c.id=$1::uuid AND c.status='alive' AND wi.hell_floor=$3
		ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		FOR UPDATE OF c,ws`,req.CharacterID,nodeKey,req.Floor).Scan(&worldID)
	if errors.Is(err,sql.ErrNoRows) {
		var activeUnderworld bool
		checkErr:=tx.QueryRowContext(ctx,`SELECT EXISTS(
			SELECT 1 FROM characters c
			JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
			JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
			JOIN server_registry sr ON sr.id=ws.server_id AND sr.node_key=$2
			WHERE c.id=$1::uuid AND c.status='alive' AND c.world_id='underworld_fengdu'
		)`,req.CharacterID,nodeKey).Scan(&activeUnderworld)
		if checkErr!=nil{return EntryResult{},fmt.Errorf("check active underworld instance: %w",checkErr)}
		if activeUnderworld{return EntryResult{},ErrWrongInstance}
		return EntryResult{},ErrNoActiveSession
	}
	if err!=nil{return EntryResult{},fmt.Errorf("validate hell trial entry session: %w",err)}
	if worldID!="underworld_fengdu"{return EntryResult{},ErrWrongWorld}

	var existingCharacter string
	var existingFloor int
	err=tx.QueryRowContext(ctx,`SELECT character_id::text,floor_number
		FROM character_hell_trial_entry_events WHERE event_id=$1::uuid`,req.EventID).Scan(&existingCharacter,&existingFloor)
	if err==nil {
		if !strings.EqualFold(existingCharacter,req.CharacterID) || existingFloor!=req.Floor {return EntryResult{},ErrEntryIdempotencyConflict}
		var count int
		if err=tx.QueryRowContext(ctx,`SELECT entry_count FROM character_hell_trial_progress
			WHERE character_id=$1::uuid AND floor_number=$2`,req.CharacterID,req.Floor).Scan(&count);err!=nil{return EntryResult{},fmt.Errorf("read idempotent hell trial entry count: %w",err)}
		return EntryResult{CharacterID:req.CharacterID,Floor:req.Floor,EntryCount:count,AlreadyApplied:true},nil
	}
	if !errors.Is(err,sql.ErrNoRows){return EntryResult{},fmt.Errorf("check hell trial entry idempotency: %w",err)}

	var status string
	err=tx.QueryRowContext(ctx,`SELECT status FROM character_hell_trial_progress
		WHERE character_id=$1::uuid AND floor_number=$2 FOR UPDATE`,req.CharacterID,req.Floor).Scan(&status)
	if errors.Is(err,sql.ErrNoRows){return EntryResult{},ErrFloorLocked}
	if err!=nil{return EntryResult{},fmt.Errorf("lock hell trial entry progress: %w",err)}

	if _,err=tx.ExecContext(ctx,`INSERT INTO character_hell_trial_entry_events(event_id,character_id,floor_number)
		VALUES($1::uuid,$2::uuid,$3)`,req.EventID,req.CharacterID,req.Floor);err!=nil{return EntryResult{},fmt.Errorf("record hell trial entry event: %w",err)}
	var count int
	err=tx.QueryRowContext(ctx,`UPDATE character_hell_trial_progress
		SET first_entered_at=COALESCE(first_entered_at,now()),last_entered_at=now(),
		    entry_count=entry_count+1,updated_at=now()
		WHERE character_id=$1::uuid AND floor_number=$2
		RETURNING entry_count`,req.CharacterID,req.Floor).Scan(&count)
	if err!=nil{return EntryResult{},fmt.Errorf("update hell trial entry count: %w",err)}
	if err=tx.Commit();err!=nil{return EntryResult{},fmt.Errorf("commit hell trial entry: %w",err)}
	return EntryResult{CharacterID:req.CharacterID,Floor:req.Floor,EntryCount:count},nil
}

func min(a,b int) int { if a<b{return a};return b }
