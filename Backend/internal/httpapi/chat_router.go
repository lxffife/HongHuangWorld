package httpapi

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/auth"
	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

// NewChatRouter builds the standalone chat service HTTP surface. It deliberately
// does not register game, account-login, world-entry, inventory, or character
// mutation routes. Account tokens are verified against the shared session store.
func NewChatRouter(logger *slog.Logger, db *sql.DB) http.Handler {
	handler, _ := NewChatRouterWithShutdown(logger, db)
	return handler
}

// NewChatRouterWithShutdown also returns a cleanup function for long-lived
// transports such as the NATS connection.
func NewChatRouterWithShutdown(logger *slog.Logger, db *sql.DB) (http.Handler, func()) {
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
			logger.Warn("chat readiness check failed", "error", err)
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		writeJSON(w, http.StatusOK, healthResponse{
			Status: "ready",
			Time:   time.Now().UTC().Format(time.RFC3339),
		})
	})

	if db == nil {
		unavailable := func(w http.ResponseWriter, _ *http.Request) {
			http.Error(w, "service unavailable", http.StatusServiceUnavailable)
		}
		for _, route := range []string{
			"POST /api/v1/chat/messages",
			"GET /api/v1/chat/socket",
			"GET /api/v1/chat/messages",
			"GET /api/v1/servers/chat/messages",
			"POST /api/v1/servers/chat/messages",
		} {
			mux.HandleFunc(route, unavailable)
		}
		return requestLogger(logger, mux), func() {}
	}

	authService := configuredAuthProvider(db)
	chatService := chat.NewService(db)
	chatHub := newChatSocketHub()
	chatEvents := newChatEventBus(chatHub, chatService, logger)
	chatAPI := &chatHandlers{authService: authService, service: chatService, hub: chatHub, events: chatEvents, logger: logger}
	serverAPI := &chatServerHandlers{
		service: chatService,
		apiKey:  os.Getenv("WORLD_SERVER_API_KEY"),
		events: chatEvents,
		logger:  logger,
	}
	mux.HandleFunc("POST /api/v1/chat/messages", chatAPI.send)
	mux.HandleFunc("GET /api/v1/chat/messages", chatAPI.list)
	mux.HandleFunc("GET /api/v1/chat/socket", chatAPI.socket)
	mux.HandleFunc("GET /api/v1/servers/chat/messages", serverAPI.poll)
	mux.HandleFunc("POST /api/v1/servers/chat/messages", serverAPI.publish)

	return requestLogger(logger, mux), chatEvents.close
}
