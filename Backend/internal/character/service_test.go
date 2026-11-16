package character

import "testing"

func TestValidUUID(t *testing.T) {
	tests := []struct {
		name  string
		value string
		want  bool
	}{
		{name: "valid lower case", value: "00000000-0000-4000-8000-000000000001", want: true},
		{name: "valid upper case", value: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", want: true},
		{name: "missing separators", value: "00000000000040008000000000000001", want: false},
		{name: "invalid hex", value: "00000000-0000-4000-8000-00000000000z", want: false},
		{name: "empty", value: "", want: false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := validUUID(test.value); got != test.want {
				t.Fatalf("validUUID(%q) = %v, want %v", test.value, got, test.want)
			}
		})
	}
}

func TestValidReward(t *testing.T) {
	const node = "qingyun-node-01"
	const eventID = "00000000-0000-4000-8000-000000000001"
	const sessionID = "00000000-0000-4000-8000-000000000003"
	const characterID = "00000000-0000-4000-8000-000000000002"

	tests := []struct {
		name   string
		reward Reward
		want   bool
	}{
		{
			name: "experience and cultivation",
			reward: Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, Experience: 100, Cultivation: 50},
			want: true,
		},
		{
			name: "attribute points only",
			reward: Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, AttributePoints: 1},
			want: true,
		},
		{
			name: "empty reward",
			reward: Reward{EventID: eventID, CharacterID: characterID},
			want: false,
		},
		{
			name: "negative experience",
			reward: Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, Experience: -1},
			want: false,
		},
		{
			name: "experience over cap",
			reward: Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, Experience: 1000001},
			want: false,
		},
		{
			name: "too many attribute points",
			reward: Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, AttributePoints: 1001},
			want: false,
		},
		{
			name: "invalid event id",
			reward: Reward{EventID: "not-a-uuid", SessionID: sessionID, CharacterID: characterID, Experience: 1},
			want: false,
		},
		{
			name: "invalid session id",
			reward: Reward{EventID: eventID, SessionID: "not-a-uuid", CharacterID: characterID, Experience: 1},
			want: false,
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := validReward(node, test.reward); got != test.want {
				t.Fatalf("validReward() = %v, want %v", got, test.want)
			}
		})
	}
	if validReward("", Reward{EventID: eventID, SessionID: sessionID, CharacterID: characterID, Experience: 1}) {
		t.Fatal("validReward accepted an empty node key")
	}
}

func TestCultivationStageThreshold(t *testing.T) {
	tests := []struct {
		name string
		current int64
		next int64
		targetStage int
		maxStage int
		want int64
	}{
		{name: "first stage threshold", current: 0, next: 10000, targetStage: 2, maxStage: 9, want: 2000},
		{name: "middle realm threshold rounds up", current: 10000, next: 100003, targetStage: 5, maxStage: 9, want: 55002},
		{name: "last stage leaves final step for realm breakthrough", current: 0, next: 10000, targetStage: 9, maxStage: 9, want: 9000},
		{name: "invalid stage", current: 100, next: 1000, targetStage: 10, maxStage: 9, want: 100},
		{name: "invalid range", current: 1000, next: 100, targetStage: 2, maxStage: 9, want: 1000},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := cultivationStageThreshold(test.current, test.next, test.targetStage, test.maxStage); got != test.want {
				t.Fatalf("cultivationStageThreshold() = %d, want %d", got, test.want)
			}
		})
	}
}
