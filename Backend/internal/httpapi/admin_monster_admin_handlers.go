package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/gameadmin"
)

type adminMonsterDefinitionUpdate struct {
	Name *string `json:"name"`; Level *int `json:"level"`; MaxHealth *float64 `json:"max_health"`; Attack *float64 `json:"attack"`; Defense *float64 `json:"defense"`; MoveSpeed *float64 `json:"move_speed"`; AggroRadius *float64 `json:"aggro_radius"`; LeashRadius *float64 `json:"leash_radius"`; Enabled *bool `json:"enabled"`
}
type adminMonsterSpawnUpdate struct {
	SpawnX *float64 `json:"spawn_x"`; SpawnZ *float64 `json:"spawn_z"`; RareSpawn *bool `json:"rare_spawn"`; SpawnChancePercent *int `json:"spawn_chance_percent"`; RetrySpawnSeconds *int `json:"retry_spawn_seconds"`; FirstSpawnDelaySeconds *int `json:"first_spawn_delay_seconds"`; Enabled *bool `json:"enabled"`
}

func (h *adminHandlers) listMonsterDefinitions(w http.ResponseWriter,r *http.Request) {
	if _,ok:=h.require(w,r,"monsters.read");!ok{return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.MonsterDefinitions(ctx)
	if err!=nil{h.logger.Error("admin monster definitions query failed","error",err);http.Error(w,"game service unavailable",503);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) updateMonsterDefinition(w http.ResponseWriter,r *http.Request) {
	actor,ok:=h.require(w,r,"monsters.manage");if !ok{return};id:=strings.TrimSpace(r.PathValue("monsterID"));if id==""||len(id)>64{http.Error(w,"invalid monster id",400);return}
	var req adminMonsterDefinitionUpdate;if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.UpdateMonsterDefinition(ctx,id,req)
	if err!=nil{if errors.Is(err,gameadmin.ErrInvalidLootRequest){http.Error(w,err.Error(),400);return};if errors.Is(err,gameadmin.ErrLootNotFound){http.Error(w,"monster definition not found",404);return};h.logger.Error("admin monster definition update failed","monster_id",id,"error",err);http.Error(w,"game service unavailable",503);return}
	if err:=h.service.RecordAudit(ctx,actor,"monster.definition.update","monster_definition",id,"success",map[string]any{"name":req.Name,"level":req.Level,"max_health":req.MaxHealth,"attack":req.Attack,"defense":req.Defense,"move_speed":req.MoveSpeed,"aggro_radius":req.AggroRadius,"leash_radius":req.LeashRadius,"enabled":req.Enabled});err!=nil{http.Error(w,"monster changed but audit recording failed",500);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) listMonsterSpawnPoints(w http.ResponseWriter,r *http.Request) {
	if _,ok:=h.require(w,r,"monsters.read");!ok{return};worldID:=strings.TrimSpace(r.URL.Query().Get("world_id"));if len(worldID)>64{http.Error(w,"invalid world_id",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.MonsterSpawnPoints(ctx,worldID)
	if err!=nil{h.logger.Error("admin monster spawn point query failed","error",err);http.Error(w,"game service unavailable",503);return};writeJSONRaw(w,result)
}
func (h *adminHandlers) updateMonsterSpawnPoint(w http.ResponseWriter,r *http.Request) {
	actor,ok:=h.require(w,r,"monsters.manage");if !ok{return};id:=strings.TrimSpace(r.PathValue("spawnID"));if id==""||len(id)>96{http.Error(w,"invalid spawn point id",400);return}
	var req adminMonsterSpawnUpdate;if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),10*time.Second);defer cancel();result,err:=h.game.UpdateMonsterSpawnPoint(ctx,id,req)
	if err!=nil{if errors.Is(err,gameadmin.ErrInvalidLootRequest){http.Error(w,err.Error(),400);return};if errors.Is(err,gameadmin.ErrLootNotFound){http.Error(w,"spawn point not found",404);return};h.logger.Error("admin monster spawn point update failed","spawn_id",id,"error",err);http.Error(w,"game service unavailable",503);return}
	if err:=h.service.RecordAudit(ctx,actor,"monster.spawn_point.update","monster_spawn_point",id,"success",map[string]any{"spawn_x":req.SpawnX,"spawn_z":req.SpawnZ,"rare_spawn":req.RareSpawn,"spawn_chance_percent":req.SpawnChancePercent,"retry_spawn_seconds":req.RetrySpawnSeconds,"first_spawn_delay_seconds":req.FirstSpawnDelaySeconds,"enabled":req.Enabled});err!=nil{http.Error(w,"spawn point changed but audit recording failed",500);return};writeJSONRaw(w,result)
}
