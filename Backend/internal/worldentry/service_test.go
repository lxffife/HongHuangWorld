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
