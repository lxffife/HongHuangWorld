package httpapi

import (
 "crypto/subtle"
 "errors"
 "log/slog"
 "net/http"
 "strings"

 "github.com/liflife/HongHuangWorld/Backend/internal/auth"
 "github.com/liflife/HongHuangWorld/Backend/internal/task"
)

type bountyHandlers struct { authService auth.Provider; service *task.Service; logger *slog.Logger; apiKey string }
func (h *bountyHandlers) accountID(w http.ResponseWriter,r *http.Request)(string,bool){
 header:=r.Header.Get("Authorization");if !strings.HasPrefix(header,"Bearer "){http.Error(w,"unauthorized",http.StatusUnauthorized);return "",false}
 account,err:=h.authService.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
 if err!=nil{http.Error(w,"unauthorized",http.StatusUnauthorized);return "",false};return account.ID,true
}

func (h *bountyHandlers) contribute(w http.ResponseWriter,r *http.Request){
 account,ok:=h.accountID(w,r);if !ok{return}
 var body struct{CurrencyID string `json:"currency_id"`;Amount int64 `json:"amount"`;EventKey string `json:"event_key"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if err:=h.service.Contribute(r.Context(),account,r.PathValue("factionID"),body.CurrencyID,body.EventKey,body.Amount);err!=nil{h.writeError(w,err);return}
 writeJSON(w,http.StatusOK,map[string]any{"ok":true})
}
func (h *bountyHandlers) publishFaction(w http.ResponseWriter,r *http.Request){
 account,ok:=h.accountID(w,r);if !ok{return}
 var body struct{EventKey string `json:"event_key"`;Title string `json:"title"`;Description string `json:"description"`;CurrencyID string `json:"currency_id"`;RewardAmount int64 `json:"reward_amount"`;MaxAssignees int `json:"max_assignees"`;DifficultyTier int `json:"difficulty_tier"`;RequiredRealmLevel int `json:"required_realm_level"`;RequiredCharacterLevel int `json:"required_character_level"`;Objectives []task.ObjectiveRequest `json:"objectives"`;ExpiresAt *string `json:"expires_at"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 if body.RequiredCharacterLevel==0 { body.RequiredCharacterLevel=1 }
 result,err:=h.service.PublishFaction(r.Context(),account,task.PublishRequest{EventKey:body.EventKey,FactionID:r.PathValue("factionID"),Title:body.Title,Description:body.Description,CurrencyID:body.CurrencyID,RewardAmount:body.RewardAmount,MaxAssignees:body.MaxAssignees,DifficultyTier:body.DifficultyTier,RequiredRealmLevel:body.RequiredRealmLevel,RequiredCharacterLevel:body.RequiredCharacterLevel,Objectives:body.Objectives,ExpiresAt:body.ExpiresAt})
 if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusCreated,result)
}
func (h *bountyHandlers) list(w http.ResponseWriter,r *http.Request){
 worldID:=r.URL.Query().Get("world_id");items,err:=h.service.ListOpen(r.Context(),worldID);if err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"tasks":items})
}
func (h *bountyHandlers) join(w http.ResponseWriter,r *http.Request){
 account,ok:=h.accountID(w,r);if !ok{return};if err:=h.service.Join(r.Context(),account,r.PathValue("taskID"));err!=nil{h.writeError(w,err);return};writeJSON(w,http.StatusOK,map[string]any{"ok":true})
}

func (h *bountyHandlers) settle(w http.ResponseWriter,r *http.Request){
 account,ok:=h.accountID(w,r);if !ok{return}
 var body struct{EventKey string `json:"event_key"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 result,err:=h.service.Settle(r.Context(),account,r.PathValue("taskID"),body.EventKey)
 if err!=nil{h.writeError(w,err);return}
 writeJSON(w,http.StatusOK,result)
}

func (h *bountyHandlers) progress(w http.ResponseWriter,r *http.Request) {
 account,ok:=h.accountID(w,r);if !ok{return}
 result,err:=h.service.GetProgress(r.Context(),account,r.PathValue("taskID"))
 if err!=nil { h.writeError(w,err);return }
 writeJSON(w,http.StatusOK,result)
}
// reportWorldEvent accepts verified objective events from an authenticated WorldServer node.
func (h *bountyHandlers) reportWorldEvent(w http.ResponseWriter,r *http.Request) {
 provided:=r.Header.Get("X-World-Server-Key")
 if h.apiKey=="" || len(provided)!=len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided),[]byte(h.apiKey))!=1 {
  http.Error(w,"unauthorized",http.StatusUnauthorized);return
 }
 nodeKey:=strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
 if nodeKey=="" { http.Error(w,"missing world server node identity",http.StatusBadRequest);return }
 var event task.WorldEvent
 if err:=decodeJSON(w,r,&event);err!=nil { http.Error(w,"invalid request body",http.StatusBadRequest);return }
 result,err:=h.service.ApplyWorldEvent(r.Context(),nodeKey,event)
 if err!=nil { h.writeError(w,err);return }
 writeJSON(w,http.StatusOK,result)
}
func (h *bountyHandlers) writeError(w http.ResponseWriter,err error){
 switch{
 case errors.Is(err,task.ErrInvalid),errors.Is(err,task.ErrInvalidWorldEvent):http.Error(w,"invalid bounty task request",http.StatusBadRequest)
 case errors.Is(err,task.ErrNotFound):http.Error(w,"bounty task not found",http.StatusNotFound)
 case errors.Is(err,task.ErrForbidden):http.Error(w,"bounty task permission denied",http.StatusForbidden)
 case errors.Is(err,task.ErrIdempotencyConflict):http.Error(w,"idempotency key conflict",http.StatusConflict)
 case errors.Is(err,task.ErrTaskNotReady):http.Error(w,"bounty task is not ready for this operation",http.StatusConflict)
 case errors.Is(err,task.ErrCharacterNotEligible):http.Error(w,"current character does not meet bounty requirements",http.StatusConflict)
 case errors.Is(err,task.ErrWorldEventSession):http.Error(w,"world session is not valid for this node and task",http.StatusForbidden)
 case errors.Is(err,task.ErrWorldEventObjective):http.Error(w,"event does not match a configured bounty objective",http.StatusConflict)
 case errors.Is(err,task.ErrNotParticipant):http.Error(w,"account is not an active bounty participant",http.StatusConflict)
 case errors.Is(err,task.ErrInsufficientTreasury),errors.Is(err,task.ErrAlreadyJoined),errors.Is(err,task.ErrTaskFull):http.Error(w,err.Error(),http.StatusConflict)
 default:h.logger.Error("bounty task request failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError)
 }
}


// cancel allows only the publishing faction's leader/officer to release the
// remaining escrow. The event key must be reused when retrying the request.
func (h *bountyHandlers) cancel(w http.ResponseWriter,r *http.Request) {
 account,ok:=h.accountID(w,r); if !ok { return }
 var body struct { EventKey string `json:"event_key"` }
 if err:=decodeJSON(w,r,&body);err!=nil { http.Error(w,"invalid request body",http.StatusBadRequest);return }
 result,err:=h.service.Cancel(r.Context(),account,r.PathValue("taskID"),body.EventKey)
 if err!=nil { h.writeError(w,err);return }
 writeJSON(w,http.StatusOK,result)
}

// expireDue is a trusted scheduler endpoint. It deliberately uses the same
// World Server key as other server-to-server commands and is never exposed to players.
func (h *bountyHandlers) expireDue(w http.ResponseWriter,r *http.Request) {
 if h.apiKey=="" { http.Error(w,"world server API is not configured",http.StatusServiceUnavailable);return }
 provided:=r.Header.Get("X-World-Server-Key")
 if len(provided)!=len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided),[]byte(h.apiKey))!=1 {
  http.Error(w,"unauthorized",http.StatusUnauthorized);return
 }
 var body struct { Limit int `json:"limit"` }
 if r.Body!=nil && r.ContentLength!=0 {
  if err:=decodeJSON(w,r,&body);err!=nil { http.Error(w,"invalid request body",http.StatusBadRequest);return }
 }
 if body.Limit==0 { body.Limit=50 }
 count,err:=h.service.ExpireDue(r.Context(),body.Limit)
 if err!=nil { h.writeError(w,err);return }
 writeJSON(w,http.StatusOK,map[string]any{"refunded_tasks":count})
}


// leave releases the participant's slot before the task is completed or expires.
func (h *bountyHandlers) leave(w http.ResponseWriter,r *http.Request) {
 account,ok:=h.accountID(w,r);if !ok{return}
 if err:=h.service.Leave(r.Context(),account,r.PathValue("taskID"));err!=nil{h.writeError(w,err);return}
 writeJSON(w,http.StatusOK,map[string]any{"ok":true,"status":"withdrawn"})
}
