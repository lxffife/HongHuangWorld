package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestChatServerPollRequiresWorldServerKey(t *testing.T) {
	handler := &chatServerHandlers{
		apiKey: "expected-secret",
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/servers/chat/messages", nil)
	res := httptest.NewRecorder()
	handler.poll(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected status %d, got %d", http.StatusUnauthorized, res.Code)
	}
}

func TestChatServerPollRejectsIncompleteCursor(t *testing.T) {
	handler := &chatServerHandlers{
		apiKey: "expected-secret",
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/servers/chat/messages?after=2026-11-18T10:00:00Z", nil)
	req.Header.Set("X-World-Server-Key", "expected-secret")
	req.Header.Set("X-World-Server-Node", "node-a")
	res := httptest.NewRecorder()
	handler.poll(res, req)
	if res.Code != http.StatusBadRequest {
		t.Fatalf("expected status %d, got %d", http.StatusBadRequest, res.Code)
	}
}
