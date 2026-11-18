package chatprojection

import (
	"encoding/json"
	"testing"
	"time"
)

func TestValidEnvelope(t *testing.T) {
	event := envelope{
		Version: 1,
		EventID: "123e4567-e89b-12d3-a456-426614174000",
		EventType: "game.character.created.v1",
		AggregateID: "123e4567-e89b-12d3-a456-426614174001",
		AggregateVersion: 42,
		OccurredAt: time.Date(2026, 11, 18, 10, 0, 0, 0, time.UTC),
		Data: json.RawMessage(`{"character_id":"123e4567-e89b-12d3-a456-426614174001"}`),
	}
	if !validEnvelope(event) {
		t.Fatal("expected valid Game event envelope to pass")
	}
}

func TestValidEnvelopeRejectsUnknownType(t *testing.T) {
	event := envelope{
		Version: 1,
		EventID: "123e4567-e89b-12d3-a456-426614174000",
		EventType: "game.unknown.v1",
		AggregateID: "aggregate-1",
		AggregateVersion: 1,
		OccurredAt: time.Now().UTC(),
		Data: json.RawMessage(`{}`),
	}
	if validEnvelope(event) {
		t.Fatal("expected unsupported event type to be rejected")
	}
}

func TestValidUUID(t *testing.T) {
	if !validUUID("123e4567-e89b-12d3-a456-426614174000") {
		t.Fatal("expected canonical UUID to pass")
	}
	for _, value := range []string{"", "not-a-uuid", "123e4567e89b12d3a456426614174000", "123e4567-e89b-12d3-a456-42661417400z"} {
		if validUUID(value) {
			t.Fatalf("expected %q to be rejected", value)
		}
	}
}
