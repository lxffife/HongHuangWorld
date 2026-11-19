package httpapi

import (
	"context"
	"database/sql"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

// NewChatRouter builds the standalone chat service HTTP surface. It deliberately
// does not register game, account-login, world-entry, inventory, or character
// mutation routes. Player tokens are verified by the independent Identity service.
func NewChatRouter(logger *slog.Logger, db *sql.DB) http.Handler {
	handler, _ := NewChatRouterWithShutdown(logger, db)
	return handler
}

// NewChatRouterWithShutdown also returns a cleanup function for long-lived
// transports such as the NATS connection.
func NewChatRouterWithShutdown(logger *slog.Logger, db *sql.DB) (http.Handler, func()) {
	return NewChatRouterWithServiceAndShutdown(logger, db, chat.NewService(db))
}

// NewChatRouterWithServiceAndShutdown injects the Chat-owned service and keeps HTTP transport setup independent.
func NewChatRouterWithServiceAndShutdown(logger *slog.Logger, db *sql.DB, chatService *chat.Service) (http.Handler, func()) {
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
			"GET /api/v1/chat/presence",
			"GET /api/v1/chat/presence/friends",
			"GET /api/v1/chat/presence/summary",
			"GET /api/v1/chat/presence/friends/summary",
			"GET /api/v1/chat/friends",
			"GET /api/v1/chat/friends/search",
			"GET /api/v1/chat/friends/requests",
			"POST /api/v1/chat/friends/requests",
			"POST /api/v1/chat/friends/requests/{requestID}/{decision}",
			"DELETE /api/v1/chat/friends/{characterID}",
			"GET /api/v1/chat/conversations/{characterID}/messages",
			"GET /api/v1/servers/chat/messages",
			"POST /api/v1/servers/chat/messages",
		} {
			mux.HandleFunc(route, unavailable)
		}
		return requestLogger(logger, mux), func() {}
	}

	authService := configuredAuthProvider()
	if chatService == nil {
		chatService = chat.NewService(db)
	}
	chatHub := newChatSocketHub()
	chatEvents := newChatEventBus(chatHub, chatService, logger)
	chatAPI := &chatHandlers{authService: authService, service: chatService, hub: chatHub, events: chatEvents, logger: logger}
	serverAPI := &chatServerHandlers{
		service: chatService,
		apiKey:  os.Getenv("WORLD_SERVER_API_KEY"),
		events: chatEvents,
		logger: logger,
	}
	mux.HandleFunc("POST /api/v1/chat/messages", chatAPI.send)
	mux.HandleFunc("GET /api/v1/chat/messages", chatAPI.list)
	mux.HandleFunc("GET /api/v1/chat/presence", chatAPI.presence)
	mux.HandleFunc("GET /api/v1/chat/presence/friends", chatAPI.friendPresence)
	mux.HandleFunc("GET /api/v1/chat/presence/summary", chatAPI.presenceSummary)
	mux.HandleFunc("GET /api/v1/chat/presence/friends/summary", chatAPI.friendPresenceSummary)
	mux.HandleFunc("GET /api/v1/chat/friends", chatAPI.listFriends)
	mux.HandleFunc("GET /api/v1/chat/friends/search", chatAPI.searchFriends)
	mux.HandleFunc("GET /api/v1/chat/friends/requests", chatAPI.incomingFriendRequests)
	mux.HandleFunc("POST /api/v1/chat/friends/requests", chatAPI.createFriendRequest)
	mux.HandleFunc("POST /api/v1/chat/friends/requests/{requestID}/{decision}", chatAPI.respondFriendRequest)
	mux.HandleFunc("DELETE /api/v1/chat/friends/{characterID}", chatAPI.removeFriend)
	mux.HandleFunc("GET /api/v1/chat/conversations/{characterID}/messages", chatAPI.conversationMessages)
	mux.HandleFunc("GET /api/v1/chat/socket", chatAPI.socket)
	mux.HandleFunc("GET /api/v1/servers/chat/messages", serverAPI.poll)
	mux.HandleFunc("POST /api/v1/servers/chat/messages", serverAPI.publish)

	return requestLogger(logger, mux), chatEvents.close
}
