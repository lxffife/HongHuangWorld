extends RefCounted
## Data-driven client map metadata.
## Region bounds are display hints only; gameplay boundaries remain server-authoritative.
## Coordinates use world X/Z meters. Bounds are [min_x, max_x, min_z, max_z].

const FENGDU_REGIONS := [
	{"id": "naihe_bridge", "name": "奈何桥", "priority": 10, "bounds": [[15.0, 29.0, -0.5, 5.5]]},
	{"id": "reincarnation_forecourt", "name": "轮回殿前", "priority": 20, "bounds": [[-35.0, -8.0, -69.0, -42.0]]},
	{"id": "fengdu_ghost_gate", "name": "酆都鬼门关", "priority": 30, "bounds": [[-12.0, 12.0, -28.0, -9.0]]},
	{"id": "forgotten_riverbank", "name": "忘川河畔", "priority": 40, "bounds": [[17.0, 27.0, -68.0, 82.0]]},
	{"id": "soul_guiding_road", "name": "引魂石道", "priority": 50, "bounds": [[-32.0, 32.0, -40.0, -26.0]]},
	{"id": "ancient_battlefield", "name": "古战场遗址", "priority": 60, "bounds": [[-1000000000.0, -36.0, 10.0, 46.0]]}
]

const QINGYUN_REGIONS := [
	{"id": "qingyun_gate", "name": "青云山门", "priority": 10, "bounds": [[-9.0, 9.0, -28.0, -16.0]]},
	{"id": "qingyun_path", "name": "青云石径", "priority": 20, "bounds": [[-7.0, 7.0, -42.0, -3.0]]},
	{"id": "qingyun_pine_forest", "name": "青云松林", "priority": 30, "bounds": [[-30.0, -8.0, -48.0, 8.0], [8.0, 30.0, -48.0, 8.0]]}
]

const FENGDU_PROTOTYPE := {
	"world_id": "underworld_fengdu",
	"bounds": [-128.0, 128.0, -128.0, 128.0],
	"world_size": 256.0,
	"heightfield_cells": 128,
	"tile_count": 4,
	"water_bodies": [
		{"id": "forgotten_river", "name": "忘川河", "kind": "river_visual", "size": [8.0, 150.0], "center": [22.0, 8.0], "height": -0.62, "color": "#344b69", "alpha": 0.76},
		{"id": "blood_sea", "name": "血海", "kind": "sea_visual", "size": [56.0, 236.0], "center": [100.0, 0.0], "height": -1.25, "color": "#681d32", "alpha": 0.84}
	],
	"landmarks": [
		{"id": "naihe_bridge_valley", "name": "奈何桥 / 忘川河谷", "position": [22.0, 2.0, 2.0], "color": "#9ebce8", "kind": "visual"},
		{"id": "reincarnation_terrace", "name": "轮回殿台地", "position": [-34.0, 8.0, -55.0], "color": "#c7b6dc", "kind": "visual"},
		{"id": "blood_sea_coast", "name": "血海岸线（样板）", "position": [78.0, -6.0, 18.0], "color": "#e58b9e", "kind": "visual"},
		{"id": "fengdu_outer_ridge", "name": "酆都北部山脊", "position": [-42.0, 12.0, -112.0], "color": "#b6a8a0", "kind": "visual"}
	]
}


static func get_world_bounds(world_id: String) -> Vector4:
	if world_id == "underworld_fengdu":
		return Vector4(-128.0, 128.0, -128.0, 128.0)
	if world_id == "qingyun_human" or world_id == "myriad_demon":
		return Vector4(-120.0, 120.0, -120.0, 120.0)
	return Vector4(-120.0, 120.0, -120.0, 120.0)


static func get_regions(world_id: String) -> Array:
	match world_id:
		"underworld_fengdu":
			return FENGDU_REGIONS.duplicate(true)
		"qingyun_human":
			return QINGYUN_REGIONS.duplicate(true)
		_:
			return []


static func get_landmarks(world_id: String) -> Array:
	if world_id != "underworld_fengdu":
		return []
	return FENGDU_PROTOTYPE["landmarks"].duplicate(true)


static func get_minimap_landmarks(world_id: String) -> Array:
	var result: Array = []
	for landmark in get_landmarks(world_id):
		var position_data: Array = landmark.get("position", [])
		if position_data.size() < 3:
			continue
		result.append({
			"id": str(landmark.get("id", "")),
			"name": str(landmark.get("name", "地标")),
			"position_x": float(position_data[0]),
			"position_z": float(position_data[2]),
			"kind": str(landmark.get("kind", "visual"))
		})
	return result


static func get_water_bodies(world_id: String) -> Array:
	if world_id != "underworld_fengdu":
		return []
	return FENGDU_PROTOTYPE["water_bodies"].duplicate(true)


static func get_prototype_definition(world_id: String) -> Dictionary:
	if world_id != "underworld_fengdu":
		return {}
	return FENGDU_PROTOTYPE.duplicate(true)


static func resolve_region_name(world_id: String, position: Vector3) -> String:
	var regions := get_regions(world_id)
	for region in regions:
		for bounds in region["bounds"]:
			if _inside_bounds(position, bounds):
				return str(region["name"])
	if world_id == "underworld_fengdu":
		return "酆都荒原"
	if world_id == "qingyun_human":
		return "青云郊野"
	return "未知区域"


static func _inside_bounds(position: Vector3, bounds: Array) -> bool:
	return (
		position.x >= float(bounds[0])
		and position.x <= float(bounds[1])
		and position.z >= float(bounds[2])
		and position.z <= float(bounds[3])
	)
