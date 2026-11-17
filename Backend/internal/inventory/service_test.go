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
