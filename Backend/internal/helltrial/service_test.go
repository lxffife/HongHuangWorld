package helltrial

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestValidateCompletion(t *testing.T) {
	valid := CompletionRequest{
		CharacterID: "123e4567-e89b-12d3-a456-426614174000",
		Floor: 1,
		EventID: "123e4567-e89b-12d3-a456-426614174001",
		ObjectiveComplete: true,
		GuardianDefeated: true,
		ObjectiveSnapshot: json.RawMessage(`{"kills":12,"required":12,"guardian_id":"floor_01_guardian"}`),
	}
	if err := validateCompletion(valid); err != nil { t.Fatalf("valid completion rejected: %v", err) }
	cases := []struct{name string; mutate func(*CompletionRequest); want error}{
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
	}
	for _,tc:=range cases { t.Run(tc.name,func(t *testing.T){req:=valid;tc.mutate(&req);if err:=validateCompletion(req);!errors.Is(err,tc.want){t.Fatalf("got %v, want %v",err,tc.want)}}) }
}

func TestFloorCountAndFinalBoundary(t *testing.T) {
	if FloorCount!=18 { t.Fatalf("expected 18 floors, got %d",FloorCount) }
	if min(19,FloorCount)!=18 { t.Fatal("floor 18 must be the terminal floor") }
	if min(4,FloorCount)!=4 { t.Fatal("intermediate floor unlock should be sequential") }
}
