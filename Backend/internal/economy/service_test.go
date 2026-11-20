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
		{"negative grant", "account-1", "nether_stone", "event-7", "grant", -1, false},
		{"positive cultivation", "account-1", "nether_stone", "event-8", "cultivation", 1, false},
		{"standalone escrow lock", "account-1", "nether_stone", "event-9", "escrow_lock", -5, false},
		{"standalone exchange leg", "account-1", "nether_stone", "event-10", "exchange_out", -5, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := validDeltaRequest(tt.account, tt.currency, tt.event, tt.kind, tt.delta); got != tt.want {
				t.Fatalf("validDeltaRequest() = %v, want %v", got, tt.want)
			}
		})
	}
}
