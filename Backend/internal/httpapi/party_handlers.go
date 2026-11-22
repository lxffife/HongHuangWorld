package httpapi

import (
 "errors"
 "log/slog"
 "net/http"
 "strings"

 "github.com/liflife/HongHuangWorld/Backend/internal/auth"
 "github.com/liflife/HongHuangWorld/Backend/internal/party"
)

type partyHandlers struct { authService auth.Provider; service *party.Service; logger *slog.Logger }

func (h *partyHandlers) accountID(w http.ResponseWriter,r *http.Request)(string,bool){
 header:=r.Header.Get("Authorization")
 if !strings.HasPrefix(header,"Bearer "){http.Error(w,"unauthorized",http.StatusUnauthorized);return "",false}
 account,err:=h.authService.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
 if err!=nil{http.Error(w,"unauthorized",http.StatusUnauthorized);return "",false}
 return account.ID,true
}
func (h *partyHandlers) current(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 result,err:=h.service.Get(r.Context(),id);if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,result)
}
func (h *partyHandlers) create(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 result,err:=h.service.Create(r.Context(),id);if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusCreated,result)
}
func (h *partyHandlers) invite(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 var body struct{Username string `json:"username"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 result,err:=h.service.Invite(r.Context(),id,body.Username);if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusCreated,result)
}
func (h *partyHandlers) invitations(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 result,err:=h.service.Invitations(r.Context(),id);if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"invitations":result})
}
func (h *partyHandlers) respond(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 var body struct{Decision string `json:"decision"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if err:=h.service.Respond(r.Context(),id,r.PathValue("invitationID"),body.Decision);err!=nil{h.writeError(w,err);return}
 writeJSON(w,http.StatusOK,map[string]any{"ok":true,"decision":body.Decision})
}
func (h *partyHandlers) leave(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 if err:=h.service.Leave(r.Context(),id);err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"ok":true})
}
func (h *partyHandlers) kick(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 var body struct{AccountID string `json:"account_id"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if err:=h.service.Kick(r.Context(),id,body.AccountID);err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"ok":true})
}
func (h *partyHandlers) transfer(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 var body struct{AccountID string `json:"account_id"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if err:=h.service.Transfer(r.Context(),id,body.AccountID);err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"ok":true,"leader_account_id":body.AccountID})
}
func (h *partyHandlers) disband(w http.ResponseWriter,r *http.Request){
 id,ok:=h.accountID(w,r);if !ok{return}
 if err:=h.service.Disband(r.Context(),id);err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"ok":true})
}
func (h *partyHandlers) writeError(w http.ResponseWriter,err error){
 switch{
 case errors.Is(err,party.ErrInvalid):http.Error(w,"invalid party request",http.StatusBadRequest)
 case errors.Is(err,party.ErrNotFound):http.Error(w,"party, member, or invitation not found",http.StatusNotFound)
 case errors.Is(err,party.ErrForbidden),errors.Is(err,party.ErrNotLeader):http.Error(w,"party permission denied",http.StatusForbidden)
 case errors.Is(err,party.ErrAlreadyInParty),errors.Is(err,party.ErrNotSameInstance),errors.Is(err,party.ErrPartyFull),errors.Is(err,party.ErrInvitationExpired):http.Error(w,err.Error(),http.StatusConflict)
 default:h.logger.Error("party request failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError)
 }
}
