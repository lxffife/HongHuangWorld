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

func TestValidConsumableRequest(t *testing.T) {
	valid := ItemUseRequest{RequestID: "00000000-0000-4000-8000-000000000001", ItemID: "small_mana_pill", Quantity: 1}
	if !validConsumableRequest(valid) { t.Fatal("expected valid consumable request") }
	invalid := []ItemUseRequest{
		{ItemID: valid.ItemID, Quantity: 1},
		{RequestID: valid.RequestID, Quantity: 1},
		{RequestID: valid.RequestID, ItemID: valid.ItemID, Quantity: 0},
		{RequestID: valid.RequestID, ItemID: valid.ItemID, Quantity: 21},
	}
	for i, request := range invalid {
		if validConsumableRequest(request) { t.Errorf("invalid request %d accepted", i) }
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

func TestConsumableReplayReturnsCurrentResourcesWithoutApplyingAgain(t *testing.T) {
	request := ItemUseRequest{
		RequestID: "00000000-0000-4000-8000-000000000001",
		ItemID: "small_mana_pill",
		Quantity: 2,
	}
	result := consumableReplayResult(request, 75, 100, 42, 60)
	if result.Applied {
		t.Fatal("idempotent replay must not report a second application")
	}
	if result.ItemID != request.ItemID || result.Quantity != request.Quantity {
		t.Fatalf("replay identity = (%q, %d), want (%q, %d)", result.ItemID, result.Quantity, request.ItemID, request.Quantity)
	}
	if result.Health != 75 || result.MaxHealth != 100 || result.Mana != 42 || result.MaxMana != 60 {
		t.Fatalf("replay resources = hp %d/%d mp %d/%d", result.Health, result.MaxHealth, result.Mana, result.MaxMana)
	}
	if result.HealthRestored != 0 || result.ManaRestored != 0 {
		t.Fatalf("replay must not report restored values: hp=%d mp=%d", result.HealthRestored, result.ManaRestored)
	}
}

func TestItemUseResultSerializesAuthoritativeResources(t *testing.T) {
	result := ItemUseResult{
		Applied: true, ItemID: "small_mana_pill", Quantity: 1,
		ManaRestored: 20, ManaEffect: 25, HealthEffect: 15, Mana: 40, MaxMana: 60,
	}
	encoded, err := json.Marshal(result)
	if err != nil { t.Fatalf("marshal item use result: %v", err) }
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil { t.Fatalf("unmarshal item use result: %v", err) }
	if decoded["mana_restored"] != float64(20) || decoded["mana_effect"] != float64(25) || decoded["health_effect"] != float64(15) || decoded["mana"] != float64(40) || decoded["max_mana"] != float64(60) {
		t.Fatalf("resource fields = restored:%v mana:%v max:%v", decoded["mana_restored"], decoded["mana"], decoded["max_mana"])
	}
}

func TestEquipmentSetBonusUsesHighestUnlockedTier(t *testing.T) {
	tiers := map[int]map[string]int{
		2: {"attack": 5},
		4: {"attack": 12, "defense": 8},
	}
	bonus, ok := equipmentSetBonusForCount(tiers, 1)
	if ok || bonus != nil { t.Fatalf("one piece should unlock no tier: %v, %v", bonus, ok) }
	bonus, ok = equipmentSetBonusForCount(tiers, 3)
	if !ok || bonus["attack"] != 5 || len(bonus) != 1 { t.Fatalf("three pieces should use tier 2: %v, %v", bonus, ok) }
	bonus, ok = equipmentSetBonusForCount(tiers, 4)
	if !ok || bonus["attack"] != 12 || bonus["defense"] != 8 { t.Fatalf("four pieces should use tier 4 only: %v, %v", bonus, ok) }
	bonus, ok = equipmentSetBonusForCount(tiers, 6)
	if !ok || bonus["attack"] != 12 { t.Fatalf("extra pieces should retain highest tier: %v, %v", bonus, ok) }
}

func TestEquipmentSetBonusIgnoresInvalidThresholds(t *testing.T) {
	tiers := map[int]map[string]int{0: {"attack": 99}, -1: {"attack": 88}, 2: {"attack": 5}}
	bonus, ok := equipmentSetBonusForCount(tiers, 2)
	if !ok || bonus["attack"] != 5 { t.Fatalf("invalid thresholds must be ignored: %v, %v", bonus, ok) }
	if bonus, ok := equipmentSetBonusForCount(tiers, 0); ok || bonus != nil { t.Fatalf("zero pieces should unlock nothing: %v, %v", bonus, ok) }
}

func TestEquipmentPrimaryAttributesApplyTheirCombatEffects(t *testing.T) {
	stats := CombatStats{Attack: 20, Defense: 3, MaxHealth: 100, Health: 80, MaxMana: 40, Mana: 20, MovementSpeed: 5}
	bonuses := map[string]int{
		"strength": 2, "constitution": 3, "agility": 4, "spirit": 5, "vitality": 6,
	}
	if err := applyEquipmentStatBonuses(&stats, bonuses); err != nil {
		t.Fatalf("apply equipment bonuses: %v", err)
	}
	if stats.Strength != 2 || stats.Constitution != 3 || stats.Agility != 4 || stats.Spirit != 5 || stats.Vitality != 6 {
		t.Fatalf("primary attributes not applied: %+v", stats)
	}
	if stats.Attack != 24 || stats.Defense != 9 || stats.MaxHealth != 160 || stats.MaxMana != 90 {
		t.Fatalf("derived combat stats = attack:%d defense:%d max_health:%d max_mana:%d", stats.Attack, stats.Defense, stats.MaxHealth, stats.MaxMana)
	}
	if stats.MovementSpeed < 5.1999 || stats.MovementSpeed > 5.2001 {
		t.Fatalf("movement speed = %v, want 5.2", stats.MovementSpeed)
	}
	if stats.Health != 80 || stats.Mana != 20 {
		t.Fatalf("equipping gear must not directly restore current resources: health=%d mana=%d", stats.Health, stats.Mana)
	}
}

func TestEquipmentSecondaryBonusesRemainAdditive(t *testing.T) {
	stats := CombatStats{Attack: 10, Defense: 2, MaxHealth: 50, MaxMana: 10, MovementSpeed: 5}
	bonuses := map[string]int{
		"strength": 1, "attack": 3, "vitality": 2, "defense": 4,
		"constitution": 1, "max_health": 7, "agility": 2, "movement_speed": 1,
	}
	if err := applyEquipmentStatBonuses(&stats, bonuses); err != nil {
		t.Fatalf("apply equipment bonuses: %v", err)
	}
	if stats.Attack != 15 || stats.Defense != 8 || stats.MaxHealth != 77 || stats.MovementSpeed < 6.0999 || stats.MovementSpeed > 6.1001 {
		t.Fatalf("hybrid equipment effects = %+v", stats)
	}
}

func TestEquipmentAttributeBonusesRejectExtremeValues(t *testing.T) {
	stats := CombatStats{Attack: 10}
	if err := applyEquipmentStatBonuses(&stats, map[string]int{"strength": 100001}); err == nil {
		t.Fatal("expected extreme equipment bonus to be rejected")
	}
	if err := applyEquipmentStatBonuses(nil, map[string]int{}); err == nil {
		t.Fatal("expected nil combat stats to be rejected")
	}
}

func TestCombatStatsSerializesAuthoritativeMovementSpeed(t *testing.T) {
	stats := CombatStats{MovementSpeed: 5.75}
	encoded, err := json.Marshal(stats)
	if err != nil {
		t.Fatalf("marshal combat stats: %v", err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("unmarshal combat stats: %v", err)
	}
	if decoded["movement_speed"] != 5.75 {
		t.Fatalf("movement_speed = %v, want 5.75", decoded["movement_speed"])
	}
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

func TestLiveConsumableResourcesAcceptEquipmentCaps(t *testing.T) {
	valid := []LiveConsumableResources{
		{Health: 140, MaxHealth: 180, Mana: 75, MaxMana: 100},
		{Health: 80, MaxHealth: 80, Mana: 0, MaxMana: 0},
		// Unequipping a bonus may lower the effective cap below the base cap.
		{Health: 60, MaxHealth: 60, Mana: 20, MaxMana: 20},
	}
	for i, resources := range valid {
		if !validLiveConsumableResources(resources) { t.Errorf("valid live resources %d rejected: %+v", i, resources) }
	}
	invalid := []LiveConsumableResources{
		{Health: -1, MaxHealth: 100, Mana: 0, MaxMana: 20},
		{Health: 101, MaxHealth: 100, Mana: 0, MaxMana: 20},
		{Health: 0, MaxHealth: 0, Mana: 0, MaxMana: 20},
		{Health: 0, MaxHealth: 10000001, Mana: 0, MaxMana: 20},
		{Health: 0, MaxHealth: 100, Mana: 21, MaxMana: 20},
	}
	for i, resources := range invalid {
		if validLiveConsumableResources(resources) { t.Errorf("invalid live resources %d accepted: %+v", i, resources) }
	}
}

func TestConsumableRestorationUsesEffectiveEquipmentCaps(t *testing.T) {
	request := ItemUseRequest{ItemID: "greater_potion", Quantity: 2}
	live := LiveConsumableResources{Health: 140, MaxHealth: 180, Mana: 75, MaxMana: 100}
	result := applyLiveConsumableEffect(request, live, 30, 20)
	if result.Health != 180 || result.MaxHealth != 180 || result.HealthRestored != 40 {
		t.Fatalf("health restoration ignored equipment cap: %+v", result)
	}
	if result.Mana != 100 || result.MaxMana != 100 || result.ManaRestored != 25 {
		t.Fatalf("mana restoration ignored equipment cap: %+v", result)
	}
	// A lower effective cap after unequipping must never leave resources above it.
	lower := applyLiveConsumableEffect(request, LiveConsumableResources{Health: 60, MaxHealth: 60, Mana: 20, MaxMana: 20}, 30, 20)
	if lower.Health != 60 || lower.Mana != 20 || lower.HealthRestored != 0 || lower.ManaRestored != 0 {
		t.Fatalf("restoration exceeded reduced equipment caps: %+v", lower)
	}
}

func TestLiveConsumableEffectReportsRequestedAmountForLateApplication(t *testing.T) {
	request := ItemUseRequest{ItemID: "greater_potion", Quantity: 2}
	live := LiveConsumableResources{Health: 180, MaxHealth: 180, Mana: 100, MaxMana: 100}
	result := applyLiveConsumableEffect(request, live, 30, 20)
	if result.HealthRestored != 0 || result.ManaRestored != 0 {
		t.Fatalf("resources already full at request time should have zero immediate restore: %+v", result)
	}
	if result.HealthEffect != 60 || result.ManaEffect != 40 {
		t.Fatalf("effect amounts = health:%d mana:%d, want 60/40", result.HealthEffect, result.ManaEffect)
	}
}


func TestEquipmentInstancePayloadSerializesAffixIdentityAndRolledStats(t *testing.T) {
	item := ItemStack{
		InstanceID: "00000000-0000-4000-8000-000000000001",
		ItemID: "starter_iron_sword", Name: "铁剑", ItemType: "equipment",
		Quality: 4, Quantity: 1,
		RolledStats: map[string]int{"attack": 5, "strength": 2},
		Affixes: []EquipmentAffix{{ID: "weapon_attack_keen", Name: "锋锐", StatKey: "attack", Value: 5}},
	}
	encoded, err := json.Marshal(item)
	if err != nil { t.Fatalf("marshal equipment instance: %v", err) }
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil { t.Fatalf("decode equipment instance: %v", err) }
	if decoded["instance_id"] != item.InstanceID { t.Fatalf("instance_id = %v", decoded["instance_id"]) }
	rolled, ok := decoded["rolled_stats"].(map[string]any)
	if !ok || rolled["attack"] != float64(5) || rolled["strength"] != float64(2) {
		t.Fatalf("rolled_stats = %v", decoded["rolled_stats"])
	}
	affixes, ok := decoded["affixes"].([]any)
	if !ok || len(affixes) != 1 { t.Fatalf("affixes = %v", decoded["affixes"]) }
	affix, ok := affixes[0].(map[string]any)
	if !ok || affix["id"] != "weapon_attack_keen" || affix["value"] != float64(5) {
		t.Fatalf("affix payload = %v", affixes[0])
	}
}

func TestSecureRandomIntStaysWithinExclusiveUpperBound(t *testing.T) {
	for i := 0; i < 128; i++ {
		value, err := secureRandomInt(7)
		if err != nil { t.Fatalf("secureRandomInt: %v", err) }
		if value < 0 || value >= 7 { t.Fatalf("random value %d outside [0,7)", value) }
	}
	if _, err := secureRandomInt(0); err == nil { t.Fatal("zero upper bound must be rejected") }
}


func TestEquipmentAffixCountScalesWithQuality(t *testing.T) {
	tests := []struct{ quality, want int }{
		{0, 0}, {1, 1}, {2, 1}, {3, 2}, {4, 2}, {5, 3}, {6, 3},
	}
	for _, test := range tests {
		if got := equipmentAffixRollCount(test.quality); got != test.want {
			t.Errorf("equipmentAffixRollCount(%d) = %d, want %d", test.quality, got, test.want)
		}
	}
}

func TestRolledEquipmentBonusesUseAuthoritativeCombatStatPipeline(t *testing.T) {
	stats := CombatStats{Attack: 20, Defense: 5, MaxHealth: 100, MaxMana: 30, MovementSpeed: 5}
	rolled := map[string]int{"attack": 4, "strength": 2, "vitality": 1, "spirit": 2, "movement_speed": 1}
	if err := applyEquipmentStatBonuses(&stats, rolled); err != nil {
		t.Fatalf("apply rolled affixes: %v", err)
	}
	if stats.Attack != 28 || stats.Defense != 6 || stats.MaxHealth != 105 || stats.MaxMana != 50 {
		t.Fatalf("rolled combat stats = %+v", stats)
	}
	if stats.MovementSpeed < 5.9999 || stats.MovementSpeed > 6.0001 {
		t.Fatalf("rolled movement speed = %v, want 6.0", stats.MovementSpeed)
	}
}


func TestInventorySlotAvailability(t *testing.T) {
	tests:=[]struct{name string;used,max int;needsNew,want bool}{
		{"free slot",39,40,true,true},
		{"last slot",40,40,true,false},
		{"stack merge at capacity",40,40,false,true},
		{"zero capacity",0,0,true,false},
		{"negative used", -1,40,false,false},
		{"expanded inventory",40,60,true,true},
	}
	for _,test:=range tests{t.Run(test.name,func(t *testing.T){
		if got:=inventorySlotAvailable(test.used,test.max,test.needsNew);got!=test.want{
			t.Fatalf("inventorySlotAvailable(%d,%d,%t)=%t want %t",test.used,test.max,test.needsNew,got,test.want)
		}
	})}
}

func TestEquipmentSalvageYieldScalesWithQuality(t *testing.T) {
	tests:=[]struct{name string;base,quality,bonus,max,want int;valid bool}{
		{"base quality",2,1,1,99,2,true},
		{"higher quality",2,3,1,99,4,true},
		{"top quality",2,5,1,99,6,true},
		{"stack overflow",2,5,1,5,0,false},
		{"invalid quality",2,6,1,99,0,false},
		{"zero base",0,2,1,99,0,false},
	}
	for _,test:=range tests{t.Run(test.name,func(t *testing.T){
		got,valid:=equipmentSalvageYield(test.base,test.quality,test.bonus,test.max)
		if got!=test.want||valid!=test.valid{t.Fatalf("yield=(%d,%t), want (%d,%t)",got,valid,test.want,test.valid)}
	})}
}

func TestEquipmentEnhancementQualityCaps(t *testing.T) {
	want := []int{0, 3, 5, 8, 10, 12}
	for quality := 0; quality <= 5; quality++ {
		if got := enhancementMaxLevel(quality); got != want[quality] {
			t.Errorf("quality %d cap = %d, want %d", quality, got, want[quality])
		}
	}
}

func TestEquipmentEnhancementCombatBonuses(t *testing.T) {
	weapon := enhancementStatBonus(4, "weapon")
	if weapon["attack"] != 8 || len(weapon) != 1 {
		t.Fatalf("weapon enhancement bonus = %v, want +8 attack", weapon)
	}
	armor := enhancementStatBonus(4, "chest")
	if armor["defense"] != 4 || len(armor) != 1 {
		t.Fatalf("armor enhancement bonus = %v, want +4 defense", armor)
	}
	if len(enhancementStatBonus(0, "weapon")) != 0 {
		t.Fatal("unenhanced equipment should not add combat bonuses")
	}
}


func TestGroundDropEligibilitySerializesForWorldServer(t *testing.T) {
	drop := GroundDropSnapshot{
		ID: "00000000-0000-4000-8000-000000000001",
		OwnerCharacterID: "00000000-0000-4000-8000-000000000002",
		EligibleCharacterIDs: []string{
			"00000000-0000-4000-8000-000000000002",
			"00000000-0000-4000-8000-000000000003",
		},
	}
	encoded, err := json.Marshal(drop)
	if err != nil { t.Fatalf("marshal ground drop: %v", err) }
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil { t.Fatalf("unmarshal ground drop: %v", err) }
	recipients, ok := decoded["eligible_character_ids"].([]any)
	if !ok || len(recipients) != 2 {
		t.Fatalf("eligible_character_ids = %v, want two authorized characters", decoded["eligible_character_ids"])
	}
}
