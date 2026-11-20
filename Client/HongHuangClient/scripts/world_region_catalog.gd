extends RefCounted
## Client-facing region labels. The catalog contains presentation bounds only;
## authoritative region membership and permissions are supplied by the server.

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")


static func resolve(world_id: String, position: Vector3) -> String:
	return WorldMapCatalog.resolve_region_name(world_id, position)
