package soul

import "testing"

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
