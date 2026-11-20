package faction

import "testing"

func TestValidName(t *testing.T) {
	tests := []struct{name string; want bool}{
		{"", false}, {"A", false}, {"幽冥宗", true}, {"二十四字名称测试二十四字名称", false},
	}
	for _, tt := range tests {
		if got := validName(tt.name); got != tt.want { t.Fatalf("validName(%q)=%v want %v", tt.name, got, tt.want) }
	}
}
