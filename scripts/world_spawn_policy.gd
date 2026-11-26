extends RefCounted
## Client-side spatial audit for Fengdu NPC and monster placement.
## This catalog is diagnostic/presentation metadata only. WorldServer remains authoritative.

const FENGDU_CITY_SAFE_BOUNDS := Vector4(-53.0, 53.0, -104.0, -16.0)

const FENGDU_MONSTER_REGIONS := [
	{
		"id": "ancient_battlefield",
		"name": "西南古战场",
		"bounds": Vector4(-100.0, -36.0, 10.0, 46.0),
		"level_min": 24,
		"level_max": 40,
		"families": ["战魂", "战神", "阴兵", "古战魂"]
	},
	{
		"id": "southern_wraith_marsh",
		"name": "南郊游魂泽",
		"bounds": Vector4(-100.0, 100.0, -15.0, 100.0),
		"level_min": 1,
		"level_max": 12,
		"families": ["游祟", "孤魂", "怨魂", "游魂", "幽魂"]
	},
	{
		"id": "western_bone_waste",
		"name": "西郊白骨荒原",
		"bounds": Vector4(-100.0, -54.0, -100.0, -15.01),
		"level_min": 10,
		"level_max": 24,
		"families": ["骸骨", "白骨", "尸兵", "骨魔", "铁骨"]
	},
	{
		"id": "eastern_forgotten_bank",
		"name": "东郊忘川古渡",
		"bounds": Vector4(54.0, 100.0, -100.0, -15.01),
		"level_min": 18,
		"level_max": 32,
		"families": ["水鬼", "溺魂", "河妖", "忘川", "鱼妖"]
	}
]


static func is_fengdu_city_safe_position(position: Vector3) -> bool:
	return _inside(position, FENGDU_CITY_SAFE_BOUNDS)


static func classify_fengdu_position(position: Vector3) -> Dictionary:
	if is_fengdu_city_safe_position(position):
		return {
			"id": "fengdu_city_safe",
			"name": "酆都城内安全区",
			"is_safe": true,
			"level_min": 0,
			"level_max": 0
		}
	for region_variant in FENGDU_MONSTER_REGIONS:
		var region: Dictionary = region_variant
		if _inside(position, region["bounds"]):
			return region.duplicate(true)
	return {
		"id": "unassigned_outer_area",
		"name": "未划定城外区域",
		"is_safe": false,
		"level_min": 0,
		"level_max": 0
	}


static func audit_npc_position(position: Vector3) -> Dictionary:
	var region := classify_fengdu_position(position)
	return {
		"valid_city_position": bool(region.get("is_safe", false)),
		"region_id": str(region.get("id", "")),
		"region_name": str(region.get("name", "未知区域"))
	}


static func audit_monster_position(position: Vector3, monster_name: String, monster_level: int) -> Dictionary:
	var region := classify_fengdu_position(position)
	var is_city := bool(region.get("is_safe", false))
	var level_min := int(region.get("level_min", 0))
	var level_max := int(region.get("level_max", 0))
	var family_match := false
	for family_variant in region.get("families", []):
		if monster_name.contains(str(family_variant)):
			family_match = true
			break
	var level_mismatch := not is_city and level_min > 0 and (monster_level < level_min or monster_level > level_max)
	return {
		"region_id": str(region.get("id", "")),
		"region_name": str(region.get("name", "未知区域")),
		"is_city_safe_zone": is_city,
		"spawn_violation": is_city,
		"level_mismatch": level_mismatch,
		"family_match": family_match,
		"recommended_level_min": level_min,
		"recommended_level_max": level_max
	}


static func get_fengdu_monster_regions() -> Array:
	return FENGDU_MONSTER_REGIONS.duplicate(true)


static func _inside(position: Vector3, bounds: Vector4) -> bool:
	return position.x >= bounds.x and position.x <= bounds.y and position.z >= bounds.z and position.z <= bounds.w
