package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestGameAdminOnlineRejectsInvalidFiltersBeforeDatabaseAccess(t *testing.T) {
	handler := &gamePlayerAdminHandlers{
		apiKey: "test-internal-key",
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	cases := []struct {
		name  string
		query string
	}{
		{name: "query too long", query: "q=" + strings.Repeat("a", 97)},
		{name: "world id too long", query: "world_id=" + strings.Repeat("w", 65)},
		{name: "node key too long", query: "node_key=" + strings.Repeat("n", 97)},
		{name: "limit too large", query: "limit=101"},
		{name: "negative offset", query: "offset=-1"},
		{name: "offset too large", query: "offset=1000001"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/v1/internal/admin/players/online?"+tc.query, nil)
			req.Header.Set("X-Game-Admin-Key", "test-internal-key")
			res := httptest.NewRecorder()
			handler.online(res, req)
			if res.Code != http.StatusBadRequest {
				t.Fatalf("expected HTTP %d, got %d: %s", http.StatusBadRequest, res.Code, res.Body.String())
			}
		})
	}
}

func TestGameAdminOnlineRequiresInternalCredential(t *testing.T) {
	handler := &gamePlayerAdminHandlers{
		apiKey: "test-internal-key",
		logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/internal/admin/players/online", nil)
	res := httptest.NewRecorder()
	handler.online(res, req)
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("expected HTTP %d, got %d", http.StatusUnauthorized, res.Code)
	}
}
