package inventory

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"math/big"
	"strings"
)

var (
	ErrInvalidRequest = errors.New("invalid inventory request")
	ErrSessionInvalid = errors.New("world session is not active on this server")
	ErrDropUnavailable = errors.New("drop is unavailable")
	ErrInventoryFull = errors.New("inventory is full")
	ErrInsufficientMaterials = errors.New("insufficient enhancement materials")
	ErrCharacterInWorld = errors.New("character has an active world session")
	ErrIdempotencyConflict = errors.New("request id was already used for another operation")
)

type ItemStack struct {
	InstanceID string `json:"instance_id,omitempty"`
	EnhancementLevel int `json:"enhancement_level,omitempty"`
	RolledStats map[string]int `json:"rolled_stats,omitempty"`
	Affixes []EquipmentAffix `json:"affixes,omitempty"`
	ItemID string `json:"item_id"`
	Name string `json:"name"`
	Category string `json:"category"`
	Quality int `json:"quality"`
	Quantity int `json:"quantity,omitempty"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
	Description string `json:"description"`
	ItemType string `json:"item_type"`
	EquipmentSlot string `json:"equipment_slot,omitempty"`
	WeaponType string `json:"weapon_type,omitempty"`
	BaseStats map[string]int `json:"base_stats,omitempty"`
	SetID string `json:"set_id,omitempty"`
	SetName string `json:"set_name,omitempty"`
	SetDescription string `json:"set_description,omitempty"`
	SetBonusTiers map[int]map[string]int `json:"set_bonus_tiers,omitempty"`
}


type LootEntry struct {
	MonsterID string `json:"monster_id"`
	ItemID string `json:"item_id"`
	ItemName string `json:"item_name"`
	Quality int `json:"quality"`
	DropChanceBP int `json:"drop_chance_bp"`
	MinQuantity int `json:"min_quantity"`
	MaxQuantity int `json:"max_quantity"`
	MaxStack int `json:"max_stack"`
	IconKey string `json:"icon_key"`
}

type EquipmentAffix struct {
	ID string `json:"id"`
	Name string `json:"name"`
	StatKey string `json:"stat_key"`
	Value int `json:"value"`
}

type GroundDrop struct {
	ID string `json:"id"`
	ItemInstanceID string `json:"item_instance_id,omitempty"`
	Quality int `json:"quality"`
	RolledStats map[string]int `json:"rolled_stats,omitempty"`
	Affixes []EquipmentAffix `json:"affixes,omitempty"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
	ExpiresAt string `json:"expires_at"`
}


type GroundDropSnapshot struct {
	ID string `json:"id"`
	ItemInstanceID string `json:"item_instance_id,omitempty"`
	RolledStats map[string]int `json:"rolled_stats,omitempty"`
	Affixes []EquipmentAffix `json:"affixes,omitempty"`
	SessionID string `json:"session_id"`
	OwnerCharacterID string `json:"owner_character_id"`
	ItemID string `json:"item_id"`
	ItemName string `json:"item_name"`
	Quality int `json:"quality"`
	Quantity int `json:"quantity"`
	PositionX float64 `json:"position_x"`
	PositionZ float64 `json:"position_z"`
	RemainingSeconds int `json:"remaining_seconds"`
}

type DropRequest struct {
	DropID string
	SessionID string
	CharacterID string
	ItemID string
	Quantity int
	PositionX float64
	PositionZ float64
}

type PickupRequest struct {
	EventID string
	DropID string
	SessionID string
	CharacterID string
}

type Result struct {
	Applied bool `json:"applied"`
	ItemID string `json:"item_id,omitempty"`
	ItemInstanceID string `json:"item_instance_id,omitempty"`
	Quantity int `json:"quantity,omitempty"`
}

type Service struct { db *sql.DB }

func NewService(db *sql.DB) *Service { return &Service{db: db} }

func (s *Service) ListItems(ctx context.Context) ([]ItemStack, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT i.id, i.name, i.category, i.quality, i.max_stack, i.icon_key, i.description, i.item_type, COALESCE(i.equipment_slot, ''), COALESCE(i.weapon_type, ''), i.base_stats, COALESCE(es.id, ''), COALESCE(es.name, ''), COALESCE(es.description, ''), COALESCE(es.bonus_tiers, '{}'::jsonb)
		FROM item_definitions i LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id WHERE i.enabled ORDER BY i.quality DESC, i.category, i.id`)
	if err != nil { return nil, fmt.Errorf("list item definitions: %w", err) }
	defer rows.Close()
	items := make([]ItemStack, 0)
	for rows.Next() {
		var item ItemStack
		var stats, setTiers []byte
		if err := rows.Scan(&item.ItemID, &item.Name, &item.Category, &item.Quality, &item.MaxStack, &item.IconKey, &item.Description, &item.ItemType, &item.EquipmentSlot, &item.WeaponType, &stats, &item.SetID, &item.SetName, &item.SetDescription, &setTiers); err != nil {
			return nil, fmt.Errorf("scan item definition: %w", err)
		}
		item.BaseStats = map[string]int{}
		if len(stats) > 0 { if err := json.Unmarshal(stats, &item.BaseStats); err != nil { return nil, fmt.Errorf("decode item stats: %w", err) } }
		if len(setTiers)>0 { if err:=json.Unmarshal(setTiers,&item.SetBonusTiers); err!=nil { return nil,fmt.Errorf("decode equipment set tiers: %w",err) } }
		items = append(items, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate item definitions: %w", err) }
	return items, nil
}


func (s *Service) ListLootTable(ctx context.Context) ([]LootEntry, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT ml.monster_id, i.id, i.name, i.quality,
		ml.drop_chance_bp, ml.min_quantity, ml.max_quantity, i.max_stack, i.icon_key
		FROM monster_loot_entries ml
		JOIN item_definitions i ON i.id = ml.item_id
		WHERE i.enabled
		ORDER BY ml.monster_id, i.quality DESC, i.id`)
	if err != nil { return nil, fmt.Errorf("list monster loot table: %w", err) }
	defer rows.Close()
	entries := make([]LootEntry, 0)
	for rows.Next() {
		var entry LootEntry
		if err := rows.Scan(&entry.MonsterID, &entry.ItemID, &entry.ItemName, &entry.Quality,
			&entry.DropChanceBP, &entry.MinQuantity, &entry.MaxQuantity, &entry.MaxStack, &entry.IconKey); err != nil {
			return nil, fmt.Errorf("scan monster loot entry: %w", err)
		}
		entries = append(entries, entry)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate monster loot table: %w", err) }
	return entries, nil
}

type InventoryCapacity struct {
	UsedSlots int `json:"used_slots"`
	MaxSlots int `json:"max_slots"`
	FreeSlots int `json:"free_slots"`
}

func equipmentSalvageYield(baseQuantity,quality,perQualityBonus,maxStack int)(int,bool){
	if baseQuantity<1||quality<1||quality>5||perQualityBonus<0||maxStack<1{return 0,false}
	quantity:=baseQuantity+(quality-1)*perQualityBonus
	if quantity<1||quantity>maxStack{return 0,false}
	return quantity,true
}

func inventorySlotAvailable(usedSlots,maxSlots int,needsNewSlot bool)bool{
	return usedSlots>=0&&maxSlots>=1&&(!needsNewSlot||usedSlots<maxSlots)
}

func ensureInventorySlot(ctx context.Context,tx *sql.Tx,characterID string,needsNewSlot bool)error{
	var usedSlots,maxSlots int
	if err:=tx.QueryRowContext(ctx,`SELECT
		(SELECT count(*) FROM character_inventory ci WHERE ci.character_id=c.id)+
		(SELECT count(*) FROM character_item_instances ii WHERE ii.character_id=c.id),
		COALESCE((SELECT cap.max_slots FROM character_inventory_capacity cap WHERE cap.character_id=c.id),40)
		FROM characters c WHERE c.id=$1::uuid`,characterID).Scan(&usedSlots,&maxSlots);err!=nil{
		return fmt.Errorf("load inventory capacity: %w",err)
	}
	if !inventorySlotAvailable(usedSlots,maxSlots,needsNewSlot){return ErrInventoryFull}
	return nil
}

func (s *Service) CurrentCapacity(ctx context.Context,accountID string)(InventoryCapacity,error){
	var result InventoryCapacity
	err:=s.db.QueryRowContext(ctx,`SELECT
		(SELECT count(*) FROM character_inventory ci WHERE ci.character_id=c.id)+
		(SELECT count(*) FROM character_item_instances ii WHERE ii.character_id=c.id),
		COALESCE((SELECT cap.max_slots FROM character_inventory_capacity cap WHERE cap.character_id=c.id),40)
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive'`,accountID).Scan(&result.UsedSlots,&result.MaxSlots)
	if errors.Is(err,sql.ErrNoRows){return InventoryCapacity{},ErrInvalidRequest}
	if err!=nil{return InventoryCapacity{},fmt.Errorf("load current inventory capacity: %w",err)}
	result.FreeSlots=max(0,result.MaxSlots-result.UsedSlots)
	return result,nil
}

func (s *Service) CurrentInventory(ctx context.Context, accountID string) ([]ItemStack, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT i.id, i.name, i.category, i.quality, ci.quantity, i.max_stack, i.icon_key, i.description, i.item_type, COALESCE(i.equipment_slot, ''), COALESCE(i.weapon_type, ''), i.base_stats, COALESCE(es.id, ''), COALESCE(es.name, ''), COALESCE(es.description, ''), COALESCE(es.bonus_tiers, '{}'::jsonb)
		FROM souls soul
		JOIN characters c ON c.id = soul.current_character_id
		JOIN character_inventory ci ON ci.character_id = c.id
		JOIN item_definitions i ON i.id = ci.item_id
		LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id
		WHERE soul.account_id = $1 AND c.status = 'alive'
		ORDER BY i.quality DESC, i.name`, accountID)
	if err != nil { return nil, fmt.Errorf("load current character inventory: %w", err) }
	defer rows.Close()
	items := make([]ItemStack, 0)
	for rows.Next() {
		var item ItemStack
		var stats, setTiers []byte
		if err := rows.Scan(&item.ItemID, &item.Name, &item.Category, &item.Quality, &item.Quantity, &item.MaxStack, &item.IconKey, &item.Description, &item.ItemType, &item.EquipmentSlot, &item.WeaponType, &stats, &item.SetID, &item.SetName, &item.SetDescription, &setTiers); err != nil {
			return nil, fmt.Errorf("scan inventory stack: %w", err)
		}
		item.BaseStats = map[string]int{}
		if len(stats) > 0 { if err := json.Unmarshal(stats, &item.BaseStats); err != nil { return nil, fmt.Errorf("decode inventory item stats: %w", err) } }
		if len(setTiers)>0 { if err:=json.Unmarshal(setTiers,&item.SetBonusTiers); err!=nil { return nil,fmt.Errorf("decode inventory set tiers: %w",err) } }
		items = append(items, item)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate inventory: %w", err) }
	if err := rows.Close(); err != nil { return nil, fmt.Errorf("close inventory stacks: %w", err) }
	instanceRows, err := s.db.QueryContext(ctx, `SELECT ii.id::text,i.id,i.name,i.category,ii.quality,i.max_stack,i.icon_key,i.description,
		i.item_type,COALESCE(i.equipment_slot,''),COALESCE(i.weapon_type,''),i.base_stats,ii.rolled_stats,ii.affixes,ii.enhancement_level,
		COALESCE(es.id,''),COALESCE(es.name,''),COALESCE(es.description,''),COALESCE(es.bonus_tiers,'{}'::jsonb)
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		JOIN character_item_instances ci ON ci.character_id=c.id
		JOIN item_instances ii ON ii.id=ci.item_instance_id
		JOIN item_definitions i ON i.id=ii.item_id
		LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id
		WHERE soul.account_id=$1 AND c.status='alive' ORDER BY ii.quality DESC,i.name,ii.id`,accountID)
	if err!=nil{return nil,fmt.Errorf("load current equipment instances: %w",err)}
	defer instanceRows.Close()
	for instanceRows.Next(){
		var item ItemStack;var baseRaw,rolledRaw,affixesRaw,setTiers []byte
		if err:=instanceRows.Scan(&item.InstanceID,&item.ItemID,&item.Name,&item.Category,&item.Quality,&item.MaxStack,&item.IconKey,&item.Description,
			&item.ItemType,&item.EquipmentSlot,&item.WeaponType,&baseRaw,&rolledRaw,&affixesRaw,&item.EnhancementLevel,&item.SetID,&item.SetName,&item.SetDescription,&setTiers);err!=nil{
			return nil,fmt.Errorf("scan equipment item instance: %w",err)
		}
		item.Quantity=1;item.BaseStats=map[string]int{};item.RolledStats=map[string]int{};item.Affixes=[]EquipmentAffix{}
		if len(baseRaw)>0{if err:=json.Unmarshal(baseRaw,&item.BaseStats);err!=nil{return nil,fmt.Errorf("decode equipment instance base stats: %w",err)}}
		if len(rolledRaw)>0{if err:=json.Unmarshal(rolledRaw,&item.RolledStats);err!=nil{return nil,fmt.Errorf("decode equipment instance rolled stats: %w",err)}}
		if len(affixesRaw)>0{if err:=json.Unmarshal(affixesRaw,&item.Affixes);err!=nil{return nil,fmt.Errorf("decode equipment instance affixes: %w",err)}}
		if len(setTiers)>0{if err:=json.Unmarshal(setTiers,&item.SetBonusTiers);err!=nil{return nil,fmt.Errorf("decode equipment instance set tiers: %w",err)}}
		items=append(items,item)
	}
	if err:=instanceRows.Err();err!=nil{return nil,fmt.Errorf("iterate equipment instances: %w",err)}
	return items, nil
}

// CreateDrop is called only by an authenticated world server after its own
// authoritative loot roll. The server supplies the item and quantity.

func (s *Service) expireGroundDrops(ctx context.Context,nodeKey string)error{
	tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin ground drop expiration: %w",err)}
	defer tx.Rollback()
	rows,err:=tx.QueryContext(ctx,`SELECT item_instance_id::text FROM ground_drops
		WHERE server_id=(SELECT id FROM server_registry WHERE node_key=$1)
		  AND status='available' AND expires_at<=now() AND item_instance_id IS NOT NULL
		FOR UPDATE`,nodeKey)
	if err!=nil{return fmt.Errorf("load expired equipment drops: %w",err)}
	instanceIDs:=make([]string,0)
	for rows.Next(){var id string;if err:=rows.Scan(&id);err!=nil{rows.Close();return fmt.Errorf("scan expired equipment instance: %w",err)};instanceIDs=append(instanceIDs,id)}
	if err:=rows.Err();err!=nil{rows.Close();return fmt.Errorf("iterate expired equipment drops: %w",err)}
	if err:=rows.Close();err!=nil{return fmt.Errorf("close expired equipment drops: %w",err)}
	if _,err:=tx.ExecContext(ctx,`UPDATE ground_drops SET status='expired',item_instance_id=NULL,updated_at=now()
		WHERE server_id=(SELECT id FROM server_registry WHERE node_key=$1)
		  AND status='available' AND expires_at<=now()`,nodeKey);err!=nil{return fmt.Errorf("mark expired ground drops: %w",err)}
	for _,id:=range instanceIDs{
		if _,err:=tx.ExecContext(ctx,`DELETE FROM item_instances ii WHERE ii.id=$1::uuid
			AND NOT EXISTS(SELECT 1 FROM character_item_instances ci WHERE ci.item_instance_id=ii.id)
			AND NOT EXISTS(SELECT 1 FROM character_equipment ce WHERE ce.item_instance_id=ii.id)`,id);err!=nil{
			return fmt.Errorf("discard expired equipment instance %s: %w",id,err)
		}
	}
	if err:=tx.Commit();err!=nil{return fmt.Errorf("commit ground drop expiration: %w",err)}
	return nil
}

func (s *Service) ListGroundDrops(ctx context.Context, nodeKey string) ([]GroundDropSnapshot, error) {
	if strings.TrimSpace(nodeKey) == "" { return nil, ErrInvalidRequest }
	if err:=s.expireGroundDrops(ctx,nodeKey);err!=nil{return nil,fmt.Errorf("expire old ground drops: %w",err)}
	rows, err := s.db.QueryContext(ctx, `SELECT d.id::text, d.session_id::text, d.owner_character_id::text,
		d.item_id, i.name, COALESCE(ii.quality, i.quality), d.quantity, d.position_x, d.position_z,
		GREATEST(0, CEIL(EXTRACT(EPOCH FROM (d.expires_at - now()))))::integer,
		COALESCE(ii.id::text, ''), COALESCE(ii.rolled_stats, '{}'::jsonb), COALESCE(ii.affixes, '[]'::jsonb)
		FROM ground_drops d
		JOIN server_registry s ON s.id = d.server_id
		JOIN item_definitions i ON i.id = d.item_id
		LEFT JOIN item_instances ii ON ii.id = d.item_instance_id
		WHERE s.node_key = $1 AND d.status = 'available' AND d.expires_at > now()
		ORDER BY d.created_at`, nodeKey)
	if err != nil { return nil, fmt.Errorf("list persisted ground drops: %w", err) }
	defer rows.Close()
	drops := make([]GroundDropSnapshot, 0)
	for rows.Next() {
		var drop GroundDropSnapshot
		var rolledRaw, affixesRaw []byte
		if err := rows.Scan(&drop.ID, &drop.SessionID, &drop.OwnerCharacterID, &drop.ItemID,
			&drop.ItemName, &drop.Quality, &drop.Quantity, &drop.PositionX, &drop.PositionZ,
			&drop.RemainingSeconds, &drop.ItemInstanceID, &rolledRaw, &affixesRaw); err != nil {
			return nil, fmt.Errorf("scan persisted ground drop: %w", err)
		}
		drop.RolledStats = map[string]int{}
		drop.Affixes = []EquipmentAffix{}
		if len(rolledRaw)>0 { if err:=json.Unmarshal(rolledRaw,&drop.RolledStats); err!=nil{return nil,fmt.Errorf("decode ground drop stats: %w",err)} }
		if len(affixesRaw)>0 { if err:=json.Unmarshal(affixesRaw,&drop.Affixes); err!=nil{return nil,fmt.Errorf("decode ground drop affixes: %w",err)} }
		drops = append(drops, drop)
	}
	if err := rows.Err(); err != nil { return nil, fmt.Errorf("iterate persisted ground drops: %w", err) }
	return drops, nil
}


func scanGroundDrop(row interface{ Scan(...any) error }, drop *GroundDrop) error {
	var statsRaw, affixesRaw []byte
	if err:=row.Scan(&drop.ID,&drop.ItemID,&drop.Quantity,&drop.PositionX,&drop.PositionZ,&drop.ExpiresAt,
		&drop.ItemInstanceID,&drop.Quality,&statsRaw,&affixesRaw);err!=nil{return err}
	drop.RolledStats=map[string]int{};drop.Affixes=[]EquipmentAffix{}
	if len(statsRaw)>0{if err:=json.Unmarshal(statsRaw,&drop.RolledStats);err!=nil{return fmt.Errorf("decode item instance stats: %w",err)}}
	if len(affixesRaw)>0{if err:=json.Unmarshal(affixesRaw,&drop.Affixes);err!=nil{return fmt.Errorf("decode item instance affixes: %w",err)}}
	return nil
}

func equipmentAffixRollCount(quality int) int {
	switch {
	case quality >= 5: return 3
	case quality >= 3: return 2
	case quality >= 1: return 1
	default: return 0
	}
}

func secureRandomInt(max int64)(int64,error){
	if max<=0{return 0,ErrInvalidRequest}
	value,err:=rand.Int(rand.Reader,big.NewInt(max));if err!=nil{return 0,fmt.Errorf("generate equipment affix roll: %w",err)}
	return value.Int64(),nil
}

func createGroundDropInstance(ctx context.Context,tx *sql.Tx,request DropRequest)(GroundDrop,error){
	result:=GroundDrop{ID:request.DropID,ItemID:request.ItemID,Quantity:request.Quantity,PositionX:request.PositionX,PositionZ:request.PositionZ,
		RolledStats:map[string]int{},Affixes:[]EquipmentAffix{}}
	var itemType,slot string;var quality int
	if err:=tx.QueryRowContext(ctx,`SELECT item_type,COALESCE(equipment_slot,''),quality FROM item_definitions WHERE id=$1 AND enabled`,request.ItemID).Scan(&itemType,&slot,&quality);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return GroundDrop{},ErrInvalidRequest};return GroundDrop{},fmt.Errorf("load dropped item type: %w",err)
	}
	result.Quality=quality
	if itemType!="equipment"{return result,nil}
	rows,err:=tx.QueryContext(ctx,`SELECT id,name,stat_key,min_value,max_value,weight FROM equipment_affix_definitions
		WHERE enabled AND min_quality<=$1 AND equipment_slot IN ('any',$2) ORDER BY id`,quality,slot)
	if err!=nil{return GroundDrop{},fmt.Errorf("load equipment affix pool: %w",err)}
	type candidate struct{id,name,key string;min,max,weight int}
	pool:=make([]candidate,0)
	for rows.Next(){var a candidate;if err:=rows.Scan(&a.id,&a.name,&a.key,&a.min,&a.max,&a.weight);err!=nil{rows.Close();return GroundDrop{},fmt.Errorf("scan equipment affix: %w",err)};pool=append(pool,a)}
	if err:=rows.Err();err!=nil{rows.Close();return GroundDrop{},fmt.Errorf("iterate equipment affixes: %w",err)};rows.Close()
	rollCount:=equipmentAffixRollCount(quality)
	for n:=0;n<rollCount&&len(pool)>0;n++{
		total:=int64(0);for _,a:=range pool{total+=int64(a.weight)}
		pick,err:=secureRandomInt(total);if err!=nil{return GroundDrop{},err}
		chosen:=0;for i,a:=range pool{pick-=int64(a.weight);if pick<0{chosen=i;break}}
		a:=pool[chosen];v,err:=secureRandomInt(int64(a.max-a.min+1));if err!=nil{return GroundDrop{},err};value:=a.min+int(v)
		result.Affixes=append(result.Affixes,EquipmentAffix{ID:a.id,Name:a.name,StatKey:a.key,Value:value})
		result.RolledStats[a.key]+=value
		pool=append(pool[:chosen],pool[chosen+1:]...)
	}
	statsRaw,err:=json.Marshal(result.RolledStats);if err!=nil{return GroundDrop{},fmt.Errorf("encode rolled equipment stats: %w",err)}
	affixesRaw,err:=json.Marshal(result.Affixes);if err!=nil{return GroundDrop{},fmt.Errorf("encode rolled equipment affixes: %w",err)}
	if _,err:=tx.ExecContext(ctx,`INSERT INTO item_instances(id,item_id,quality,rolled_stats,affixes) VALUES($1::uuid,$2,$3,$4::jsonb,$5::jsonb)`,
		request.DropID,request.ItemID,quality,string(statsRaw),string(affixesRaw));err!=nil{return GroundDrop{},fmt.Errorf("persist equipment instance: %w",err)}
	result.ItemInstanceID=request.DropID
	return result,nil
}

func (s *Service) CreateDrop(ctx context.Context, nodeKey string, request DropRequest) (GroundDrop, error) {
	if strings.TrimSpace(nodeKey) == "" || !validUUID(request.DropID) || !validUUID(request.SessionID) ||
		!validUUID(request.CharacterID) || strings.TrimSpace(request.ItemID) == "" ||
		request.Quantity < 1 || request.Quantity > 9999 ||
		math.IsNaN(request.PositionX) || math.IsInf(request.PositionX, 0) ||
		math.IsNaN(request.PositionZ) || math.IsInf(request.PositionZ, 0) {
		return GroundDrop{}, ErrInvalidRequest
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return GroundDrop{}, fmt.Errorf("begin ground drop: %w", err) }
	defer tx.Rollback()
	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrSessionInvalid }
		return GroundDrop{}, fmt.Errorf("resolve drop server: %w", err)
	}
	var maxStack int
	if err := tx.QueryRowContext(ctx, `SELECT max_stack FROM item_definitions WHERE id = $1 AND enabled`, request.ItemID).Scan(&maxStack); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return GroundDrop{}, ErrInvalidRequest }
		return GroundDrop{}, fmt.Errorf("load drop item: %w", err)
	}
	if request.Quantity > maxStack { return GroundDrop{}, ErrInvalidRequest }
	// The drop UUID is also the item-instance UUID, making retries stable.
	var existing GroundDrop
	err = scanGroundDrop(tx.QueryRowContext(ctx, `SELECT d.id::text, d.item_id, d.quantity, d.position_x, d.position_z, d.expires_at::text,
		COALESCE(ii.id::text, ''), COALESCE(ii.quality, i.quality), COALESCE(ii.rolled_stats, '{}'::jsonb), COALESCE(ii.affixes, '[]'::jsonb)
		FROM ground_drops d JOIN item_definitions i ON i.id=d.item_id
		LEFT JOIN item_instances ii ON ii.id=d.item_instance_id
		WHERE d.id=$1::uuid AND d.server_id=$2 AND d.session_id=$3::uuid
		  AND d.owner_character_id=$4::uuid AND d.item_id=$5 AND d.quantity=$6
		  AND d.position_x=$7 AND d.position_z=$8 AND d.status='available' AND d.expires_at>now()`,
		request.DropID,serverID,request.SessionID,request.CharacterID,request.ItemID,request.Quantity,request.PositionX,request.PositionZ), &existing)
	if err == nil {
		if err:=tx.Commit();err!=nil{return GroundDrop{},fmt.Errorf("commit recovered ground drop: %w",err)}
		return existing,nil
	}
	if !errors.Is(err,sql.ErrNoRows){return GroundDrop{},fmt.Errorf("recover existing ground drop: %w",err)}
	var valid bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM world_sessions WHERE id = $1::uuid AND server_id = $2 AND character_id = $3::uuid AND session_state = 'active'
	)`, request.SessionID, serverID, request.CharacterID).Scan(&valid); err != nil {
		return GroundDrop{}, fmt.Errorf("verify drop session: %w", err)
	}
	if !valid { return GroundDrop{}, ErrSessionInvalid }
	result,err:=createGroundDropInstance(ctx,tx,request)
	if err!=nil{return GroundDrop{},err}
	err=tx.QueryRowContext(ctx,`INSERT INTO ground_drops
		(id,server_id,session_id,owner_character_id,item_id,item_instance_id,quantity,position_x,position_z,expires_at)
		VALUES($1::uuid,$2,$3::uuid,$4::uuid,$5,NULLIF($6,'')::uuid,$7,$8,$9,now()+INTERVAL '15 minutes')
		RETURNING id::text,item_id,quantity,position_x,position_z,expires_at::text`,
		request.DropID,serverID,request.SessionID,request.CharacterID,request.ItemID,result.ItemInstanceID,
		request.Quantity,request.PositionX,request.PositionZ).Scan(&result.ID,&result.ItemID,&result.Quantity,&result.PositionX,&result.PositionZ,&result.ExpiresAt)
	if err!=nil{return GroundDrop{},fmt.Errorf("create ground drop: %w",err)}
	if err := tx.Commit(); err != nil { return GroundDrop{}, fmt.Errorf("commit ground drop: %w", err) }
	return result, nil
}

// PickupDrop is called after the WorldServer has validated range and pickup
// permissions. The DB transaction atomically consumes a drop and transfers either
// a stackable item or its unique equipment instance into the character inventory.
func (s *Service) PickupDrop(ctx context.Context, nodeKey string, request PickupRequest) (Result, error) {
	if strings.TrimSpace(nodeKey) == "" || !validUUID(request.EventID) || !validUUID(request.DropID) ||
		!validUUID(request.SessionID) || !validUUID(request.CharacterID) {
		return Result{}, ErrInvalidRequest
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Result{}, fmt.Errorf("begin item pickup: %w", err) }
	defer tx.Rollback()
	var serverID string
	if err := tx.QueryRowContext(ctx, `SELECT id::text FROM server_registry WHERE node_key = $1`, nodeKey).Scan(&serverID); err != nil {
		if errors.Is(err, sql.ErrNoRows) { return Result{}, ErrSessionInvalid }
		return Result{}, fmt.Errorf("resolve pickup server: %w", err)
	}
	var duplicate bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM item_pickup_events WHERE server_id = $1 AND event_id = $2::uuid)`, serverID, request.EventID).Scan(&duplicate); err != nil {
		return Result{}, fmt.Errorf("check pickup idempotency: %w", err)
	}
	if duplicate {
		if err := tx.Commit(); err != nil { return Result{}, fmt.Errorf("commit duplicate pickup: %w", err) }
		return Result{Applied: false}, nil
	}
	var lockedCharacter string
	err=tx.QueryRowContext(ctx,`SELECT c.id::text FROM world_sessions ws
		JOIN characters c ON c.id=ws.character_id
		WHERE ws.id=$1::uuid AND ws.server_id=$2 AND ws.character_id=$3::uuid
		  AND ws.session_state='active' AND c.status='alive'
		FOR UPDATE OF c`,request.SessionID,serverID,request.CharacterID).Scan(&lockedCharacter)
	if errors.Is(err,sql.ErrNoRows){return Result{},ErrSessionInvalid}
	if err!=nil{return Result{},fmt.Errorf("lock active pickup character: %w",err)}
	var usedSlots,maxSlots int
	err=tx.QueryRowContext(ctx,`SELECT
		(SELECT count(*) FROM character_inventory ci WHERE ci.character_id=c.id)+
		(SELECT count(*) FROM character_item_instances ii WHERE ii.character_id=c.id),
		COALESCE((SELECT cap.max_slots FROM character_inventory_capacity cap WHERE cap.character_id=c.id),40)
		FROM characters c WHERE c.id=$1::uuid`,lockedCharacter).Scan(&usedSlots,&maxSlots)
	if err!=nil{return Result{},fmt.Errorf("load pickup inventory capacity: %w",err)}
	// Another request with the same event ID may have completed while this
	// transaction waited for the character row lock.
	if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM item_pickup_events WHERE server_id=$1 AND event_id=$2::uuid)`,serverID,request.EventID).Scan(&duplicate);err!=nil{
		return Result{},fmt.Errorf("recheck pickup idempotency: %w",err)
	}
	if duplicate{
		if err:=tx.Commit();err!=nil{return Result{},fmt.Errorf("commit concurrent duplicate pickup: %w",err)}
		return Result{Applied:false},nil
	}
	var itemID string
	var itemInstanceID sql.NullString
	var quantity int
	err = tx.QueryRowContext(ctx, `SELECT item_id,item_instance_id::text,quantity FROM ground_drops
		WHERE id=$1::uuid AND server_id=$2 AND owner_character_id=$3::uuid
		  AND status='available' AND expires_at>now() FOR UPDATE`,
		request.DropID,serverID,request.CharacterID).Scan(&itemID,&itemInstanceID,&quantity)
	if errors.Is(err,sql.ErrNoRows){return Result{},ErrDropUnavailable}
	if err!=nil{return Result{},fmt.Errorf("lock ground drop: %w",err)}
	if itemInstanceID.Valid {
		if !inventorySlotAvailable(usedSlots,maxSlots,true){return Result{},ErrInventoryFull}
		if _,err:=tx.ExecContext(ctx,`INSERT INTO character_item_instances(character_id,item_instance_id)
			VALUES($1::uuid,$2::uuid)`,request.CharacterID,itemInstanceID.String);err!=nil{
			return Result{},fmt.Errorf("transfer equipment instance to inventory: %w",err)
		}
	} else {
		var existingStack bool
		if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2)`,request.CharacterID,itemID).Scan(&existingStack);err!=nil{
			return Result{},fmt.Errorf("check existing inventory stack: %w",err)
		}
		if !inventorySlotAvailable(usedSlots,maxSlots,!existingStack){return Result{},ErrInventoryFull}
		var maxStack int
		if err:=tx.QueryRowContext(ctx,`SELECT max_stack FROM item_definitions WHERE id=$1 AND enabled`,itemID).Scan(&maxStack);err!=nil{
			return Result{},fmt.Errorf("load pickup item definition: %w",err)
		}
		stackResult,err:=tx.ExecContext(ctx,`INSERT INTO character_inventory(character_id,item_id,quantity)
			VALUES($1::uuid,$2,$3) ON CONFLICT(character_id,item_id) DO UPDATE
			SET quantity=character_inventory.quantity+EXCLUDED.quantity,updated_at=now()
			WHERE character_inventory.quantity+EXCLUDED.quantity<=$4`,request.CharacterID,itemID,quantity,maxStack)
		if err!=nil{return Result{},fmt.Errorf("apply inventory stack: %w",err)}
		affected,err:=stackResult.RowsAffected();if err!=nil{return Result{},fmt.Errorf("check inventory stack update: %w",err)}
		if affected==0{return Result{},ErrInventoryFull}
	}
	if _, err := tx.ExecContext(ctx, `UPDATE ground_drops SET status = 'picked', picked_by_character_id = $1::uuid, picked_at = now(), updated_at = now()
		WHERE id = $2::uuid AND server_id = $3 AND status = 'available'`, request.CharacterID, request.DropID, serverID); err != nil {
		return Result{}, fmt.Errorf("consume ground drop: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO item_pickup_events (server_id, event_id, drop_id, character_id, item_id, quantity)
		VALUES ($1, $2::uuid, $3::uuid, $4::uuid, $5, $6)`, serverID, request.EventID, request.DropID, request.CharacterID, itemID, quantity); err != nil {
		return Result{}, fmt.Errorf("record pickup event: %w", err)
	}
	if err := tx.Commit(); err != nil { return Result{}, fmt.Errorf("commit item pickup: %w", err) }
	return Result{Applied:true,ItemID:itemID,ItemInstanceID:itemInstanceID.String,Quantity:quantity},nil
}

func validUUID(value string) bool {
	if len(value) != 36 { return false }
	for i, char := range value {
		if i == 8 || i == 13 || i == 18 || i == 23 { if char != '-' { return false }; continue }
		if !((char >= '0' && char <= '9') || (char >= 'a' && char <= 'f') || (char >= 'A' && char <= 'F')) { return false }
	}
	return true
}

type EquippedItem struct {
	InstanceID string `json:"instance_id,omitempty"`
	EnhancementLevel int `json:"enhancement_level,omitempty"`
	RolledStats map[string]int `json:"rolled_stats,omitempty"`
	Affixes []EquipmentAffix `json:"affixes,omitempty"`
	Slot string `json:"slot"`
	ItemID string `json:"item_id"`
	Name string `json:"name"`
	Quality int `json:"quality"`
	WeaponType string `json:"weapon_type,omitempty"`
	IconKey string `json:"icon_key"`
	Description string `json:"description"`
	BaseStats map[string]int `json:"base_stats"`
	SetID string `json:"set_id,omitempty"`
	SetName string `json:"set_name,omitempty"`
	SetDescription string `json:"set_description,omitempty"`
	SetBonusTiers map[int]map[string]int `json:"set_bonus_tiers,omitempty"`
}
type EnhancementRequest struct { RequestID string; InstanceID string }
type EnhancementResult struct { Applied bool `json:"applied"`; Succeeded bool `json:"succeeded"`; OldLevel int `json:"old_level"`; EnhancementLevel int `json:"enhancement_level"`; MaxLevel int `json:"max_level"`; MaterialName string `json:"material_name"`; MaterialQuantity int `json:"material_quantity"`; SuccessRateBP int `json:"success_rate_bp"` }

type SalvageRequest struct {
	RequestID string
	InstanceID string
}

type SalvageResult struct {
	Applied bool `json:"applied"`
	EquipmentItemID string `json:"equipment_item_id"`
	MaterialItemID string `json:"material_item_id"`
	MaterialName string `json:"material_name"`
	MaterialQuantity int `json:"material_quantity"`
	EquipmentQuality int `json:"equipment_quality"`
}

type EquipmentRequest struct { ItemID string; InstanceID string; Slot string }
var validEquipmentSlots = map[string]bool{"weapon":true,"head":true,"chest":true,"legs":true,"boots":true,"accessory":true}

func (s *Service) CurrentEquipment(ctx context.Context, accountID string) ([]EquippedItem, error) {
	rows,err:=s.db.QueryContext(ctx,`SELECT e.slot,i.id,i.name,COALESCE(ii.quality,i.quality),COALESCE(ii.id::text,''),COALESCE(i.weapon_type,''),i.icon_key,i.description,
		i.base_stats,COALESCE(ii.rolled_stats,'{}'::jsonb),COALESCE(ii.affixes,'[]'::jsonb),COALESCE(ii.enhancement_level,0),
		COALESCE(es.id,''),COALESCE(es.name,''),COALESCE(es.description,''),COALESCE(es.bonus_tiers,'{}'::jsonb)
		FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		JOIN character_equipment e ON e.character_id=c.id JOIN item_definitions i ON i.id=e.item_id
		LEFT JOIN item_instances ii ON ii.id=e.item_instance_id
		LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id
		WHERE soul.account_id=$1 AND c.status='alive' ORDER BY e.slot`,accountID)
	if err!=nil{return nil,fmt.Errorf("load current equipment: %w",err)}
	defer rows.Close()
	items:=make([]EquippedItem,0)
	for rows.Next(){
		var item EquippedItem;var baseRaw,rolledRaw,affixesRaw,setTiers []byte
		if err:=rows.Scan(&item.Slot,&item.ItemID,&item.Name,&item.Quality,&item.InstanceID,&item.WeaponType,&item.IconKey,&item.Description,
			&baseRaw,&rolledRaw,&affixesRaw,&item.EnhancementLevel,&item.SetID,&item.SetName,&item.SetDescription,&setTiers);err!=nil{
			return nil,fmt.Errorf("scan equipped item: %w",err)
		}
		item.BaseStats=map[string]int{};item.RolledStats=map[string]int{};item.Affixes=[]EquipmentAffix{}
		if len(baseRaw)>0{if err:=json.Unmarshal(baseRaw,&item.BaseStats);err!=nil{return nil,fmt.Errorf("decode equipment stats: %w",err)}}
		if len(rolledRaw)>0{if err:=json.Unmarshal(rolledRaw,&item.RolledStats);err!=nil{return nil,fmt.Errorf("decode equipment rolled stats: %w",err)}}
		if len(affixesRaw)>0{if err:=json.Unmarshal(affixesRaw,&item.Affixes);err!=nil{return nil,fmt.Errorf("decode equipment affixes: %w",err)}}
		if len(setTiers)>0{if err:=json.Unmarshal(setTiers,&item.SetBonusTiers);err!=nil{return nil,fmt.Errorf("decode equipped set tiers: %w",err)}}
		items=append(items,item)
	}
	if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate current equipment: %w",err)}
	return items,nil
}
// Equip mutates the authoritative loadout even during an active world session.
// WorldServer polls the session combat snapshot and applies the change asynchronously.
func ensureEquipmentSessionStable(ctx context.Context, tx *sql.Tx, characterID string) error {
	var transitioning bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM world_sessions WHERE character_id=$1::uuid AND session_state IN ('connecting','saving'))`, characterID).Scan(&transitioning); err != nil {
		return fmt.Errorf("check equipment session transition: %w", err)
	}
	if transitioning { return ErrCharacterInWorld }
	return nil
}

func (s *Service) Equip(ctx context.Context,accountID string,request EquipmentRequest)error{
	if strings.TrimSpace(accountID)==""||!validEquipmentSlots[request.Slot]||
		(strings.TrimSpace(request.InstanceID)==""&&strings.TrimSpace(request.ItemID)=="")||
		(request.InstanceID!=""&&!validUUID(request.InstanceID)){return ErrInvalidRequest}
	tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin equip item: %w",err)};defer tx.Rollback()
	var characterID string
	if err:=tx.QueryRowContext(ctx,`SELECT c.id::text FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c`,accountID).Scan(&characterID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};return fmt.Errorf("resolve current character: %w",err)
	}
	if err:=ensureEquipmentSessionStable(ctx,tx,characterID);err!=nil{return err}
	itemID:=""
	if request.InstanceID!=""{
		var itemSlot string
		err=tx.QueryRowContext(ctx,`SELECT i.id,i.equipment_slot FROM character_item_instances ci
			JOIN item_instances ii ON ii.id=ci.item_instance_id JOIN item_definitions i ON i.id=ii.item_id
			WHERE ci.character_id=$1::uuid AND ii.id=$2::uuid AND i.enabled AND i.item_type='equipment'
			FOR UPDATE OF ci,ii`,characterID,request.InstanceID).Scan(&itemID,&itemSlot)
		if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};if err!=nil{return fmt.Errorf("lock equipment instance: %w",err)}
		if request.ItemID!=""&&request.ItemID!=itemID{return ErrInvalidRequest}
		if itemSlot!=request.Slot{return ErrInvalidRequest}
	}else{
		var itemSlot string
		if err:=tx.QueryRowContext(ctx,`SELECT equipment_slot FROM item_definitions WHERE id=$1 AND enabled AND item_type='equipment'`,request.ItemID).Scan(&itemSlot);err!=nil{
			if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};return fmt.Errorf("load equipment definition: %w",err)
		}
		if itemSlot!=request.Slot{return ErrInvalidRequest}
		itemID=request.ItemID
	}
	var quantity int
	if request.InstanceID==""{
		if err:=tx.QueryRowContext(ctx,`SELECT quantity FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2 FOR UPDATE`,characterID,itemID).Scan(&quantity);err!=nil{
			if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};return fmt.Errorf("lock inventory equipment: %w",err)
		}
	}
	var previousItem string;var previousInstance sql.NullString
	err=tx.QueryRowContext(ctx,`SELECT item_id,item_instance_id::text FROM character_equipment
		WHERE character_id=$1::uuid AND slot=$2 FOR UPDATE`,characterID,request.Slot).Scan(&previousItem,&previousInstance)
	if err!=nil&&!errors.Is(err,sql.ErrNoRows){return fmt.Errorf("lock previous equipment: %w",err)}
	if previousItem==itemID&&((request.InstanceID==""&&!previousInstance.Valid)||(request.InstanceID!=""&&previousInstance.Valid&&previousInstance.String==request.InstanceID)){
		return tx.Commit()
	}
	if request.InstanceID!=""{
		if _,err:=tx.ExecContext(ctx,`DELETE FROM character_item_instances WHERE character_id=$1::uuid AND item_instance_id=$2::uuid`,characterID,request.InstanceID);err!=nil{
			return fmt.Errorf("consume equipment instance: %w",err)
		}
	}else if quantity==1{
		if _,err:=tx.ExecContext(ctx,`DELETE FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2`,characterID,itemID);err!=nil{return fmt.Errorf("consume equipment item: %w",err)}
	}else{
		if _,err:=tx.ExecContext(ctx,`UPDATE character_inventory SET quantity=quantity-1,updated_at=now() WHERE character_id=$1::uuid AND item_id=$2`,characterID,itemID);err!=nil{return fmt.Errorf("consume equipment item: %w",err)}
	}
	if previousItem!=""{
		needsNewSlot:=previousInstance.Valid
		if !previousInstance.Valid{
			var existingPreviousStack bool
			if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2)`,characterID,previousItem).Scan(&existingPreviousStack);err!=nil{
				return fmt.Errorf("check replaced item stack: %w",err)
			}
			needsNewSlot=!existingPreviousStack
		}
		if err:=ensureInventorySlot(ctx,tx,characterID,needsNewSlot);err!=nil{return err}
		if previousInstance.Valid{
			if _,err:=tx.ExecContext(ctx,`INSERT INTO character_item_instances(character_id,item_instance_id) VALUES($1::uuid,$2::uuid)`,characterID,previousInstance.String);err!=nil{
				return fmt.Errorf("return replaced equipment instance: %w",err)
			}
		}else{
			var max int
			if err:=tx.QueryRowContext(ctx,`SELECT max_stack FROM item_definitions WHERE id=$1 AND enabled`,previousItem).Scan(&max);err!=nil{return fmt.Errorf("load replaced item stack limit: %w",err)}
			res,err:=tx.ExecContext(ctx,`INSERT INTO character_inventory(character_id,item_id,quantity) VALUES($1::uuid,$2,1)
				ON CONFLICT(character_id,item_id) DO UPDATE SET quantity=character_inventory.quantity+1,updated_at=now()
				WHERE character_inventory.quantity+1<=$3`,characterID,previousItem,max)
			if err!=nil{return fmt.Errorf("return replaced equipment: %w",err)}
			n,err:=res.RowsAffected();if err!=nil{return err};if n==0{return ErrInventoryFull}
		}
	}
	instanceArg:=request.InstanceID
	_,err=tx.ExecContext(ctx,`INSERT INTO character_equipment(character_id,slot,item_id,item_instance_id)
		VALUES($1::uuid,$2,$3,NULLIF($4,'')::uuid)
		ON CONFLICT(character_id,slot) DO UPDATE SET item_id=EXCLUDED.item_id,item_instance_id=EXCLUDED.item_instance_id,equipped_at=now()`,
		characterID,request.Slot,itemID,instanceArg)
	if err!=nil{return fmt.Errorf("save equipped item: %w",err)}
	if err:=tx.Commit();err!=nil{return fmt.Errorf("commit equipped item: %w",err)}
	return nil
}


func enhancementMaxLevel(quality int) int {
	switch quality { case 1: return 3; case 2: return 5; case 3: return 8; case 4: return 10; case 5: return 12; default: return 0 }
}

func enhancementStatBonus(level int, slot string) map[string]int {
	if level <= 0 { return map[string]int{} }
	if slot == "weapon" { return map[string]int{"attack": level * 2} }
	return map[string]int{"defense": level}
}

func (s *Service) EnhanceEquipment(ctx context.Context, accountID string, request EnhancementRequest) (EnhancementResult, error) {
	if strings.TrimSpace(accountID)=="" || !validUUID(request.RequestID) || !validUUID(request.InstanceID) { return EnhancementResult{}, ErrInvalidRequest }
	tx,err:=s.db.BeginTx(ctx,nil); if err!=nil{return EnhancementResult{},fmt.Errorf("begin equipment enhancement: %w",err)}; defer tx.Rollback()
	var characterID string
	if err:=tx.QueryRowContext(ctx, "SELECT c.id::text FROM souls soul JOIN characters c ON c.id=soul.current_character_id WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c",accountID).Scan(&characterID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return EnhancementResult{},ErrInvalidRequest};return EnhancementResult{},fmt.Errorf("resolve enhancement character: %w",err)
	}
	if err:=ensureEquipmentSessionStable(ctx,tx,characterID);err!=nil{return EnhancementResult{},err}
	var replay EnhancementResult; var replayInstance string; var replayTarget,replayQuality int
	err=tx.QueryRowContext(ctx, "SELECT item_instance_id::text,succeeded,old_level,target_level,equipment_quality,material_quantity,success_rate_bp,(SELECT name FROM item_definitions WHERE id=material_item_id) FROM equipment_enhancement_events WHERE character_id=$1::uuid AND request_id=$2::uuid",characterID,request.RequestID).
		Scan(&replayInstance,&replay.Succeeded,&replay.OldLevel,&replayTarget,&replayQuality,&replay.MaterialQuantity,&replay.SuccessRateBP,&replay.MaterialName)
	if err==nil{
		if replayInstance!=request.InstanceID{return EnhancementResult{},ErrIdempotencyConflict}
		replay.Applied=false
		replay.EnhancementLevel=replay.OldLevel
		if replay.Succeeded { replay.EnhancementLevel=replayTarget }
		replay.MaxLevel=enhancementMaxLevel(replayQuality)
		if err:=tx.Commit();err!=nil{return EnhancementResult{},fmt.Errorf("commit enhancement replay: %w",err)}
		return replay,nil
	}
	if !errors.Is(err,sql.ErrNoRows){return EnhancementResult{},fmt.Errorf("check enhancement idempotency: %w",err)}
	var itemID,slot string;var quality,oldLevel int
	err=tx.QueryRowContext(ctx, "SELECT ii.item_id,i.equipment_slot,ii.quality,ii.enhancement_level FROM character_item_instances ci JOIN item_instances ii ON ii.id=ci.item_instance_id JOIN item_definitions i ON i.id=ii.item_id WHERE ci.character_id=$1::uuid AND ii.id=$2::uuid AND i.enabled AND i.item_type='equipment' AND NOT EXISTS(SELECT 1 FROM character_equipment ce WHERE ce.item_instance_id=ii.id) FOR UPDATE OF ci,ii",characterID,request.InstanceID).Scan(&itemID,&slot,&quality,&oldLevel)
	if errors.Is(err,sql.ErrNoRows){return EnhancementResult{},ErrInvalidRequest};if err!=nil{return EnhancementResult{},fmt.Errorf("lock enhancement equipment: %w",err)}
	maxLevel:=enhancementMaxLevel(quality);if maxLevel==0||oldLevel>=maxLevel{return EnhancementResult{},ErrInvalidRequest}
	target:=oldLevel+1
	var materialID,materialName string;var cost,rate int
	err=tx.QueryRowContext(ctx, "SELECT r.material_item_id,m.name,er.material_quantity,er.success_rate_bp FROM equipment_salvage_recipes r JOIN item_definitions m ON m.id=r.material_item_id AND m.enabled JOIN equipment_enhancement_rules er ON er.target_level=$2 WHERE r.equipment_item_id=$1 AND r.enabled",itemID,target).Scan(&materialID,&materialName,&cost,&rate)
	if errors.Is(err,sql.ErrNoRows){return EnhancementResult{},ErrInvalidRequest};if err!=nil{return EnhancementResult{},fmt.Errorf("load enhancement recipe: %w",err)}
	var available int
	err=tx.QueryRowContext(ctx,"SELECT quantity FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2 FOR UPDATE",characterID,materialID).Scan(&available)
	if errors.Is(err,sql.ErrNoRows){return EnhancementResult{},ErrInsufficientMaterials}
	if err!=nil{return EnhancementResult{},fmt.Errorf("lock enhancement materials: %w",err)}
	if available<cost{return EnhancementResult{},ErrInsufficientMaterials}
	roll,err:=secureRandomInt(10000);if err!=nil{return EnhancementResult{},err}
	succeeded:=int(roll)<rate
	if _,err:=tx.ExecContext(ctx,"UPDATE character_inventory SET quantity=quantity-$3,updated_at=now() WHERE character_id=$1::uuid AND item_id=$2 AND quantity >= $3",characterID,materialID,cost);err!=nil{return EnhancementResult{},fmt.Errorf("consume enhancement materials: %w",err)}
	if _,err:=tx.ExecContext(ctx,"DELETE FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2 AND quantity<=0",characterID,materialID);err!=nil{return EnhancementResult{},fmt.Errorf("remove empty material stack: %w",err)}
	newLevel:=oldLevel
	if succeeded { newLevel=target; if _,err:=tx.ExecContext(ctx,"UPDATE item_instances SET enhancement_level=$2 WHERE id=$1::uuid",request.InstanceID,newLevel);err!=nil{return EnhancementResult{},fmt.Errorf("apply equipment enhancement: %w",err)} }
	if _,err:=tx.ExecContext(ctx,"INSERT INTO equipment_enhancement_events(character_id,request_id,item_instance_id,equipment_item_id,old_level,target_level,equipment_quality,material_item_id,material_quantity,success_rate_bp,succeeded) VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6,$7,$8,$9,$10,$11)",characterID,request.RequestID,request.InstanceID,itemID,oldLevel,target,quality,materialID,cost,rate,succeeded);err!=nil{return EnhancementResult{},fmt.Errorf("record enhancement attempt: %w",err)}
	result:=EnhancementResult{Applied:true,Succeeded:succeeded,OldLevel:oldLevel,EnhancementLevel:newLevel,MaxLevel:maxLevel,MaterialName:materialName,MaterialQuantity:cost,SuccessRateBP:rate}
	if err:=tx.Commit();err!=nil{return EnhancementResult{},fmt.Errorf("commit equipment enhancement: %w",err)}
	return result,nil
}

func (s *Service) SalvageEquipment(ctx context.Context,accountID string,request SalvageRequest)(SalvageResult,error){
	if strings.TrimSpace(accountID)==""||!validUUID(request.RequestID)||!validUUID(request.InstanceID){return SalvageResult{},ErrInvalidRequest}
	tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return SalvageResult{},fmt.Errorf("begin equipment salvage: %w",err)};defer tx.Rollback()
	var characterID string
	if err:=tx.QueryRowContext(ctx,`SELECT c.id::text FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c`,accountID).Scan(&characterID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return SalvageResult{},ErrInvalidRequest}
		return SalvageResult{},fmt.Errorf("resolve salvage character: %w",err)
	}
	// Inventory mutations are safe during an active session because only
	// unequipped instances are salvaged. Block only session hand-off windows.
	if err:=ensureEquipmentSessionStable(ctx,tx,characterID);err!=nil{return SalvageResult{},err}
	var existing SalvageResult
	var existingInstance string
	err=tx.QueryRowContext(ctx,`SELECT item_instance_id::text,equipment_item_id,material_item_id,
		(SELECT name FROM item_definitions WHERE id=material_item_id),material_quantity,equipment_quality
		FROM equipment_salvage_events WHERE character_id=$1::uuid AND request_id=$2::uuid`,characterID,request.RequestID).
		Scan(&existingInstance,&existing.EquipmentItemID,&existing.MaterialItemID,&existing.MaterialName,&existing.MaterialQuantity,&existing.EquipmentQuality)
	if err==nil{
		if existingInstance!=request.InstanceID{return SalvageResult{},ErrIdempotencyConflict}
		existing.Applied=false
		if err:=tx.Commit();err!=nil{return SalvageResult{},fmt.Errorf("commit recovered salvage request: %w",err)}
		return existing,nil
	}
	if !errors.Is(err,sql.ErrNoRows){return SalvageResult{},fmt.Errorf("check salvage idempotency: %w",err)}
	var itemID,materialID,materialName string
	var quality,baseQuantity,perQualityBonus,maxStack int
	err=tx.QueryRowContext(ctx,`SELECT ii.item_id,ii.quality,r.material_item_id,m.name,
		r.base_quantity,r.per_quality_bonus,m.max_stack
		FROM character_item_instances owned
		JOIN item_instances ii ON ii.id=owned.item_instance_id
		JOIN item_definitions i ON i.id=ii.item_id AND i.enabled AND i.item_type='equipment'
		JOIN equipment_salvage_recipes r ON r.equipment_item_id=i.id AND r.enabled
		JOIN item_definitions m ON m.id=r.material_item_id AND m.enabled AND m.item_type='material'
		WHERE owned.character_id=$1::uuid AND ii.id=$2::uuid
		FOR UPDATE OF owned,ii`,characterID,request.InstanceID).
		Scan(&itemID,&quality,&materialID,&materialName,&baseQuantity,&perQualityBonus,&maxStack)
	if errors.Is(err,sql.ErrNoRows){return SalvageResult{},ErrInvalidRequest}
	if err!=nil{return SalvageResult{},fmt.Errorf("lock salvage equipment and recipe: %w",err)}
	var equipped bool
	if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM character_equipment WHERE item_instance_id=$1::uuid)`,request.InstanceID).Scan(&equipped);err!=nil{
		return SalvageResult{},fmt.Errorf("check equipped salvage instance: %w",err)
	}
	if equipped{return SalvageResult{},ErrInvalidRequest}
	quantity,validYield:=equipmentSalvageYield(baseQuantity,quality,perQualityBonus,maxStack)
	if !validYield{return SalvageResult{},ErrInvalidRequest}
	result:=SalvageResult{Applied:true,EquipmentItemID:itemID,MaterialItemID:materialID,MaterialName:materialName,MaterialQuantity:quantity,EquipmentQuality:quality}
	grant,err:=tx.ExecContext(ctx,`INSERT INTO character_inventory(character_id,item_id,quantity)
		VALUES($1::uuid,$2,$3)
		ON CONFLICT(character_id,item_id) DO UPDATE
		SET quantity=character_inventory.quantity+EXCLUDED.quantity,updated_at=now()
		WHERE character_inventory.quantity+EXCLUDED.quantity<=$4`,characterID,materialID,quantity,maxStack)
	if err!=nil{return SalvageResult{},fmt.Errorf("grant salvage material: %w",err)}
	affected,err:=grant.RowsAffected()
	if err!=nil{return SalvageResult{},fmt.Errorf("verify salvage material grant: %w",err)}
	if affected!=1{return SalvageResult{},ErrInventoryFull}
	if _,err:=tx.ExecContext(ctx,`INSERT INTO equipment_salvage_events(character_id,request_id,item_instance_id,equipment_item_id,material_item_id,material_quantity,equipment_quality)
		VALUES($1::uuid,$2::uuid,$3::uuid,$4,$5,$6,$7)`,characterID,request.RequestID,request.InstanceID,itemID,materialID,quantity,quality);err!=nil{
		return SalvageResult{},fmt.Errorf("record equipment salvage: %w",err)
	}
	if _,err:=tx.ExecContext(ctx,`UPDATE ground_drops SET item_instance_id=NULL WHERE item_instance_id=$1::uuid AND status='picked'`,request.InstanceID);err!=nil{
		return SalvageResult{},fmt.Errorf("detach picked ground drop history: %w",err)
	}
	if _,err:=tx.ExecContext(ctx,`DELETE FROM character_item_instances WHERE character_id=$1::uuid AND item_instance_id=$2::uuid`,characterID,request.InstanceID);err!=nil{
		return SalvageResult{},fmt.Errorf("consume salvaged equipment ownership: %w",err)
	}
	if _,err:=tx.ExecContext(ctx,`DELETE FROM item_instances WHERE id=$1::uuid`,request.InstanceID);err!=nil{
		return SalvageResult{},fmt.Errorf("delete salvaged equipment instance: %w",err)
	}
	if err:=tx.Commit();err!=nil{return SalvageResult{},fmt.Errorf("commit equipment salvage: %w",err)}
	return result,nil
}

func (s *Service) Unequip(ctx context.Context,accountID,slot string)error{
	if strings.TrimSpace(accountID)==""||!validEquipmentSlots[slot]{return ErrInvalidRequest}
	tx,err:=s.db.BeginTx(ctx,nil);if err!=nil{return fmt.Errorf("begin unequip item: %w",err)};defer tx.Rollback()
	var characterID string
	if err:=tx.QueryRowContext(ctx,`SELECT c.id::text FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c`,accountID).Scan(&characterID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};return fmt.Errorf("resolve current character: %w",err)
	}
	if err:=ensureEquipmentSessionStable(ctx,tx,characterID);err!=nil{return err}
	var itemID string;var instanceID sql.NullString
	if err:=tx.QueryRowContext(ctx,`SELECT item_id,item_instance_id::text FROM character_equipment
		WHERE character_id=$1::uuid AND slot=$2 FOR UPDATE`,characterID,slot).Scan(&itemID,&instanceID);err!=nil{
		if errors.Is(err,sql.ErrNoRows){return ErrInvalidRequest};return fmt.Errorf("load equipped item: %w",err)
	}
	needsNewSlot:=instanceID.Valid
	if !instanceID.Valid{
		var existingStack bool
		if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(SELECT 1 FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2)`,characterID,itemID).Scan(&existingStack);err!=nil{
			return fmt.Errorf("check unequipped item stack: %w",err)
		}
		needsNewSlot=!existingStack
	}
	if err:=ensureInventorySlot(ctx,tx,characterID,needsNewSlot);err!=nil{return err}
	if instanceID.Valid{
		if _,err:=tx.ExecContext(ctx,`INSERT INTO character_item_instances(character_id,item_instance_id) VALUES($1::uuid,$2::uuid)`,characterID,instanceID.String);err!=nil{
			return fmt.Errorf("return unequipped equipment instance: %w",err)
		}
	}else{
		var max int
		if err:=tx.QueryRowContext(ctx,`SELECT max_stack FROM item_definitions WHERE id=$1 AND enabled`,itemID).Scan(&max);err!=nil{return fmt.Errorf("load equipment stack limit: %w",err)}
		res,err:=tx.ExecContext(ctx,`INSERT INTO character_inventory(character_id,item_id,quantity) VALUES($1::uuid,$2,1)
			ON CONFLICT(character_id,item_id) DO UPDATE SET quantity=character_inventory.quantity+1,updated_at=now()
			WHERE character_inventory.quantity+1<=$3`,characterID,itemID,max)
		if err!=nil{return fmt.Errorf("return unequipped item: %w",err)}
		n,err:=res.RowsAffected();if err!=nil{return err};if n==0{return ErrInventoryFull}
	}
	if _,err:=tx.ExecContext(ctx,`DELETE FROM character_equipment WHERE character_id=$1::uuid AND slot=$2`,characterID,slot);err!=nil{return fmt.Errorf("remove equipment slot: %w",err)}
	if err:=tx.Commit();err!=nil{return fmt.Errorf("commit unequipped item: %w",err)}
	return nil
}
type CombatStats struct {
	Equipment []EquippedItem `json:"equipment"`
	Health int `json:"health"`
	Mana int `json:"mana"`
	Attack int `json:"attack"`
	Defense int `json:"defense"`
	Strength int `json:"strength"`
	Constitution int `json:"constitution"`
	Agility int `json:"agility"`
	Spirit int `json:"spirit"`
	Vitality int `json:"vitality"`
	MovementSpeed float64 `json:"movement_speed"`
	MaxHealth int `json:"max_health"`
	MaxMana int `json:"max_mana"`
}

// CurrentSessionCombatStats is restricted to a live session on the requesting
// node. Equipment bonuses are combined with the character's persisted base stats.
func (s *Service) CurrentSessionCombatStats(ctx context.Context, nodeKey, sessionID, characterID string) (CombatStats, error) {
	if strings.TrimSpace(nodeKey)=="" || !validUUID(sessionID) || !validUUID(characterID) { return CombatStats{}, ErrInvalidRequest }
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true, Isolation: sql.LevelRepeatableRead})
	if err != nil { return CombatStats{}, fmt.Errorf("begin combat stats snapshot: %w", err) }
	defer tx.Rollback()
	var result CombatStats
	err=tx.QueryRowContext(ctx,`SELECT a.health,a.mana,a.attack,a.defense,a.strength,a.constitution,a.agility,a.spirit,a.vitality,a.movement_speed,a.max_health,a.max_mana
		FROM world_sessions ws
		JOIN server_registry sr ON sr.id=ws.server_id
		JOIN character_attributes a ON a.character_id=ws.character_id
		WHERE sr.node_key=$1 AND ws.id=$2::uuid AND ws.character_id=$3::uuid AND ws.session_state='active'`,
		nodeKey,sessionID,characterID).Scan(&result.Health,&result.Mana,&result.Attack,&result.Defense,&result.Strength,&result.Constitution,&result.Agility,&result.Spirit,&result.Vitality,&result.MovementSpeed,&result.MaxHealth,&result.MaxMana)
	if errors.Is(err,sql.ErrNoRows) { return CombatStats{},ErrSessionInvalid }
	if err!=nil { return CombatStats{},fmt.Errorf("load session combat attributes: %w",err) }
	rows,err:=tx.QueryContext(ctx,`SELECT i.base_stats,COALESCE(ii.rolled_stats,'{}'::jsonb),COALESCE(ii.enhancement_level,0),COALESCE(e.slot,''),COALESCE(i.equipment_set_id,''),COALESCE(es.bonus_tiers,'{}'::jsonb)
		FROM character_equipment e JOIN item_definitions i ON i.id=e.item_id
		LEFT JOIN item_instances ii ON ii.id=e.item_instance_id
		LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id AND es.enabled
		WHERE e.character_id=$1::uuid AND i.enabled`,characterID)
	if err!=nil { return CombatStats{},fmt.Errorf("load equipped combat bonuses: %w",err) }
	defer rows.Close()
	setCounts:=map[string]int{}
	setTiers:=map[string]map[int]map[string]int{}
	for rows.Next() {
		var raw, rolledRaw, tierRaw []byte
		var setID, slot string
		var enhancementLevel int
		if err:=rows.Scan(&raw,&rolledRaw,&enhancementLevel,&slot,&setID,&tierRaw); err!=nil { return CombatStats{},fmt.Errorf("scan equipped combat bonuses: %w",err) }
		bonuses:=map[string]int{}
		if len(raw)>0 { if err:=json.Unmarshal(raw,&bonuses); err!=nil { return CombatStats{},fmt.Errorf("decode equipped combat bonuses: %w",err) } }
		if err := applyEquipmentStatBonuses(&result, bonuses); err != nil { return CombatStats{}, err }
		rolledBonuses:=map[string]int{}
		if len(rolledRaw)>0 { if err:=json.Unmarshal(rolledRaw,&rolledBonuses); err!=nil { return CombatStats{},fmt.Errorf("decode rolled equipment bonuses: %w",err) } }
		if err:=applyEquipmentStatBonuses(&result,rolledBonuses);err!=nil{return CombatStats{},err}
		if err:=applyEquipmentStatBonuses(&result,enhancementStatBonus(enhancementLevel,slot));err!=nil{return CombatStats{},err}
		if setID!="" {
			setCounts[setID]++
			if _,exists:=setTiers[setID]; !exists {
				tiers:=map[int]map[string]int{}
				if len(tierRaw)>0 { if err:=json.Unmarshal(tierRaw,&tiers); err!=nil { return CombatStats{},fmt.Errorf("decode equipment set tiers: %w",err) } }
				setTiers[setID]=tiers
			}
		}
	}
	if err:=rows.Err(); err!=nil { return CombatStats{},fmt.Errorf("iterate equipped combat bonuses: %w",err) }
	if err:=rows.Close(); err!=nil { return CombatStats{},fmt.Errorf("close equipped combat bonuses: %w",err) }
	for setID,count:=range setCounts {
		bonuses,ok:=equipmentSetBonusForCount(setTiers[setID],count)
		if !ok { continue }
		if err:=applyEquipmentStatBonuses(&result,bonuses); err!=nil { return CombatStats{},err }
	}
	if math.IsNaN(result.MovementSpeed) || math.IsInf(result.MovementSpeed, 0) || result.MovementSpeed <= 0 {
		return CombatStats{}, ErrInvalidRequest
	}
	// Keep movement bonuses meaningful without allowing extreme equipment or
	// inherited attributes to bypass server-side movement limits.
	result.MovementSpeed = math.Max(1.0, math.Min(10.0, result.MovementSpeed))
	// Return the authoritative equipment list with combat stats so WorldServer
	// can refresh weapon behavior and replicated appearance in the same update.
	equipmentRows, err := tx.QueryContext(ctx, `SELECT e.slot,i.id,i.name,COALESCE(ii.quality,i.quality),COALESCE(ii.id::text,''),COALESCE(i.weapon_type,''),i.icon_key,i.description,
		i.base_stats,COALESCE(ii.rolled_stats,'{}'::jsonb),COALESCE(ii.affixes,'[]'::jsonb),COALESCE(ii.enhancement_level,0),
		COALESCE(es.id,''),COALESCE(es.name,''),COALESCE(es.description,''),COALESCE(es.bonus_tiers,'{}'::jsonb)
		FROM world_sessions ws JOIN server_registry sr ON sr.id=ws.server_id
		JOIN character_equipment e ON e.character_id=ws.character_id
		JOIN item_definitions i ON i.id=e.item_id
		LEFT JOIN item_instances ii ON ii.id=e.item_instance_id
		LEFT JOIN equipment_sets es ON es.id=i.equipment_set_id AND es.enabled
		WHERE sr.node_key=$1 AND ws.id=$2::uuid AND ws.character_id=$3::uuid AND ws.session_state='active' AND i.enabled
		ORDER BY e.slot`,nodeKey,sessionID,characterID)
	if err != nil { return CombatStats{}, fmt.Errorf("load session equipment: %w", err) }
	defer equipmentRows.Close()
	result.Equipment = make([]EquippedItem, 0)
	for equipmentRows.Next() {
		var item EquippedItem
		var rawStats,rawRolled,rawAffixes,rawTiers []byte
		if err:=equipmentRows.Scan(&item.Slot,&item.ItemID,&item.Name,&item.Quality,&item.InstanceID,&item.WeaponType,&item.IconKey,&item.Description,
			&rawStats,&rawRolled,&rawAffixes,&item.EnhancementLevel,&item.SetID,&item.SetName,&item.SetDescription,&rawTiers);err!=nil{
			return CombatStats{},fmt.Errorf("scan session equipment: %w",err)
		}
		item.BaseStats=map[string]int{};item.RolledStats=map[string]int{};item.Affixes=[]EquipmentAffix{}
		if len(rawStats)>0{if err:=json.Unmarshal(rawStats,&item.BaseStats);err!=nil{return CombatStats{},fmt.Errorf("decode session equipment stats: %w",err)}}
		if len(rawRolled)>0{if err:=json.Unmarshal(rawRolled,&item.RolledStats);err!=nil{return CombatStats{},fmt.Errorf("decode session equipment rolled stats: %w",err)}}
		if len(rawAffixes)>0{if err:=json.Unmarshal(rawAffixes,&item.Affixes);err!=nil{return CombatStats{},fmt.Errorf("decode session equipment affixes: %w",err)}}
		if len(rawTiers)>0{if err:=json.Unmarshal(rawTiers,&item.SetBonusTiers);err!=nil{return CombatStats{},fmt.Errorf("decode session equipment set tiers: %w",err)}}
		result.Equipment = append(result.Equipment, item)
	}
	if err := equipmentRows.Err(); err != nil { return CombatStats{}, fmt.Errorf("iterate session equipment: %w", err) }
	if err := equipmentRows.Close(); err != nil { return CombatStats{}, fmt.Errorf("close session equipment: %w", err) }
	if result.MaxHealth < 1 || result.MaxMana < 0 { return CombatStats{},ErrInvalidRequest }
	if result.Health > result.MaxHealth { result.Health = result.MaxHealth }
	if result.Mana > result.MaxMana { result.Mana = result.MaxMana }
	if result.Health<0 || result.Health>result.MaxHealth || result.Mana<0 || result.Mana>result.MaxMana || result.Attack<1 || result.Attack>100000 || result.Defense<0 || result.Defense>100000 ||
		result.MaxHealth<1 || result.MaxHealth>10000000 || result.MaxMana<0 || result.MaxMana>10000000 {
		return CombatStats{},ErrInvalidRequest
	}
	if err := tx.Commit(); err != nil { return CombatStats{}, fmt.Errorf("commit combat stats snapshot: %w", err) }
	return result,nil
}

// equipmentSetBonusForCount selects only the highest unlocked tier; tiers are
// cumulative thresholds, not additive rewards.
func equipmentSetBonusForCount(tiers map[int]map[string]int, count int) (map[string]int, bool) {
	if count < 1 { return nil, false }
	best := 0
	var bonuses map[string]int
	for required, candidate := range tiers {
		if required > 0 && required <= count && required > best {
			best, bonuses = required, candidate
		}
	}
	return bonuses, best > 0
}

// applyEquipmentStatBonuses keeps equipment primary attributes consistent with
// the effects granted by allocating those same attributes to a character.
// Direct secondary bonuses remain additive, so hybrid equipment can provide both.
func applyEquipmentStatBonuses(stats *CombatStats, bonuses map[string]int) error {
	if stats == nil {
		return ErrInvalidRequest
	}
	for _, value := range bonuses {
		if value < -100000 || value > 100000 {
			return ErrInvalidRequest
		}
	}

	strength := bonuses["strength"]
	constitution := bonuses["constitution"]
	agility := bonuses["agility"]
	spirit := bonuses["spirit"]
	vitality := bonuses["vitality"]

	stats.Strength += strength
	stats.Constitution += constitution
	stats.Agility += agility
	stats.Spirit += spirit
	stats.Vitality += vitality
	stats.Attack += bonuses["attack"] + strength*2
	stats.Defense += bonuses["defense"] + vitality
	stats.MaxHealth += bonuses["max_health"] + constitution*10 + vitality*5
	stats.MaxMana += bonuses["max_mana"] + spirit*10
	stats.MovementSpeed += float64(bonuses["movement_speed"]) + float64(agility)*0.05
	return nil
}

type ItemUseRequest struct {
	RequestID string
	ItemID string
	Quantity int
}

type LiveConsumableResources struct {
	Health int
	MaxHealth int
	Mana int
	MaxMana int
}
type ItemUseResult struct {
	Applied bool `json:"applied"`
	ItemID string `json:"item_id"`
	Quantity int `json:"quantity"`
	HealthRestored int `json:"health_restored"`
	ManaRestored int `json:"mana_restored"`
	HealthEffect int `json:"health_effect"`
	ManaEffect int `json:"mana_effect"`
	Health int `json:"health"`
	MaxHealth int `json:"max_health"`
	Mana int `json:"mana"`
	MaxMana int `json:"max_mana"`
}

func (s *Service) UseConsumable(ctx context.Context, accountID string, request ItemUseRequest) (ItemUseResult,error) {
	if strings.TrimSpace(accountID)=="" || !validConsumableRequest(request) {
		return ItemUseResult{},ErrInvalidRequest
	}
	tx,err:=s.db.BeginTx(ctx,nil)
	if err!=nil { return ItemUseResult{},fmt.Errorf("begin consumable use: %w",err) }
	defer tx.Rollback()
	var characterID string
	if err:=tx.QueryRowContext(ctx,`SELECT c.id::text FROM souls soul JOIN characters c ON c.id=soul.current_character_id
		WHERE soul.account_id=$1 AND c.status='alive' FOR UPDATE OF c`,accountID).Scan(&characterID); err!=nil {
		if errors.Is(err,sql.ErrNoRows) { return ItemUseResult{},ErrInvalidRequest }
		return ItemUseResult{},fmt.Errorf("resolve current character for consumable: %w",err)
	}
	result,err:=s.useConsumableForCharacter(ctx,tx,characterID,request,true,nil)
	if err!=nil { return ItemUseResult{},err }
	if err:=tx.Commit(); err!=nil { return ItemUseResult{},fmt.Errorf("commit consumable use: %w",err) }
	return result,nil
}

// UseConsumableForSession is the trusted WorldServer path. The server identity,
// live session and character are verified in one transaction before an item or
// resource value is changed. WorldServer applies the returned resource values.
func (s *Service) UseConsumableForSession(ctx context.Context,nodeKey,sessionID,characterID string,request ItemUseRequest, live LiveConsumableResources) (ItemUseResult,error) {
	if strings.TrimSpace(nodeKey)=="" || !validUUID(sessionID) || !validUUID(characterID) || !validConsumableRequest(request) || !validLiveConsumableResources(live) {
		return ItemUseResult{},ErrInvalidRequest
	}
	tx,err:=s.db.BeginTx(ctx,nil)
	if err!=nil { return ItemUseResult{},fmt.Errorf("begin session consumable use: %w",err) }
	defer tx.Rollback()
	var resolvedCharacterID string
	err=tx.QueryRowContext(ctx,`SELECT c.id::text
		FROM world_sessions ws
		JOIN server_registry sr ON sr.id=ws.server_id
		JOIN characters c ON c.id=ws.character_id
		WHERE sr.node_key=$1 AND ws.id=$2::uuid AND ws.character_id=$3::uuid
		  AND ws.session_state='active' AND c.status='alive'
		FOR UPDATE OF ws,c`,nodeKey,sessionID,characterID).Scan(&resolvedCharacterID)
	if errors.Is(err,sql.ErrNoRows) { return ItemUseResult{},ErrSessionInvalid }
	if err!=nil { return ItemUseResult{},fmt.Errorf("verify active session for consumable: %w",err) }
	result,err:=s.useConsumableForCharacter(ctx,tx,resolvedCharacterID,request,false,&live)
	if err!=nil { return ItemUseResult{},err }
	if err:=tx.Commit(); err!=nil { return ItemUseResult{},fmt.Errorf("commit session consumable use: %w",err) }
	return result,nil
}

func validConsumableRequest(request ItemUseRequest) bool {
	return validUUID(request.RequestID) && strings.TrimSpace(request.ItemID)!="" && request.Quantity>=1 && request.Quantity<=20
}

func applyLiveConsumableEffect(request ItemUseRequest, live LiveConsumableResources, heal, restore int) ItemUseResult {
	result := ItemUseResult{ItemID: request.ItemID, Quantity: request.Quantity}
	result.Health = min(live.MaxHealth, live.Health + heal*request.Quantity)
	result.MaxHealth = live.MaxHealth
	result.Mana = min(live.MaxMana, live.Mana + restore*request.Quantity)
	result.MaxMana = live.MaxMana
	result.HealthRestored = result.Health - live.Health
	result.ManaRestored = result.Mana - live.Mana
	result.HealthEffect = heal * request.Quantity
	result.ManaEffect = restore * request.Quantity
	return result
}

func validLiveConsumableResources(live LiveConsumableResources) bool {
	return live.Health >= 0 && live.MaxHealth >= 1 && live.Health <= live.MaxHealth && live.MaxHealth <= 10000000 &&
		live.Mana >= 0 && live.MaxMana >= 0 && live.Mana <= live.MaxMana && live.MaxMana <= 10000000
}

func consumableReplayResult(request ItemUseRequest, health, maxHealth, mana, maxMana int) ItemUseResult {
	return ItemUseResult{
		Applied: false,
		ItemID: request.ItemID,
		Quantity: request.Quantity,
		Health: health,
		MaxHealth: maxHealth,
		Mana: mana,
		MaxMana: maxMana,
	}
}

func (s *Service) useConsumableForCharacter(ctx context.Context,tx *sql.Tx,characterID string,request ItemUseRequest,blockActiveSession bool,live *LiveConsumableResources) (ItemUseResult,error) {
	var previousItemID string
	var previousQuantity int
	var previousEffect []byte
	err:=tx.QueryRowContext(ctx,`SELECT item_id,quantity,effect_applied FROM item_use_events WHERE character_id=$1::uuid AND request_id=$2::uuid`,characterID,request.RequestID).Scan(&previousItemID,&previousQuantity,&previousEffect)
	if err==nil {
		if previousItemID!=request.ItemID || previousQuantity!=request.Quantity { return ItemUseResult{},ErrInvalidRequest }
		// A retry may arrive after the original transaction committed but its HTTP
		// response was lost. Return the recorded result/effect so WorldServer can
		// apply it once to its latest live resources without consuming the item twice.
 		var health, maxHealth, mana, maxMana, healthRestored, manaRestored, healthEffect, manaEffect int
		if live != nil {
			var saved map[string]int
			if err := json.Unmarshal(previousEffect, &saved); err != nil { return ItemUseResult{}, fmt.Errorf("decode duplicate consumable result: %w", err) }
			if _, exists := saved["result_health"]; !exists {
				// Replay an event created before effective resource results were stored.
				// The WorldServer only retries when it did not receive the first response.
				return applyLiveConsumableEffect(request, *live, saved["heal_health"], saved["restore_mana"]), nil
			}
			health, maxHealth = saved["result_health"], saved["effective_max_health"]
			mana, maxMana = saved["result_mana"], saved["effective_max_mana"]
			healthRestored, manaRestored = saved["health_restored"], saved["mana_restored"]
			healthEffect, manaEffect = saved["health_effect"], saved["mana_effect"]
		} else if err:=tx.QueryRowContext(ctx,`SELECT health,max_health,mana,max_mana FROM character_attributes WHERE character_id=$1::uuid`,characterID).Scan(&health,&maxHealth,&mana,&maxMana); err!=nil {
			return ItemUseResult{},fmt.Errorf("load resources for duplicate consumable request: %w",err)
		}
		result := consumableReplayResult(request,health,maxHealth,mana,maxMana)
		result.HealthRestored, result.ManaRestored = healthRestored, manaRestored
		result.HealthEffect, result.ManaEffect = healthEffect, manaEffect
		return result,nil
	}
	if !errors.Is(err,sql.ErrNoRows) { return ItemUseResult{},fmt.Errorf("check consumable idempotency: %w",err) }
	if blockActiveSession {
		// WorldServer owns live health/mana while a character is in a world.
		// The account API must not mutate persisted resources behind its back.
		var inWorld bool
		if err:=tx.QueryRowContext(ctx,`SELECT EXISTS(
			SELECT 1 FROM world_sessions
			WHERE character_id=$1::uuid AND session_state IN ('connecting','active','saving')
		)`,characterID).Scan(&inWorld); err!=nil {
			return ItemUseResult{},fmt.Errorf("check active character session before consumable use: %w",err)
		}
		if inWorld { return ItemUseResult{},ErrCharacterInWorld }
	}
	var itemType string
	var raw []byte
	if err:=tx.QueryRowContext(ctx,`SELECT item_type,use_effect FROM item_definitions WHERE id=$1 AND enabled`,request.ItemID).Scan(&itemType,&raw); err!=nil {
		if errors.Is(err,sql.ErrNoRows) { return ItemUseResult{},ErrInvalidRequest }
		return ItemUseResult{},fmt.Errorf("load consumable definition: %w",err)
	}
	if itemType!="consumable" { return ItemUseResult{},ErrInvalidRequest }
	heal,restore,effect,parseErr:=parseConsumableEffect(raw)
	if parseErr!=nil { return ItemUseResult{},ErrInvalidRequest }
	var owned int
	if err:=tx.QueryRowContext(ctx,`SELECT quantity FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2 FOR UPDATE`,characterID,request.ItemID).Scan(&owned); err!=nil {
		if errors.Is(err,sql.ErrNoRows) { return ItemUseResult{},ErrInvalidRequest }
		return ItemUseResult{},fmt.Errorf("lock consumable inventory stack: %w",err)
	}
	if owned<request.Quantity { return ItemUseResult{},ErrInvalidRequest }
	result:=ItemUseResult{ItemID:request.ItemID,Quantity:request.Quantity}
	var oldHealth,oldMana,baseMaxHealth,baseMaxMana int
	if err:=tx.QueryRowContext(ctx,`SELECT health,mana,max_health,max_mana FROM character_attributes WHERE character_id=$1::uuid FOR UPDATE`,characterID).Scan(&oldHealth,&oldMana,&baseMaxHealth,&baseMaxMana); err!=nil {
		return ItemUseResult{},fmt.Errorf("lock character consumable attributes: %w",err)
	}
	if live == nil { live = &LiveConsumableResources{Health: oldHealth, MaxHealth: baseMaxHealth, Mana: oldMana, MaxMana: baseMaxMana} }
	if !validLiveConsumableResources(*live) { return ItemUseResult{}, ErrInvalidRequest }
	result = applyLiveConsumableEffect(request, *live, heal, restore)
	// Persist only base-cap values; WorldServer owns equipment-derived excess.
	_, err = tx.ExecContext(ctx, `UPDATE character_attributes SET health=LEAST($2,max_health), mana=LEAST($3,max_mana), updated_at=now() WHERE character_id=$1::uuid`, characterID, result.Health, result.Mana)
	if err != nil { return ItemUseResult{}, fmt.Errorf("apply consumable effects: %w", err) }
	if owned==request.Quantity {
		if _,err:=tx.ExecContext(ctx,`DELETE FROM character_inventory WHERE character_id=$1::uuid AND item_id=$2`,characterID,request.ItemID); err!=nil {
			return ItemUseResult{},fmt.Errorf("remove consumed inventory stack: %w",err)
		}
	} else {
		res,err:=tx.ExecContext(ctx,`UPDATE character_inventory SET quantity=quantity-$3,updated_at=now()
			WHERE character_id=$1::uuid AND item_id=$2 AND quantity > $3`,characterID,request.ItemID,request.Quantity)
		if err!=nil { return ItemUseResult{},fmt.Errorf("consume inventory items: %w",err) }
		affected,err:=res.RowsAffected()
		if err!=nil || affected!=1 { return ItemUseResult{},ErrInvalidRequest }
	}
	effectResult := map[string]int{}
	for key, value := range effect { effectResult[key] = value }
	effectResult["result_health"], effectResult["effective_max_health"] = result.Health, result.MaxHealth
	effectResult["result_mana"], effectResult["effective_max_mana"] = result.Mana, result.MaxMana
	effectResult["health_restored"], effectResult["mana_restored"] = result.HealthRestored, result.ManaRestored
	effectResult["health_effect"], effectResult["mana_effect"] = result.HealthEffect, result.ManaEffect
	effectJSON,_:=json.Marshal(effectResult)
	if _,err:=tx.ExecContext(ctx,`INSERT INTO item_use_events(character_id,request_id,item_id,quantity,effect_applied)
		VALUES($1::uuid,$2::uuid,$3,$4,$5::jsonb)`,characterID,request.RequestID,request.ItemID,request.Quantity,string(effectJSON)); err!=nil {
		return ItemUseResult{},fmt.Errorf("record consumable use: %w",err)
	}
	result.Applied=true
	return result,nil
}

func parseConsumableEffect(raw []byte) (int,int,map[string]int,error) {
	effect:=map[string]int{}
	if len(raw)==0 { return 0,0,nil,ErrInvalidRequest }
	if err:=json.Unmarshal(raw,&effect); err!=nil || len(effect)==0 || len(effect)>2 { return 0,0,nil,ErrInvalidRequest }
	heal,restore:=effect["heal_health"],effect["restore_mana"]
	if heal<0 || restore<0 || heal>10000 || restore>10000 || (heal==0 && restore==0) { return 0,0,nil,ErrInvalidRequest }
	for key:=range effect { if key!="heal_health" && key!="restore_mana" { return 0,0,nil,ErrInvalidRequest } }
	return heal,restore,effect,nil
}

type MonsterSpawnConfig struct {
	RuntimeID string `json:"runtime_id"`
	MonsterID string `json:"monster_id"`
	Name string `json:"name"`
	Level int `json:"level"`
	MaxHealth float64 `json:"max_health"`
	Attack float64 `json:"attack"`
	Defense float64 `json:"defense"`
	MoveSpeed float64 `json:"move_speed"`
	AggroRadius float64 `json:"aggro_radius"`
	LeashRadius float64 `json:"leash_radius"`
	SpawnX float64 `json:"spawn_x"`
	SpawnZ float64 `json:"spawn_z"`
	RareSpawn bool `json:"rare_spawn"`
	SpawnChancePercent int `json:"spawn_chance_percent"`
	RetrySpawnSeconds int `json:"retry_spawn_seconds"`
	FirstSpawnDelaySeconds int `json:"first_spawn_delay_seconds"`
}

func (s *Service) ListMonsterSpawnConfig(ctx context.Context, worldID string) ([]MonsterSpawnConfig,error) {
	rows,err:=s.db.QueryContext(ctx,`SELECT sp.id,md.id,md.name,md.level,md.max_health,md.attack,md.defense,md.move_speed,md.aggro_radius,md.leash_radius,sp.spawn_x,sp.spawn_z,sp.rare_spawn,sp.spawn_chance_percent,sp.retry_spawn_seconds,sp.first_spawn_delay_seconds
		FROM world_monster_spawn_points sp
		JOIN monster_definitions md ON md.id=sp.monster_id
		WHERE sp.world_id=$1 AND sp.enabled=TRUE AND md.enabled=TRUE
		ORDER BY md.level,sp.id`,worldID)
	if err!=nil{return nil,fmt.Errorf("list world monster spawn config: %w",err)}
	defer rows.Close()
	items:=make([]MonsterSpawnConfig,0)
	for rows.Next(){var v MonsterSpawnConfig;if err:=rows.Scan(&v.RuntimeID,&v.MonsterID,&v.Name,&v.Level,&v.MaxHealth,&v.Attack,&v.Defense,&v.MoveSpeed,&v.AggroRadius,&v.LeashRadius,&v.SpawnX,&v.SpawnZ,&v.RareSpawn,&v.SpawnChancePercent,&v.RetrySpawnSeconds,&v.FirstSpawnDelaySeconds);err!=nil{return nil,fmt.Errorf("scan world monster spawn config: %w",err)};items=append(items,v)}
	if err:=rows.Err();err!=nil{return nil,fmt.Errorf("iterate world monster spawn config: %w",err)}
	return items,nil
}

func (s *Service) ListMonsterSpawnConfigForNode(ctx context.Context,nodeKey string) ([]MonsterSpawnConfig,error) {
	var worldID string
	err:=s.db.QueryRowContext(ctx,`SELECT wi.world_id
		FROM server_registry sr
		JOIN world_instances wi ON wi.server_id=sr.id
		WHERE sr.node_key=$1 AND sr.status='ready' AND sr.admin_state='normal' AND wi.status='ready'
		ORDER BY wi.created_at LIMIT 1`,nodeKey).Scan(&worldID)
	if err!=nil{return nil,fmt.Errorf("resolve ready world for server node: %w",err)}
	return s.ListMonsterSpawnConfig(ctx,worldID)
}
