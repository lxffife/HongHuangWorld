extends Node3D
## Isolated 256m x 256m Fengdu terrain study.
## This is an editor/playtest prototype only; it does not replace the live world
## and does not define server-authoritative region boundaries.

const WorldEnvironmentBuilder = preload("res://scripts/world_environment_builder.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const WorldTerrainStreamingManager = preload("res://scripts/experiments/fengdu_terrain_streaming_manager.gd")

var _map_definition: Dictionary = {}

const GROUND_LOW := Color("#292632")
const GROUND_MID := Color("#45404c")
const GROUND_HIGH := Color("#655d68")
const SHORE_COLOR := Color("#51404a")
const RIVER_COLOR := Color("#344b69")
const BLOOD_COLOR := Color("#681d32")

func _ready() -> void:
	_map_definition = WorldMapCatalog.get_prototype_definition("underworld_fengdu")
	_build_environment()
	_build_heightfield()
	_build_water()
	_build_landmark_markers()
	_build_preview_camera()


func _build_environment() -> void:
	add_child(WorldEnvironmentBuilder.build("underworld_fengdu"))


func _build_heightfield() -> void:
	var focus := Marker3D.new()
	focus.name = "StreamingFocus"
	focus.position = Vector3.ZERO
	add_child(focus)

	var streaming_manager := Node3D.new()
	streaming_manager.name = "TerrainStreamingManager"
	streaming_manager.set_script(WorldTerrainStreamingManager)
	streaming_manager.set("source_path", NodePath(".."))
	streaming_manager.set("focus_path", NodePath("../StreamingFocus"))
	var tile_count := int(_map_definition["tile_count"])
	var grid_cells := int(_map_definition["heightfield_cells"])
	streaming_manager.set("tile_count", tile_count)
	streaming_manager.set("cells_per_tile", int(grid_cells / tile_count))
	streaming_manager.set("world_size", float(_map_definition["world_size"]))
	streaming_manager.set("load_radius", 2)
	streaming_manager.set("unload_radius", 3)
	streaming_manager.set("max_operations_per_frame", 2)
	add_child(streaming_manager)


func _build_terrain_tile(tile_x: int, tile_z: int, cells_per_tile: int) -> Node3D:
	var world_size := float(_map_definition["world_size"])
	var tile_count := int(_map_definition["tile_count"])
	var half_size := world_size * 0.5
	var tile_size := world_size / float(tile_count)
	var tile_min_x := -half_size + float(tile_x) * tile_size
	var tile_min_z := -half_size + float(tile_z) * tile_size
	var tile_max_x := tile_min_x + tile_size
	var tile_max_z := tile_min_z + tile_size
	var tile_step := tile_size / float(cells_per_tile)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z_index in range(cells_per_tile):
		for x_index in range(cells_per_tile):
			var x0 := tile_min_x + float(x_index) * tile_step
			var z0 := tile_min_z + float(z_index) * tile_step
			var x1 := x0 + tile_step
			var z1 := z0 + tile_step
			_add_terrain_vertex(surface, Vector3(x0, _height_at(x0, z0), z0))
			_add_terrain_vertex(surface, Vector3(x0, _height_at(x0, z1), z1))
			_add_terrain_vertex(surface, Vector3(x1, _height_at(x1, z0), z0))
			_add_terrain_vertex(surface, Vector3(x1, _height_at(x1, z0), z0))
			_add_terrain_vertex(surface, Vector3(x0, _height_at(x0, z1), z1))
			_add_terrain_vertex(surface, Vector3(x1, _height_at(x1, z1), z1))

	surface.generate_normals()
	var terrain_mesh := surface.commit()
	var terrain_material := StandardMaterial3D.new()
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 1.0
	terrain_mesh.surface_set_material(0, terrain_material)

	var tile := Node3D.new()
	tile.name = "TerrainTile_%02d_%02d" % [tile_x, tile_z]
	tile.set_meta("tile_x", tile_x)
	tile.set_meta("tile_z", tile_z)
	tile.set_meta("world_min_x", tile_min_x)
	tile.set_meta("world_max_x", tile_max_x)
	tile.set_meta("world_min_z", tile_min_z)
	tile.set_meta("world_max_z", tile_max_z)

	var visual := MeshInstance3D.new()
	visual.name = "TerrainVisual"
	visual.mesh = terrain_mesh
	tile.add_child(visual)

	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	var collision := CollisionShape3D.new()
	collision.shape = terrain_mesh.create_trimesh_shape()
	body.add_child(collision)
	tile.add_child(body)
	return tile


func _add_terrain_vertex(surface: SurfaceTool, vertex: Vector3) -> void:
	surface.set_color(_terrain_color(vertex))
	surface.add_vertex(vertex)


func _height_at(x: float, z: float) -> float:
	# Broken ridgelines around the northern and western perimeter.
	var north_ridge := 9.0 * exp(-pow((z + 103.0) / 22.0, 2.0))
	var west_ridge := 6.5 * exp(-pow((x + 104.0) / 19.0, 2.0))
	var ridge_breaks := 0.72 + 0.28 * sin(z * 0.055 + x * 0.021)
	var mountain := (north_ridge + west_ridge) * ridge_breaks

	# A broad lower river valley follows the existing Forgotten River X coordinate.
	var river_valley := -2.1 * exp(-pow((x - 22.0) / 13.0, 2.0))
	var river_bed := -1.0 * exp(-pow((x - 22.0) / 4.2, 2.0))

	# Raised terrace for the future Reincarnation Hall district.
	var plateau_mask := _smoothstep(0.0, 1.0, 1.0 - Vector2(x + 34.0, z + 55.0).length() / 45.0)
	var plateau := 5.0 * plateau_mask

	# Eastern edge descends into the Blood Sea shelf.
	var coast_wave := 4.0 * sin(z * 0.035) + 2.0 * sin(z * 0.081)
	var coast_line := 72.0 + coast_wave
	var sea_slope := _smoothstep(coast_line - 17.0, coast_line + 7.0, x)
	var sea_cliff := -8.0 * sea_slope
	var coast_shelf := -2.0 * _smoothstep(coast_line - 4.0, coast_line + 13.0, x)

	var low_terrain := 0.65 * sin(x * 0.031) * cos(z * 0.027)
	return mountain + river_valley + river_bed + plateau + sea_cliff + coast_shelf + low_terrain


func _terrain_color(vertex: Vector3) -> Color:
	if vertex.x > 65.0:
		return SHORE_COLOR.lerp(BLOOD_COLOR, clampf((vertex.x - 65.0) / 24.0, 0.0, 0.48))
	if vertex.y > 7.0:
		return GROUND_HIGH
	if vertex.y > 2.5:
		return GROUND_MID
	return GROUND_LOW


func _build_water() -> void:
	for water_data in WorldMapCatalog.get_water_bodies("underworld_fengdu"):
		var size_data: Array = water_data["size"]
		var center_data: Array = water_data["center"]
		var size := Vector2(float(size_data[0]), float(size_data[1]))
		var position := Vector3(float(center_data[0]), float(water_data["height"]), float(center_data[1]))
		_add_water_plane("%sSurface" % str(water_data["id"]).capitalize(), size, position, Color(str(water_data["color"])), float(water_data["alpha"]))


func _add_water_plane(node_name: String, size: Vector2, world_position: Vector3, color: Color, alpha: float) -> void:
	var water := MeshInstance3D.new()
	water.name = node_name
	var plane := PlaneMesh.new()
	plane.size = size
	water.mesh = plane
	water.position = world_position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.24
	material.metallic = 0.22
	material.emission_enabled = true
	material.emission = color.darkened(0.32)
	material.emission_energy_multiplier = 0.34
	water.material_override = material
	add_child(water)


func _build_landmark_markers() -> void:
	for landmark in WorldMapCatalog.get_landmarks("underworld_fengdu"):
		var position_data: Array = landmark["position"]
		var world_position := Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
		_add_marker(str(landmark["id"]).to_pascal_case(), str(landmark["name"]), world_position, Color(str(landmark["color"])))


func _add_marker(node_name: String, title: String, world_position: Vector3, color: Color) -> void:
	var marker := Node3D.new()
	marker.name = node_name
	var marker_position := world_position
	marker_position.y = _height_at(world_position.x, world_position.z) + 1.5
	marker.position = marker_position
	var pillar := MeshInstance3D.new()
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.16
	pillar_mesh.bottom_radius = 0.16
	pillar_mesh.height = 3.0
	pillar.mesh = pillar_mesh
	var pillar_material := StandardMaterial3D.new()
	pillar_material.albedo_color = color
	pillar_material.emission_enabled = true
	pillar_material.emission = color
	pillar_material.emission_energy_multiplier = 1.3
	pillar.material_override = pillar_material
	marker.add_child(pillar)
	var label := Label3D.new()
	label.text = title
	label.position.y = 2.2
	label.font_size = 38
	label.outline_size = 7
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	marker.add_child(label)
	add_child(marker)


func _build_preview_camera() -> void:
	var camera := Camera3D.new()
	camera.name = "PrototypePreviewCamera"
	camera.position = Vector3(0.0, 92.0, 178.0)
	camera.look_at(Vector3(0.0, 0.0, -8.0), Vector3.UP)
	camera.current = true
	camera.fov = 58.0
	add_child(camera)


static func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	var t := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
