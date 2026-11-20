package httpapi

import (
 "io"
 "log/slog"
 "net/http"
 "net/http/httptest"
 "testing"

 "github.com/liflife/HongHuangWorld/Backend/internal/adminauth"
)

func TestAdminRoutesUnavailableWithoutDatabase(t *testing.T) {
 handler:=NewAdminRouter(slog.New(slog.NewTextHandler(io.Discard,nil)),nil)
 cases:=[]struct{method,path string}{
  {http.MethodPost,"/api/v1/admin/auth/login"},
  {http.MethodGet,"/api/v1/admin/auth/me"},
  {http.MethodPost,"/api/v1/admin/auth/logout"},
  {http.MethodPost,"/api/v1/admin/auth/password"},
  {http.MethodGet,"/api/v1/admin/users"},
  {http.MethodPost,"/api/v1/admin/users"},
  {http.MethodGet,"/api/v1/admin/permissions"},
  {http.MethodGet,"/api/v1/admin/monsters/definitions"},
  {http.MethodPost,"/api/v1/admin/monsters/definitions"},
  {http.MethodPatch,"/api/v1/admin/monsters/definitions/wilderness_wolf"},
  {http.MethodGet,"/api/v1/admin/monsters/spawn-points"},
  {http.MethodPost,"/api/v1/admin/monsters/spawn-points"},
  {http.MethodPatch,"/api/v1/admin/monsters/spawn-points/wolf-001"},
  {http.MethodGet,"/api/v1/admin/loot/items"},
  {http.MethodPatch,"/api/v1/admin/loot/items/wolf_fang"},
  {http.MethodGet,"/api/v1/admin/loot/tables"},
  {http.MethodPut,"/api/v1/admin/loot/tables/wilderness_wolf/wolf_fang"},
  {http.MethodDelete,"/api/v1/admin/loot/tables/wilderness_wolf/wolf_fang"},
  {http.MethodGet,"/api/v1/admin/game-config/npcs"},
  {http.MethodPatch,"/api/v1/admin/game-config/npcs/fengdu_soul_guide/state"},
  {http.MethodGet,"/api/v1/admin/worlds"},
  {http.MethodGet,"/api/v1/admin/worlds/underworld_fengdu/instances"},
  {http.MethodPatch,"/api/v1/admin/worlds/underworld_fengdu/state"},
  {http.MethodGet,"/api/v1/admin/servers/nodes"},
  {http.MethodPatch,"/api/v1/admin/servers/nodes/test-node/state"},
  {http.MethodGet,"/api/v1/admin/players"},
  {http.MethodGet,"/api/v1/admin/players/online"},
  {http.MethodGet,"/api/v1/admin/players/test-player"},
  {http.MethodPatch,"/api/v1/admin/players/test-player/status"},
  {http.MethodPost,"/api/v1/admin/players/test-player/disconnect"},
  {http.MethodPut,"/api/v1/admin/users/00000000-0000-4000-8000-000000000001/permissions"},
 }
 for _,tc:=range cases { t.Run(tc.method+" "+tc.path,func(t *testing.T){
  req:=httptest.NewRequest(tc.method,tc.path,nil);res:=httptest.NewRecorder();handler.ServeHTTP(res,req)
  if res.Code!=http.StatusServiceUnavailable { t.Fatalf("expected %d, got %d",http.StatusServiceUnavailable,res.Code) }
 }) }
}

func TestAdminPermissionChecks(t *testing.T) {
 user:=adminauth.User{Permissions:[]string{"players.read"}}
 if !hasPermission(user,"players.read"){t.Fatal("explicit permission should be accepted")}
 if hasPermission(user,"players.ban"){t.Fatal("ungranted permission must be rejected")}
 kickOnly:=adminauth.User{Permissions:[]string{"players.kick"}}
 if !hasPermission(kickOnly,"players.kick"){t.Fatal("explicit kick permission should be accepted")}
 if hasPermission(kickOnly,"players.ban"){t.Fatal("kick permission must not grant ban permission")}
 banOnly:=adminauth.User{Permissions:[]string{"players.ban"}}
 if !hasPermission(banOnly,"players.ban"){t.Fatal("explicit ban permission should be accepted")}
 if hasPermission(banOnly,"players.kick"){t.Fatal("ban permission must not grant manual kick permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"servers.control"){t.Fatal("super administrator should have all permissions")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"servers.manage"){t.Fatal("super administrator should have node management permission")}
 if hasPermission(user,"servers.manage"){t.Fatal("node management must require its own permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"worlds.manage"){t.Fatal("super administrator should have world management permission")}
 if hasPermission(user,"worlds.manage"){t.Fatal("world management must require its own permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"game_config.manage"){t.Fatal("super administrator should have game config permission")}
 if hasPermission(user,"game_config.manage"){t.Fatal("game config management must require its own permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"monsters.read"){t.Fatal("super administrator should have monster read permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"monsters.manage"){t.Fatal("super administrator should have monster management permission")}
 if hasPermission(user,"monsters.read"){t.Fatal("monster read must require its own permission")}
 if hasPermission(user,"monsters.manage"){t.Fatal("monster management must require its own permission")}
}
