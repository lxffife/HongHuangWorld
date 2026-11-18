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
	FateEncounterAvailable bool `json:"fate_encounter_available"`
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
		        COALESCE(trait.trait_id, ''), COALESCE(n.dialogue->'fate_reactions'->>trait.trait_id, ''),
		        (COALESCE(n.dialogue->'fate_encounters'->trait.trait_id, '{}'::jsonb) <> '{}'::jsonb
		         AND NOT EXISTS (SELECT 1 FROM soul_fate_encounter_claims claim
		                         WHERE claim.soul_id=soul.id
		                           AND claim.encounter_id=n.dialogue->'fate_encounters'->trait.trait_id->>'id'))
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
		&item.FateTraitID,&item.FateReaction,&item.FateEncounterAvailable)
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


var (
	ErrExplorationUnavailable = errors.New("exploration point is unavailable")
	ErrExplorationResolved = errors.New("exploration point was already discovered by this soul")
)

type ExplorationPoint struct {
	ID string `json:"id"`
	WorldID string `json:"world_id"`
	RegionID string `json:"region_id"`
	RegionName string `json:"region_name"`
	Name string `json:"name"`
	Description string `json:"description"`
	PositionX float64 `json:"position_x"`
	PositionY float64 `json:"position_y"`
	PositionZ float64 `json:"position_z"`
	InteractionRadius float64 `json:"interaction_radius"`
	DangerLevel int `json:"danger_level"`
	Discovered bool `json:"discovered"`
}

type ExplorationResult struct {
	PointID string `json:"point_id"`
	Name string `json:"name"`
	Description string `json:"description"`
	Merit int64 `json:"merit"`
	Karma int64 `json:"karma"`
	MeritDelta int64 `json:"merit_delta"`
	KarmaDelta int64 `json:"karma_delta"`
}

// ListExplorationPoints returns the current world's authored points and the
// soul-level discovery state. The soul identity is resolved from the bearer account.
func (s *Service) ListExplorationPoints(ctx context.Context, accountID string) ([]ExplorationPoint, error) {
	var soulID, worldID string
	err := s.db.QueryRowContext(ctx,
		`SELECT soul.id::text, wi.world_id
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 WHERE soul.account_id=$1
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`, accountID).Scan(&soulID, &worldID)
	if errors.Is(err, sql.ErrNoRows) { return nil, ErrNoActiveSession }
	if err != nil { return nil, fmt.Errorf("resolve exploration session: %w", err) }

	rows, err := s.db.QueryContext(ctx,
		`SELECT p.id,p.world_id,p.region_id,
                COALESCE(route.region_name,
                    CASE p.region_id
                        WHEN 'fengdu_gate_outskirts' THEN '酆都鬼门关'
                        WHEN 'wangchuan_riverside' THEN '忘川河畔'
                        WHEN 'naihe_bridge' THEN '奈何桥'
                        WHEN 'reincarnation_hall_front' THEN '轮回殿前'
                        ELSE p.region_id
                    END),
                p.name,p.description,
		        p.position_x,p.position_y,p.position_z,p.interaction_radius,p.danger_level,
		        (d.point_id IS NOT NULL)
		 FROM world_exploration_points p
		 LEFT JOIN reincarnation_birth_routes route ON route.world_id=p.world_id AND route.region_id=p.region_id AND route.enabled=TRUE
		 LEFT JOIN soul_exploration_discoveries d ON d.point_id=p.id AND d.soul_id=$1::uuid
		 WHERE p.world_id=$2 AND p.enabled=TRUE
		 ORDER BY p.region_id,p.id`, soulID, worldID)
	if err != nil { return nil, fmt.Errorf("query exploration points: %w", err) }
	defer rows.Close()
	points := make([]ExplorationPoint, 0)
	for rows.Next() {
		var point ExplorationPoint
		if err := rows.Scan(&point.ID,&point.WorldID,&point.RegionID,&point.RegionName,&point.Name,&point.Description,
			&point.PositionX,&point.PositionY,&point.PositionZ,&point.InteractionRadius,&point.DangerLevel,&point.Discovered); err != nil {
			return nil, fmt.Errorf("scan exploration point: %w", err)
		}
		points = append(points, point)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate exploration points: %w", err) }
	return points, nil
}

// DiscoverExplorationPoint checks the character's last server-saved position,
// then atomically records a soul-wide discovery and its fate-ledger reward.
func (s *Service) DiscoverExplorationPoint(ctx context.Context, accountID, pointID string) (ExplorationResult, error) {
	if pointID == "" || len(pointID) > 96 { return ExplorationResult{}, ErrExplorationUnavailable }
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return ExplorationResult{}, fmt.Errorf("begin exploration discovery: %w", err) }
	defer tx.Rollback()

	var soulID, worldID string
	var point ExplorationPoint
	var meritDelta, karmaDelta int64
	err = tx.QueryRowContext(ctx,
		`SELECT soul.id::text,wi.world_id,p.id,p.world_id,p.region_id,p.name,p.description,
		        p.position_x,p.position_y,p.position_z,p.interaction_radius,p.danger_level,
		        p.merit_reward,p.karma_delta
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_exploration_points p ON p.world_id=wi.world_id AND p.id=$2 AND p.enabled=TRUE
		 WHERE soul.account_id=$1
		   AND SQRT(POWER(c.position_x-p.position_x,2)+POWER(c.position_y-p.position_y,2)+POWER(c.position_z-p.position_z,2)) <= p.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		 FOR UPDATE OF soul,c,ws`, accountID, pointID).Scan(
		&soulID,&worldID,&point.ID,&point.WorldID,&point.RegionID,&point.Name,&point.Description,
		&point.PositionX,&point.PositionY,&point.PositionZ,&point.InteractionRadius,&point.DangerLevel,
		&meritDelta,&karmaDelta)
	if errors.Is(err, sql.ErrNoRows) {
		var active bool
		checkErr := tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul
			 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
			 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
			 WHERE soul.account_id=$1)`, accountID).Scan(&active)
		if checkErr != nil { return ExplorationResult{}, fmt.Errorf("check exploration session: %w", checkErr) }
		if !active { return ExplorationResult{}, ErrNoActiveSession }
		var exists bool
		checkErr = tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_exploration_points p ON p.world_id=c.world_id AND p.id=$2 AND p.enabled=TRUE
			 WHERE soul.account_id=$1)`, accountID, pointID).Scan(&exists)
		if checkErr != nil { return ExplorationResult{}, fmt.Errorf("check exploration point: %w", checkErr) }
		if !exists { return ExplorationResult{}, ErrExplorationUnavailable }
		return ExplorationResult{}, ErrTooFar
	}
	if err != nil { return ExplorationResult{}, fmt.Errorf("validate exploration distance: %w", err) }

	var eventID string
	err = tx.QueryRowContext(ctx,
		`INSERT INTO soul_exploration_discoveries(soul_id,point_id)
		 VALUES($1,$2) ON CONFLICT(soul_id,point_id) DO NOTHING
		 RETURNING fate_event_id::text`, soulID, point.ID).Scan(&eventID)
	if errors.Is(err, sql.ErrNoRows) { return ExplorationResult{}, ErrExplorationResolved }
	if err != nil { return ExplorationResult{}, fmt.Errorf("claim exploration point: %w", err) }

	if meritDelta != 0 || karmaDelta != 0 {
		if _, err = tx.ExecContext(ctx,
			`INSERT INTO soul_fate_events(soul_id,event_id,source,world_id,karma_delta,merit_delta)
			 VALUES($1,$2::uuid,'world_exploration',$3,$4,$5)`,
			soulID,eventID,worldID,karmaDelta,meritDelta); err != nil {
			return ExplorationResult{}, fmt.Errorf("record exploration fate event: %w", err)
		}
	}
	result := ExplorationResult{PointID:point.ID,Name:point.Name,Description:point.Description,
		MeritDelta:meritDelta,KarmaDelta:karmaDelta}
	err = tx.QueryRowContext(ctx,
		`UPDATE souls SET merit=merit+$1,karma=karma+$2,updated_at=now()
		 WHERE id=$3 RETURNING merit,karma`, meritDelta,karmaDelta,soulID).Scan(&result.Merit,&result.Karma)
	if err != nil { return ExplorationResult{}, fmt.Errorf("apply exploration reward: %w", err) }
	if err := tx.Commit(); err != nil { return ExplorationResult{}, fmt.Errorf("commit exploration discovery: %w", err) }
	return result,nil
}


var (
	ErrExplorationEventUnavailable = errors.New("exploration event is unavailable")
	ErrExplorationEventResolved = errors.New("exploration event was already resolved by this soul")
)

type ExplorationEventChoice struct {
	ID string `json:"id"`
	Text string `json:"text"`
	Description string `json:"description"`
}

type explorationEventChoiceConfig struct {
	ID string `json:"id"`
	Text string `json:"text"`
	Description string `json:"description"`
	Result string `json:"result"`
	EffectKey string `json:"effect_key"`
}

type ExplorationEvent struct {
	ID string `json:"id"`
	PointID string `json:"point_id"`
	PointName string `json:"point_name"`
	Title string `json:"title"`
	Description string `json:"description"`
	EventType string `json:"event_type"`
	PositionX float64 `json:"position_x"`
	PositionY float64 `json:"position_y"`
	PositionZ float64 `json:"position_z"`
	InteractionRadius float64 `json:"interaction_radius"`
	DangerLevel int `json:"danger_level"`
	MeritReward int64 `json:"merit_reward"`
	KarmaDelta int64 `json:"karma_delta"`
	Choices []ExplorationEventChoice `json:"choices"`
	Status string `json:"status"`
	Discovered bool `json:"discovered"`
	Unlocked bool `json:"unlocked"`
	Completed bool `json:"completed"`
}

type ExplorationEventResult struct {
	EventID string `json:"event_id"`
	ChoiceID string `json:"choice_id"`
	ChoiceText string `json:"choice_text"`
	Title string `json:"title"`
	Description string `json:"description"`
	Outcome string `json:"outcome"`
	Merit int64 `json:"merit"`
	Karma int64 `json:"karma"`
	MeritDelta int64 `json:"merit_delta"`
	KarmaDelta int64 `json:"karma_delta"`
}

// ListAvailableExplorationEvents returns the active world's enabled events with
// soul discovery/claim state and current-body eligibility. Reward fields are
// previews only; TriggerExplorationEvent remains authoritative.
func (s *Service) ListAvailableExplorationEvents(ctx context.Context, accountID string) ([]ExplorationEvent, error) {
	var soulID, worldID string
	err := s.db.QueryRowContext(ctx,
		`SELECT soul.id::text,wi.world_id
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 WHERE soul.account_id=$1
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`, accountID).Scan(&soulID,&worldID)
	if errors.Is(err,sql.ErrNoRows) { return nil,ErrNoActiveSession }
	if err!=nil { return nil,fmt.Errorf("resolve exploration event session: %w",err) }

	rows,err:=s.db.QueryContext(ctx,
		`SELECT e.id,e.point_id,p.name,e.title,e.description,e.event_type,
		        p.position_x,p.position_y,p.position_z,p.interaction_radius,p.danger_level,
		        e.merit_reward,e.karma_delta,e.choices,
		        (d.point_id IS NOT NULL),
		        (d.point_id IS NOT NULL
		          AND (e.required_race_id IS NULL OR e.required_race_id=c.race_id)
		          AND (e.required_fate_trait_id IS NULL OR e.required_fate_trait_id=COALESCE(trait.trait_id,'unmarked_fate'))
		          AND (e.required_event_id IS NULL OR EXISTS (
		              SELECT 1 FROM soul_exploration_event_claims prior_claim
		              WHERE prior_claim.soul_id=soul.id AND prior_claim.event_id=e.required_event_id
		                AND prior_claim.choice_id=e.required_choice_id))),
		        (claim.event_id IS NOT NULL),
		        CASE
		          WHEN claim.event_id IS NOT NULL THEN 'completed'
		          WHEN e.required_event_id IS NOT NULL AND NOT EXISTS (
		              SELECT 1 FROM soul_exploration_event_claims prior_claim
		              WHERE prior_claim.soul_id=soul.id AND prior_claim.event_id=e.required_event_id
		                AND prior_claim.choice_id=e.required_choice_id) THEN 'locked'
		          WHEN d.point_id IS NOT NULL
		            AND (e.required_race_id IS NULL OR e.required_race_id=c.race_id)
		            AND (e.required_fate_trait_id IS NULL OR e.required_fate_trait_id=COALESCE(trait.trait_id,'unmarked_fate'))
		            AND (e.required_event_id IS NULL OR EXISTS (
		                SELECT 1 FROM soul_exploration_event_claims prior_claim
		                WHERE prior_claim.soul_id=soul.id AND prior_claim.event_id=e.required_event_id
		                  AND prior_claim.choice_id=e.required_choice_id))
		            THEN 'available'
		          ELSE 'locked'
		        END
		 FROM world_exploration_events e
		 JOIN world_exploration_points p ON p.id=e.point_id AND p.world_id=$2 AND p.enabled=TRUE
		 JOIN souls soul ON soul.id=$1::uuid
		 JOIN characters c ON c.id=soul.current_character_id
		 LEFT JOIN character_fate_traits trait ON trait.character_id=c.id
		 LEFT JOIN soul_exploration_discoveries d ON d.point_id=p.id AND d.soul_id=soul.id
		 LEFT JOIN soul_exploration_event_claims claim ON claim.soul_id=soul.id AND claim.event_id=e.id
		 WHERE e.enabled=TRUE
		 ORDER BY p.region_id,e.id`,soulID,worldID)
	if err!=nil { return nil,fmt.Errorf("query exploration events: %w",err) }
	defer rows.Close()
	items:=make([]ExplorationEvent,0)
	for rows.Next() {
		var item ExplorationEvent
		var choicesJSON []byte
		if err:=rows.Scan(&item.ID,&item.PointID,&item.PointName,&item.Title,&item.Description,&item.EventType,
			&item.PositionX,&item.PositionY,&item.PositionZ,&item.InteractionRadius,&item.DangerLevel,
			&item.MeritReward,&item.KarmaDelta,&choicesJSON,&item.Discovered,&item.Unlocked,&item.Completed,&item.Status);err!=nil {
			return nil,fmt.Errorf("scan exploration event: %w",err)
		}
		if len(choicesJSON)>0 {
			var configured []explorationEventChoiceConfig
			if err:=json.Unmarshal(choicesJSON,&configured);err!=nil { return nil,fmt.Errorf("decode exploration event choices: %w",err) }
			item.Choices=make([]ExplorationEventChoice,0,len(configured))
			for _,choice:=range configured { item.Choices=append(item.Choices,ExplorationEventChoice{ID:choice.ID,Text:choice.Text,Description:choice.Description}) }
		}
		items=append(items,item)
	}
	if err:=rows.Err();err!=nil { return nil,fmt.Errorf("iterate exploration events: %w",err) }
	return items,nil
}

func (s *Service) TriggerExplorationEvent(ctx context.Context, accountID,eventID,choiceID string) (ExplorationEventResult,error) {
	if eventID=="" || len(eventID)>96 || len(choiceID)>64 { return ExplorationEventResult{},ErrExplorationEventUnavailable }
	tx,err:=s.db.BeginTx(ctx,nil)
	if err!=nil { return ExplorationEventResult{},fmt.Errorf("begin exploration event: %w",err) }
	defer tx.Rollback()
	var soulID,worldID string
	var event ExplorationEvent
	var meritDelta,karmaDelta int64
	var choicesJSON []byte
	err=tx.QueryRowContext(ctx,
		`SELECT soul.id::text,wi.world_id,e.id,e.point_id,p.name,e.title,e.description,e.event_type,
		        p.position_x,p.position_y,p.position_z,p.interaction_radius,p.danger_level,
		        e.merit_reward,e.karma_delta,e.choices
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_exploration_events e ON e.id=$2 AND e.enabled=TRUE
		 JOIN world_exploration_points p ON p.id=e.point_id AND p.world_id=wi.world_id AND p.enabled=TRUE
		 JOIN soul_exploration_discoveries d ON d.point_id=p.id AND d.soul_id=soul.id
		 WHERE soul.account_id=$1
		   AND (e.required_race_id IS NULL OR e.required_race_id=c.race_id)
		   AND (e.required_fate_trait_id IS NULL OR e.required_fate_trait_id=COALESCE((SELECT trait_id FROM character_fate_traits WHERE character_id=c.id),'unmarked_fate'))
		   AND (e.required_event_id IS NULL OR EXISTS (
		       SELECT 1 FROM soul_exploration_event_claims prior_claim
		       WHERE prior_claim.soul_id=soul.id
		         AND prior_claim.event_id=e.required_event_id
		         AND prior_claim.choice_id=e.required_choice_id))
		   AND SQRT(POWER(c.position_x-p.position_x,2)+POWER(c.position_y-p.position_y,2)+POWER(c.position_z-p.position_z,2))<=p.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1
		 FOR UPDATE OF soul,c,ws`,accountID,eventID).Scan(
		&soulID,&worldID,&event.ID,&event.PointID,&event.PointName,&event.Title,&event.Description,&event.EventType,
		&event.PositionX,&event.PositionY,&event.PositionZ,&event.InteractionRadius,&event.DangerLevel,&meritDelta,&karmaDelta,&choicesJSON)
	if errors.Is(err,sql.ErrNoRows) {
		var active bool
		checkErr:=tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
			 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active' WHERE soul.account_id=$1)`,accountID).Scan(&active)
		if checkErr!=nil { return ExplorationEventResult{},fmt.Errorf("check exploration event session: %w",checkErr) }
		if !active { return ExplorationEventResult{},ErrNoActiveSession }
		var known bool
		checkErr=tx.QueryRowContext(ctx,
			`SELECT EXISTS(SELECT 1 FROM souls soul JOIN characters c ON c.id=soul.current_character_id
			 JOIN world_exploration_events e ON e.id=$2 AND e.enabled=TRUE
			 JOIN world_exploration_points p ON p.id=e.point_id AND p.world_id=c.world_id AND p.enabled=TRUE
			 JOIN soul_exploration_discoveries d ON d.point_id=p.id AND d.soul_id=soul.id
			 LEFT JOIN character_fate_traits trait ON trait.character_id=c.id
			 WHERE soul.account_id=$1
			   AND (e.required_race_id IS NULL OR e.required_race_id=c.race_id)
			   AND (e.required_fate_trait_id IS NULL OR e.required_fate_trait_id=COALESCE(trait.trait_id,'unmarked_fate'))
			   AND (e.required_event_id IS NULL OR EXISTS (
			       SELECT 1 FROM soul_exploration_event_claims prior_claim
			       WHERE prior_claim.soul_id=soul.id AND prior_claim.event_id=e.required_event_id
			         AND prior_claim.choice_id=e.required_choice_id)) )`,accountID,eventID).Scan(&known)
		if checkErr!=nil { return ExplorationEventResult{},fmt.Errorf("check exploration event unlock: %w",checkErr) }
		if !known { return ExplorationEventResult{},ErrExplorationEventUnavailable }
		return ExplorationEventResult{},ErrTooFar
	}
	if err!=nil { return ExplorationEventResult{},fmt.Errorf("validate exploration event: %w",err) }
	var selected *explorationEventChoiceConfig
	if len(choicesJSON)>0 {
		var configured []explorationEventChoiceConfig
		if err:=json.Unmarshal(choicesJSON,&configured);err!=nil { return ExplorationEventResult{},fmt.Errorf("decode exploration event choices: %w",err) }
		if choiceID=="" { return ExplorationEventResult{},ErrExplorationEventUnavailable }
		for i:=range configured { if configured[i].ID==choiceID { selected=&configured[i]; break } }
		if selected==nil { return ExplorationEventResult{},ErrExplorationEventUnavailable }
		switch selected.EffectKey {
		case "lantern_keep": meritDelta,karmaDelta=2,-1
		case "lantern_take": meritDelta,karmaDelta=1,1
		case "river_accept": meritDelta,karmaDelta=2,-1
		case "river_release": meritDelta,karmaDelta=1,1
		case "bridge_honor": meritDelta,karmaDelta=2,-2
		case "bridge_break": meritDelta,karmaDelta=1,2
		case "tablet_record": meritDelta,karmaDelta=3,-1
		case "tablet_conceal": meritDelta,karmaDelta=0,2
		case "stream_attune": meritDelta,karmaDelta=2,-1
		case "stream_purify": meritDelta,karmaDelta=1,0
		case "bridge_repair": meritDelta,karmaDelta=2,-2
		case "bridge_dismantle": meritDelta,karmaDelta=1,2
		case "beast_honor": meritDelta,karmaDelta=3,-1
		case "beast_awaken": meritDelta,karmaDelta=2,2
		case "lantern_shadow_follow": meritDelta,karmaDelta=3,-1
		case "lantern_shadow_release": meritDelta,karmaDelta=1,-1
		default: return ExplorationEventResult{},ErrExplorationEventUnavailable
		}
	} else if choiceID!="" {
		return ExplorationEventResult{},ErrExplorationEventUnavailable
	}
	var fateEventID string
	err=tx.QueryRowContext(ctx,
		`INSERT INTO soul_exploration_event_claims(soul_id,event_id,choice_id)
		 VALUES($1,$2,$3) ON CONFLICT(soul_id,event_id) DO NOTHING RETURNING fate_event_id::text`,soulID,event.ID,choiceID).Scan(&fateEventID)
	if errors.Is(err,sql.ErrNoRows) { return ExplorationEventResult{},ErrExplorationEventResolved }
	if err!=nil { return ExplorationEventResult{},fmt.Errorf("claim exploration event: %w",err) }
	if meritDelta!=0 || karmaDelta!=0 {
		if _,err=tx.ExecContext(ctx,
			`INSERT INTO soul_fate_events(soul_id,event_id,source,world_id,karma_delta,merit_delta)
			 VALUES($1,$2::uuid,'exploration_event',$3,$4,$5)`,soulID,fateEventID,worldID,karmaDelta,meritDelta);err!=nil {
			return ExplorationEventResult{},fmt.Errorf("record exploration event fate: %w",err)
		}
	}
	result:=ExplorationEventResult{EventID:event.ID,Title:event.Title,Description:event.Description,MeritDelta:meritDelta,KarmaDelta:karmaDelta}
	if selected!=nil { result.ChoiceID=selected.ID; result.ChoiceText=selected.Text; result.Outcome=selected.Result; result.Description=selected.Result }
	err=tx.QueryRowContext(ctx,
		`UPDATE souls SET merit=merit+$1,karma=karma+$2,updated_at=now() WHERE id=$3 RETURNING merit,karma`,
		meritDelta,karmaDelta,soulID).Scan(&result.Merit,&result.Karma)
	if err!=nil { return ExplorationEventResult{},fmt.Errorf("apply exploration event reward: %w",err) }
	if err:=tx.Commit();err!=nil { return ExplorationEventResult{},fmt.Errorf("commit exploration event: %w",err) }
	return result,nil
}


// ExplorationRegionProgress summarizes soul-persistent discoveries for one region.
type ExplorationRegionProgress struct {
	RegionID string `json:"region_id"`
	RegionName string `json:"region_name"`
	TotalPoints int `json:"total_points"`
	DiscoveredPoints int `json:"discovered_points"`
	TotalEvents int `json:"total_events"`
	ClaimedEvents int `json:"claimed_events"`
}

type ExplorationProgress struct {
	WorldID string `json:"world_id"`
	Regions []ExplorationRegionProgress `json:"regions"`
	TotalPoints int `json:"total_points"`
	DiscoveredPoints int `json:"discovered_points"`
	TotalEvents int `json:"total_events"`
	ClaimedEvents int `json:"claimed_events"`
}

// GetExplorationProgress aggregates only content applicable to the active
// character. Discovery and event claims remain soul-wide across reincarnation.
func (s *Service) GetExplorationProgress(ctx context.Context, accountID string) (ExplorationProgress, error) {
	var soulID, worldID, raceID, traitID string
	err := s.db.QueryRowContext(ctx,
		`SELECT soul.id::text,wi.world_id,c.race_id,COALESCE(trait.trait_id,'unmarked_fate')
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 LEFT JOIN character_fate_traits trait ON trait.character_id=c.id
		 WHERE soul.account_id=$1
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`, accountID).
		Scan(&soulID,&worldID,&raceID,&traitID)
	if errors.Is(err,sql.ErrNoRows) { return ExplorationProgress{},ErrNoActiveSession }
	if err != nil { return ExplorationProgress{},fmt.Errorf("resolve exploration progress session: %w",err) }

	rows, err := s.db.QueryContext(ctx,
		`SELECT p.region_id,
		        COALESCE(route.region_name,
		            CASE p.region_id
		                WHEN 'fengdu_gate_outskirts' THEN '酆都鬼门关'
		                WHEN 'wangchuan_riverside' THEN '忘川河畔'
		                WHEN 'naihe_bridge' THEN '奈何桥'
		                WHEN 'reincarnation_hall_front' THEN '轮回殿前'
		                ELSE p.region_id
		            END),
		        COUNT(DISTINCT p.id),
		        COUNT(DISTINCT d.point_id),
		        COUNT(DISTINCT e.id),
		        COUNT(DISTINCT claim.event_id)
		 FROM world_exploration_points p
		 LEFT JOIN reincarnation_birth_routes route
		   ON route.world_id=p.world_id AND route.region_id=p.region_id AND route.enabled=TRUE
		 LEFT JOIN soul_exploration_discoveries d
		   ON d.point_id=p.id AND d.soul_id=$1::uuid
		 LEFT JOIN world_exploration_events e
		   ON e.point_id=p.id AND e.enabled=TRUE
		  AND (e.required_race_id IS NULL OR e.required_race_id=$3)
		  AND (e.required_fate_trait_id IS NULL OR e.required_fate_trait_id=$4)
		 LEFT JOIN soul_exploration_event_claims claim
		   ON claim.event_id=e.id AND claim.soul_id=$1::uuid
		 WHERE p.world_id=$2 AND p.enabled=TRUE
		 GROUP BY p.region_id,route.region_name
		 ORDER BY p.region_id`, soulID,worldID,raceID,traitID)
	if err != nil { return ExplorationProgress{},fmt.Errorf("query exploration region progress: %w",err) }
	defer rows.Close()

	result := ExplorationProgress{WorldID:worldID,Regions:make([]ExplorationRegionProgress,0)}
	for rows.Next() {
		var item ExplorationRegionProgress
		if err := rows.Scan(&item.RegionID,&item.RegionName,&item.TotalPoints,&item.DiscoveredPoints,&item.TotalEvents,&item.ClaimedEvents); err != nil {
			return ExplorationProgress{},fmt.Errorf("scan exploration region progress: %w",err)
		}
		result.TotalPoints += item.TotalPoints
		result.DiscoveredPoints += item.DiscoveredPoints
		result.TotalEvents += item.TotalEvents
		result.ClaimedEvents += item.ClaimedEvents
		result.Regions = append(result.Regions,item)
	}
	if err := rows.Err(); err != nil { return ExplorationProgress{},fmt.Errorf("iterate exploration region progress: %w",err) }
	return result,nil
}
