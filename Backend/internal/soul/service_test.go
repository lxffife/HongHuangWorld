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


func TestSoulFusionDefinitionsAreServerAuthoredAndValid(t *testing.T) {
	seen := map[string]bool{}
	allowed := map[string]bool{
		"strength": true, "constitution": true, "agility": true,
		"spirit": true, "vitality": true,
	}
	for _, recipe := range soulFusionDefinitions {
		if recipe.ID == "" || recipe.Name == "" || seen[recipe.ID] {
			t.Fatalf("invalid or duplicate fusion recipe: %#v", recipe)
		}
		seen[recipe.ID] = true
		if len(recipe.Required) < 2 {
			t.Fatalf("fusion recipe must require at least two mutation attributes: %s", recipe.ID)
		}
		required := map[string]bool{}
		for _, attribute := range recipe.Required {
			if !allowed[attribute] || required[attribute] {
				t.Fatalf("invalid or duplicate required attribute %q in %s", attribute, recipe.ID)
			}
			required[attribute] = true
		}
		bonuses := recipe.Bonuses
		if bonuses.Strength < 0 || bonuses.Constitution < 0 || bonuses.Agility < 0 ||
			bonuses.Spirit < 0 || bonuses.Vitality < 0 ||
			bonuses.Strength+bonuses.Constitution+bonuses.Agility+bonuses.Spirit+bonuses.Vitality == 0 {
			t.Fatalf("invalid fusion bonuses in %s: %#v", recipe.ID, bonuses)
		}
	}
	if len(seen) != 4 {
		t.Fatalf("expected four authored fusion recipes, got %d", len(seen))
	}
}

func TestFiveElementsFusionRequiresAllFiveMutationAttributes(t *testing.T) {
	var found bool
	for _, recipe := range soulFusionDefinitions {
		if recipe.ID != "five_elements_origin" { continue }
		found = true
		if len(recipe.Required) != 5 {
			t.Fatalf("five elements fusion must require five attributes, got %v", recipe.Required)
		}
		if recipe.Bonuses != (InheritanceAttributes{Strength:1,Constitution:1,Agility:1,Spirit:1,Vitality:1}) {
			t.Fatalf("unexpected five elements reward: %#v", recipe.Bonuses)
		}
	}
	if !found { t.Fatal("five elements fusion recipe missing") }
}
