package auth

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestHTTPClientAuthenticateUsesInternalServiceCredential(t *testing.T) {
	const token = "player-session-token"
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/api/v1/internal/auth/introspect" {
			t.Fatalf("unexpected request: %s %s", r.Method, r.URL.Path)
		}
		if r.Header.Get("Authorization") != "Bearer "+token {
			t.Fatalf("unexpected authorization header")
		}
		if r.Header.Get("X-Identity-Service-Key") != "service-secret" {
			t.Fatalf("missing identity service credential")
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(Account{ID:"account-1", Username:"player"})
	}))
	defer server.Close()

	client := NewHTTPClient(server.URL, "service-secret")
	account, err := client.Authenticate(context.Background(), token)
	if err != nil { t.Fatalf("Authenticate() error = %v", err) }
	if account.ID != "account-1" || account.Username != "player" {
		t.Fatalf("unexpected account: %+v", account)
	}
}

func TestHTTPClientAuthenticateRejectsUnauthorized(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
	}))
	defer server.Close()
	client := NewHTTPClient(server.URL, "service-secret")
	if _, err := client.Authenticate(context.Background(), "expired-token"); err != ErrUnauthorized {
		t.Fatalf("Authenticate() error = %v, want ErrUnauthorized", err)
	}
}

func TestHTTPClientLoginPreservesSessionResponse(t *testing.T) {
	expires := time.Now().UTC().Add(time.Hour).Truncate(time.Second)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var request credentialsRequest
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil { t.Fatal(err) }
		if request.Username != "player" || request.Password != "secret" { t.Fatalf("unexpected credentials payload") }
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(sessionResponse{Account:Account{ID:"account-1", Username:"player"}, Token:"new-token", ExpiresAt:expires})
	}))
	defer server.Close()
	client := NewHTTPClient(server.URL, "")
	account, token, gotExpiry, err := client.Login(context.Background(), "player", "secret")
	if err != nil { t.Fatalf("Login() error = %v", err) }
	if account.ID != "account-1" || token != "new-token" || !gotExpiry.Equal(expires) {
		t.Fatalf("unexpected login result: account=%+v token=%q expiry=%v", account, token, gotExpiry)
	}
}


func TestHTTPClientCachesSuccessfulIntrospectionBriefly(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests == 1 {
			w.Header().Set("Content-Type", "application/json")
			_ = json.NewEncoder(w).Encode(Account{ID:"account-1", Username:"player"})
			return
		}
		http.Error(w, "temporarily unavailable", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	client := NewHTTPClient(server.URL, "service-secret")
	first, err := client.Authenticate(context.Background(), "active-token")
	if err != nil { t.Fatalf("first Authenticate() error = %v", err) }
	second, err := client.Authenticate(context.Background(), "active-token")
	if err != nil { t.Fatalf("cached Authenticate() error = %v", err) }
	if first.ID != second.ID || requests != 1 {
		t.Fatalf("expected cached identity result, requests=%d first=%+v second=%+v", requests, first, second)
	}
}
