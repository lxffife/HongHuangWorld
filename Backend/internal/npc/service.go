package npc

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

var (
	ErrNoActiveSession = errors.New("character has no active world session")
	ErrNotFound = errors.New("npc not found in current world")
	ErrTooFar = errors.New("npc is outside interaction range")
	ErrChoiceUnavailable = errors.New("npc fate choice is unavailable")
	ErrChoiceResolved = errors.New("npc fate choice was already resolved")
	ErrEncounterUnavailable = errors.New("fate encounter is unavailable")
	ErrEncounterResolved = errors.New("fate encounter was already discovered")
)

type Definition struct {
	ID string `json:"id"`
	WorldID string `json:"world_id"`
	Name string `json:"name"`
	Title string `json:"title"`
	Type string `json:"npc_type"`
	InteractionType string `json:"interaction_type"`
	PositionX float64 `json:"position_x"`
	PositionY float64 `json:"position_y"`
	PositionZ float64 `json:"position_z"`
	RotationY float64 `json:"rotation_y"`
	InteractionRadius float64 `json:"interaction_radius"`
	Dialogue json.RawMessage `json:"dialogue"`
	FateTraitID string `json:"fate_trait_id,omitempty"`
	FateReaction string `json:"fate_reaction,omitempty"`
}

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

func (s *Service) ListForAccount(ctx context.Context, accountID string) ([]Definition, error) {
	var characterID string
	err := s.db.QueryRowContext(ctx,
		`SELECT c.id::text
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 WHERE soul.account_id=$1 AND c.status='alive'
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`, accountID).Scan(&characterID)
	if errors.Is(err, sql.ErrNoRows) { return nil, ErrNoActiveSession }
	if err != nil { return nil, fmt.Errorf("resolve active character world: %w", err) }
	rows, err := s.db.QueryContext(ctx,
		`SELECT id,world_id,name,title,npc_type,interaction_type,
		        position_x,position_y,position_z,rotation_y,interaction_radius,dialogue
		 FROM world_npc_definitions
		 WHERE world_id=(SELECT world_id FROM characters WHERE id=$1::uuid)
		   AND enabled=TRUE
		 ORDER BY id`, characterID)
	if err != nil { return nil, fmt.Errorf("query world NPCs: %w", err) }
	defer rows.Close()
	items := make([]Definition,0)
	for rows.Next() {
		var item Definition
		if err := rows.Scan(&item.ID,&item.WorldID,&item.Name,&item.Title,&item.Type,&item.InteractionType,
			&item.PositionX,&item.PositionY,&item.PositionZ,&item.RotationY,&item.InteractionRadius,&item.Dialogue); err != nil {
			return nil, fmt.Errorf("scan world NPC: %w", err)
		}
		items=append(items,item)
	}
	if err:=rows.Err(); err!=nil { return nil, fmt.Errorf("iterate world NPCs: %w",err) }
	return items,nil
}

// Interact validates the active session's authoritative server-side character
// position. A client cannot choose a world or submit its own coordinates.
func (s *Service) Interact(ctx context.Context, accountID, npcID string) (Definition,error) {
	var item Definition
	err:=s.db.QueryRowContext(ctx,
		`SELECT n.id,n.world_id,n.name,n.title,n.npc_type,n.interaction_type,
		        n.position_x,n.position_y,n.position_z,n.rotation_y,n.interaction_radius,n.dialogue,
		        COALESCE(trait.trait_id, ''), COALESCE(n.dialogue->'fate_reactions'->>trait.trait_id, '')
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_npc_definitions n ON n.world_id=wi.world_id AND n.id=$2 AND n.enabled=TRUE
		 LEFT JOIN character_fate_traits trait ON trait.character_id=c.id
		 WHERE soul.account_id=$1
		   AND SQRT(POWER(c.position_x-n.position_x,2)+POWER(c.position_y-n.position_y,2)+POWER(c.position_z-n.position_z,2)) <= n.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`,accountID,npcID).Scan(
		&item.ID,&item.WorldID,&item.Name,&item.Title,&item.Type,&item.InteractionType,
		&item.PositionX,&item.PositionY,&item.PositionZ,&item.RotationY,&item.InteractionRadius,&item.Dialogue,
		&item.FateTraitID,&item.FateReaction)
	if errors.Is(err,sql.ErrNoRows) {
		var active bool
		checkErr:=s.db.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
			 WHERE soul.account_id=$1 AND c.status='alive')`,accountID).Scan(&active)
		if checkErr!=nil { return Definition{},fmt.Errorf("check NPC interaction session: %w",checkErr) }
		if !active { return Definition{},ErrNoActiveSession }
		var exists bool
		checkErr=s.db.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_npc_definitions n ON n.world_id=c.world_id AND n.id=$2 AND n.enabled=TRUE
			 WHERE soul.account_id=$1)`,accountID,npcID).Scan(&exists)
		if checkErr!=nil { return Definition{},fmt.Errorf("check NPC existence: %w",checkErr) }
		if !exists { return Definition{},ErrNotFound }
		return Definition{},ErrTooFar
	}
	if err!=nil { return Definition{},fmt.Errorf("validate NPC interaction: %w",err) }
	return item,nil
}


type FateChoice struct {
	ID string `json:"id"`
	Text string `json:"text"`
	Description string `json:"description"`
	EffectKey string `json:"effect_key"`
	Result string `json:"result"`
}

type FateChoiceResult struct {
	NPCID string `json:"npc_id"`
	ChoiceID string `json:"choice_id"`
	Result string `json:"result"`
	Karma int64 `json:"karma"`
	Merit int64 `json:"merit"`
	KarmaDelta int64 `json:"karma_delta"`
	MeritDelta int64 `json:"merit_delta"`
}

// ChooseFate validates the active character's server-stored position and resolves
// an authored choice. The client submits identifiers only; effect values stay here.
func (s *Service) ChooseFate(ctx context.Context, accountID, npcID, choiceID string) (FateChoiceResult, error) {
	if npcID == "" || choiceID == "" || len(npcID) > 64 || len(choiceID) > 64 {
		return FateChoiceResult{}, ErrChoiceUnavailable
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return FateChoiceResult{}, fmt.Errorf("begin NPC fate choice: %w", err) }
	defer tx.Rollback()

	var soulID, worldID string
	var dialogue []byte
	err = tx.QueryRowContext(ctx,
		`SELECT soul.id::text, wi.world_id, n.dialogue
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_npc_definitions n ON n.world_id=wi.world_id AND n.id=$2 AND n.enabled=TRUE
		 WHERE soul.account_id=$1
		   AND SQRT(POWER(c.position_x-n.position_x,2)+POWER(c.position_y-n.position_y,2)+POWER(c.position_z-n.position_z,2)) <= n.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		 FOR UPDATE OF soul,c,ws`, accountID, npcID).Scan(&soulID, &worldID, &dialogue)
	if errors.Is(err, sql.ErrNoRows) {
		var active bool
		checkErr := tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
			 WHERE soul.account_id=$1 AND c.status='alive')`, accountID).Scan(&active)
		if checkErr != nil { return FateChoiceResult{}, fmt.Errorf("check NPC fate session: %w", checkErr) }
		if !active { return FateChoiceResult{}, ErrNoActiveSession }
		var exists bool
		checkErr = tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_npc_definitions n ON n.world_id=c.world_id AND n.id=$2 AND n.enabled=TRUE
			 WHERE soul.account_id=$1)`, accountID, npcID).Scan(&exists)
		if checkErr != nil { return FateChoiceResult{}, fmt.Errorf("check NPC fate target: %w", checkErr) }
		if !exists { return FateChoiceResult{}, ErrNotFound }
		return FateChoiceResult{}, ErrTooFar
	}
	if err != nil { return FateChoiceResult{}, fmt.Errorf("validate NPC fate choice: %w", err) }
	if worldID != "underworld_fengdu" { return FateChoiceResult{}, ErrChoiceUnavailable }

	var config struct { Choices []FateChoice `json:"choices"` }
	if err := json.Unmarshal(dialogue, &config); err != nil {
		return FateChoiceResult{}, fmt.Errorf("decode NPC fate choices: %w", err)
	}
	var selected *FateChoice
	for i := range config.Choices {
		if config.Choices[i].ID == choiceID { selected = &config.Choices[i]; break }
	}
	if selected == nil { return FateChoiceResult{}, ErrChoiceUnavailable }

	var karmaDelta, meritDelta int64
	switch selected.EffectKey {
	case "judge_mercy":
		karmaDelta, meritDelta = -1, 2
	case "judge_corruption":
		karmaDelta, meritDelta = 3, -2
	default:
		return FateChoiceResult{}, ErrChoiceUnavailable
	}

	var fateEventID string
	err = tx.QueryRowContext(ctx,
		`INSERT INTO soul_fate_choice_claims (soul_id,npc_id,choice_id,fate_event_id)
		 VALUES ($1,$2,$3,gen_random_uuid())
		 ON CONFLICT (soul_id,npc_id) DO NOTHING
		 RETURNING fate_event_id::text`, soulID, npcID, choiceID).Scan(&fateEventID)
	if errors.Is(err, sql.ErrNoRows) { return FateChoiceResult{}, ErrChoiceResolved }
	if err != nil { return FateChoiceResult{}, fmt.Errorf("claim NPC fate choice: %w", err) }

	if _, err = tx.ExecContext(ctx,
		`INSERT INTO soul_fate_events (soul_id,event_id,source,world_id,karma_delta,merit_delta)
		 VALUES ($1,$2::uuid,$3,$4,$5,$6)`,
		soulID, fateEventID, "npc_choice", worldID, karmaDelta, meritDelta); err != nil {
		return FateChoiceResult{}, fmt.Errorf("record NPC fate event: %w", err)
	}
	var result FateChoiceResult
	result.NPCID, result.ChoiceID = npcID, choiceID
	result.Result, result.KarmaDelta, result.MeritDelta = selected.Result, karmaDelta, meritDelta
	err = tx.QueryRowContext(ctx,
		`UPDATE souls SET karma=karma+$1, merit=merit+$2, updated_at=now()
		 WHERE id=$3 RETURNING karma,merit`, karmaDelta, meritDelta, soulID).Scan(&result.Karma, &result.Merit)
	if err != nil { return FateChoiceResult{}, fmt.Errorf("apply NPC fate outcome: %w", err) }
	if err := tx.Commit(); err != nil { return FateChoiceResult{}, fmt.Errorf("commit NPC fate choice: %w", err) }
	return result, nil
}


type FateEncounterResult struct {
	EncounterID string `json:"encounter_id"`
	Title string `json:"title"`
	Description string `json:"description"`
	Merit int64 `json:"merit"`
	Karma int64 `json:"karma"`
	MeritDelta int64 `json:"merit_delta"`
	KarmaDelta int64 `json:"karma_delta"`
}

// DiscoverFateEncounter resolves a trait-specific hidden encounter from
// server-authored NPC data. The soul can claim each encounter only once.
func (s *Service) DiscoverFateEncounter(ctx context.Context, accountID, npcID string) (FateEncounterResult, error) {
	if npcID == "" || len(npcID) > 64 { return FateEncounterResult{}, ErrChoiceUnavailable }
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return FateEncounterResult{}, fmt.Errorf("begin fate encounter: %w", err) }
	defer tx.Rollback()

	var soulID, worldID, traitID string
	var configJSON []byte
	err = tx.QueryRowContext(ctx,
		`SELECT soul.id::text, wi.world_id, COALESCE(trait.trait_id, ''),
		        COALESCE(n.dialogue->'fate_encounters'->trait.trait_id, '{}'::jsonb)
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_npc_definitions n ON n.world_id=wi.world_id AND n.id=$2 AND n.enabled=TRUE
		 LEFT JOIN character_fate_traits trait ON trait.character_id=c.id
		 WHERE soul.account_id=$1
		   AND SQRT(POWER(c.position_x-n.position_x,2)+POWER(c.position_y-n.position_y,2)+POWER(c.position_z-n.position_z,2)) <= n.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		 FOR UPDATE OF soul,c,ws`, accountID, npcID).Scan(&soulID,&worldID,&traitID,&configJSON)
	if errors.Is(err,sql.ErrNoRows) {
		var active bool
		checkErr:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active' WHERE soul.account_id=$1 AND c.status='alive')`,accountID).Scan(&active)
		if checkErr!=nil { return FateEncounterResult{},fmt.Errorf("check encounter session: %w",checkErr) }
		if !active { return FateEncounterResult{},ErrNoActiveSession }
		return FateEncounterResult{},ErrTooFar
	}
	if err!=nil { return FateEncounterResult{},fmt.Errorf("load fate encounter: %w",err) }
	if worldID!="underworld_fengdu" || traitID=="" { return FateEncounterResult{},ErrEncounterUnavailable }

	var authored struct {
		ID string `json:"id"`
		Title string `json:"title"`
		Description string `json:"description"`
		MeritDelta int64 `json:"merit_delta"`
		KarmaDelta int64 `json:"karma_delta"`
	}
	if err:=json.Unmarshal(configJSON,&authored);err!=nil { return FateEncounterResult{},fmt.Errorf("decode fate encounter: %w",err) }
	if authored.ID=="" || authored.Title=="" || authored.Description=="" || len(authored.ID)>64 || authored.MeritDelta<0 || authored.MeritDelta>5 || authored.KarmaDelta>0 || authored.KarmaDelta < -5 || (authored.MeritDelta==0 && authored.KarmaDelta==0) {
		return FateEncounterResult{},ErrEncounterUnavailable
	}
	var eventID string
	err=tx.QueryRowContext(ctx,
		`INSERT INTO soul_fate_encounter_claims (soul_id,encounter_id,npc_id)
		 VALUES ($1,$2,$3) ON CONFLICT (soul_id,encounter_id) DO NOTHING
		 RETURNING fate_event_id::text`,soulID,authored.ID,npcID).Scan(&eventID)
	if errors.Is(err,sql.ErrNoRows) { return FateEncounterResult{},ErrEncounterResolved }
	if err!=nil { return FateEncounterResult{},fmt.Errorf("claim fate encounter: %w",err) }
	if _,err=tx.ExecContext(ctx,
		`INSERT INTO soul_fate_events (soul_id,event_id,source,world_id,karma_delta,merit_delta)
		 VALUES ($1,$2::uuid,'hidden_fate_encounter',$3,$4,$5)`,soulID,eventID,worldID,authored.KarmaDelta,authored.MeritDelta);err!=nil {
		return FateEncounterResult{},fmt.Errorf("record fate encounter event: %w",err)
	}
	result:=FateEncounterResult{EncounterID:authored.ID,Title:authored.Title,Description:authored.Description,MeritDelta:authored.MeritDelta,KarmaDelta:authored.KarmaDelta}
	err=tx.QueryRowContext(ctx,`UPDATE souls SET merit=merit+$1,karma=karma+$2,updated_at=now() WHERE id=$3 RETURNING merit,karma`,authored.MeritDelta,authored.KarmaDelta,soulID).Scan(&result.Merit,&result.Karma)
	if err!=nil { return FateEncounterResult{},fmt.Errorf("apply fate encounter outcome: %w",err) }
	if err:=tx.Commit();err!=nil { return FateEncounterResult{},fmt.Errorf("commit fate encounter: %w",err) }
	return result,nil
}
