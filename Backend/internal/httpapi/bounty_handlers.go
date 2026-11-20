package httpapi

import (
 "errors"
 "log/slog"
 "net/http"
 "strings"

 "github.com/liflife/HongHuangWorld/Backend/internal/auth"
 "github.com/liflife/HongHuangWorld/Backend/internal/task"
)

type bountyHandlers struct { authService auth.Provider; service *task.Service; logger *slog.Logger }
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
 var body struct{EventKey string `json:"event_key"`;Title string `json:"title"`;Description string `json:"description"`;CurrencyID string `json:"currency_id"`;RewardAmount int64 `json:"reward_amount"`;MaxAssignees int `json:"max_assignees"`;DifficultyTier int `json:"difficulty_tier"`;RequiredRealmLevel int `json:"required_realm_level"`;ExpiresAt *string `json:"expires_at"`}
 if err:=decodeJSON(w,r,&body);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
 result,err:=h.service.PublishFaction(r.Context(),account,task.PublishRequest{EventKey:body.EventKey,FactionID:r.PathValue("factionID"),Title:body.Title,Description:body.Description,CurrencyID:body.CurrencyID,RewardAmount:body.RewardAmount,MaxAssignees:body.MaxAssignees,DifficultyTier:body.DifficultyTier,RequiredRealmLevel:body.RequiredRealmLevel,ExpiresAt:body.ExpiresAt})
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
func (h *bountyHandlers) writeError(w http.ResponseWriter,err error){
 switch{
 case errors.Is(err,task.ErrInvalid):http.Error(w,"invalid bounty task request",http.StatusBadRequest)
 case errors.Is(err,task.ErrNotFound):http.Error(w,"bounty task not found",http.StatusNotFound)
 case errors.Is(err,task.ErrForbidden):http.Error(w,"bounty task permission denied",http.StatusForbidden)
 case errors.Is(err,task.ErrIdempotencyConflict):http.Error(w,"idempotency key conflict",http.StatusConflict)
 case errors.Is(err,task.ErrTaskNotReady):http.Error(w,"bounty task is not ready for settlement",http.StatusConflict)
 case errors.Is(err,task.ErrInsufficientTreasury),errors.Is(err,task.ErrAlreadyJoined),errors.Is(err,task.ErrTaskFull):http.Error(w,err.Error(),http.StatusConflict)
 default:h.logger.Error("bounty task request failed","error",err);http.Error(w,"internal server error",http.StatusInternalServerError)
 }
}
