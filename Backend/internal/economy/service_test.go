package economy

import "testing"

func TestValidDeltaRequest(t *testing.T) {
	tests := []struct {
		name string
		account, currency, event, kind string
		delta int64
		want bool
	}{
		{"grant", "account-1", "nether_stone", "event-1", "grant", 50, true},
		{"spend", "account-1", "nether_stone", "event-2", "cultivation", -10, true},
		{"zero delta", "account-1", "nether_stone", "event-3", "grant", 0, false},
		{"missing account", "", "nether_stone", "event-4", "grant", 1, false},
		{"missing currency", "account-1", "", "event-5", "grant", 1, false},
		{"long event key", "account-1", "nether_stone", string(make([]byte, 129)), "grant", 1, false},
		{"unknown entry type", "account-1", "nether_stone", "event-6", "mint", 1, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := validDeltaRequest(tt.account, tt.currency, tt.event, tt.kind, tt.delta); got != tt.want {
				t.Fatalf("validDeltaRequest() = %v, want %v", got, tt.want)
			}
		})
	}
}
