package httpapi

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/character"
	"github.com/liflife/HongHuangWorld/Backend/internal/soul"
	"github.com/liflife/HongHuangWorld/Backend/internal/serverregistry"
	"github.com/liflife/HongHuangWorld/Backend/internal/world"
	"github.com/liflife/HongHuangWorld/Backend/internal/worldentry"
)

type healthResponse struct {
	Status string `json:"status"`
	Time   string `json:"time"`
}

func NewRouter(logger *slog.Logger, db *sql.DB) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, healthResponse{
			Status: "ok",
			Time:   time.Now().UTC().Format(time.RFC3339),
		})
	})
	mux.HandleFunc("GET /ready", func(w http.ResponseWriter, r *http.Request) {
		if db == nil {
			http.Error(w, "database is not configured", http.StatusServiceUnavailable)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := db.PingContext(ctx); err != nil {
			logger.Warn("readiness check failed", "error", err)
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, healthResponse{Status: "ready", Time: time.Now().UTC().Format(time.RFC3339)})
	})

	if db != nil {
		handlers := &authHandlers{service: auth.NewService(db), logger: logger}
		mux.HandleFunc("POST /api/v1/auth/register", handlers.register)
		mux.HandleFunc("POST /api/v1/auth/login", handlers.login)
		mux.HandleFunc("GET /api/v1/account/me", handlers.me)
		souls := &soulHandlers{authService: auth.NewService(db), soulService: soul.NewService(db), logger: logger}
		mux.HandleFunc("POST /api/v1/souls", souls.create)
		mux.HandleFunc("GET /api/v1/souls/current", souls.current)
		worlds := &worldHandlers{service: world.NewService(db), logger: logger}
		mux.HandleFunc("GET /api/v1/worlds", worlds.list)
		characters := &characterHandlers{authService: auth.NewService(db), characterService: character.NewService(db), logger: logger}
		mux.HandleFunc("GET /api/v1/cultivation/systems", characters.catalog)
		mux.HandleFunc("POST /api/v1/characters/first-life", characters.createFirstLife)
		mux.HandleFunc("GET /api/v1/characters/current", characters.current)
		mux.HandleFunc("GET /api/v1/characters/current/status", characters.currentStatus)
		mux.HandleFunc("POST /api/v1/characters/current/attributes/allocate", characters.allocateAttributePoints)
		servers := &serverHandlers{service: serverregistry.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/servers/heartbeat", servers.heartbeat)
		rewards := &characterRewardHandlers{characterService: character.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/servers/characters/rewards", rewards.apply)
		entry := &worldEntryHandlers{authService: auth.NewService(db), entryService: worldentry.NewService(db), apiKey: os.Getenv("WORLD_SERVER_API_KEY"), logger: logger}
		mux.HandleFunc("POST /api/v1/worlds/enter", entry.issue)
		mux.HandleFunc("POST /api/v1/servers/tickets/redeem", entry.redeem)
	} else {
		unavailable := func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "service unavailable", http.StatusServiceUnavailable)
		}
		mux.HandleFunc("POST /api/v1/auth/register", unavailable)
		mux.HandleFunc("POST /api/v1/auth/login", unavailable)
		mux.HandleFunc("GET /api/v1/account/me", unavailable)
		mux.HandleFunc("POST /api/v1/souls", unavailable)
		mux.HandleFunc("GET /api/v1/souls/current", unavailable)
		mux.HandleFunc("GET /api/v1/worlds", unavailable)
		mux.HandleFunc("GET /api/v1/cultivation/systems", unavailable)
		mux.HandleFunc("POST /api/v1/characters/first-life", unavailable)
		mux.HandleFunc("GET /api/v1/characters/current", unavailable)
		mux.HandleFunc("GET /api/v1/characters/current/status", unavailable)
		mux.HandleFunc("POST /api/v1/characters/current/attributes/allocate", unavailable)
		mux.HandleFunc("POST /api/v1/servers/heartbeat", unavailable)
		mux.HandleFunc("POST /api/v1/servers/characters/rewards", unavailable)
		mux.HandleFunc("POST /api/v1/worlds/enter", unavailable)
		mux.HandleFunc("POST /api/v1/servers/tickets/redeem", unavailable)
	}

	return requestLogger(logger, mux)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func requestLogger(logger *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		next.ServeHTTP(w, r)
		logger.Info("http request", "method", r.Method, "path", r.URL.Path, "duration_ms", time.Since(started).Milliseconds())
	})
}
