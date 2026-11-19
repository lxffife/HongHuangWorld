package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/gameadmin"
)

type adminLootItemUpdate struct{Name *string `json:"name"`;Description *string `json:"description"`;IconKey *string `json:"icon_key"`;MaxStack *int `json:"max_stack"`;Enabled *bool `json:"enabled"`}
type adminLootEntryUpdate struct{DropChanceBP *int `json:"drop_chance_bp"`;MinQuantity *int `json:"min_quantity"`;MaxQuantity *int `json:"max_quantity"`}

func (h *adminHandlers) listLootItems(w http.ResponseWriter,r *http.Request){
	if _,ok:=h.require(w,r,"monsters.read");!ok{return};ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.LootItems(ctx)
	if err!=nil{h.logger.Error("admin loot item list failed","error",err);http.Error(w,"game service unavailable",503);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) updateLootItem(w http.ResponseWriter,r *http.Request){
	actor,ok:=h.require(w,r,"monsters.manage");if !ok{return};id:=strings.TrimSpace(r.PathValue("itemID"));if id==""||len(id)>64{http.Error(w,"invalid item id",400);return}
	var req adminLootItemUpdate;if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.UpdateLootItem(ctx,id,req)
	if err!=nil{if errors.Is(err,gameadmin.ErrInvalidLootRequest){http.Error(w,err.Error(),400);return};if errors.Is(err,gameadmin.ErrLootNotFound){http.Error(w,"item not found",404);return};h.logger.Error("admin loot item update failed","item_id",id,"error",err);http.Error(w,"game service unavailable",503);return}
	if err:=h.service.RecordAudit(ctx,actor,"loot.item.update","item",id,"success",map[string]any{"name":req.Name,"description_changed":req.Description!=nil,"icon_changed":req.IconKey!=nil,"max_stack":req.MaxStack,"enabled":req.Enabled});err!=nil{http.Error(w,"item changed but audit recording failed",500);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) listLootTables(w http.ResponseWriter,r *http.Request){
	if _,ok:=h.require(w,r,"monsters.read");!ok{return};ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.LootTables(ctx)
	if err!=nil{h.logger.Error("admin loot table list failed","error",err);http.Error(w,"game service unavailable",503);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) upsertLootEntry(w http.ResponseWriter,r *http.Request){
	actor,ok:=h.require(w,r,"monsters.manage");if !ok{return};monsterID,itemID:=strings.TrimSpace(r.PathValue("monsterID")),strings.TrimSpace(r.PathValue("itemID"));if monsterID==""||len(monsterID)>64||itemID==""||len(itemID)>64{http.Error(w,"invalid monster or item id",400);return}
	var req adminLootEntryUpdate;if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.UpsertLootEntry(ctx,monsterID,itemID,req)
	if err!=nil{if errors.Is(err,gameadmin.ErrInvalidLootRequest){http.Error(w,err.Error(),400);return};if errors.Is(err,gameadmin.ErrLootNotFound){http.Error(w,"enabled item not found",404);return};h.logger.Error("admin loot entry update failed","monster_id",monsterID,"item_id",itemID,"error",err);http.Error(w,"game service unavailable",503);return}
	if err:=h.service.RecordAudit(ctx,actor,"loot.entry.upsert","monster_loot_entry",monsterID+":"+itemID,"success",map[string]any{"drop_chance_bp":req.DropChanceBP,"min_quantity":req.MinQuantity,"max_quantity":req.MaxQuantity});err!=nil{http.Error(w,"loot entry changed but audit recording failed",500);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) deleteLootEntry(w http.ResponseWriter,r *http.Request){
	actor,ok:=h.require(w,r,"monsters.manage");if !ok{return};monsterID,itemID:=strings.TrimSpace(r.PathValue("monsterID")),strings.TrimSpace(r.PathValue("itemID"));if monsterID==""||len(monsterID)>64||itemID==""||len(itemID)>64{http.Error(w,"invalid monster or item id",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.DeleteLootEntry(ctx,monsterID,itemID)
	if err!=nil{if errors.Is(err,gameadmin.ErrLootNotFound){http.Error(w,"loot entry not found",404);return};h.logger.Error("admin loot entry delete failed","error",err);http.Error(w,"game service unavailable",503);return}
	if err:=h.service.RecordAudit(ctx,actor,"loot.entry.delete","monster_loot_entry",monsterID+":"+itemID,"success",map[string]any{"deleted":true});err!=nil{http.Error(w,"loot entry deleted but audit recording failed",500);return};writeJSONRaw(w,result)
}
func writeJSONRaw(w http.ResponseWriter,result []byte){w.Header().Set("Content-Type","application/json; charset=utf-8");w.WriteHeader(http.StatusOK);_,_=w.Write(result)}
