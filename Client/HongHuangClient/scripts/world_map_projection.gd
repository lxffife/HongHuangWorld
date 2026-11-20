extends RefCounted
## Shared X/Z projection for every map surface.
## The same world coordinates can be rendered by the minimap, full map, or debug overlays.
## This class deliberately knows nothing about Terrain3D or scene nodes.

static func world_to_map(
	world_position: Vector3,
	world_origin: Vector3,
	map_origin: Vector2,
	pixels_per_meter: Vector2,
	invert_z: bool = true
) -> Vector2:
	var delta := Vector2(
		world_position.x - world_origin.x,
		world_position.z - world_origin.z
	)
	if invert_z:
		delta.y = -delta.y
	return map_origin + Vector2(delta.x * pixels_per_meter.x, delta.y * pixels_per_meter.y)


static func map_to_world(
	map_position: Vector2,
	world_origin: Vector3,
	map_origin: Vector2,
	pixels_per_meter: Vector2,
	invert_z: bool = true
) -> Vector3:
	var safe_scale := Vector2(
		maxf(absf(pixels_per_meter.x), 0.000001),
		maxf(absf(pixels_per_meter.y), 0.000001)
	)
	var delta := (map_position - map_origin) / safe_scale
	if invert_z:
		delta.y = -delta.y
	return Vector3(world_origin.x + delta.x, world_origin.y, world_origin.z + delta.y)


static func is_inside_circle(point: Vector2, center: Vector2, radius: float) -> bool:
	return point.distance_squared_to(center) <= radius * radius


static func world_xz_in_bounds(
	world_position: Vector3,
	min_x: float,
	max_x: float,
	min_z: float,
	max_z: float
) -> bool:
	return (
		world_position.x >= min_x
		and world_position.x <= max_x
		and world_position.z >= min_z
		and world_position.z <= max_z
	)
