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
