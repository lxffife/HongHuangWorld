package database

import (
	"context"
	"testing"
)

func TestOpenPostgresRequiresURL(t *testing.T) {
	_, err := OpenPostgres(context.Background(), "")
	if err == nil {
		t.Fatal("expected an error when DATABASE_URL is empty")
	}
}
