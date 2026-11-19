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

type gameMonsterAdminHandlers struct { db *sql.DB; apiKey string; logger *slog.Logger }
func (h *gameMonsterAdminHandlers) authorize(w http.ResponseWriter,r *http.Request) bool {
	return (&gamePlayerAdminHandlers{apiKey:h.apiKey}).authorize(w,r)
}

func (h *gameMonsterAdminHandlers) listDefinitions(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
	rows,err:=h.db.QueryContext(ctx,`SELECT id,name,level,max_health,attack,defense,move_speed,aggro_radius,leash_radius,enabled,created_at,updated_at FROM monster_definitions ORDER BY level,id`)
	if err!=nil{h.logger.Error("monster definition list failed","error",err);http.Error(w,"internal server error",500);return};defer rows.Close()
	type item struct{ID string `json:"id"`;Name string `json:"name"`;Level int `json:"level"`;MaxHealth float64 `json:"max_health"`;Attack float64 `json:"attack"`;Defense float64 `json:"defense"`;MoveSpeed float64 `json:"move_speed"`;AggroRadius float64 `json:"aggro_radius"`;LeashRadius float64 `json:"leash_radius"`;Enabled bool `json:"enabled"`;CreatedAt time.Time `json:"created_at"`;UpdatedAt time.Time `json:"updated_at"`}
	items:=make([]item,0);for rows.Next(){var v item;if err:=rows.Scan(&v.ID,&v.Name,&v.Level,&v.MaxHealth,&v.Attack,&v.Defense,&v.MoveSpeed,&v.AggroRadius,&v.LeashRadius,&v.Enabled,&v.CreatedAt,&v.UpdatedAt);err!=nil{http.Error(w,"internal server error",500);return};items=append(items,v)}
	if err:=rows.Err();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"items":items,"total":len(items)})
}

func (h *gameMonsterAdminHandlers) updateDefinition(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return};id:=strings.TrimSpace(r.PathValue("monsterID"));if id==""||len(id)>64{http.Error(w,"invalid monster id",400);return}
	var req struct{Name *string `json:"name"`;Level *int `json:"level"`;MaxHealth *float64 `json:"max_health"`;Attack *float64 `json:"attack"`;Defense *float64 `json:"defense"`;MoveSpeed *float64 `json:"move_speed"`;AggroRadius *float64 `json:"aggro_radius"`;LeashRadius *float64 `json:"leash_radius"`;Enabled *bool `json:"enabled"`}
	if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	if req.Name==nil&&req.Level==nil&&req.MaxHealth==nil&&req.Attack==nil&&req.Defense==nil&&req.MoveSpeed==nil&&req.AggroRadius==nil&&req.LeashRadius==nil&&req.Enabled==nil{http.Error(w,"no monster fields supplied",400);return}
	if req.Name!=nil{*req.Name=strings.TrimSpace(*req.Name);if *req.Name==""||len(*req.Name)>96{http.Error(w,"name must contain 1 to 96 characters",400);return}}
	if req.Level!=nil&&(*req.Level<1||*req.Level>10000){http.Error(w,"level must be between 1 and 10000",400);return}
	finite:=func(v *float64)bool{return v==nil||(*v>=0&&*v<1e9&&*v==*v)}
	for _,v:=range []*float64{req.MaxHealth,req.Attack,req.Defense,req.MoveSpeed,req.AggroRadius,req.LeashRadius}{if !finite(v){http.Error(w,"monster stats must be finite and within supported bounds",400);return}}
	if req.MaxHealth!=nil&&*req.MaxHealth<=0||req.MoveSpeed!=nil&&*req.MoveSpeed<=0||req.AggroRadius!=nil&&*req.AggroRadius<=0||req.LeashRadius!=nil&&*req.LeashRadius<=0{http.Error(w,"health, speed and radii must be positive",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel();tx,err:=h.db.BeginTx(ctx,nil);if err!=nil{http.Error(w,"internal server error",500);return};defer tx.Rollback()
	var currentAggro,currentLeash float64
	err=tx.QueryRowContext(ctx,`SELECT aggro_radius,leash_radius FROM monster_definitions WHERE id=$1 FOR UPDATE`,id).Scan(&currentAggro,&currentLeash)
	if errors.Is(err,sql.ErrNoRows){http.Error(w,"monster definition not found",404);return};if err!=nil{http.Error(w,"internal server error",500);return}
	if req.AggroRadius!=nil{currentAggro=*req.AggroRadius};if req.LeashRadius!=nil{currentLeash=*req.LeashRadius}
	if currentLeash<currentAggro{http.Error(w,"leash_radius cannot be smaller than aggro_radius",400);return}
	_,err=tx.ExecContext(ctx,`UPDATE monster_definitions SET name=COALESCE($2,name),level=COALESCE($3,level),max_health=COALESCE($4,max_health),attack=COALESCE($5,attack),defense=COALESCE($6,defense),move_speed=COALESCE($7,move_speed),aggro_radius=COALESCE($8,aggro_radius),leash_radius=COALESCE($9,leash_radius),enabled=COALESCE($10,enabled),updated_at=now() WHERE id=$1`,id,req.Name,req.Level,req.MaxHealth,req.Attack,req.Defense,req.MoveSpeed,req.AggroRadius,req.LeashRadius,req.Enabled)
	if err!=nil{http.Error(w,"internal server error",500);return};if err=tx.Commit();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"monster_id":id,"updated":true})
}

func (h *gameMonsterAdminHandlers) listSpawnPoints(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return};worldID:=strings.TrimSpace(r.URL.Query().Get("world_id"));if len(worldID)>64{http.Error(w,"invalid world_id",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
	rows,err:=h.db.QueryContext(ctx,`SELECT sp.id,sp.world_id,w.name AS world_name,sp.monster_id,md.name AS monster_name,md.level,sp.spawn_x,sp.spawn_z,sp.rare_spawn,sp.spawn_chance_percent,sp.retry_spawn_seconds,sp.first_spawn_delay_seconds,sp.enabled,sp.created_at,sp.updated_at FROM world_monster_spawn_points sp JOIN world_definitions w ON w.id=sp.world_id JOIN monster_definitions md ON md.id=sp.monster_id WHERE ($1='' OR sp.world_id=$1) ORDER BY sp.world_id,md.level,sp.id LIMIT 2000`,worldID)
	if err!=nil{h.logger.Error("monster spawn point list failed","error",err);http.Error(w,"internal server error",500);return};defer rows.Close()
	type item struct{ID string `json:"id"`;WorldID string `json:"world_id"`;WorldName string `json:"world_name"`;MonsterID string `json:"monster_id"`;MonsterName string `json:"monster_name"`;Level int `json:"level"`;SpawnX float64 `json:"spawn_x"`;SpawnZ float64 `json:"spawn_z"`;RareSpawn bool `json:"rare_spawn"`;SpawnChancePercent int `json:"spawn_chance_percent"`;RetrySpawnSeconds int `json:"retry_spawn_seconds"`;FirstSpawnDelaySeconds int `json:"first_spawn_delay_seconds"`;Enabled bool `json:"enabled"`;CreatedAt time.Time `json:"created_at"`;UpdatedAt time.Time `json:"updated_at"`}
	items:=make([]item,0);for rows.Next(){var v item;if err:=rows.Scan(&v.ID,&v.WorldID,&v.WorldName,&v.MonsterID,&v.MonsterName,&v.Level,&v.SpawnX,&v.SpawnZ,&v.RareSpawn,&v.SpawnChancePercent,&v.RetrySpawnSeconds,&v.FirstSpawnDelaySeconds,&v.Enabled,&v.CreatedAt,&v.UpdatedAt);err!=nil{http.Error(w,"internal server error",500);return};items=append(items,v)}
	if err:=rows.Err();err!=nil{http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"items":items,"total":len(items),"limit":2000})
}

func (h *gameMonsterAdminHandlers) updateSpawnPoint(w http.ResponseWriter,r *http.Request) {
	if !h.authorize(w,r){return};id:=strings.TrimSpace(r.PathValue("spawnID"));if id==""||len(id)>96{http.Error(w,"invalid spawn point id",400);return}
	var req struct{SpawnX *float64 `json:"spawn_x"`;SpawnZ *float64 `json:"spawn_z"`;RareSpawn *bool `json:"rare_spawn"`;SpawnChancePercent *int `json:"spawn_chance_percent"`;RetrySpawnSeconds *int `json:"retry_spawn_seconds"`;FirstSpawnDelaySeconds *int `json:"first_spawn_delay_seconds"`;Enabled *bool `json:"enabled"`}
	if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
	if req.SpawnX==nil&&req.SpawnZ==nil&&req.RareSpawn==nil&&req.SpawnChancePercent==nil&&req.RetrySpawnSeconds==nil&&req.FirstSpawnDelaySeconds==nil&&req.Enabled==nil{http.Error(w,"no spawn point fields supplied",400);return}
	for _,v:=range []*float64{req.SpawnX,req.SpawnZ}{if v!=nil&&(*v!=*v||*v>1e7||*v< -1e7){http.Error(w,"spawn coordinates are out of range",400);return}}
	if req.SpawnChancePercent!=nil&&(*req.SpawnChancePercent<1||*req.SpawnChancePercent>100){http.Error(w,"spawn_chance_percent must be between 1 and 100",400);return}
	for _,v:=range []*int{req.RetrySpawnSeconds,req.FirstSpawnDelaySeconds}{if v!=nil&&(*v<0||*v>604800){http.Error(w,"spawn delays must be between 0 and 604800 seconds",400);return}}
	if req.RetrySpawnSeconds!=nil&&*req.RetrySpawnSeconds<1{http.Error(w,"retry_spawn_seconds must be at least 1",400);return}
	ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
	var updatedID string
	err:=h.db.QueryRowContext(ctx,`UPDATE world_monster_spawn_points SET spawn_x=COALESCE($2,spawn_x),spawn_z=COALESCE($3,spawn_z),rare_spawn=COALESCE($4,rare_spawn),spawn_chance_percent=COALESCE($5,spawn_chance_percent),retry_spawn_seconds=COALESCE($6,retry_spawn_seconds),first_spawn_delay_seconds=COALESCE($7,first_spawn_delay_seconds),enabled=COALESCE($8,enabled),updated_at=now() WHERE id=$1 RETURNING id`,id,req.SpawnX,req.SpawnZ,req.RareSpawn,req.SpawnChancePercent,req.RetrySpawnSeconds,req.FirstSpawnDelaySeconds,req.Enabled).Scan(&updatedID)
	if errors.Is(err,sql.ErrNoRows){http.Error(w,"spawn point not found",404);return};if err!=nil{h.logger.Error("monster spawn point update failed","spawn_id",id,"error",err);http.Error(w,"internal server error",500);return}
	writeJSON(w,200,map[string]any{"spawn_point_id":updatedID,"updated":true})
}

func registerGameMonsterAdminRoutes(mux *http.ServeMux,db *sql.DB,logger *slog.Logger){
	h:=&gameMonsterAdminHandlers{db:db,apiKey:strings.TrimSpace(os.Getenv("GAME_ADMIN_INTERNAL_API_KEY")),logger:logger}
	mux.HandleFunc("GET /api/v1/internal/admin/monsters/definitions",h.listDefinitions)
	mux.HandleFunc("PATCH /api/v1/internal/admin/monsters/definitions/{monsterID}",h.updateDefinition)
	mux.HandleFunc("GET /api/v1/internal/admin/monsters/spawn-points",h.listSpawnPoints)
	mux.HandleFunc("PATCH /api/v1/internal/admin/monsters/spawn-points/{spawnID}",h.updateSpawnPoint)
}
