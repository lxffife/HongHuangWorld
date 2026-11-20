package inventory

import (
	"encoding/json"
	"testing"
)

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

func TestParseConsumableEffect(t *testing.T) {
	tests:=[]struct{name string; raw string; wantHealth,wantMana int; wantErr bool}{
		{"health restore",`{"heal_health":30}`,30,0,false},
		{"mana restore",`{"restore_mana":20}`,0,20,false},
		{"combined restore",`{"heal_health":10,"restore_mana":5}`,10,5,false},
		{"empty",`{}`,0,0,true},
		{"unsupported key",`{"damage":10}`,0,0,true},
		{"negative",`{"heal_health":-1}`,0,0,true},
		{"too large",`{"heal_health":10001}`,0,0,true},
		{"invalid json",`{"heal_health":}`,0,0,true},
	}
	for _,tt:=range tests {
		t.Run(tt.name,func(t *testing.T){
			health,mana,_,err:=parseConsumableEffect([]byte(tt.raw))
			if (err!=nil)!=tt.wantErr { t.Fatalf("error=%v wantErr=%v",err,tt.wantErr) }
			if err==nil && (health!=tt.wantHealth || mana!=tt.wantMana) { t.Fatalf("got health=%d mana=%d",health,mana) }
		})
	}
}

func TestValidEquipmentSlots(t *testing.T) {
	for _,slot:=range []string{"weapon","head","chest","legs","boots","accessory"} {
		if !validEquipmentSlots[slot] { t.Errorf("expected slot %q to be valid",slot) }
	}
	for _,slot:=range []string{"ring","hands","invalid",""} {
		if validEquipmentSlots[slot] { t.Errorf("expected slot %q to be invalid",slot) }
	}
}

func TestWeaponTypeSerializesForInventoryAndEquipment(t *testing.T) {
	stack := ItemStack{ItemID: "starter_iron_sword", WeaponType: "sword"}
	stackJSON, err := json.Marshal(stack)
	if err != nil { t.Fatalf("marshal inventory item: %v", err) }
	var stackDecoded map[string]any
	if err := json.Unmarshal(stackJSON, &stackDecoded); err != nil { t.Fatalf("unmarshal inventory item: %v", err) }
	if stackDecoded["weapon_type"] != "sword" { t.Fatalf("inventory weapon_type = %v, want sword", stackDecoded["weapon_type"]) }

	equipped := EquippedItem{Slot: "weapon", ItemID: "starter_iron_sword", WeaponType: "sword"}
	equippedJSON, err := json.Marshal(equipped)
	if err != nil { t.Fatalf("marshal equipped item: %v", err) }
	var equippedDecoded map[string]any
	if err := json.Unmarshal(equippedJSON, &equippedDecoded); err != nil { t.Fatalf("unmarshal equipped item: %v", err) }
	if equippedDecoded["weapon_type"] != "sword" { t.Fatalf("equipped weapon_type = %v, want sword", equippedDecoded["weapon_type"]) }
}

func TestCombatStatsSerializesCurrentAndMaximumMana(t *testing.T) {
	stats := CombatStats{Health: 80, MaxHealth: 100, Mana: 12, MaxMana: 40}
	encoded, err := json.Marshal(stats)
	if err != nil {
		t.Fatalf("marshal combat stats: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal combat stats: %v", err)
	}
	if decoded["mana"] != float64(12) || decoded["max_mana"] != float64(40) {
		t.Fatalf("mana fields = (%v, %v), want (12, 40)", decoded["mana"], decoded["max_mana"])
	}
}
