package gameadmin

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestSetServerNodeStatePreservesSessionConflict(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPatch || r.Header.Get("X-Game-Admin-Key") != "internal-test-key" {
			http.Error(w, "invalid internal request", http.StatusUnauthorized)
			return
		}
		w.WriteHeader(http.StatusConflict)
		_, _ = w.Write([]byte(`{"error":"node still has sessions","previous_state":"draining","remaining_sessions":3}`))
	}))
	defer server.Close()

	client := New(server.URL, "internal-test-key")
	_, err := client.SetServerNodeState(context.Background(), "node-1", "disabled")
	if !errors.Is(err, ErrNodeHasSessions) {
		t.Fatalf("expected ErrNodeHasSessions, got %v", err)
	}
	var conflict *NodeSessionsConflictError
	if !errors.As(err, &conflict) { t.Fatalf("expected typed session conflict, got %T", err) }
	if conflict.PreviousState != "draining" || conflict.RemainingSessions != 3 {
		t.Fatalf("unexpected conflict details: %+v", conflict)
	}
}
