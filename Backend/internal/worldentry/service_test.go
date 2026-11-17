package worldentry

import (
	"context"
	"errors"
	"math"
	"testing"
)

func TestSaveAndCloseRejectsInvalidSnapshots(t *testing.T) {
	service := NewService(nil)
	valid := SessionSnapshot{
		NodeKey: "node-1", SessionID: "00000000-0000-4000-8000-000000000001",
		CharacterID: "00000000-0000-4000-8000-000000000002",
		PositionX: 1, PositionY: 0, PositionZ: -1, RotationY: 0,
	}
	cases := []struct {
		name  string
		input SessionSnapshot
	}{
		{name: "missing node key", input: SessionSnapshot{SessionID: valid.SessionID, CharacterID: valid.CharacterID}},
		{name: "non-finite x", input: func() SessionSnapshot { v := valid; v.PositionX = math.NaN(); return v }()},
		{name: "outside horizontal bounds", input: func() SessionSnapshot { v := valid; v.PositionX = 101; return v }()},
		{name: "negative height", input: func() SessionSnapshot { v := valid; v.PositionY = -0.1; return v }()},
		{name: "non-finite rotation", input: func() SessionSnapshot { v := valid; v.RotationY = math.Inf(1); return v }()},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			err := service.SaveAndClose(context.Background(), test.input)
			if !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("expected ErrInvalidSessionSnapshot, got %v", err)
			}
		})
	}
}


func TestSavePositionRejectsInvalidSnapshots(t *testing.T) {
	service := NewService(nil)
	valid := SessionSnapshot{
		NodeKey: "node-1", SessionID: "00000000-0000-4000-8000-000000000001",
		CharacterID: "00000000-0000-4000-8000-000000000002",
		PositionX: 1, PositionY: 0, PositionZ: -1, RotationY: 0,
	}
	cases := []struct {
		name  string
		input SessionSnapshot
	}{
		{name: "missing session", input: func() SessionSnapshot { v := valid; v.SessionID = ""; return v }()},
		{name: "non-finite z", input: func() SessionSnapshot { v := valid; v.PositionZ = math.Inf(1); return v }()},
		{name: "outside horizontal bounds", input: func() SessionSnapshot { v := valid; v.PositionZ = -101; return v }()},
		{name: "height exceeds world bounds", input: func() SessionSnapshot { v := valid; v.PositionY = 101; return v }()},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			err := service.SavePosition(context.Background(), test.input)
			if !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("expected ErrInvalidSessionSnapshot, got %v", err)
			}
		})
	}
}

func TestWorldSnapshotsRejectInvalidHealth(t *testing.T) {
	service := NewService(nil)
	valid := SessionSnapshot{
		NodeKey: "node-1", SessionID: "00000000-0000-4000-8000-000000000001",
		CharacterID: "00000000-0000-4000-8000-000000000002",
		PositionX: 1, PositionY: 0, PositionZ: -1, RotationY: 0,
	}
	negative := -1
	tooLarge := 100001
	for _, test := range []struct {
		name string
		health *int
	}{
		{name: "negative health", health: &negative},
		{name: "health above server bound", health: &tooLarge},
	} {
		t.Run(test.name, func(t *testing.T) {
			input := valid
			input.Health = test.health
			if err := service.SavePosition(context.Background(), input); !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("SavePosition error = %v, want ErrInvalidSessionSnapshot", err)
			}
			if err := service.SaveAndClose(context.Background(), input); !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("SaveAndClose error = %v, want ErrInvalidSessionSnapshot", err)
			}
		})
	}
}

func TestWorldSnapshotAllowsOmittedHealth(t *testing.T) {
	var input SessionSnapshot
	if input.Health != nil {
		t.Fatal("omitted health must remain nil for backward-compatible position-only snapshots")
	}
}
