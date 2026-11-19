package httpapi

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"
)

type gameLootAdminHandlers struct { db *sql.DB; apiKey string; logger *slog.Logger }

func (h *gameLootAdminHandlers) authorize(w http.ResponseWriter,r *http.Request) bool {
	return (&gamePlayerAdminHandlers{apiKey:h.apiKey}).authorize(w,r)
}
func (h *gameLootAdminHandlers) listItems(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
	rows,err:=h.db.QueryContext(ctx,`SELECT i.id,i.name,i.category,i.item_type,i.quality,i.max_stack,i.icon_key,i.description,i.equipment_slot,i.base_stats,i.use_effect,COALESCE(i.equipment_set_id,''),i.enabled,i.created_at,i.updated_at FROM item_definitions i ORDER BY i.category,i.quality DESC,i.id LIMIT 1000`)
	if err!=nil{h.logger.Error("game admin item catalog query failed","error",err);http.Error(w,"internal server error",500);return};defer rows.Close()
	cols,_:=rows.Columns();items:=make([]map[string]any,0)
	for rows.Next(){values:=make([]any,len(cols));dest:=make([]any,len(cols));for i:=range values{dest[i]=&values[i]};if err:=rows.Scan(dest...);err!=nil{http.Error(w,"internal server error",500);return};item:=map[string]any{};for i,v:=range values{if b,ok:=v.([]byte);ok{item[cols[i]]=json.RawMessage(b)}else{item[cols[i]]=v}};items=append(items,item)}
	if err:=rows.Err();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"items":items,"total":len(items),"limit":1000})
}
func (h *gameLootAdminHandlers) updateItem(w http.ResponseWriter,r *http.Request){
	if !h.authorize(w,r){return};id:=strings.TrimSpace(r.PathValue("itemID"));if id==""||len(id)>64{http.Error(w,"invalid item id",400);return}
	var req struct{Name *string `json:"name"`;Description *string `json:"description"`;IconKey *string `json:"icon_key"`;MaxStack *int `json:"max_stack"`;Enabled *bool `json:"enabled"`}
	if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	if req.Name==nil&&req.Description==nil&&req.IconKey==nil&&req.MaxStack==nil&&req.Enabled==nil{http.Error(w,"no item fields supplied",400);return}
	if req.Name!=nil{*req.Name=strings.TrimSpace(*req.Name);if *req.Name==""||len(*req.Name)>64{http.Error(w,"name must contain 1 to 64 characters",400);return}}
	if req.Description!=nil&&len(*req.Description)>2000{http.Error(w,"description is too long",400);return};if req.IconKey!=nil&&len(*req.IconKey)>96{http.Error(w,"icon_key is too long",400);return}
	if req.MaxStack!=nil&&(*req.MaxStack<1||*req.MaxStack>9999){http.Error(w,"max_stack must be between 1 and 9999",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel();tx,err:=h.db.BeginTx(ctx,nil);if err!=nil{http.Error(w,"internal server error",500);return};defer tx.Rollback()
	var lockedID string;err=tx.QueryRowContext(ctx,`SELECT id FROM item_definitions WHERE id=$1 FOR UPDATE`,id).Scan(&lockedID)
	if errors.Is(err,sql.ErrNoRows){http.Error(w,"item not found",404);return};if err!=nil{http.Error(w,"internal server error",500);return}
	oldSnapshot,err:=readConfigSnapshot(ctx,tx,"item_definitions","id=$1",id);if err!=nil{http.Error(w,"internal server error",500);return}
	if req.MaxStack!=nil{var used int;err=tx.QueryRowContext(ctx,`SELECT GREATEST(COALESCE((SELECT MAX(quantity) FROM character_inventory WHERE item_id=$1),0),COALESCE((SELECT MAX(max_quantity) FROM monster_loot_entries WHERE item_id=$1),0),COALESCE((SELECT MAX(quantity) FROM ground_drops WHERE item_id=$1 AND status='available'),0))`,id).Scan(&used);if err!=nil{http.Error(w,"internal server error",500);return};if *req.MaxStack<used{http.Error(w,"max_stack cannot be lower than existing inventory, loot or ground-drop quantities",400);return}}
	_,err=tx.ExecContext(ctx,`UPDATE item_definitions SET name=COALESCE($2,name),description=COALESCE($3,description),icon_key=COALESCE($4,icon_key),max_stack=COALESCE($5,max_stack),enabled=COALESCE($6,enabled),updated_at=now() WHERE id=$1`,id,req.Name,req.Description,req.IconKey,req.MaxStack,req.Enabled)
	if err!=nil{h.logger.Error("game admin item update failed","item_id",id,"error",err);http.Error(w,"internal server error",500);return}
	newSnapshot,err:=readConfigSnapshot(ctx,tx,"item_definitions","id=$1",id);if err!=nil{http.Error(w,"internal server error",500);return}
	if err=recordConfigRevision(ctx,tx,"item_definition",id,"update",oldSnapshot,newSnapshot);err!=nil{h.logger.Error("record item revision failed","item_id",id,"error",err);http.Error(w,"internal server error",500);return}
	if err=tx.Commit();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"item_id":id,"updated":true})
}
func (h *gameLootAdminHandlers) listLoot(w http.ResponseWriter,r *http.Request){
	if !h.authorize(w,r){return};ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
	rows,err:=h.db.QueryContext(ctx,`SELECT ml.monster_id,i.id,i.name,i.category,i.quality,ml.drop_chance_bp,ml.min_quantity,ml.max_quantity,i.max_stack,i.enabled,SUM(ml.drop_chance_bp) OVER(PARTITION BY ml.monster_id)::int FROM monster_loot_entries ml JOIN item_definitions i ON i.id=ml.item_id ORDER BY ml.monster_id,i.quality DESC,i.id LIMIT 2000`)
	if err!=nil{h.logger.Error("game admin loot table query failed","error",err);http.Error(w,"internal server error",500);return};defer rows.Close()
	type entry struct{MonsterID string `json:"monster_id"`;ItemID string `json:"item_id"`;ItemName string `json:"item_name"`;Category string `json:"category"`;Quality int `json:"quality"`;DropChanceBP int `json:"drop_chance_bp"`;MinQuantity int `json:"min_quantity"`;MaxQuantity int `json:"max_quantity"`;MaxStack int `json:"max_stack"`;ItemEnabled bool `json:"item_enabled"`;TotalChanceBP int `json:"total_chance_bp"`}
	items:=make([]entry,0);for rows.Next(){var v entry;if err:=rows.Scan(&v.MonsterID,&v.ItemID,&v.ItemName,&v.Category,&v.Quality,&v.DropChanceBP,&v.MinQuantity,&v.MaxQuantity,&v.MaxStack,&v.ItemEnabled,&v.TotalChanceBP);err!=nil{http.Error(w,"internal server error",500);return};items=append(items,v)}
	if err:=rows.Err();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"entries":items,"total":len(items),"limit":2000})
}
func (h *gameLootAdminHandlers) upsertLoot(w http.ResponseWriter,r *http.Request){
	if !h.authorize(w,r){return};monsterID,itemID:=strings.TrimSpace(r.PathValue("monsterID")),strings.TrimSpace(r.PathValue("itemID"));if monsterID==""||len(monsterID)>64||itemID==""||len(itemID)>64{http.Error(w,"invalid monster or item id",400);return}
	var req struct{DropChanceBP *int `json:"drop_chance_bp"`;MinQuantity *int `json:"min_quantity"`;MaxQuantity *int `json:"max_quantity"`}
	if err:=decodeJSON(w,r,&req);err!=nil||req.DropChanceBP==nil||req.MinQuantity==nil||req.MaxQuantity==nil{http.Error(w,"drop_chance_bp, min_quantity and max_quantity are required",400);return}
	if *req.DropChanceBP<0||*req.DropChanceBP>10000||*req.MinQuantity<1||*req.MaxQuantity<*req.MinQuantity{http.Error(w,"invalid drop probability or quantity range",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel();tx,err:=h.db.BeginTx(ctx,nil);if err!=nil{http.Error(w,"internal server error",500);return};defer tx.Rollback()
	if _,err=tx.ExecContext(ctx,`SELECT pg_advisory_xact_lock(hashtext($1))`,monsterID);err!=nil{http.Error(w,"internal server error",500);return}
	var maxStack int;err=tx.QueryRowContext(ctx,`SELECT max_stack FROM item_definitions WHERE id=$1 AND enabled=TRUE FOR SHARE`,itemID).Scan(&maxStack)
	if errors.Is(err,sql.ErrNoRows){http.Error(w,"enabled item not found",404);return};if err!=nil{http.Error(w,"internal server error",500);return};if *req.MaxQuantity>maxStack{http.Error(w,"max_quantity cannot exceed item max_stack",400);return}
	var otherTotal int;err=tx.QueryRowContext(ctx,`SELECT COALESCE(SUM(drop_chance_bp),0)::int FROM monster_loot_entries WHERE monster_id=$1 AND item_id<>$2`,monsterID,itemID).Scan(&otherTotal);if err!=nil{http.Error(w,"internal server error",500);return}
	var currentChance sql.NullInt64
	currentErr:=tx.QueryRowContext(ctx,`SELECT drop_chance_bp FROM monster_loot_entries WHERE monster_id=$1 AND item_id=$2`,monsterID,itemID).Scan(&currentChance)
	if currentErr!=nil&&!errors.Is(currentErr,sql.ErrNoRows){http.Error(w,"internal server error",500);return}
	if otherTotal+*req.DropChanceBP>10000&&(!currentChance.Valid||int64(*req.DropChanceBP)>=currentChance.Int64){http.Error(w,"total drop chance for a monster cannot exceed 10000 basis points (100%); reduce existing entries first",400);return}
	_,err=tx.ExecContext(ctx,`INSERT INTO monster_loot_entries(monster_id,item_id,drop_chance_bp,min_quantity,max_quantity) VALUES($1,$2,$3,$4,$5) ON CONFLICT(monster_id,item_id) DO UPDATE SET drop_chance_bp=EXCLUDED.drop_chance_bp,min_quantity=EXCLUDED.min_quantity,max_quantity=EXCLUDED.max_quantity`,monsterID,itemID,*req.DropChanceBP,*req.MinQuantity,*req.MaxQuantity)
	if err!=nil{h.logger.Error("game admin loot upsert failed","monster_id",monsterID,"item_id",itemID,"error",err);http.Error(w,"internal server error",500);return};if err=tx.Commit();err!=nil{http.Error(w,"internal server error",500);return}
	writeJSON(w,200,map[string]any{"monster_id":monsterID,"item_id":itemID,"drop_chance_bp":*req.DropChanceBP,"min_quantity":*req.MinQuantity,"max_quantity":*req.MaxQuantity})
}
func (h *gameLootAdminHandlers) deleteLoot(w http.ResponseWriter,r *http.Request){
	if !h.authorize(w,r){return};monsterID,itemID:=strings.TrimSpace(r.PathValue("monsterID")),strings.TrimSpace(r.PathValue("itemID"));if monsterID==""||len(monsterID)>64||itemID==""||len(itemID)>64{http.Error(w,"invalid monster or item id",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),6*time.Second);defer cancel();result,err:=h.db.ExecContext(ctx,`DELETE FROM monster_loot_entries WHERE monster_id=$1 AND item_id=$2`,monsterID,itemID);if err!=nil{http.Error(w,"internal server error",500);return};n,_:=result.RowsAffected();if n==0{http.Error(w,"loot entry not found",404);return};writeJSON(w,200,map[string]any{"deleted":true,"monster_id":monsterID,"item_id":itemID})
}
func registerGameLootAdminRoutes(mux *http.ServeMux,db *sql.DB,logger *slog.Logger){
	h:=&gameLootAdminHandlers{db:db,apiKey:strings.TrimSpace(os.Getenv("GAME_ADMIN_INTERNAL_API_KEY")),logger:logger}
	mux.HandleFunc("GET /api/v1/internal/admin/loot/items",h.listItems)
	mux.HandleFunc("PATCH /api/v1/internal/admin/loot/items/{itemID}",h.updateItem)
	mux.HandleFunc("GET /api/v1/internal/admin/loot/tables",h.listLoot)
	mux.HandleFunc("PUT /api/v1/internal/admin/loot/tables/{monsterID}/{itemID}",h.upsertLoot)
	mux.HandleFunc("DELETE /api/v1/internal/admin/loot/tables/{monsterID}/{itemID}",h.deleteLoot)
}
