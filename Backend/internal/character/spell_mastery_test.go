package character

import "testing"

func TestValidSpellMasteryReward(t *testing.T) {
	const eventID="550e8400-e29b-41d4-a716-446655440000"
	const sessionID="550e8400-e29b-41d4-a716-446655440001"
	const characterID="550e8400-e29b-41d4-a716-446655440002"
	tests:=[]struct{name,node string; reward SpellMasteryReward; want bool}{
		{"valid fireball","node-a",SpellMasteryReward{eventID,sessionID,characterID,"fireball",10},true},
		{"valid ice bolt","node-a",SpellMasteryReward{eventID,sessionID,characterID,"ice_bolt",1},true},
		{"empty node","",SpellMasteryReward{eventID,sessionID,characterID,"fireball",1},false},
		{"unknown spell","node-a",SpellMasteryReward{eventID,sessionID,characterID,"meteor",1},false},
		{"zero xp","node-a",SpellMasteryReward{eventID,sessionID,characterID,"fireball",0},false},
		{"over cap","node-a",SpellMasteryReward{eventID,sessionID,characterID,"fireball",11},false},
		{"bad event","node-a",SpellMasteryReward{"bad",sessionID,characterID,"fireball",1},false},
		{"bad session","node-a",SpellMasteryReward{eventID,"bad",characterID,"fireball",1},false},
		{"bad character","node-a",SpellMasteryReward{eventID,sessionID,"bad","fireball",1},false},
	}
	for _,tt:=range tests { t.Run(tt.name,func(t *testing.T){if got:=validSpellMasteryReward(tt.node,tt.reward);got!=tt.want{t.Fatalf("validSpellMasteryReward()=%v want %v",got,tt.want)}})}
}
