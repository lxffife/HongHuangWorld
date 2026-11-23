package party

import (
 "strings"
 "testing"
)

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

func TestValidFocusTargetID(t *testing.T) {
 for _, id := range []string{"", "monster-uuid-123", "a"} {
  if !validFocusTargetID(id) { t.Errorf("valid focus target %q was rejected", id) }
 }
 for _, id := range []string{strings.Repeat("x", 97), "monster\ntarget", "monster\ttarget"} {
  if validFocusTargetID(id) { t.Errorf("invalid focus target %q was accepted", id) }
 }
}
