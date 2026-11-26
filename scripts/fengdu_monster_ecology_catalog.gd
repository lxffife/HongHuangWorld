extends RefCounted
## Client-side encounter design templates. These are recommendations for server authors,
## not spawn commands; WorldServer remains authoritative for every live monster.

const ENCOUNTERS := {
	"southern_wraith_marsh": {
		"region_name": "南郊游魂泽",
		"normal": {"name": "游魂游荡群", "level_min": 1, "level_max": 6, "suggested_count": 5, "activity_radius": 12.0, "families": ["游祟", "孤魂", "游魂"]},
		"elite": {"name": "怨念聚合体", "level_min": 7, "level_max": 10, "suggested_count": 1, "activity_radius": 18.0, "families": ["怨魂", "幽魂"]},
		"boss": {"name": "泽心缚魂将", "level_min": 11, "level_max": 12, "suggested_count": 1, "activity_radius": 24.0, "families": ["缚魂", "怨魂"]}
	},
	"western_bone_waste": {
		"region_name": "西郊白骨荒原",
		"normal": {"name": "白骨巡游群", "level_min": 10, "level_max": 16, "suggested_count": 4, "activity_radius": 14.0, "families": ["骸骨", "白骨", "尸兵"]},
		"elite": {"name": "铁骨守墓者", "level_min": 17, "level_max": 21, "suggested_count": 1, "activity_radius": 20.0, "families": ["铁骨", "骨魔"]},
		"boss": {"name": "荒原葬骨君", "level_min": 22, "level_max": 24, "suggested_count": 1, "activity_radius": 28.0, "families": ["葬骨", "骨魔"]}
	},
	"eastern_forgotten_bank": {
		"region_name": "东郊忘川古渡",
		"normal": {"name": "忘川水鬼群", "level_min": 18, "level_max": 23, "suggested_count": 4, "activity_radius": 14.0, "families": ["水鬼", "溺魂", "鱼妖"]},
		"elite": {"name": "渡口巡河妖", "level_min": 24, "level_max": 29, "suggested_count": 1, "activity_radius": 20.0, "families": ["河妖", "忘川"]},
		"boss": {"name": "沉舟河伯残念", "level_min": 30, "level_max": 32, "suggested_count": 1, "activity_radius": 30.0, "families": ["河伯", "沉舟"]}
	},
	"ancient_battlefield": {
		"region_name": "西南古战场",
		"normal": {"name": "古战游魂队", "level_min": 24, "level_max": 29, "suggested_count": 4, "activity_radius": 16.0, "families": ["战魂", "阴兵"]},
		"elite": {"name": "百战阴将", "level_min": 30, "level_max": 36, "suggested_count": 1, "activity_radius": 24.0, "families": ["战神", "古战魂"]},
		"boss": {"name": "无旗战主", "level_min": 37, "level_max": 40, "suggested_count": 1, "activity_radius": 34.0, "families": ["战主", "古战魂"]}
	}
}


static func get_region_encounters(region_id: String) -> Dictionary:
	var encounters: Dictionary = ENCOUNTERS.get(region_id, {})
	return encounters.duplicate(true)


static func get_all_region_ids() -> Array:
	return ENCOUNTERS.keys()


static func get_encounter_tiers(region_id: String) -> Array:
	var encounters := get_region_encounters(region_id)
	var tiers: Array = []
	for tier_id in ["normal", "elite", "boss"]:
		if encounters.has(tier_id):
			var tier: Dictionary = (encounters[tier_id] as Dictionary).duplicate(true)
			tier["tier_id"] = tier_id
			tiers.append(tier)
	return tiers
