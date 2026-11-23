package helltrial

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestValidateCompletion(t *testing.T) {
	valid := CompletionRequest{
		SessionID: "123e4567-e89b-12d3-a456-426614174002",
		CharacterID: "123e4567-e89b-12d3-a456-426614174000",
		Floor: 1,
		EventID: "123e4567-e89b-12d3-a456-426614174001",
		ObjectiveComplete: true,
		GuardianDefeated: true,
		ObjectiveSnapshot: json.RawMessage(`{"floor":1,"objective_kills":3,"objective_required":3,"objective_complete":true,"participant_contribution":32,"minimum_contribution":32,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`),
	}
	if err := validateCompletion(valid); err != nil { t.Fatalf("valid completion rejected: %v", err) }
	cases := []struct{name string; mutate func(*CompletionRequest); want error}{
		{"invalid session UUID",func(r *CompletionRequest){r.SessionID="not-a-uuid"},ErrInvalid},
		{"invalid character UUID",func(r *CompletionRequest){r.CharacterID="not-a-uuid"},ErrInvalid},
		{"invalid event UUID",func(r *CompletionRequest){r.EventID="not-a-uuid"},ErrInvalid},
		{"floor below range",func(r *CompletionRequest){r.Floor=0},ErrInvalid},
		{"floor above range",func(r *CompletionRequest){r.Floor=19},ErrInvalid},
		{"missing snapshot",func(r *CompletionRequest){r.ObjectiveSnapshot=nil},ErrInvalid},
		{"non-object snapshot",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`[]`)},ErrInvalid},
		{"invalid snapshot",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{bad}`)},ErrInvalid},
		{"oversized snapshot",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"payload":"`+strings.Repeat("x",16*1024)+`"}`)},ErrInvalid},
		{"objective incomplete",func(r *CompletionRequest){r.ObjectiveComplete=false},ErrObjectiveIncomplete},
		{"guardian alive",func(r *CompletionRequest){r.GuardianDefeated=false},ErrGuardianAlive},
		{"wrong floor proof",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":2,"objective_kills":3,"objective_required":3,"objective_complete":true,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrInvalid},
		{"wrong guardian identity",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":3,"objective_required":3,"objective_complete":true,"guardian_id":"fake_guardian","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrInvalid},
		{"objective count below requirement",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":2,"objective_required":3,"objective_complete":true,"participant_contribution":32,"minimum_contribution":32,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrObjectiveIncomplete},
		{"objective count above requirement",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":4,"objective_required":3,"objective_complete":true,"participant_contribution":32,"minimum_contribution":32,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrObjectiveIncomplete},
		{"snapshot guardian alive",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":3,"objective_required":3,"objective_complete":true,"participant_contribution":32,"minimum_contribution":32,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":false,"source":"worldserver_authoritative_monster_death"}`)},ErrGuardianAlive},
		{"participant contribution below threshold",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":3,"objective_required":3,"objective_complete":true,"participant_contribution":31,"minimum_contribution":32,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrContributionInsufficient},
		{"forged contribution threshold",func(r *CompletionRequest){r.ObjectiveSnapshot=json.RawMessage(`{"floor":1,"objective_kills":3,"objective_required":3,"objective_complete":true,"participant_contribution":32,"minimum_contribution":1,"guardian_id":"hell_f01_tongue_jailer","guardian_defeated":true,"source":"worldserver_authoritative_monster_death"}`)},ErrInvalid},
	}
	for _,tc:=range cases { t.Run(tc.name,func(t *testing.T){req:=valid;tc.mutate(&req);if err:=validateCompletion(req);!errors.Is(err,tc.want){t.Fatalf("got %v, want %v",err,tc.want)}}) }
}

func TestMinimumContributionDamage(t *testing.T) {
	if got := minimumContribution(1); got != 32 {
		t.Fatalf("floor 1 threshold = %d, want 32", got)
	}
	if got := minimumContribution(2); got != 43 {
		t.Fatalf("floor 2 threshold = %d, want 43", got)
	}
	if got := minimumContribution(18); got != 233 {
		t.Fatalf("floor 18 threshold = %d, want 233", got)
	}
	if got := minimumContribution(0); got != 0 {
		t.Fatalf("invalid floor threshold = %d, want 0", got)
	}
}

func TestGuardianDefinitionCatalog(t *testing.T) {
	if len(guardianDefinitionIDs) != FloorCount {
		t.Fatalf("expected %d guardian definitions, got %d", FloorCount, len(guardianDefinitionIDs))
	}
	seen := make(map[string]struct{}, FloorCount)
	for floor, id := range guardianDefinitionIDs {
		if id == "" {
			t.Fatalf("floor %d has an empty guardian definition", floor+1)
		}
		if _, exists := seen[id]; exists {
			t.Fatalf("guardian definition %q is reused", id)
		}
		seen[id] = struct{}{}
	}
}

func TestFloorCountAndFinalBoundary(t *testing.T) {
	if FloorCount!=18 { t.Fatalf("expected 18 floors, got %d",FloorCount) }
	if min(19,FloorCount)!=18 { t.Fatal("floor 18 must be the terminal floor") }
	if min(4,FloorCount)!=4 { t.Fatal("intermediate floor unlock should be sequential") }
}

func TestValidateEntry(t *testing.T) {
	valid := EntryRequest{
		SessionID: "123e4567-e89b-12d3-a456-426614174002",
		CharacterID: "123e4567-e89b-12d3-a456-426614174000",
		Floor: 18,
		EventID: "123e4567-e89b-12d3-a456-426614174001",
	}
	if err := validateEntry(valid); err != nil { t.Fatalf("valid floor entry rejected: %v", err) }
	cases := []struct{name string; mutate func(*EntryRequest)}{
		{"invalid session",func(r *EntryRequest){r.SessionID="bad"}},
		{"invalid character",func(r *EntryRequest){r.CharacterID="bad"}},
		{"invalid event",func(r *EntryRequest){r.EventID="bad"}},
		{"floor zero",func(r *EntryRequest){r.Floor=0}},
		{"floor nineteen",func(r *EntryRequest){r.Floor=19}},
	}
	for _,tc:=range cases { t.Run(tc.name,func(t *testing.T){req:=valid;tc.mutate(&req);if err:=validateEntry(req);!errors.Is(err,ErrInvalid){t.Fatalf("got %v, want ErrInvalid",err)}}) }
}
