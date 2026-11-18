package httpapi

import (
	"crypto/subtle"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/liflife/HongHuangWorld/Backend/internal/chat"
)

type chatServerHandlers struct {
	service *chat.Service
	apiKey string
	events *chatEventBus
	logger *slog.Logger
}

// poll returns a durable, ordered page for the authenticated WorldServer node.
// The client must persist both cursor fields only after it has accepted the page.
func (h *chatServerHandlers) poll(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	if nodeKey == "" {
		http.Error(w, "missing world server node identity", http.StatusBadRequest)
		return
	}

	var after time.Time
	afterRaw := strings.TrimSpace(r.URL.Query().Get("after"))
	afterID := strings.TrimSpace(r.URL.Query().Get("after_id"))
	if (afterRaw == "") != (afterID == "") {
		http.Error(w, "after and after_id must be supplied together", http.StatusBadRequest)
		return
	}
	if afterRaw != "" {
		parsed, err := time.Parse(time.RFC3339Nano, afterRaw)
		if err != nil {
			http.Error(w, "invalid chat cursor timestamp", http.StatusBadRequest)
			return
		}
		after = parsed
	}
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed < 1 || parsed > 100 {
			http.Error(w, "limit must be between 1 and 100", http.StatusBadRequest)
			return
		}
		limit = parsed
	}
	batch, err := h.service.ListForServer(r.Context(), nodeKey, after, afterID, limit)
	if err != nil {
		if err == chat.ErrInvalidServerCursor || err == chat.ErrInvalidInput {
			http.Error(w, "invalid chat poll request", http.StatusBadRequest)
			return
		}
		h.logger.Error("poll world server chat messages failed", "node_key", nodeKey, "error", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	nextAfter := afterRaw
	nextID := afterID
	if len(batch.Items) > 0 {
		nextAfter = batch.NextCreatedAt.UTC().Format(time.RFC3339Nano)
		nextID = batch.NextID
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"items": batch.Items,
		"next_cursor": map[string]string{"after": nextAfter, "after_id": nextID},
		"has_more": len(batch.Items) == limit,
	})
}

type chatServerSendRequest struct {
	SessionID string `json:"session_id"`
	CharacterID string `json:"character_id"`
	chat.SendRequest
}

// publish persists a public message after verifying the active session belongs
// to the authenticated WorldServer node.
func (h *chatServerHandlers) publish(w http.ResponseWriter, r *http.Request) {
	provided := r.Header.Get("X-World-Server-Key")
	if h.apiKey == "" || len(provided) != len(h.apiKey) ||
		subtle.ConstantTimeCompare([]byte(provided), []byte(h.apiKey)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	nodeKey := strings.TrimSpace(r.Header.Get("X-World-Server-Node"))
	if nodeKey == "" {
		http.Error(w, "missing world server node identity", http.StatusBadRequest)
		return
	}
	var req chatServerSendRequest
	if err := decodeJSON(w, r, &req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}
	item, err := h.service.SendFromServer(r.Context(), nodeKey, req.SessionID, req.CharacterID, req.SendRequest)
	if err != nil {
		switch {
		case err == chat.ErrInvalidInput:
			http.Error(w, "invalid chat request", http.StatusBadRequest)
		case err == chat.ErrNoCharacter:
			http.Error(w, "world session is not active for this node", http.StatusForbidden)
		case err == chat.ErrIdempotencyConflict:
			http.Error(w, "client_message_id already used with different content", http.StatusConflict)
		case err == chat.ErrRateLimited:
			http.Error(w, "chat rate limit exceeded", http.StatusTooManyRequests)
		case err == chat.ErrUnsupportedChannel:
			http.Error(w, "chat channel is not available yet", http.StatusNotImplemented)
		default:
			h.logger.Error("publish world server chat message failed", "node_key", nodeKey, "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
		}
		return
	}
	if h.events != nil {
		h.events.publish(item)
	}
	writeJSON(w, http.StatusCreated, map[string]any{"message": item})
}

