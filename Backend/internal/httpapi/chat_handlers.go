package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

type chatHandlers struct {
	authService auth.Provider
	service *chat.Service
	hub *chatSocketHub
	events *chatEventBus
	logger *slog.Logger
}

func (h *chatHandlers) send(w http.ResponseWriter,r *http.Request){
	account,ok:=h.authenticate(w,r);if !ok{return}
	var req chat.SendRequest
	if err:=decodeJSON(w,r,&req);err!=nil{http.Error(w,"invalid request body",http.StatusBadRequest);return}
	item,err:=h.service.Send(r.Context(),account.ID,req)
	if err!=nil{h.writeError(w,err);return}
	if h.events != nil { h.events.publish(item) } else if h.hub != nil { h.hub.broadcast(item) }
	writeJSON(w,http.StatusCreated,map[string]any{"message":item})
}

func (h *chatHandlers) list(w http.ResponseWriter,r *http.Request){
	account,ok:=h.authenticate(w,r);if !ok{return}
	channel:=strings.TrimSpace(r.URL.Query().Get("channel"))
	before:=strings.TrimSpace(r.URL.Query().Get("before"))
	limit:=50
	if raw:=r.URL.Query().Get("limit");raw!=""{if parsed,err:=strconv.Atoi(raw);err==nil{limit=parsed}}
	items,err:=h.service.List(r.Context(),account.ID,channel,before,limit)
	if err!=nil{h.writeError(w,err);return}
	writeJSON(w,http.StatusOK,map[string]any{"items":items,"retention_days":30})
}

func (h *chatHandlers) authenticate(w http.ResponseWriter,r *http.Request)(auth.Account,bool){
	header:=r.Header.Get("Authorization")
	if !strings.HasPrefix(header,"Bearer "){http.Error(w,"unauthorized",http.StatusUnauthorized);return auth.Account{},false}
	account,err:=h.authService.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
	if err!=nil{http.Error(w,"unauthorized",http.StatusUnauthorized);return auth.Account{},false}
	return account,true
}

func (h *chatHandlers) writeError(w http.ResponseWriter,err error){
	if h.writeSocialError(w, err) { return }
	switch{
	case errors.Is(err,chat.ErrInvalidInput):http.Error(w,"invalid chat request",http.StatusBadRequest)
	case errors.Is(err,chat.ErrNoCharacter):http.Error(w,"no active character",http.StatusConflict)
	case errors.Is(err,chat.ErrIdempotencyConflict):http.Error(w,"client_message_id already used with different content",http.StatusConflict)
	case errors.Is(err,chat.ErrRateLimited):http.Error(w,"chat rate limit exceeded",http.StatusTooManyRequests)
	case errors.Is(err,chat.ErrUnsupportedChannel):http.Error(w,"chat channel is not available yet",http.StatusNotImplemented)
	case errors.Is(err,chat.ErrFriendRequired):http.Error(w,"accepted friendship required",http.StatusForbidden)
	case errors.Is(err,chat.ErrBlocked):http.Error(w,"private messaging is blocked",http.StatusForbidden)
	default:
		h.logger.Error("chat request failed","error",err)
		http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}
