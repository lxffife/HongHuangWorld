extends RefCounted

const UnderworldVisualFactory = preload("res://scripts/underworld_visual_factory.gd")
const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")
const QingyunVisualFactory = preload("res://scripts/qingyun_visual_factory.gd")
const WorldChunkStreamerScript = preload("res://scripts/world_chunk_streamer.gd")
const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const FengduCityBuilder = preload("res://scripts/fengdu_city_builder.gd")
const HellFloorBuilder = preload("res://scripts/underworld_hell_floor_builder.gd")
const FengduOuterRoadBuilder = preload("res://scripts/fengdu_outer_road_builder.gd")

## Builds the static visual and collision layer for a world.
## Kept independent from WorldScene so the same region layout can later be
## backed by Terrain3D tiles without changing HUD, navigation or networking.
static func build(world_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WorldTerrain"
	var is_underworld := world_id == "underworld_fengdu"
	var is_hell_floor := world_id.begins_with("underworld_hell_")
	var streamer := Node3D.new()
	streamer.name = "ChunkStreamer"
	streamer.set_script(WorldChunkStreamerScript)
	streamer.call("configure", world_id, 48.0, 1)
	streamer.call("update_streaming", Vector3.ZERO)
	root.add_child(streamer)

	if is_underworld:
		root.add_child(FengduCityBuilder.build())
		_add_fengdu_outer_region_markers(root)
		_add_fengdu_region_dressing(root)
		root.add_child(FengduOuterRoadBuilder.build())
		# Fengdu gate and the soul lantern avenue.
		root.add_child(UnderworldVisualFactory.create_fengdu_gate())
		for side in [-1.0, 1.0]:
			var lantern_position := Vector3(side * 7.0, 2.1, -14.0)
			var lantern := VisualModelLibrary.instantiate_model("fengdu_lantern", func() -> Node3D: return _create_soul_lantern_fallback())
			lantern.name = "SoulLantern_" + str(side)
			lantern.position = lantern_position
			root.add_child(lantern)
			var flame := MeshInstance3D.new()
			flame.name = "SoulLanternFlame_" + str(side)
			var flame_mesh := SphereMesh.new()
			flame_mesh.radius = 0.34
			flame_mesh.height = 0.9
			flame.mesh = flame_mesh
			flame.position = lantern_position + Vector3(0.0, 2.05, 0.0)
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

	elif is_hell_floor:
		root.add_child(HellFloorBuilder.build(WorldMapCatalog.resolve_hell_floor_number(world_id)))
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

static func _add_fengdu_outer_region_markers(root: Node3D) -> void:
	# Landmark beacons make the four outer hunting territories legible in-world.
	# They are visual-only: no collision, navigation or server-authority changes.
	var markers := [
		{"id": "SouthernWraithMarsh", "title": "南郊游魂泽", "subtitle": "游魂 · Lv.1–12", "position": Vector3(0.0, 0.0, 72.0), "color": Color("#75a9d5")},
		{"id": "WesternBoneWaste", "title": "西郊白骨荒原", "subtitle": "骸骨 · Lv.10–24", "position": Vector3(-78.0, 0.0, -58.0), "color": Color("#c4b58c")},
		{"id": "EasternForgottenBank", "title": "东郊忘川古渡", "subtitle": "水鬼 · Lv.18–32", "position": Vector3(78.0, 0.0, -58.0), "color": Color("#6bbdc2")},
		{"id": "AncientBattlefield", "title": "西南古战场", "subtitle": "战魂 · Lv.24–40", "position": Vector3(-78.0, 0.0, 30.0), "color": Color("#bd7774")}
	]
	for marker_variant in markers:
		var marker_data: Dictionary = marker_variant
		var marker := Node3D.new()
		marker.name = "OuterRegion_" + str(marker_data["id"])
		marker.position = marker_data["position"]
		var color: Color = marker_data["color"]
		var base := MeshInstance3D.new()
		base.name = "BeaconBase"
		var base_mesh := CylinderMesh.new()
		base_mesh.top_radius = 1.25
		base_mesh.bottom_radius = 1.65
		base_mesh.height = 0.55
		base.mesh = base_mesh
		base.position.y = 0.28
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("#34313b")
		stone.roughness = 0.94
		base.material_override = stone
		marker.add_child(base)
		var pillar := MeshInstance3D.new()
		pillar.name = "BeaconPillar"
		var pillar_mesh := BoxMesh.new()
		pillar_mesh.size = Vector3(0.72, 3.2, 0.72)
		pillar.mesh = pillar_mesh
		pillar.position.y = 2.0
		pillar.material_override = stone
		marker.add_child(pillar)
		var crystal := MeshInstance3D.new()
		crystal.name = "RegionCrystal"
		var crystal_mesh := SphereMesh.new()
		crystal_mesh.radius = 0.58
		crystal_mesh.height = 1.2
		crystal.mesh = crystal_mesh
		crystal.position.y = 4.0
		var crystal_material := StandardMaterial3D.new()
		crystal_material.albedo_color = color
		crystal_material.emission_enabled = true
		crystal_material.emission = color
		crystal_material.emission_energy_multiplier = 1.35
		crystal_material.roughness = 0.3
		crystal.material_override = crystal_material
		marker.add_child(crystal)
		var title := Label3D.new()
		title.name = "RegionTitle"
		title.text = str(marker_data["title"])
		title.position.y = 5.2
		title.font_size = 34
		title.outline_size = 7
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.modulate = color
		marker.add_child(title)
		var subtitle := Label3D.new()
		subtitle.name = "RegionSubtitle"
		subtitle.text = str(marker_data["subtitle"])
		subtitle.position.y = 4.35
		subtitle.font_size = 20
		subtitle.outline_size = 5
		subtitle.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		subtitle.modulate = Color("#e4dce9")
		marker.add_child(subtitle)
		root.add_child(marker)


static func _add_fengdu_region_dressing(root: Node3D) -> void:
	# Lightweight, deterministic visual dressing. No physics bodies are created.
	var marsh := Node3D.new()
	marsh.name = "RegionDressing_SouthernWraithMarsh"
	root.add_child(marsh)
	var reed_material := _region_material(Color("#536d68"), 0.92)
	var pool_material := _region_material(Color(0.16, 0.32, 0.38, 0.62), 0.22, true)
	var mud_material := _region_material(Color("#343b39"), 1.0)
	for i in range(7):
		var x := -17.0 + float(i) * 5.6
		var z := 55.0 + float((i * 7) % 13) - 6.0
		_add_region_cylinder(marsh, "MarshReedCluster_%02d" % i, 0.10, 0.16, 2.2 + float(i % 3) * 0.45, Vector3(x, 1.15, z), reed_material, Vector3(0.0, 0.0, deg_to_rad(float((i % 3) - 1) * 7.0)))
	for i in range(3):
		var pool := MeshInstance3D.new()
		pool.name = "MarshPool_%02d" % i
		var pool_mesh := CylinderMesh.new()
		pool_mesh.top_radius = 2.6
		pool_mesh.bottom_radius = 2.6
		pool_mesh.height = 0.035
		pool.mesh = pool_mesh
		pool.position = Vector3(-10.0 + float(i) * 10.0, 0.025, 83.0 + float(i % 2) * 5.0)
		pool.material_override = pool_material
		marsh.add_child(pool)
	for i in range(5):
		_add_region_box(marsh, "MarshMudMound_%02d" % i, Vector3(2.0, 0.35, 1.7), Vector3(-20.0 + float(i) * 9.0, 0.16, 94.0 - float(i % 2) * 5.0), mud_material, Vector3(0.0, deg_to_rad(float(i * 19)), 0.0))

	var bone_waste := Node3D.new()
	bone_waste.name = "RegionDressing_WesternBoneWaste"
	root.add_child(bone_waste)
	var bone_material := _region_material(Color("#c5b99e"), 0.9)
	var rock_material := _region_material(Color("#514c48"), 1.0)
	for i in range(9):
		var x := -91.0 + float((i * 17) % 31)
		var z := -86.0 + float(i) * 6.1
		_add_region_cylinder(bone_waste, "BonePillar_%02d" % i, 0.12, 0.22, 1.1 + float(i % 4) * 0.32, Vector3(x, 0.7, z), bone_material, Vector3(0.0, 0.0, deg_to_rad(float((i % 3) - 1) * 18.0)))
	for i in range(7):
		_add_region_box(bone_waste, "BrokenRib_%02d" % i, Vector3(3.0, 0.22, 0.32), Vector3(-88.0 + float((i * 13) % 28), 0.28, -78.0 + float(i) * 8.0), bone_material, Vector3(0.0, 0.0, deg_to_rad(float((i % 4) * 13 - 20))))
	for i in range(6):
		_add_region_sphere(bone_waste, "BoneWasteRock_%02d" % i, Vector3(-94.0 + float((i * 11) % 32), 0.75, -92.0 + float(i) * 12.0), 0.8 + float(i % 3) * 0.35, rock_material)

	var forgotten_bank := Node3D.new()
	forgotten_bank.name = "RegionDressing_EasternForgottenBank"
	root.add_child(forgotten_bank)
	var river_stone := _region_material(Color("#59666a"), 0.86)
	var bank_lantern := _region_material(Color("#6d9ca5"), 0.35, false, Color("#3d8794"))
	for i in range(8):
		var z := -91.0 + float(i) * 10.5
		_add_region_box(forgotten_bank, "ForgottenBankStone_%02d" % i, Vector3(1.3, 0.75, 1.0), Vector3(83.0 + float(i % 2) * 3.0, 0.36, z), river_stone, Vector3(0.0, deg_to_rad(float(i * 23)), 0.0))
	for i in range(4):
		_add_region_cylinder(forgotten_bank, "ForgottenBankMarker_%02d" % i, 0.16, 0.24, 2.6, Vector3(91.0, 1.3, -72.0 + float(i) * 20.0), bank_lantern)
		_add_region_sphere(forgotten_bank, "ForgottenBankSoulLight_%02d" % i, Vector3(91.0, 2.9, -72.0 + float(i) * 20.0), 0.38, bank_lantern)

	var battlefield := Node3D.new()
	battlefield.name = "RegionDressing_AncientBattlefield"
	root.add_child(battlefield)
	var spear_material := _region_material(Color("#756b61"), 0.88)
	var banner_material := _region_material(Color("#713f46"), 0.96)
	var stone_material := _region_material(Color("#484044"), 0.98)
	for i in range(7):
		var x := -91.0 + float(i) * 7.2
		var z := 18.0 + float((i * 9) % 22)
		_add_region_cylinder(battlefield, "BrokenSpear_%02d" % i, 0.055, 0.075, 3.2, Vector3(x, 1.35, z), spear_material, Vector3(0.0, 0.0, deg_to_rad(float((i % 3) * 12 + 18))))
	for i in range(4):
		var x := -94.0 + float(i) * 15.0
		_add_region_cylinder(battlefield, "BattleStandardPole_%02d" % i, 0.07, 0.09, 4.2, Vector3(x, 2.1, 43.0), spear_material)
		_add_region_box(battlefield, "BattleStandardCloth_%02d" % i, Vector3(1.8, 2.0, 0.08), Vector3(x + 0.9, 3.1, 43.0), banner_material, Vector3(0.0, 0.0, deg_to_rad(float((i % 2) * 8 - 4))))
	for i in range(5):
		_add_region_box(battlefield, "BattlefieldTombstone_%02d" % i, Vector3(1.0, 1.8, 0.35), Vector3(-96.0 + float(i) * 10.0, 0.9, 12.0), stone_material, Vector3(0.0, deg_to_rad(float(i * 11)), deg_to_rad(float((i % 3) * 5 - 5))))


static func _region_material(color: Color, roughness: float = 0.9, transparent: bool = false, emission: Color = Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 0.8
	return material


static func _add_region_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	parent.add_child(instance)


static func _add_region_cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = material
	parent.add_child(instance)


static func _add_region_sphere(parent: Node3D, node_name: String, position: Vector3, radius: float, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	parent.add_child(instance)


static func _create_soul_lantern_fallback() -> Node3D:
	var root := Node3D.new()
	var stand := MeshInstance3D.new()
	var stand_mesh := CylinderMesh.new()
	stand_mesh.top_radius = 0.16
	stand_mesh.bottom_radius = 0.24
	stand_mesh.height = 1.65
	stand.mesh = stand_mesh
	stand.position.y = 0.82
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#393344")
	stone.roughness = 0.92
	stand.material_override = stone
	root.add_child(stand)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.58, 0.52, 0.58)
	lamp.mesh = lamp_mesh
	lamp.position.y = 1.82
	var lamp_material := StandardMaterial3D.new()
	lamp_material.albedo_color = Color("#7b91bd")
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("#537fc4")
	lamp_material.emission_energy_multiplier = 1.8
	lamp.material_override = lamp_material
	root.add_child(lamp)
	return root


func _add_world_box(root: Node3D, node_name: String, size: Vector3, world_position: Vector3, color: Color, emissive: bool = false) -> void:
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
