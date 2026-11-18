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


func (h *npcHandlers) chooseFate(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	var request struct {
		NPCID string `json:"npc_id"`
		ChoiceID string `json:"choice_id"`
	}
	if err := decodeJSON(w, r, &request); err != nil || strings.TrimSpace(request.NPCID) == "" || strings.TrimSpace(request.ChoiceID) == "" {
		http.Error(w, "npc_id and choice_id are required", http.StatusBadRequest)
		return
	}
	result, err := h.service.ChooseFate(r.Context(), account.ID, strings.TrimSpace(request.NPCID), strings.TrimSpace(request.ChoiceID))
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, npc.ErrNoActiveSession):
		http.Error(w, "active world session required", http.StatusConflict)
	case errors.Is(err, npc.ErrNotFound):
		http.Error(w, "npc not found in current world", http.StatusNotFound)
	case errors.Is(err, npc.ErrTooFar):
		http.Error(w, "move closer to interact with this NPC", http.StatusConflict)
	case errors.Is(err, npc.ErrChoiceUnavailable):
		http.Error(w, "NPC fate choice is unavailable", http.StatusBadRequest)
	case errors.Is(err, npc.ErrChoiceResolved):
		http.Error(w, "this fate choice has already been resolved for your soul", http.StatusConflict)
	default:
		h.logger.Error("resolve NPC fate choice failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}


func (h *npcHandlers) discoverFateEncounter(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	var request struct { NPCID string `json:"npc_id"` }
	if err := decodeJSON(w, r, &request); err != nil || strings.TrimSpace(request.NPCID) == "" || len(request.NPCID) > 64 {
		http.Error(w, "npc_id is required", http.StatusBadRequest)
		return
	}
	result, err := h.service.DiscoverFateEncounter(r.Context(), account.ID, strings.TrimSpace(request.NPCID))
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, npc.ErrNoActiveSession):
		http.Error(w, "active world session required", http.StatusConflict)
	case errors.Is(err, npc.ErrTooFar):
		http.Error(w, "move closer to this NPC", http.StatusConflict)
	case errors.Is(err, npc.ErrEncounterUnavailable):
		http.Error(w, "no hidden fate encounter is available for this character", http.StatusNotFound)
	case errors.Is(err, npc.ErrEncounterResolved):
		http.Error(w, "this hidden fate encounter has already been discovered by your soul", http.StatusConflict)
	default:
		h.logger.Error("discover fate encounter failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}


func (h *npcHandlers) listExplorationPoints(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	items, err := h.service.ListExplorationPoints(r.Context(), account.ID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, map[string]any{"points": items})
	case errors.Is(err, npc.ErrNoActiveSession):
		http.Error(w, "active world session required", http.StatusConflict)
	default:
		h.logger.Error("list world exploration points failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *npcHandlers) discoverExplorationPoint(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	var request struct { PointID string `json:"point_id"` }
	if err := decodeJSON(w, r, &request); err != nil || strings.TrimSpace(request.PointID) == "" || len(request.PointID) > 96 {
		http.Error(w, "point_id is required", http.StatusBadRequest)
		return
	}
	result, err := h.service.DiscoverExplorationPoint(r.Context(), account.ID, strings.TrimSpace(request.PointID))
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, npc.ErrNoActiveSession):
		http.Error(w, "active world session required", http.StatusConflict)
	case errors.Is(err, npc.ErrNotFound):
		http.Error(w, "exploration point not found", http.StatusNotFound)
	case errors.Is(err, npc.ErrTooFar):
		http.Error(w, "move closer to this exploration point", http.StatusConflict)
	case errors.Is(err, npc.ErrExplorationUnavailable):
		http.Error(w, "exploration point is unavailable", http.StatusNotFound)
	case errors.Is(err, npc.ErrExplorationResolved):
		http.Error(w, "this point has already been discovered by your soul", http.StatusConflict)
	default:
		h.logger.Error("discover world exploration point failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}


func (h *npcHandlers) listExplorationEvents(w http.ResponseWriter,r *http.Request) {
	account,ok:=h.currentAccount(w,r); if !ok{return}
	items,err:=h.service.ListAvailableExplorationEvents(r.Context(),account.ID)
	switch {
	case err==nil: writeJSON(w,http.StatusOK,map[string]any{"events":items})
	case errors.Is(err,npc.ErrNoActiveSession): http.Error(w,"active world session required",http.StatusConflict)
	default: h.logger.Error("list exploration events failed","error",err); http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}

func (h *npcHandlers) triggerExplorationEvent(w http.ResponseWriter,r *http.Request) {
	account,ok:=h.currentAccount(w,r); if !ok{return}
	var request struct {
		EventID string `json:"event_id"`
		ChoiceID string `json:"choice_id"`
	}
	if err:=decodeJSON(w,r,&request);err!=nil || strings.TrimSpace(request.EventID)=="" || strings.TrimSpace(request.ChoiceID)=="" || len(request.EventID)>96 || len(request.ChoiceID)>64 {
		http.Error(w,"event_id and choice_id are required",http.StatusBadRequest);return
	}
	result,err:=h.service.TriggerExplorationEvent(r.Context(),account.ID,strings.TrimSpace(request.EventID),strings.TrimSpace(request.ChoiceID))
	switch {
	case err==nil: writeJSON(w,http.StatusOK,result)
	case errors.Is(err,npc.ErrNoActiveSession): http.Error(w,"active world session required",http.StatusConflict)
	case errors.Is(err,npc.ErrTooFar): http.Error(w,"move closer to the exploration event",http.StatusConflict)
	case errors.Is(err,npc.ErrExplorationEventUnavailable): http.Error(w,"exploration event is unavailable or locked",http.StatusNotFound)
	case errors.Is(err,npc.ErrExplorationEventResolved): http.Error(w,"this event has already been resolved by your soul",http.StatusConflict)
	default: h.logger.Error("trigger exploration event failed","error",err); http.Error(w,"internal server error",http.StatusInternalServerError)
	}
}


func (h *npcHandlers) explorationProgress(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok { return }
	result, err := h.service.GetExplorationProgress(r.Context(), account.ID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, npc.ErrNoActiveSession):
		http.Error(w, "active world session required", http.StatusConflict)
	default:
		h.logger.Error("get exploration progress failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}
