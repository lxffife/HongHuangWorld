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

func TestCalculateExchangeAmount(t *testing.T) {
	tests := []struct {
		name string
		amount, numerator, denominator int64
		feeBP int
		gross, fee, net int64
		wantErr bool
	}{
		{"official rational rate", 100, 4, 5, 100, 80, 1, 79, false},
		{"fee rounds up", 1, 1, 1, 100, 1, 1, 0, true},
		{"zero fee", 100, 3, 2, 0, 150, 0, 150, false},
		{"fraction rounds down", 3, 1, 2, 0, 1, 0, 1, false},
		{"zero input", 0, 1, 1, 0, 0, 0, 0, true},
		{"invalid fee", 10, 1, 1, 3001, 0, 0, 0, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			gross, fee, net, err := CalculateExchangeAmount(tt.amount, tt.numerator, tt.denominator, tt.feeBP)
			if (err != nil) != tt.wantErr { t.Fatalf("error = %v, wantErr %v", err, tt.wantErr) }
			if err == nil && (gross != tt.gross || fee != tt.fee || net != tt.net) {
				t.Fatalf("got (%d,%d,%d), want (%d,%d,%d)", gross, fee, net, tt.gross, tt.fee, tt.net)
			}
		})
	}
}

func TestResolveCultivationEfficiency(t *testing.T) {
	affinities := []CultivationAffinity{
		{TargetTag: "all", EfficiencyBP: 5000},
		{TargetTag: "race:ghost", EfficiencyBP: 10000},
		{TargetTag: "path:nether:orthodox", EfficiencyBP: 12000},
	}
	if got := ResolveCultivationEfficiency("fiat", false, affinities, []string{"race:ghost"}); got != 0 {
		t.Fatalf("fiat efficiency = %d, want 0", got)
	}
	if got := ResolveCultivationEfficiency("cultivation", false, affinities, []string{"race:ghost"}); got != 0 {
		t.Fatalf("disabled cultivation efficiency = %d, want 0", got)
	}
	if got := ResolveCultivationEfficiency("cultivation", true, affinities, []string{"race:ghost"}); got != 10000 {
		t.Fatalf("ghost efficiency = %d, want 10000", got)
	}
	if got := ResolveCultivationEfficiency("cultivation", true, affinities, []string{"path:nether:orthodox"}); got != 12000 {
		t.Fatalf("specific path efficiency = %d, want 12000", got)
	}
	if got := ResolveCultivationEfficiency("cultivation", true, affinities, []string{"race:human"}); got != 5000 {
		t.Fatalf("fallback efficiency = %d, want 5000", got)
	}
}
