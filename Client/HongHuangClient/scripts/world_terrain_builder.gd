extends RefCounted

const UnderworldVisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const QingyunVisualFactory = preload("res://scripts/qingyun_visual_factory.gd")
const WorldChunkStreamerScript = preload("res://scripts/world_chunk_streamer.gd")
const FengduCityBuilder = preload("res://scripts/fengdu_city_builder.gd")

## Builds the static visual and collision layer for a world.
## Kept independent from WorldScene so the same region layout can later be
## backed by Terrain3D tiles without changing HUD, navigation or networking.
static func build(world_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WorldTerrain"
	var is_underworld := world_id == "underworld_fengdu"
	var streamer := Node3D.new()
	streamer.name = "ChunkStreamer"
	streamer.set_script(WorldChunkStreamerScript)
	streamer.call("configure", world_id, 48.0, 1)
	streamer.call("update_streaming", Vector3.ZERO)
	root.add_child(streamer)

	if is_underworld:
		root.add_child(FengduCityBuilder.build())
		# Fengdu gate and the soul lantern avenue.
		root.add_child(UnderworldVisualFactory.create_fengdu_gate())
		for side in [-1.0, 1.0]:
			var lantern_position := Vector3(side * 7.0, 2.1, -14.0)
			_add_world_box(root, "SoulLanternStone_" + str(side), Vector3(0.8, 2.2, 0.8), lantern_position, Color("#393344"))
			var flame := MeshInstance3D.new()
			flame.name = "SoulLanternFlame_" + str(side)
			var flame_mesh := SphereMesh.new()
			flame_mesh.radius = 0.34
			flame_mesh.height = 0.9
			flame.mesh = flame_mesh
			flame.position = lantern_position + Vector3(0.0, 1.45, 0.0)
			var flame_material := StandardMaterial3D.new()
			flame_material.albedo_color = Color("#82a8d8")
			flame_material.emission_enabled = true
			flame_material.emission = Color("#537fc4")
			flame_material.emission_energy_multiplier = 2.4
			flame.material_override = flame_material
			root.add_child(flame)
		for i in range(8):
			var x := -24.0 + float(i) * 7.0
			var height := 2.8 + float(i % 3) * 0.8
			_add_world_box(root, "UnderworldStele_" + str(i), Vector3(0.9, height, 0.8), Vector3(x, height * 0.5, -31.0), Color("#373342"))

		# The River of Forgetfulness runs north-south; a stone bridge crosses it.
		var river := MeshInstance3D.new()
		river.name = "RiverOfForgetfulness"
		var river_mesh := PlaneMesh.new()
		river_mesh.size = Vector2(8.0, 150.0)
		river.mesh = river_mesh
		river.position = Vector3(22.0, 0.045, 8.0)
		var water_material := StandardMaterial3D.new()
		water_material.albedo_color = Color(0.18, 0.34, 0.52, 0.78)
		water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		water_material.metallic = 0.28
		water_material.roughness = 0.2
		water_material.emission_enabled = true
		water_material.emission = Color("#243f70")
		water_material.emission_energy_multiplier = 0.45
		river.material_override = water_material
		root.add_child(river)
		for side in [-1.0, 1.0]:
			_add_world_box(root, "RiverBank_" + str(side), Vector3(1.0, 0.65, 150.0), Vector3(22.0 + side * 4.5, 0.22, 8.0), Color("#383344"))
		_add_world_box(root, "NaiheBridgeDeck", Vector3(13.0, 0.65, 3.2), Vector3(22.0, 0.72, 2.0), Color("#777080"))
		_add_world_box(root, "NaiheBridgeRailLeft", Vector3(13.0, 0.8, 0.28), Vector3(22.0, 1.38, 0.45), Color("#9b91a3"))
		_add_world_box(root, "NaiheBridgeRailRight", Vector3(13.0, 0.8, 0.28), Vector3(22.0, 1.38, 3.55), Color("#9b91a3"))
		for i in range(7):
			var x := 16.5 + float(i) * 1.85
			_add_world_box(root, "BridgePostL_" + str(i), Vector3(0.32, 1.2, 0.32), Vector3(x, 1.55, 0.45), Color("#aaa0ae"))
			_add_world_box(root, "BridgePostR_" + str(i), Vector3(0.32, 1.2, 0.32), Vector3(x, 1.55, 3.55), Color("#aaa0ae"))
		_add_world_landmark_label(root, "NaiheBridgeName", "奈何桥", Vector3(22.0, 3.1, 2.0), Color("#b8c9e8"))

		# Distant reincarnation hall silhouette, placed beyond the gate avenue.
		_add_world_box(root, "ReincarnationHallBase", Vector3(22.0, 1.2, 12.0), Vector3(-22.0, 0.6, -55.0), Color("#383344"))
		_add_world_box(root, "ReincarnationHallBody", Vector3(16.0, 7.0, 9.0), Vector3(-22.0, 4.1, -55.0), Color("#51465c"))
		_add_world_box(root, "ReincarnationHallRoof", Vector3(20.0, 1.0, 12.0), Vector3(-22.0, 8.1, -55.0), Color("#292536"))
		_add_world_box(root, "ReincarnationHallRoofTop", Vector3(12.0, 0.7, 8.0), Vector3(-22.0, 9.0, -55.0), Color("#65536d"))
		_add_world_landmark_label(root, "ReincarnationHallName", "轮回殿", Vector3(-22.0, 11.0, -54.0), Color("#c4b6dc"))
	else:
		# Qingyun mountain gate, sect hall, stone path and layered pine silhouettes.
		root.add_child(QingyunVisualFactory.create_mountain_gate())
		root.add_child(QingyunVisualFactory.create_sect_hall())
		for i in range(12):
			var z := -4.0 - float(i) * 3.0
			var width := 5.5 if i < 7 else 7.0
			_add_world_box(root, "QingyunPathStone_" + str(i), Vector3(width, 0.12, 2.2), Vector3(0.0, 0.04, z), Color("#777e70"))
		for i in range(16):
			var side := -1.0 if i % 2 == 0 else 1.0
			var row := float(i / 2)
			var x := side * (9.0 + float(i % 3) * 2.0)
			var z := -8.0 - row * 7.0
			var pine := QingyunVisualFactory.create_pine(6.5 + float(i % 3) * 0.6)
			pine.position = Vector3(x, 0.0, z)
			root.add_child(pine)
		# Natural rocks frame the path without obscuring the spawn area.
		for i in range(12):
			var rock := MeshInstance3D.new()
			var rock_mesh := SphereMesh.new()
			rock_mesh.radius = randf_range(0.7, 2.0)
			rock_mesh.height = rock_mesh.radius * 1.5
			rock.mesh = rock_mesh
			rock.position = Vector3(randf_range(-28.0, 28.0), rock_mesh.radius * 0.35, randf_range(-28.0, 28.0))
			var rock_material := StandardMaterial3D.new()
			rock_material.albedo_color = Color("#53645d")
			rock_material.roughness = 1.0
			rock.material_override = rock_material
			root.add_child(rock)
	return root

static func _add_world_box(root: Node3D, node_name: String, size: Vector3, world_position: Vector3, color: Color, emissive: bool = false) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	instance.mesh = box
	instance.position = world_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.8
	instance.material_override = material
	root.add_child(instance)

static func _add_world_landmark_label(root: Node3D, node_name: String, text_value: String, world_position: Vector3, color: Color) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text_value
	label.position = world_position
	label.font_size = 42
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	root.add_child(label)
