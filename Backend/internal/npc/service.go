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
		        n.position_x,n.position_y,n.position_z,n.rotation_y,n.interaction_radius,n.dialogue
		 FROM souls soul
		 JOIN characters c ON c.id=soul.current_character_id AND c.status='alive'
		 JOIN world_sessions ws ON ws.character_id=c.id AND ws.session_state='active'
		 JOIN world_instances wi ON wi.id=ws.instance_id AND wi.world_id=c.world_id
		 JOIN world_npc_definitions n ON n.world_id=wi.world_id AND n.id=$2 AND n.enabled=TRUE
		 WHERE soul.account_id=$1
		   AND SQRT(POWER(c.position_x-n.position_x,2)+POWER(c.position_y-n.position_y,2)+POWER(c.position_z-n.position_z,2)) <= n.interaction_radius
		 ORDER BY ws.connected_at DESC NULLS LAST LIMIT 1`,accountID,npcID).Scan(
		&item.ID,&item.WorldID,&item.Name,&item.Title,&item.Type,&item.InteractionType,
		&item.PositionX,&item.PositionY,&item.PositionZ,&item.RotationY,&item.InteractionRadius,&item.Dialogue)
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
