package httpapi

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"log/slog"
	"net/http"
 "strings"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
)

func NewIdentityRouter(logger *slog.Logger, db *sql.DB) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{Status: "ok", Time: time.Now().UTC().Format(time.RFC3339)})
	})
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if db == nil || db.PingContext(ctx) != nil {
			http.Error(w, "identity database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, healthResponse{Status: "ready", Time: time.Now().UTC().Format(time.RFC3339)})
	})
	if db == nil {
		unavailable := func(w http.ResponseWriter, _ *http.Request) { http.Error(w, "service unavailable", http.StatusServiceUnavailable) }
		for _, route := range []string{"POST /api/v1/auth/register", "POST /api/v1/auth/login", "GET /api/v1/account/me", "POST /api/v1/internal/auth/introspect"} {
			mux.HandleFunc(route, unavailable)
		}
		return requestLogger(logger, mux)
	}
	service := auth.NewService(db)
	handlers := &authHandlers{service: service, logger: logger}
	mux.HandleFunc("POST /api/v1/auth/register", handlers.register)
	mux.HandleFunc("POST /api/v1/auth/login", handlers.login)
	mux.HandleFunc("GET /api/v1/account/me", handlers.me)
	internalKey := os.Getenv("IDENTITY_INTERNAL_API_KEY")
	adminHandlers := &identityAdminHandlers{service: auth.NewService(db), internalKey: internalKey, logger: logger}
	mux.HandleFunc("GET /api/v1/internal/admin/accounts", adminHandlers.listAccounts)
	mux.HandleFunc("PATCH /api/v1/internal/admin/accounts/{id}/status", adminHandlers.setAccountStatus)
	mux.HandleFunc("POST /api/v1/internal/auth/introspect", func(w http.ResponseWriter, r *http.Request) {
		providedKey := r.Header.Get("X-Identity-Service-Key")
		if internalKey == "" || len(providedKey) != len(internalKey) || subtle.ConstantTimeCompare([]byte(providedKey), []byte(internalKey)) != 1 {
			http.Error(w, "unauthorized service", http.StatusUnauthorized)
			return
		}
		header := r.Header.Get("Authorization")
		const prefix = "Bearer "
		if len(header) <= len(prefix) || header[:len(prefix)] != prefix {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		account, err := service.Authenticate(r.Context(), header[len(prefix):])
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		writeJSON(w, http.StatusOK, account)
	})
	return requestLogger(logger, mux)
}
