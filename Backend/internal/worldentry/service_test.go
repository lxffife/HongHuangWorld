package worldentry

import (
	"context"
	"encoding/json"
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

func TestPlayerSnapshotSerializesBirthInheritance(t *testing.T) {
	snapshot := PlayerSnapshot{
		CharacterID: "character-1",
		BirthInheritance: map[string]any{
			"dominant_attribute": "spirit",
			"source_growth_stage": float64(3),
		},
		Equipment: []map[string]any{
			{"slot": "weapon", "item_id": "iron_sword", "name": "铁剑", "quality": float64(2), "weapon_type": "sword"},
		},
	}
	encoded, err := json.Marshal(snapshot)
	if err != nil {
		t.Fatalf("marshal player snapshot: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal player snapshot: %v", err)
	}
	birth, ok := decoded["birth_inheritance"].(map[string]any)
	if !ok {
		t.Fatal("birth_inheritance was not included as an object")
	}
	if birth["dominant_attribute"] != "spirit" {
		t.Fatalf("dominant_attribute = %v, want spirit", birth["dominant_attribute"])
	}
	equipment, ok := decoded["equipment"].([]any)
	if !ok || len(equipment) != 1 {
		t.Fatalf("equipment = %v, want one equipped item", decoded["equipment"])
	}
	weapon, ok := equipment[0].(map[string]any)
	if !ok || weapon["slot"] != "weapon" || weapon["item_id"] != "iron_sword" || weapon["weapon_type"] != "sword" {
		t.Fatalf("weapon appearance = %v, want iron_sword in weapon slot", equipment[0])
	}
}

func TestWorldSnapshotsRejectInvalidMana(t *testing.T) {
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
		mana *int
	}{
		{name: "negative mana", mana: &negative},
		{name: "mana above server bound", mana: &tooLarge},
	} {
		t.Run(test.name, func(t *testing.T) {
			input := valid
			input.Mana = test.mana
			if err := service.SavePosition(context.Background(), input); !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("SavePosition error = %v, want ErrInvalidSessionSnapshot", err)
			}
			if err := service.SaveAndClose(context.Background(), input); !errors.Is(err, ErrInvalidSessionSnapshot) {
				t.Fatalf("SaveAndClose error = %v, want ErrInvalidSessionSnapshot", err)
			}
		})
	}
}

func TestWorldSnapshotAllowsOmittedMana(t *testing.T) {
	var input SessionSnapshot
	if input.Mana != nil {
		t.Fatal("omitted mana must remain nil for backward-compatible position-only snapshots")
	}
}
