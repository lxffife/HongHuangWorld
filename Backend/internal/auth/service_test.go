package auth

import (
	"testing"
	"time"
)

func TestNewSessionToken(t *testing.T) {
	token, hash, expiresAt, err := newSessionToken(30 * 24 * time.Hour)
	if err != nil {
		t.Fatalf("newSessionToken returned error: %v", err)
	}
	if token == "" {
		t.Fatal("expected a non-empty token")
	}
	if len(hash) != 32 {
		t.Fatalf("expected 32-byte hash, got %d", len(hash))
	}
	if !expiresAt.After(time.Now()) {
		t.Fatal("expected expiry in the future")
	}
}

func TestUsernamePattern(t *testing.T) {
	valid := []string{"player_01", "abc", "A_USER_99"}
	for _, value := range valid {
		if !usernamePattern.MatchString(value) {
			t.Errorf("expected %q to be valid", value)
		}
	}
	invalid := []string{"ab", "has space", "name!", "this_username_is_far_too_long_for_the_limit"}
	for _, value := range invalid {
		if usernamePattern.MatchString(value) {
			t.Errorf("expected %q to be invalid", value)
		}
	}
}
