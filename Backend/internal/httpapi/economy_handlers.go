package httpapi

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/economy"
)

type economyHandlers struct {
	authService auth.Provider
	service *economy.Service
	logger *slog.Logger
}

func (h *economyHandlers) catalog(w http.ResponseWriter, r *http.Request) {
	currencies, err := h.service.ListCurrencies(r.Context())
	if err != nil {
		h.logger.Error("list economy currencies failed", "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"currencies": currencies})
}

func (h *economyHandlers) wallet(w http.ResponseWriter, r *http.Request) {
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
	entries, err := h.service.Wallet(r.Context(), account.ID)
	if err != nil {
		h.logger.Error("load economy wallet failed", "account_id", account.ID, "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"balances": entries})
}
