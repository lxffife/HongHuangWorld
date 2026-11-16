package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHealth(t *testing.T) {
	handler := NewRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusOK { t.Fatalf("expected status %d, got %d", http.StatusOK, res.Code) }
	if got := res.Header().Get("Content-Type"); !strings.Contains(got, "application/json") { t.Fatalf("expected JSON content type, got %q", got) }
	if !strings.Contains(res.Body.String(), `"status":"ok"`) { t.Fatalf("unexpected health response: %s", res.Body.String()) }
}

func TestReadyWithoutDatabase(t *testing.T) {
	handler := NewRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	req := httptest.NewRequest(http.MethodGet, "/ready", nil)
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	if res.Code != http.StatusServiceUnavailable { t.Fatalf("expected status %d, got %d", http.StatusServiceUnavailable, res.Code) }
}

func TestEndpointsUnavailableWithoutDatabase(t *testing.T) {
	handler := NewRouter(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
	tests := []struct { method, path, body string }{
		{http.MethodPost, "/api/v1/auth/register", `{"username":"tester","password":"long-enough-password"}`},
		{http.MethodGet, "/api/v1/souls/current", ""},
		{http.MethodGet, "/api/v1/cultivation/systems", ""},
		{http.MethodPost, "/api/v1/characters/first-life", `{"name":"测试角色","world_id":"qingyun_human"}`},
		{http.MethodGet, "/api/v1/characters/current/status", ""},
		{http.MethodPost, "/api/v1/characters/current/breakthrough", "{}"},
		{http.MethodPost, "/api/v1/characters/current/attributes/allocate", `{"attribute":"strength","points":1}`},
		{http.MethodGet, "/api/v1/items", ""},
		{http.MethodGet, "/api/v1/characters/current/inventory", ""},
		{http.MethodPost, "/api/v1/servers/drops", "{}"},
		{http.MethodPost, "/api/v1/servers/drops/pickup", "{}"},
		{http.MethodPost, "/api/v1/servers/heartbeat", "{}"},
		{http.MethodPost, "/api/v1/servers/characters/rewards", "{}"},
		{http.MethodPost, "/api/v1/worlds/enter", "{}"},
	}
	for _, test := range tests {
		t.Run(test.method+" "+test.path, func(t *testing.T) {
			req := httptest.NewRequest(test.method, test.path, strings.NewReader(test.body))
			res := httptest.NewRecorder()
			handler.ServeHTTP(res, req)
			if res.Code != http.StatusServiceUnavailable { t.Fatalf("expected status %d, got %d", http.StatusServiceUnavailable, res.Code) }
		})
	}
}
