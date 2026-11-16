package httpapi

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/soul"
)

type soulHandlers struct {
	authService *auth.Service
	soulService *soul.Service
	logger      *slog.Logger
}

type createSoulRequest struct {
	Name   string `json:"name"`
	Origin string `json:"origin"`
}

func (h *soulHandlers) create(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	var request createSoulRequest
	if err := decodeJSON(w, r, &request); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	created, err := h.soulService.Create(r.Context(), account.ID, request.Name, request.Origin)
	if err != nil {
		switch {
		case errors.Is(err, soul.ErrInvalid):
			http.Error(w, "soul name or origin is invalid", http.StatusBadRequest)
		case errors.Is(err, soul.ErrConflict):
			http.Error(w, "account already has a soul", http.StatusConflict)
		default:
			h.logger.Error("create soul failed", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
		return
	}
	writeJSON(w, http.StatusCreated, created)
}

func (h *soulHandlers) current(w http.ResponseWriter, r *http.Request) {
	account, ok := h.currentAccount(w, r)
	if !ok {
		return
	}
	current, err := h.soulService.Current(r.Context(), account.ID)
	if err != nil {
		if errors.Is(err, soul.ErrNotFound) {
			http.Error(w, "soul not found", http.StatusNotFound)
			return
		}
		h.logger.Error("load current soul failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, current)
}

func (h *soulHandlers) currentAccount(w http.ResponseWriter, r *http.Request) (auth.Account, bool) {
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
