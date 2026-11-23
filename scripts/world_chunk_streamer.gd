extends Node3D
## Lightweight client-side chunk streamer. Gameplay bounds and movement remain server-authoritative.
## Each loaded tile owns its visual ground and a matching static collision slab.

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")

var world_id := ""
var chunk_size := 48.0
var stream_radius := 1
var _loaded_chunks: Dictionary = {}
var _last_center := Vector2i(999999, 999999)
var _world_bounds := Vector4(-120.0, 120.0, -120.0, 120.0)


func configure(next_world_id: String, tile_size: float = 48.0, radius: int = 1) -> void:
	world_id = next_world_id
	chunk_size = maxf(tile_size, 16.0)
	stream_radius = maxi(radius, 1)
	# Keep visual chunks aligned with the current WorldServer movement clamp (±100 m).
	# The schematic underworld atlas is intentionally much larger than this prototype.
	_world_bounds = Vector4(-100.0, 100.0, -100.0, 100.0)


func update_streaming(world_position: Vector3) -> void:
	var center := _chunk_index(world_position)
	if center == _last_center:
		return
	_last_center = center
	var wanted: Dictionary = {}
	var max_x := _chunk_count_x()
	var max_z := _chunk_count_z()
	for z in range(maxi(0, center.y - stream_radius), mini(max_z, center.y + stream_radius + 1)):
		for x in range(maxi(0, center.x - stream_radius), mini(max_x, center.x + stream_radius + 1)):
			var key := Vector2i(x, z)
			wanted[key] = true
			if not _loaded_chunks.has(key):
				_loaded_chunks[key] = _create_chunk(key)
				add_child(_loaded_chunks[key])
	for key_variant in _loaded_chunks.keys():
		var key: Vector2i = key_variant
		if not wanted.has(key):
			var chunk_node := _loaded_chunks[key] as Node3D
			if is_instance_valid(chunk_node):
				chunk_node.queue_free()
			_loaded_chunks.erase(key)
	set_meta("loaded_chunk_count", _loaded_chunks.size())
	set_meta("chunk_size", chunk_size)


func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()


func _chunk_count_x() -> int:
	return maxi(1, ceili((_world_bounds.y - _world_bounds.x) / chunk_size))


func _chunk_count_z() -> int:
	return maxi(1, ceili((_world_bounds.w - _world_bounds.z) / chunk_size))


func _chunk_index(world_position: Vector3) -> Vector2i:
	var x := int(floor((world_position.x - _world_bounds.x) / chunk_size))
	var z := int(floor((world_position.z - _world_bounds.z) / chunk_size))
	return Vector2i(clampi(x, 0, _chunk_count_x() - 1), clampi(z, 0, _chunk_count_z() - 1))


func _create_chunk(index: Vector2i) -> StaticBody3D:
	var start_x := _world_bounds.x + float(index.x) * chunk_size
	var start_z := _world_bounds.z + float(index.y) * chunk_size
	var width := minf(chunk_size, _world_bounds.y - start_x)
	var depth := minf(chunk_size, _world_bounds.w - start_z)
	var center := Vector3(start_x + width * 0.5, 0.0, start_z + depth * 0.5)
	var body := StaticBody3D.new()
	body.name = "GroundChunk_%d_%d" % [index.x, index.y]
	body.position = center
	body.set_meta("chunk_index", index)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GroundVisual"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mesh_instance.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = _chunk_color(index, center)
	material.roughness = 0.96
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.2, depth)
	collision.shape = shape
	collision.position.y = -0.1
	body.add_child(collision)
	return body


func _chunk_color(index: Vector2i, center: Vector3) -> Color:
	var base := Color("#211f30") if world_id == "underworld_fengdu" else Color("#354c43")
	if world_id == "underworld_fengdu":
		if center.x > 72.0:
			base = Color("#351d2c")
		elif center.z < -84.0:
			base = Color("#302d3b")
		elif center.x > 28.0 and center.x < 38.0:
			base = Color("#26354b")
	else:
		if center.z < -48.0:
			base = Color("#405448")
		elif center.x < -48.0:
			base = Color("#465044")
	var variation := float(posmod(index.x * 17 + index.y * 31, 5)) * 0.012
	return Color(
		clampf(base.r + variation, 0.0, 1.0),
		clampf(base.g + variation, 0.0, 1.0),
		clampf(base.b + variation, 0.0, 1.0),
		1.0
	)
