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
  {http.MethodGet,"/api/v1/admin/worlds"},
  {http.MethodGet,"/api/v1/admin/worlds/underworld_fengdu/instances"},
  {http.MethodPatch,"/api/v1/admin/worlds/underworld_fengdu/state"},
  {http.MethodGet,"/api/v1/admin/servers/nodes"},
  {http.MethodPatch,"/api/v1/admin/servers/nodes/test-node/state"},
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
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"servers.control"){t.Fatal("super administrator should have all permissions")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"servers.manage"){t.Fatal("super administrator should have node management permission")}
 if hasPermission(user,"servers.manage"){t.Fatal("node management must require its own permission")}
 if !hasPermission(adminauth.User{IsSuperAdmin:true},"worlds.manage"){t.Fatal("super administrator should have world management permission")}
 if hasPermission(user,"worlds.manage"){t.Fatal("world management must require its own permission")}
}
