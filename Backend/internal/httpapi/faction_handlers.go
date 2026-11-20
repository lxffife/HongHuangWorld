package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/faction"
)

type factionHandlers struct {
	authService auth.Provider
	service *faction.Service
	logger *slog.Logger
}

func (h *factionHandlers) accountID(w http.ResponseWriter, r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") { http.Error(w, "unauthorized", http.StatusUnauthorized); return "", false }
	account, err := h.authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil { http.Error(w, "unauthorized", http.StatusUnauthorized); return "", false }
	return account.ID, true
}

func (h *factionHandlers) createSect(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r); if !ok { return }
	var body struct { WorldID string `json:"world_id"`; Name string `json:"name"`; Description string `json:"description"` }
	if err := decodeJSON(w, r, &body); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.service.CreateSect(r.Context(), accountID, body.WorldID, body.Name, body.Description)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusCreated, result)
}

func (h *factionHandlers) mine(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r); if !ok { return }
	result, err := h.service.ListMine(r.Context(), accountID)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"factions": result})
}

func (h *factionHandlers) apply(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r); if !ok { return }
	var body struct { Message string `json:"message"` }
	if err := decodeJSON(w, r, &body); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	result, err := h.service.Apply(r.Context(), accountID, r.PathValue("factionID"), body.Message)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusCreated, result)
}

func (h *factionHandlers) applications(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r); if !ok { return }
	result, err := h.service.ListApplications(r.Context(), accountID, r.PathValue("factionID"))
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"applications": result})
}

func (h *factionHandlers) review(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r); if !ok { return }
	var body struct { Decision string `json:"decision"` }
	if err := decodeJSON(w, r, &body); err != nil { http.Error(w, "invalid request body", http.StatusBadRequest); return }
	err := h.service.ReviewApplication(r.Context(), accountID, r.PathValue("factionID"), r.PathValue("applicationID"), body.Decision)
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "decision": body.Decision})
}

func (h *factionHandlers) writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, faction.ErrInvalid): http.Error(w, "invalid faction request", http.StatusBadRequest)
	case errors.Is(err, faction.ErrNotFound): http.Error(w, "faction not found", http.StatusNotFound)
	case errors.Is(err, faction.ErrForbidden): http.Error(w, "faction permission denied", http.StatusForbidden)
	case errors.Is(err, faction.ErrAlreadyMember), errors.Is(err, faction.ErrPendingApplication): http.Error(w, err.Error(), http.StatusConflict)
	default:
		h.logger.Error("faction request failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
	}
}

func (h *factionHandlers) members(w http.ResponseWriter, r *http.Request) {
	accountID, ok := h.accountID(w, r)
	if !ok { return }
	result, err := h.service.ListMembers(r.Context(), accountID, r.PathValue("factionID"))
	if err != nil { h.writeError(w, err); return }
	writeJSON(w, http.StatusOK, map[string]any{"members": result})
}
