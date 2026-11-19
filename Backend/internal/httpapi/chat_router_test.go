package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestChatRouterHealthWithoutDatabase(t *testing.T) {
	handler := NewChatRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)

	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusOK {
		t.Fatalf("health: expected %d, got %d", http.StatusOK, res.Code)
	}
}

func TestChatRouterReadinessWithoutDatabase(t *testing.T) {
	handler := NewChatRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)

	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusServiceUnavailable {
		t.Fatalf("ready: expected %d, got %d", http.StatusServiceUnavailable, res.Code)
	}
}

func TestChatRouterKeepsChatRoutesAndRejectsGameRoutes(t *testing.T) {
	handler := NewChatRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)

	for _, test := range []struct {
		method string
		path   string
		want   int
	}{
		{http.MethodPost, "/api/v1/chat/messages", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/messages", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/socket", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/preferences/friends", http.StatusServiceUnavailable},
		{http.MethodPut, "/api/v1/chat/preferences/friends", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/friends", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/friends/search?q=ab", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/friends/requests", http.StatusServiceUnavailable},
		{http.MethodPost, "/api/v1/chat/friends/requests", http.StatusServiceUnavailable},
		{http.MethodPost, "/api/v1/chat/friends/requests/00000000-0000-0000-0000-000000000001/accept", http.StatusServiceUnavailable},
		{http.MethodDelete, "/api/v1/chat/friends/00000000-0000-0000-0000-000000000001", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/chat/conversations/00000000-0000-0000-0000-000000000001/messages", http.StatusServiceUnavailable},
		{http.MethodGet, "/api/v1/servers/chat/messages", http.StatusServiceUnavailable},
		{http.MethodPost, "/api/v1/servers/chat/messages", http.StatusServiceUnavailable},
		{http.MethodPost, "/api/v1/auth/login", http.StatusNotFound},
		{http.MethodPost, "/api/v1/worlds/enter", http.StatusNotFound},
	} {
		t.Run(test.method+" "+test.path, func(t *testing.T) {
			req := httptest.NewRequest(test.method, test.path, nil)
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != test.want {
				t.Fatalf("expected %d, got %d", test.want, res.Code)
			}
		})
	}
}
