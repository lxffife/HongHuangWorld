package httpapi

import (
 "context"
 "database/sql"
 "log/slog"
 "os"
 "net/http"
 "time"

 "github.com/liflife/HongHuangWorld/Backend/internal/adminauth"
 "github.com/liflife/HongHuangWorld/Backend/internal/identityadmin"
 "github.com/liflife/HongHuangWorld/Backend/internal/gameadmin"
)

func NewAdminRouter(logger *slog.Logger,db *sql.DB) http.Handler {
 mux:=http.NewServeMux()
 mux.HandleFunc("GET /health",func(w http.ResponseWriter,r *http.Request){writeJSON(w,http.StatusOK,healthResponse{Status:"ok",Time:time.Now().UTC().Format(time.RFC3339)})})
 mux.HandleFunc("GET /ready",func(w http.ResponseWriter,r *http.Request){
  if db==nil{http.Error(w,"database is not configured",http.StatusServiceUnavailable);return}
  ctx,cancel:=context.WithTimeout(r.Context(),2*time.Second);defer cancel()
  if err:=db.PingContext(ctx);err!=nil{http.Error(w,"database unavailable",http.StatusServiceUnavailable);return}
  writeJSON(w,http.StatusOK,healthResponse{Status:"ready",Time:time.Now().UTC().Format(time.RFC3339)})
 })
 if db==nil { unavailable:=func(w http.ResponseWriter,_ *http.Request){http.Error(w,"service unavailable",http.StatusServiceUnavailable)}
  for _,route:=range []string{"POST /api/v1/admin/auth/login","GET /api/v1/admin/auth/me","GET /api/v1/admin/audit-logs","GET /api/v1/admin/dashboard","POST /api/v1/admin/auth/logout","POST /api/v1/admin/auth/password","GET /api/v1/admin/users","POST /api/v1/admin/users","GET /api/v1/admin/permissions","PUT /api/v1/admin/users/{id}/permissions","PATCH /api/v1/admin/users/{id}/status","GET /api/v1/admin/players","GET /api/v1/admin/players/online","GET /api/v1/admin/servers/nodes","PATCH /api/v1/admin/servers/nodes/{nodeKey}/state","GET /api/v1/admin/players/{id}","PATCH /api/v1/admin/players/{id}/status","POST /api/v1/admin/players/{id}/disconnect"}{mux.HandleFunc(route,unavailable)}
 } else {
  h:=&adminHandlers{service:adminauth.NewService(db),identity:identityadmin.New(os.Getenv("IDENTITY_API_BASE"),os.Getenv("IDENTITY_INTERNAL_API_KEY")),game:gameadmin.New(os.Getenv("GAME_API_BASE"),os.Getenv("GAME_ADMIN_INTERNAL_API_KEY")),logger:logger}
  mux.HandleFunc("POST /api/v1/admin/auth/login",h.login)
  mux.HandleFunc("GET /api/v1/admin/auth/me",h.me)
  mux.HandleFunc("GET /api/v1/admin/dashboard",h.dashboard)
  mux.HandleFunc("GET /api/v1/admin/audit-logs",h.listAuditLogs)
  mux.HandleFunc("POST /api/v1/admin/auth/logout",h.logout)
  mux.HandleFunc("POST /api/v1/admin/auth/password",h.changePassword)
  mux.HandleFunc("GET /api/v1/admin/users",h.listUsers)
  mux.HandleFunc("POST /api/v1/admin/users",h.createUser)
  mux.HandleFunc("GET /api/v1/admin/permissions",h.listPermissions)
  mux.HandleFunc("PUT /api/v1/admin/users/{id}/permissions",h.setPermissions)
  mux.HandleFunc("PATCH /api/v1/admin/users/{id}/status",h.setUserStatus)
  mux.HandleFunc("GET /api/v1/admin/players",h.listPlayers)
  mux.HandleFunc("GET /api/v1/admin/servers/nodes",h.listServerNodes)
  mux.HandleFunc("PATCH /api/v1/admin/servers/nodes/{nodeKey}/state",h.setServerNodeState)
  mux.HandleFunc("GET /api/v1/admin/players/online",h.listOnlinePlayers)
  mux.HandleFunc("GET /api/v1/admin/players/{id}",h.playerDetail)
  mux.HandleFunc("POST /api/v1/admin/players/{id}/disconnect",h.disconnectPlayer)
  mux.HandleFunc("PATCH /api/v1/admin/players/{id}/status",h.setPlayerStatus)
 }
 return requestLogger(logger,mux)
}
