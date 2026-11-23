package httpapi

import (
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHellTrialProgressRequiresAuthentication(t *testing.T) {
	h := &hellTrialHandlers{logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	req := httptest.NewRequest(http.MethodGet, "/api/v1/characters/current/hell-trials", nil)
	res := httptest.NewRecorder()
	h.current(res, req)
	if res.Code != http.StatusUnauthorized { t.Fatalf("expected 401, got %d", res.Code) }
}

func TestHellTrialCompletionRequiresServerKey(t *testing.T) {
	h := &hellTrialHandlers{apiKey: "server-secret", logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/servers/hell-trials/completions", strings.NewReader(`{}`))
	res := httptest.NewRecorder()
	h.complete(res, req)
	if res.Code != http.StatusUnauthorized { t.Fatalf("expected 401, got %d", res.Code) }
}

func TestHellTrialCompletionRequiresNodeIdentity(t *testing.T) {
	h := &hellTrialHandlers{apiKey: "server-secret", logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/servers/hell-trials/completions", strings.NewReader(`{}`))
	req.Header.Set("X-World-Server-Key", "server-secret")
	res := httptest.NewRecorder()
	h.complete(res, req)
	if res.Code != http.StatusBadRequest { t.Fatalf("expected 400, got %d", res.Code) }
}

func TestHellTrialCompletionRejectsMalformedJSON(t *testing.T) {
	h := &hellTrialHandlers{apiKey: "server-secret", logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	req := httptest.NewRequest(http.MethodPost, "/api/v1/servers/hell-trials/completions", strings.NewReader("{"))
	req.Header.Set("X-World-Server-Key", "server-secret")
	req.Header.Set("X-World-Server-Node", "fengdu-world-01")
	res := httptest.NewRecorder()
	h.complete(res, req)
	if res.Code != http.StatusBadRequest { t.Fatalf("expected 400, got %d", res.Code) }
}
