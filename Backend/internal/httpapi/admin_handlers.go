package httpapi

import (
 "context"
	"encoding/json"
 "errors"
 "log/slog"
 "net"
 "net/http"
 "strconv"
 "strings"
 "time"

 "github.com/liflife/HongHuangWorld/Backend/internal/adminauth"
 "github.com/liflife/HongHuangWorld/Backend/internal/identityadmin"
 "github.com/liflife/HongHuangWorld/Backend/internal/gameadmin"
)

func (h *adminHandlers) dashboard(w http.ResponseWriter,r *http.Request) {
 if _,ok:=h.require(w,r,"dashboard.read");!ok{return}
 ctx,cancel:=context.WithTimeout(r.Context(),3*time.Second);defer cancel()
 out,err:=h.service.Dashboard(ctx)
 if err!=nil { h.logger.Error("admin dashboard query failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return }
 writeJSON(w,http.StatusOK,out)
}

type adminHandlers struct { service *adminauth.Service; identity *identityadmin.Client; game *gameadmin.Client; logger *slog.Logger }
type adminLoginRequest struct { Username string `json:"username"`; Password string `json:"password"` }
type adminPasswordRequest struct { CurrentPassword string `json:"current_password"`; NewPassword string `json:"new_password"` }
type adminCreateUserRequest struct { Username string `json:"username"`; Email string `json:"email"`; Password string `json:"password"` }
type adminSetPermissionsRequest struct { Permissions []string `json:"permissions"` }
type adminSetUserStatusRequest struct { Status string `json:"status"` }
type adminAuthResponse struct { User adminauth.User `json:"user"`; Token string `json:"access_token"`; TokenType string `json:"token_type"`; ExpiresAt time.Time `json:"expires_at"` }

func (h *adminHandlers) login(w http.ResponseWriter,r *http.Request) {
 var req adminLoginRequest
 if err:=decodeJSON(w,r,&req);err!=nil { http.Error(w,"invalid request body",http.StatusBadRequest);return }
 user,token,expires,err:=h.service.Login(r.Context(),req.Username,req.Password,remoteIP(r),r.UserAgent())
 if err!=nil { if errors.Is(err,adminauth.ErrInvalidCredentials){http.Error(w,"invalid username or password",http.StatusUnauthorized);return};h.logger.Error("admin login failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return }
 writeJSON(w,http.StatusOK,adminAuthResponse{User:user,Token:token,TokenType:"Bearer",ExpiresAt:expires})
}
func (h *adminHandlers) authenticate(r *http.Request)(adminauth.User,error) {
 header:=r.Header.Get("Authorization");if !strings.HasPrefix(header,"Bearer "){return adminauth.User{},adminauth.ErrUnauthorized}
 return h.service.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
}
func hasPermission(u adminauth.User,key string) bool { if u.IsSuperAdmin{return true};for _,p:=range u.Permissions{if p==key{return true}};return false }
func (h *adminHandlers) require(w http.ResponseWriter,r *http.Request,key string)(adminauth.User,bool) {
 u,err:=h.authenticate(r);if err!=nil{http.Error(w,"unauthorized",http.StatusUnauthorized);return adminauth.User{},false}
 if key!="" && !hasPermission(u,key){http.Error(w,"forbidden",http.StatusForbidden);return adminauth.User{},false};return u,true
}
func (h *adminHandlers) logout(w http.ResponseWriter,r *http.Request) {
 if _,ok:=h.require(w,r,"");!ok{return}
 token:=strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"),"Bearer "))
 if err:=h.service.RevokeSession(r.Context(),token);err!=nil{h.logger.Error("admin logout failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return}
 writeJSON(w,http.StatusOK,map[string]string{"status":"logged_out"})
}
func (h *adminHandlers) me(w http.ResponseWriter,r *http.Request){u,ok:=h.require(w,r,"");if !ok{return};writeJSON(w,http.StatusOK,u)}
func (h *adminHandlers) changePassword(w http.ResponseWriter,r *http.Request){
 u,ok:=h.require(w,r,"");if !ok{return};var req adminPasswordRequest
 if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 token,expires,err:=h.service.ChangePassword(r.Context(),u,req.CurrentPassword,req.NewPassword,remoteIP(r),r.UserAgent())
 if err!=nil{if errors.Is(err,adminauth.ErrInvalidInput){http.Error(w,"password must contain 12 to 72 bytes",http.StatusBadRequest);return};if errors.Is(err,adminauth.ErrInvalidCredentials){http.Error(w,"current password is incorrect",http.StatusUnauthorized);return};h.logger.Error("admin password change failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return}
 writeJSON(w,http.StatusOK,map[string]any{"access_token":token,"token_type":"Bearer","expires_at":expires})
}
func (h *adminHandlers) listUsers(w http.ResponseWriter,r *http.Request){if _,ok:=h.require(w,r,"admin_users.read");!ok{return};items,err:=h.service.ListUsers(r.Context());if err!=nil{h.logger.Error("list admin users failed","error",err);http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"items":items})}
func (h *adminHandlers) createUser(w http.ResponseWriter,r *http.Request){
 actor,ok:=h.require(w,r,"admin_users.manage");if !ok{return};var req adminCreateUserRequest
 if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
 user,err:=h.service.CreateUser(r.Context(),actor,req.Username,req.Email,req.Password)
 if err!=nil{if errors.Is(err,adminauth.ErrInvalidInput){http.Error(w,"invalid username, email or password",400);return};if errors.Is(err,adminauth.ErrConflict){http.Error(w,"username or email already exists",409);return};h.logger.Error("create admin user failed","error",err);http.Error(w,"internal server error",500);return}
 writeJSON(w,http.StatusCreated,user)
}
func (h *adminHandlers) listPermissions(w http.ResponseWriter,r *http.Request){if _,ok:=h.require(w,r,"admin_users.read");!ok{return};items,err:=h.service.ListPermissions(r.Context());if err!=nil{h.logger.Error("list admin permissions failed","error",err);http.Error(w,"internal server error",500);return};writeJSON(w,200,map[string]any{"items":items})}
func (h *adminHandlers) setPermissions(w http.ResponseWriter,r *http.Request){
 actor,ok:=h.require(w,r,"admin_users.manage");if !ok{return};var req adminSetPermissionsRequest
 if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
 err:=h.service.SetPermissions(r.Context(),actor,r.PathValue("id"),req.Permissions)
 if err!=nil{if errors.Is(err,adminauth.ErrInvalidInput){http.Error(w,"invalid target user or permission list",400);return};if errors.Is(err,adminauth.ErrForbidden){http.Error(w,"only a super administrator may grant administrator-management permission",403);return};h.logger.Error("set admin permissions failed","error",err);http.Error(w,"internal server error",500);return}
 writeJSON(w,200,map[string]string{"status":"updated"})
}
func remoteIP(r *http.Request) string { host,_,err:=net.SplitHostPort(r.RemoteAddr);if err==nil{return host};return "" }

func (h *adminHandlers) listAuditLogs(w http.ResponseWriter, r *http.Request) {
 if _,ok:=h.require(w,r,"audit.read");!ok{return}
 q:=r.URL.Query()
 limit:=50
 if raw:=q.Get("limit");raw!="" { n,err:=strconv.Atoi(raw);if err!=nil||n<1||n>100{http.Error(w,"limit must be between 1 and 100",http.StatusBadRequest);return};limit=n }
 offset:=0
 if raw:=q.Get("offset");raw!="" { n,err:=strconv.Atoi(raw);if err!=nil||n<0||n>1000000{http.Error(w,"invalid offset",http.StatusBadRequest);return};offset=n }
 result:=q.Get("result");if result!=""&&result!="success"&&result!="failure"&&result!="denied"{http.Error(w,"invalid result filter",http.StatusBadRequest);return}
 filter:=adminauth.AuditFilter{ActorID:strings.TrimSpace(q.Get("actor_id")),ResourceType:strings.TrimSpace(q.Get("resource_type")),ResourceID:strings.TrimSpace(q.Get("resource_id")),Action:strings.TrimSpace(q.Get("action")),Result:result,Limit:limit,Offset:offset}
 if raw:=q.Get("from");raw!="" { t,err:=time.Parse(time.RFC3339,raw);if err!=nil{http.Error(w,"from must be RFC3339",http.StatusBadRequest);return};filter.From=&t }
 if raw:=q.Get("to");raw!="" { t,err:=time.Parse(time.RFC3339,raw);if err!=nil{http.Error(w,"to must be RFC3339",http.StatusBadRequest);return};filter.To=&t }
 if filter.From!=nil&&filter.To!=nil&&!filter.From.Before(*filter.To){http.Error(w,"from must be earlier than to",http.StatusBadRequest);return}
 ctx,cancel:=context.WithTimeout(r.Context(),5*time.Second);defer cancel()
 page,err:=h.service.ListAuditLogs(ctx,filter)
 if err!=nil{h.logger.Error("list admin audit logs failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return}
 writeJSON(w,http.StatusOK,page)
}

func (h *adminHandlers) setUserStatus(w http.ResponseWriter,r *http.Request) {
 actor,ok:=h.require(w,r,"admin_users.manage");if !ok{return}
 var req adminSetUserStatusRequest
 if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if req.Status!="active"&&req.Status!="disabled"{http.Error(w,"status must be active or disabled",http.StatusBadRequest);return}
 if err:=h.service.SetUserStatus(r.Context(),actor,r.PathValue("id"),req.Status);err!=nil{
  if errors.Is(err,adminauth.ErrInvalidInput){http.Error(w,"invalid target user",http.StatusBadRequest);return}
  if errors.Is(err,adminauth.ErrForbidden){http.Error(w,"cannot change your own status",http.StatusForbidden);return}
  h.logger.Error("set admin user status failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError);return
 }
 writeJSON(w,http.StatusOK,map[string]string{"status":"updated"})
}

func (h *adminHandlers) listPlayers(w http.ResponseWriter,r *http.Request) {
 if _,ok:=h.require(w,r,"players.read");!ok{return}
 limit:=50
 if raw:=r.URL.Query().Get("limit");raw!="" { n,err:=strconv.Atoi(raw);if err!=nil||n<1||n>100{http.Error(w,"limit must be between 1 and 100",400);return};limit=n }
 ctx,cancel:=context.WithTimeout(r.Context(),6*time.Second);defer cancel()
 page,err:=h.identity.ListAccounts(ctx,strings.TrimSpace(r.URL.Query().Get("q")),limit)
 if err!=nil{h.logger.Error("admin player search failed","error",err);http.Error(w,"identity service unavailable",http.StatusServiceUnavailable);return}
 writeJSON(w,http.StatusOK,page)
}

func (h *adminHandlers) listWorlds(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.require(w, r, "worlds.read"); !ok { return }
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := h.game.Worlds(ctx)
	if err != nil { h.logger.Error("admin worlds lookup failed", "error", err); http.Error(w, "game service unavailable", http.StatusServiceUnavailable); return }
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}

func (h *adminHandlers) listWorldInstances(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.require(w, r, "worlds.read"); !ok { return }
	worldID := strings.TrimSpace(r.PathValue("worldID"))
	if worldID == "" || len(worldID) > 64 { http.Error(w, "invalid world id", http.StatusBadRequest); return }
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := h.game.WorldInstances(ctx, worldID)
	if err != nil {
		if strings.Contains(err.Error(), "world not found") { http.Error(w, "world not found", http.StatusNotFound); return }
		h.logger.Error("admin world instances lookup failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}

func (h *adminHandlers) setWorldEnabled(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.require(w, r, "worlds.manage")
	if !ok { return }
	worldID := strings.TrimSpace(r.PathValue("worldID"))
	if worldID == "" || len(worldID) > 64 { http.Error(w, "invalid world id", http.StatusBadRequest); return }
	var request struct { Enabled *bool `json:"enabled"` }
	if err := decodeJSON(w, r, &request); err != nil || request.Enabled == nil { http.Error(w, "enabled must be a boolean", http.StatusBadRequest); return }
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	result, err := h.game.SetWorldEnabled(ctx, worldID, *request.Enabled)
	if err != nil {
		if strings.Contains(err.Error(), "world not found") { http.Error(w, "world not found", http.StatusNotFound); return }
		if strings.Contains(err.Error(), "invalid world state") { http.Error(w, "invalid world state", http.StatusBadRequest); return }
		h.logger.Error("admin world state update failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	if err := h.service.RecordAudit(ctx, actor, "world.state", "world", worldID, "success", map[string]any{"enabled": *request.Enabled, "game_response": json.RawMessage(result)}); err != nil {
		h.logger.Error("record world state audit failed", "error", err)
		http.Error(w, "world state changed but audit recording failed", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}

func (h *adminHandlers) listServerNodes(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.require(w, r, "servers.read"); !ok { return }
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := h.game.ServerNodes(ctx)
	if err != nil {
		h.logger.Error("admin server node lookup failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}

func (h *adminHandlers) setServerNodeState(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.require(w, r, "servers.manage")
	if !ok { return }
	nodeKey := strings.TrimSpace(r.PathValue("nodeKey"))
	if nodeKey == "" || len(nodeKey) > 96 { http.Error(w, "invalid node key", http.StatusBadRequest); return }
	var request struct { AdminState string `json:"admin_state"` }
	if err := decodeJSON(w, r, &request); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	if request.AdminState != "normal" && request.AdminState != "draining" && request.AdminState != "disabled" { http.Error(w, "admin_state must be normal, draining or disabled", http.StatusBadRequest); return }
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := h.game.SetServerNodeState(ctx, nodeKey, request.AdminState)
	if err != nil {
		if strings.Contains(err.Error(), "not found") { http.Error(w, "world server node not found", http.StatusNotFound); return }
		if strings.Contains(err.Error(), "invalid world server node state") { http.Error(w, "invalid node state", http.StatusBadRequest); return }
		h.logger.Error("admin server node state update failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	if err := h.service.RecordAudit(ctx, actor, "server.node.state", "server_node", nodeKey, "success", map[string]any{"admin_state": request.AdminState, "game_response": json.RawMessage(result)}); err != nil {
		h.logger.Error("record server node state audit failed", "error", err)
		http.Error(w, "node state changed but audit recording failed", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}
func (h *adminHandlers) listOnlinePlayers(w http.ResponseWriter, r *http.Request) {
	if _, ok := h.require(w, r, "players.read"); !ok { return }
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	result, err := h.game.OnlinePlayers(ctx)
	if err != nil {
		h.logger.Error("admin online player lookup failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(result)
}
func (h *adminHandlers) setPlayerStatus(w http.ResponseWriter,r *http.Request) {
 actor,ok:=h.require(w,r,"players.ban");if !ok{return}
 var req struct { Status string `json:"status"`; Reason string `json:"reason"` }
 if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",400);return}
 if req.Status!="active"&&req.Status!="locked"{http.Error(w,"status must be active or locked",400);return}
 req.Reason=strings.TrimSpace(req.Reason)
 if req.Status=="locked"&&(len([]rune(req.Reason))<2||len([]rune(req.Reason))>300){http.Error(w,"ban reason must contain 2 to 300 characters",400);return}
 if req.Status=="active"&&len([]rune(req.Reason))>300{http.Error(w,"reason is too long",400);return}
 ctx,cancel:=context.WithTimeout(r.Context(),6*time.Second);defer cancel()
 id:=r.PathValue("id")
 if err:=h.identity.SetAccountStatus(ctx,id,req.Status);err!=nil{
  if strings.Contains(err.Error(),"not found"){http.Error(w,"player not found",404);return}
  h.logger.Error("admin player status update failed","error",err);http.Error(w,"identity service unavailable",503);return
 }
 action:="player.unban";if req.Status=="locked"{action="player.ban"}
 details:=map[string]any{"status":req.Status,"reason":req.Reason}
 response:=map[string]any{"status":req.Status}
 if req.Status=="locked" {
  disconnect,disconnectErr:=h.game.DisconnectPlayer(ctx,id)
  if disconnectErr!=nil {
   h.logger.Error("player was locked but world disconnect request failed","error",disconnectErr)
   details["disconnect_requested"]=false
   details["disconnect_error"]="game service unavailable"
   response["disconnect_requested"]=false
   response["warning"]="账号已封禁，但游戏会话断开请求未能送达，请稍后重试强制下线"
  } else {
   details["disconnect_requested"]=true
   details["requested_sessions"]=disconnect.RequestedSessions
   response["disconnect_requested"]=true
   response["requested_sessions"]=disconnect.RequestedSessions
  }
 }
 if err:=h.service.RecordAudit(ctx,actor,action,"player",id,"success",details);err!=nil{
  h.logger.Error("record player moderation audit failed","error",err)
  http.Error(w,"player status changed but audit recording failed",http.StatusInternalServerError);return
 }
 if req.Status=="locked" { writeJSON(w,http.StatusAccepted,response);return }
 writeJSON(w,http.StatusOK,response)
}

func (h *adminHandlers) playerDetail(w http.ResponseWriter, r *http.Request) {
 if _,ok:=h.require(w,r,"players.read");!ok{return}
 id:=strings.TrimSpace(r.PathValue("id"))
 if id=="" || len(id)>64 { http.Error(w,"invalid player id",http.StatusBadRequest);return }
 ctx,cancel:=context.WithTimeout(r.Context(),8*time.Second);defer cancel()
 account,err:=h.identity.GetAccount(ctx,id)
 if err!=nil {
  if strings.Contains(err.Error(),"not found") { http.Error(w,"player not found",http.StatusNotFound);return }
  h.logger.Error("admin player detail identity lookup failed","error",err)
  http.Error(w,"identity service unavailable",http.StatusServiceUnavailable);return
 }
 auditPage,err:=h.service.ListAuditLogs(ctx,adminauth.AuditFilter{ResourceType:"player",ResourceID:id,Limit:20})
 if err!=nil { h.logger.Error("admin player audit lookup failed","error",err);http.Error(w,"audit service unavailable",http.StatusServiceUnavailable);return }
 gameDetail,err:=h.game.PlayerDetail(ctx,id)
 if err!=nil {
  if strings.Contains(err.Error(),"not found") { http.Error(w,"game player not found",http.StatusNotFound);return }
  h.logger.Error("admin player detail game lookup failed","error",err)
  http.Error(w,"game service unavailable",http.StatusServiceUnavailable);return
 }
 writeJSON(w,http.StatusOK,map[string]any{"account":account,"game":gameDetail,"audit_logs":auditPage.Items})
}

func (h *adminHandlers) disconnectPlayer(w http.ResponseWriter, r *http.Request) {
	actor, ok := h.require(w, r, "players.ban")
	if !ok { return }
	id := strings.TrimSpace(r.PathValue("id"))
	if id == "" || len(id) > 64 {
		http.Error(w, "invalid player id", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 8*time.Second)
	defer cancel()
	if _, err := h.identity.GetAccount(ctx, id); err != nil {
		if strings.Contains(err.Error(), "not found") {
			http.Error(w, "player not found", http.StatusNotFound)
			return
		}
		h.logger.Error("admin disconnect player identity lookup failed", "error", err)
		http.Error(w, "identity service unavailable", http.StatusServiceUnavailable)
		return
	}
	result, err := h.game.DisconnectPlayer(ctx, id)
	if err != nil {
		h.logger.Error("admin disconnect player request failed", "error", err)
		http.Error(w, "game service unavailable", http.StatusServiceUnavailable)
		return
	}
	if err := h.service.RecordAudit(ctx, actor, "player.disconnect", "player", id, "success", map[string]any{
		"requested_sessions": result.RequestedSessions,
		"status": result.Status,
	}); err != nil {
		h.logger.Error("record player disconnect audit failed", "error", err)
		http.Error(w, "disconnect was requested but audit recording failed", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusAccepted, result)
}
