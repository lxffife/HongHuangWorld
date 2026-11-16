package httpapi

import (
	"crypto/subtle"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
)

type worldEntryHandlers struct {
	authService  *auth.Service
	entryService *worldentry.Service
	apiKey       string
	logger       *slog.Logger
}

type redeemTicketRequest struct {
	NodeKey string `json:"node_key"`
	Ticket  string `json:"ticket"`
}

type closeWorldSessionRequest struct {
	NodeKey     string  `json:"node_key"`
	SessionID   string  `json:"session_id"`
	CharacterID string  `json:"character_id"`
	PositionX   float64 `json:"position_x"`
	PositionY   float64 `json:"position_y"`
	PositionZ   float64 `json:"position_z"`
	RotationY   float64 `json:"rotation_y"`
}

func (h *worldEntryHandlers) issue(w http.ResponseWriter, r *http.Request) {
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
	entry, err := h.entryService.Issue(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, worldentry.ErrNoAvailableServer) {
			http.Error(w, "no available world server for current character", http.StatusServiceUnavailable)
			return
		}
		h.logger.Error("issue world entry ticket failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, entry)
}

func (h *worldEntryHandlers) redeem(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) || subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	var request redeemTicketRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	snapshot, err := h.entryService.Redeem(r.Context(), request.NodeKey, request.Ticket)
	if err != nil {
		if errors.Is(err, worldentry.ErrInvalidTicket) {
			http.Error(w, "invalid or expired ticket", http.StatusUnauthorized)
			return
		}
		h.logger.Error("redeem world entry ticket failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, snapshot)
}


func (h *worldEntryHandlers) saveSnapshot(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var request closeWorldSessionRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	err := h.entryService.SavePosition(r.Context(), worldentry.SessionSnapshot{
		NodeKey: request.NodeKey, SessionID: request.SessionID, CharacterID: request.CharacterID,
		PositionX: request.PositionX, PositionY: request.PositionY, PositionZ: request.PositionZ,
		RotationY: request.RotationY,
	})
	if err != nil {
		if errors.Is(err, worldentry.ErrInvalidSessionSnapshot) {
			http.Error(w, "invalid or inactive world session snapshot", http.StatusConflict)
			return
		}
		h.logger.Error("save periodic world snapshot failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "saved"})
}

func (h *worldEntryHandlers) closeSession(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}

	var request closeWorldSessionRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	err := h.entryService.SaveAndClose(r.Context(), worldentry.SessionSnapshot{
		NodeKey: request.NodeKey, SessionID: request.SessionID, CharacterID: request.CharacterID,
		PositionX: request.PositionX, PositionY: request.PositionY, PositionZ: request.PositionZ,
		RotationY: request.RotationY,
	})
	if err != nil {
		if errors.Is(err, worldentry.ErrInvalidSessionSnapshot) {
			http.Error(w, "invalid or unauthorized world session snapshot", http.StatusBadRequest)
			return
		}
		h.logger.Error("save and close world session failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "closed"})
}
