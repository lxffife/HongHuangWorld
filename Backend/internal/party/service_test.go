package party

import "testing"

func TestValidLootMode(t *testing.T) {
	for _, mode := range []string{"personal", "free_for_all", "round_robin", "leader"} {
		if !validLootMode(mode) {
			t.Errorf("valid loot mode %q was rejected", mode)
		}
	}
	for _, mode := range []string{"", "random", "all", "leader_priority", "FREE_FOR_ALL"} {
		if validLootMode(mode) {
			t.Errorf("invalid loot mode %q was accepted", mode)
		}
	}
}
