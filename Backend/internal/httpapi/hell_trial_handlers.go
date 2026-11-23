package httpapi

import (
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/helltrial"
)

type hellTrialHandlers struct {
	authService auth.Provider
	service *helltrial.Service
	apiKey string
	logger *slog.Logger
}

func (h *hellTrialHandlers) current(w http.ResponseWriter, r *http.Request) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	account, err := h.authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	result, err := h.service.Current(r.Context(), account.ID)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, helltrial.ErrNoActiveSession):
		http.Error(w, "active underworld world session required", http.StatusConflict)
	case errors.Is(err, helltrial.ErrWrongWorld):
		http.Error(w, "hell trials are only available in the underworld", http.StatusConflict)
	case errors.Is(err, helltrial.ErrInvalid):
		http.Error(w, "invalid account", http.StatusBadRequest)
	default:
		h.logger.Error("get hell trial progress failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// enter records a floor entry reported by the WorldServer that owns the active session.
func (h *hellTrialHandlers) enter(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	if nodeKey == "" || len(nodeKey) > 96 {
		http.Error(w, "missing world server node identity", http.StatusBadRequest)
		return
	}
	var request helltrial.EntryRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid entry request", http.StatusBadRequest)
		return
	}
	result, err := h.service.RecordEntry(r.Context(), nodeKey, request)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, helltrial.ErrInvalid):
		http.Error(w, "invalid entry request", http.StatusBadRequest)
	case errors.Is(err, helltrial.ErrNoActiveSession):
		http.Error(w, "character is not active on this world server", http.StatusForbidden)
	case errors.Is(err, helltrial.ErrWrongWorld):
		http.Error(w, "hell trials are only available in the underworld", http.StatusForbidden)
	case errors.Is(err, helltrial.ErrWrongInstance):
		http.Error(w, "character is not inside the requested hell floor instance", http.StatusConflict)
	case errors.Is(err, helltrial.ErrFloorLocked):
		http.Error(w, "hell trial floor is locked", http.StatusConflict)
	case errors.Is(err, helltrial.ErrEntryIdempotencyConflict):
		http.Error(w, "entry event ID was already used for another character or floor", http.StatusConflict)
	default:
		h.logger.Error("record hell trial entry failed", "node_key", nodeKey, "character_id", request.CharacterID, "floor", request.Floor, "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

// complete is a trusted WorldServer callback, not a player-facing endpoint.
func (h *hellTrialHandlers) complete(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	if nodeKey == "" || len(nodeKey) > 96 {
		http.Error(w, "missing world server node identity", http.StatusBadRequest)
		return
	}
	var request helltrial.CompletionRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid completion request", http.StatusBadRequest)
		return
	}
	result, err := h.service.Complete(r.Context(), nodeKey, request)
	switch {
	case err == nil:
		writeJSON(w, http.StatusOK, result)
	case errors.Is(err, helltrial.ErrInvalid):
		http.Error(w, "invalid completion request", http.StatusBadRequest)
	case errors.Is(err, helltrial.ErrNoActiveSession):
		http.Error(w, "character is not active on this world server", http.StatusForbidden)
	case errors.Is(err, helltrial.ErrWrongWorld):
		http.Error(w, "hell trials are only available in the underworld", http.StatusForbidden)
	case errors.Is(err, helltrial.ErrWrongInstance):
		http.Error(w, "character is not inside the requested hell floor instance", http.StatusConflict)
	case errors.Is(err, helltrial.ErrFloorLocked):
		http.Error(w, "hell trial floor is locked", http.StatusConflict)
	case errors.Is(err, helltrial.ErrObjectiveIncomplete):
		http.Error(w, "hell trial objective is incomplete", http.StatusConflict)
	case errors.Is(err, helltrial.ErrGuardianAlive):
		http.Error(w, "hell trial guardian is still alive", http.StatusConflict)
	case errors.Is(err, helltrial.ErrAlreadyCompleted):
		http.Error(w, "hell trial floor already completed with another event", http.StatusConflict)
	default:
		h.logger.Error("complete hell trial failed", "node_key", nodeKey, "character_id", request.CharacterID, "floor", request.Floor, "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}
