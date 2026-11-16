package inventory

import "testing"

func TestValidUUID(t *testing.T) {
	tests := []struct { name, value string; want bool }{
		{"lowercase uuid", "00000000-0000-4000-8000-000000000001", true},
		{"uppercase uuid", "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", true},
		{"missing separators", "00000000000040008000000000000001", false},
		{"invalid hex", "00000000-0000-4000-8000-00000000000z", false},
		{"empty", "", false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := validUUID(test.value); got != test.want {
				t.Fatalf("validUUID(%q) = %v, want %v", test.value, got, test.want)
			}
		})
	}
}
