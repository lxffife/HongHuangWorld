package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/npc"
)

type npcHandlers struct {
	authService *auth.Service
	service *npc.Service
	logger *slog.Logger
}

func (h *npcHandlers) currentAccount(w http.ResponseWriter,r *http.Request)(auth.Account,bool) {
	header:=r.Header.Get("Authorization")
	if !strings.HasPrefix(header,"Bearer ") { http.Error(w,"unauthorized",http.StatusUnauthorized); return auth.Account{},false }
	account,err:=h.authService.Authenticate(r.Context(),strings.TrimSpace(strings.TrimPrefix(header,"Bearer ")))
	if err!=nil { http.Error(w,"unauthorized",http.StatusUnauthorized); return auth.Account{},false }
	return account,true
}

func (h *npcHandlers) list(w http.ResponseWriter,r *http.Request) {
	account,ok:=h.currentAccount(w,r); if !ok{return}
	items,err:=h.service.ListForAccount(r.Context(),account.ID)
	switch {
	case err==nil: writeJSON(w,http.StatusOK,map[string]any{"npcs":items})
	case errors.Is(err,npc.ErrNoActiveSession): http.Error(w,"active world session required",http.StatusConflict)
	default: h.logger.Error("list world NPCs failed","error",err); http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}

func (h *npcHandlers) interact(w http.ResponseWriter,r *http.Request) {
	account,ok:=h.currentAccount(w,r); if !ok{return}
	var request struct { NPCID string `json:"npc_id"` }
	if err:=decodeJSON(w,r,&request);err!=nil || strings.TrimSpace(request.NPCID)=="" || len(request.NPCID)>64 {
		http.Error(w,"npc_id is required",http.StatusBadRequest);return
	}
	item,err:=h.service.Interact(r.Context(),account.ID,strings.TrimSpace(request.NPCID))
	switch {
	case err==nil: writeJSON(w,http.StatusOK,map[string]any{"npc":item,"interaction_type":item.InteractionType,"dialogue":item.Dialogue})
	case errors.Is(err,npc.ErrNoActiveSession): http.Error(w,"active world session required",http.StatusConflict)
	case errors.Is(err,npc.ErrNotFound): http.Error(w,"npc not found in current world",http.StatusNotFound)
	case errors.Is(err,npc.ErrTooFar): http.Error(w,"move closer to interact with this NPC",http.StatusConflict)
	default: h.logger.Error("interact with world NPC failed","error",err); http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}
