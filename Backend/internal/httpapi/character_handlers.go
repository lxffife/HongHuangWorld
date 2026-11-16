package httpapi

import (
	"database/sql"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/character"
)

type characterHandlers struct {
	authService      *auth.Service
	characterService *character.Service
	logger           *slog.Logger
}

type createCharacterRequest struct {
	Name    string `json:"name"`
	WorldID string `json:"world_id"`
	RaceID  string `json:"race_id"`
}

func (h *characterHandlers) createFirstLife(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request createCharacterRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	created, err := h.characterService.CreateFirstLife(r.Context(), account.ID, request.Name, request.WorldID, request.RaceID)
	if err != nil {
		switch {
		case errors.Is(err, character.ErrInvalid):
			http.Error(w, "character name or world id is invalid", http.StatusBadRequest)
		case errors.Is(err, character.ErrSoulRequired):
			http.Error(w, "create a soul profile first", http.StatusConflict)
		case errors.Is(err, character.ErrWorldInvalid):
			http.Error(w, "world is unavailable", http.StatusBadRequest)
		case errors.Is(err, character.ErrExists):
			http.Error(w, "first-life character already exists", http.StatusConflict)
		default:
			h.logger.Error("create first-life character failed", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (h *characterHandlers) currentStatus(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	status, err := h.characterService.CurrentStatus(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "character status not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current character status failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, status)
}

func (h *characterHandlers) current(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	current, err := h.characterService.Current(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			http.Error(w, "character not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current character failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, current)
}

func (h *characterHandlers) currentAccount(w http.ResponseWriter, r *http.Request) (auth.Account, bool) {
	header := r.Header.Get("Authorization")
	if !strings.HasPrefix(header, "Bearer ") {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return auth.Account{}, false
	}
	account, err := h.authService.Authenticate(r.Context(), strings.TrimSpace(strings.TrimPrefix(header, "Bearer ")))
	if err != nil {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return auth.Account{}, false
	}
	return account, true
}
