package faction

import "testing"

func TestValidName(t *testing.T) {
	tests := []struct{name string; want bool}{
		{"", false}, {"A", false}, {"幽冥宗", true}, {"一二三四五六七八九十一二三四五六七八九十一二三四五六", false},
	}
	for _, tt := range tests {
		if got := validName(tt.name); got != tt.want { t.Fatalf("validName(%q)=%v want %v", tt.name, got, tt.want) }
	}
}

func TestCanManageRole(t *testing.T) {
	for _, role := range []string{"leader", "officer"} {
		if !canManageRole(role) { t.Fatalf("%s should manage faction applications", role) }
	}
	for _, role := range []string{"member", "guest", ""} {
		if canManageRole(role) { t.Fatalf("%s must not manage faction applications", role) }
	}
}
