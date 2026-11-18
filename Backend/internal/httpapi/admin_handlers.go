package httpapi

import (
 "errors"
 "log/slog"
 "net"
 "net/http"
 "strings"
 "time"

 "github.com/liflife/HongHuangWorld/Backend/internal/adminauth"
)

type adminHandlers struct { service *adminauth.Service; logger *slog.Logger }
type adminLoginRequest struct { Username string `json:"username"`; Password string `json:"password"` }
type adminPasswordRequest struct { CurrentPassword string `json:"current_password"`; NewPassword string `json:"new_password"` }
type adminCreateUserRequest struct { Username string `json:"username"`; Email string `json:"email"`; Password string `json:"password"` }
type adminSetPermissionsRequest struct { Permissions []string `json:"permissions"` }
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
