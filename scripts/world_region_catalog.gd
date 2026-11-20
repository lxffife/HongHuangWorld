extends RefCounted
## Client-side display labels for known prototype regions.
## These rectangles are presentation hints only; server region metadata remains authoritative.
## Keep this catalog independent from terrain nodes and rendering plugins.

const WorldMapProjection = preload("res://scripts/world_map_projection.gd")


static func resolve(world_id: String, position: Vector3) -> String:
	if world_id == "underworld_fengdu":
		if _inside(position, 15.0, 29.0, -0.5, 5.5):
			return "奈何桥"
		if _inside(position, -35.0, -8.0, -69.0, -42.0):
			return "轮回殿前"
		if _inside(position, -12.0, 12.0, -28.0, -9.0):
			return "酆都鬼门关"
		if _inside(position, 17.0, 27.0, -68.0, 82.0):
			return "忘川河畔"
		if _inside(position, -32.0, 32.0, -40.0, -26.0):
			return "引魂石道"
		if _inside(position, -1000000000.0, -36.0, 10.0, 46.0):
			return "古战场遗址"
		return "酆都荒原"

	if world_id == "qingyun_human":
		if _inside(position, -9.0, 9.0, -28.0, -16.0):
			return "青云山门"
		if _inside(position, -7.0, 7.0, -42.0, -3.0):
			return "青云石径"
		if _inside(position, -30.0, -8.0, -48.0, 8.0) or _inside(position, 8.0, 30.0, -48.0, 8.0):
			return "青云松林"
		return "青云郊野"

	return "未知区域"


static func _inside(position: Vector3, min_x: float, max_x: float, min_z: float, max_z: float) -> bool:
	return WorldMapProjection.world_xz_in_bounds(position, min_x, max_x, min_z, max_z)
