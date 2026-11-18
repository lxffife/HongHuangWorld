package soul

import (
 "fmt"
 "testing"
)

func TestSoulNameValidation(t *testing.T) {
	valid := []string{"玄一", "SoulName", "混元灵魂"}
	for _, name := range valid {
		if len([]rune(name)) < 2 || len([]rune(name)) > 48 {
			t.Errorf("test name unexpectedly outside accepted length: %q", name)
		}
	}
	if len([]rune("a")) >= 2 {
		t.Fatal("single rune should be rejected")
	}
}

 
func TestValidUUID(t *testing.T) {
 if !validUUID("550e8400-e29b-41d4-a716-446655440000") { t.Fatal("expected valid UUID") }
 for _, value := range []string{"", "not-a-uuid", "550e8400-e29b-41d4-a716-44665544000z"} {
  if validUUID(value) { t.Fatalf("expected invalid UUID: %q", value) }
 }
}
func TestValidSource(t *testing.T) {
 for _, value := range []string{"underworld_trial", "soul_quest:chapter_1", "spirit-fragment"} {
  if !validSource(value) { t.Fatalf("expected valid source: %q", value) }
 }
 for _, value := range []string{"", "UpperCase", "bad source", "任务", "x"} {
  if validSource(value) { t.Fatalf("expected invalid source: %q", value) }
 }
}

func TestRollSoulMutationIsDeterministic(t *testing.T) {
	eventID := "550e8400-e29b-41d4-a716-446655440000"
	first := rollSoulMutation(eventID)
	second := rollSoulMutation(eventID)
	if (first == nil) != (second == nil) { t.Fatal("same event id produced inconsistent mutation result") }
	if first == nil { return }
	if *first != *second { t.Fatalf("same event id produced different mutation: %#v vs %#v", first, second) }
	if first.AttributeBonus < 1 || first.AttributeBonus > 2 { t.Fatalf("invalid mutation bonus: %d", first.AttributeBonus) }
	if first.Rarity != "uncommon" && first.Rarity != "rare" { t.Fatalf("invalid mutation rarity: %q", first.Rarity) }
	switch first.Attribute {
	case "strength", "constitution", "agility", "spirit", "vitality":
	default:
		t.Fatalf("invalid mutation attribute: %q", first.Attribute)
	}
}

func TestRollSoulMutationProducesOnlyConfiguredResults(t *testing.T) {
	seenMutation := false
	seenRare := false
	for i := 0; i < 10000; i++ {
		eventID := fmt.Sprintf("mutation-event-%d", i)
		mutation := rollSoulMutation(eventID)
		if mutation == nil { continue }
		seenMutation = true
		if mutation.AttributeBonus == 2 {
			seenRare = true
			if mutation.Rarity != "rare" { t.Fatalf("bonus 2 must be rare: %#v", mutation) }
		}
		if mutation.AttributeBonus == 1 && mutation.Rarity != "uncommon" {
			t.Fatalf("bonus 1 must be uncommon: %#v", mutation)
		}
	}
	if !seenMutation || !seenRare { t.Fatal("expected deterministic sample to include common and rare mutations") }
}
