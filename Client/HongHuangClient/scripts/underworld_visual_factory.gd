extends RefCounted
## Procedural, replaceable visual blockouts for the Underworld bestiary.
## Keep gameplay/network state in world_scene.gd; this file only builds presentation.

const VisualModelLibrary = preload("res://scripts/visual_model_library.gd")

static func create_monster(monster_name: String, monster_level: int) -> Node3D:
	var archetype := _resolve_archetype(monster_name)
	var root := VisualModelLibrary.instantiate_model(
		archetype,
		func() -> Node3D: return _create_procedural_monster(archetype, monster_name)
	)
	root.name = "MonsterVisual"
	root.set_meta("visual_archetype", archetype)
	var level_scale := clampf(1.0 + float(maxi(monster_level - 1, 0)) * 0.018, 1.0, 1.32)
	root.scale *= Vector3.ONE * level_scale
	return root


static func _create_procedural_monster(archetype: String, monster_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "MonsterVisual"
	match archetype:
		"wolf":
			_build_wolf(root, Color("#98705a"), Color("#d9b08b"))
		"iron_beast":
			_build_iron_beast(root)
		"warrior":
			_build_warrior(root, monster_name)
		"life_soul":
			_build_wraith(root, Color("#75d79a"), Color("#b4ffd0"))
		"wind_soul":
			_build_wraith(root, Color("#67cfc5"), Color("#b6fff0"))
		"fire_soul":
			_build_wraith(root, Color("#a94f37"), Color("#ffd08a"))
			_build_fire_soul_details(root)
		"frost_soul":
			_build_wraith(root, Color("#5688b7"), Color("#d7f4ff"))
			_build_frost_soul_details(root)
		_:
			_build_wraith(root, Color("#668fc7"), Color("#c1e1ff"))
	return root


static func _resolve_archetype(monster_name: String) -> String:
	if monster_name.contains("荒原狼") or monster_name.contains("狼"):
		return "wolf"
	if monster_name.contains("铁骨") or monster_name.contains("兽魂"):
		return "iron_beast"
	if monster_name.contains("战神") or monster_name.contains("战魂") or monster_name.contains("炽战"):
		return "warrior"
	if monster_name.contains("生机") or monster_name.contains("古魂"):
		return "life_soul"
	if monster_name.contains("疾风") or monster_name.contains("风灵"):
		return "wind_soul"
	if monster_name.contains("烈焰") or monster_name.contains("火灵") or monster_name.contains("炎魂") or monster_name.contains("炽魂"):
		return "fire_soul"
	if monster_name.contains("寒冰") or monster_name.contains("冰魄") or monster_name.contains("霜魂"):
		return "frost_soul"
	return "wraith"


static func _material(color: Color, emission_energy: float = 0.0, metallic: float = 0.0, alpha: float = 1.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.roughness = 0.72
	material.metallic = metallic
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material


static func _part(parent: Node3D, part_name: String, mesh: Mesh, at: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, emission_energy: float = 0.0, metallic: float = 0.0, alpha: float = 1.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.position = at
	instance.rotation = rotation
	instance.material_override = _material(color, emission_energy, metallic, alpha)
	parent.add_child(instance)
	return instance


static func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh


static func _sphere(radius: float, height: float = -1.0) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height if height > 0.0 else radius * 2.0
	mesh.radial_segments = 18
	mesh.rings = 10
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh



static func create_fengdu_wall_segment() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "FengduWallSegment"
	var stone := Color("#45414f")
	var trim := Color("#786b73")
	_part(root, "WallBase", _box(Vector3(8.0, 0.72, 1.2)), Vector3(0.0, 0.36, 0.0), Color("#302e3a"))
	_part(root, "WallBody", _box(Vector3(7.4, 3.8, 0.92)), Vector3(0.0, 2.55, 0.0), stone)
	_part(root, "WallCoping", _box(Vector3(8.2, 0.34, 1.25)), Vector3(0.0, 4.62, 0.0), trim)
	for x in [-3.4, -1.7, 0.0, 1.7, 3.4]:
		_part(root, "Battlement_" + str(x), _box(Vector3(0.72, 0.82, 1.0)), Vector3(x, 5.18, 0.0), stone)
	_part(root, "WallRune", _box(Vector3(0.16, 1.7, 0.08)), Vector3(0.0, 2.55, -0.51), Color("#a77d59"), Vector3.ZERO, 0.28, 0.22)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.4, 4.2, 1.0)
	collision.shape = shape
	collision.position = Vector3(0.0, 2.5, 0.0)
	root.add_child(collision)
	return root


static func create_ghost_lantern() -> Node3D:
	var root := Node3D.new()
	root.name = "GhostLantern"
	var dark_iron := Color("#34313c")
	var bronze := Color("#8e7657")
	var ghost_fire := Color("#85c8c1")
	var base := CylinderMesh.new()
	base.top_radius = 0.48
	base.bottom_radius = 0.62
	base.height = 0.28
	base.radial_segments = 10
	_part(root, "LanternBase", base, Vector3(0.0, 0.14, 0.0), dark_iron, Vector3.ZERO, 0.0, 0.5)
	var post := CylinderMesh.new()
	post.top_radius = 0.12
	post.bottom_radius = 0.18
	post.height = 2.4
	post.radial_segments = 10
	_part(root, "LanternPost", post, Vector3(0.0, 1.48, 0.0), bronze, Vector3.ZERO, 0.0, 0.55)
	_part(root, "LanternBowl", _box(Vector3(0.92, 0.18, 0.92)), Vector3(0.0, 2.64, 0.0), dark_iron, Vector3.ZERO, 0.0, 0.42)
	_part(root, "LanternGlass", _box(Vector3(0.66, 0.88, 0.66)), Vector3(0.0, 3.16, 0.0), ghost_fire, Vector3.ZERO, 1.8, 0.12, 0.48)
	_part(root, "LanternCap", _box(Vector3(1.08, 0.18, 1.08)), Vector3(0.0, 3.68, 0.0), bronze, Vector3.ZERO, 0.0, 0.5)
	var point := OmniLight3D.new()
	point.name = "GhostLanternLight"
	point.position = Vector3(0.0, 3.12, 0.0)
	point.light_color = ghost_fire
	point.light_energy = 1.15
	point.omni_range = 8.0
	root.add_child(point)
	return root


static func create_soul_tombstone() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "SoulTombstone"
	var stone := Color("#55515d")
	var inscription := Color("#92aaa8")
	_part(root, "TombBase", _box(Vector3(1.25, 0.24, 0.72)), Vector3(0.0, 0.12, 0.0), Color("#373641"))
	_part(root, "TombBody", _box(Vector3(0.86, 1.35, 0.30)), Vector3(0.0, 0.91, 0.0), stone)
	_part(root, "TombCrown", _sphere(0.44, 0.48), Vector3(0.0, 1.55, 0.0), stone)
	_part(root, "TombInscription", _box(Vector3(0.08, 0.72, 0.035)), Vector3(0.0, 0.96, -0.17), inscription, Vector3.ZERO, 0.25)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, 1.8, 0.38)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.9, 0.0)
	root.add_child(collision)
	return root


static func create_soul_pillar() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "SoulPillar"
	var stone := Color("#3c3948")
	var rune := Color("#8bbec4")
	_part(root, "PillarFoot", _box(Vector3(1.7, 0.35, 1.7)), Vector3(0.0, 0.18, 0.0), stone)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.42
	shaft.bottom_radius = 0.58
	shaft.height = 4.8
	shaft.radial_segments = 8
	_part(root, "PillarShaft", shaft, Vector3(0.0, 2.72, 0.0), stone, Vector3.ZERO, 0.0, 0.24)
	_part(root, "PillarCap", _box(Vector3(1.25, 0.32, 1.25)), Vector3(0.0, 5.2, 0.0), Color("#65596b"))
	_part(root, "PillarSigil", _box(Vector3(0.10, 2.5, 0.12)), Vector3(0.0, 2.85, -0.48), rune, Vector3.ZERO, 1.0, 0.15)
	return root


static func create_fengdu_watchtower() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "FengduWatchtower"
	var stone := Color("#45414f")
	var trim := Color("#897783")
	var dark_roof := Color("#242638")
	_part(root, "TowerFoot", _box(Vector3(3.8, 0.55, 3.8)), Vector3(0.0, 0.28, 0.0), Color("#302e3a"))
	_part(root, "TowerBase", _box(Vector3(3.1, 2.0, 3.1)), Vector3(0.0, 1.45, 0.0), stone)
	_part(root, "TowerUpper", _box(Vector3(2.7, 2.4, 2.7)), Vector3(0.0, 3.55, 0.0), trim)
	for side in [-1.0, 1.0]:
		_part(root, "ArrowSlit" + str(side), _box(Vector3(0.12, 0.9, 0.08)), Vector3(side * 0.72, 3.65, -1.37), Color("#b6a0a0"), Vector3.ZERO, 0.18)
	_part(root, "RoofLower", _box(Vector3(4.0, 0.35, 4.0)), Vector3(0.0, 4.92, 0.0), dark_roof)
	_part(root, "RoofUpper", _box(Vector3(3.0, 0.32, 3.0)), Vector3(0.0, 5.34, 0.0), dark_roof)
	_part(root, "RoofRidge", _box(Vector3(2.1, 0.22, 0.42)), Vector3(0.0, 5.62, 0.0), trim)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.2, 5.0, 3.2)
	collision.shape = shape
	collision.position = Vector3(0.0, 2.55, 0.0)
	root.add_child(collision)
	return root


static func create_ghost_market_stall() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "GhostMarketStall"
	var wood := Color("#51443f")
	var cloth := Color("#59475f")
	var gold := Color("#b18a5a")
	_part(root, "Counter", _box(Vector3(3.4, 1.05, 1.25)), Vector3(0.0, 0.58, 0.0), wood)
	_part(root, "CounterTop", _box(Vector3(3.65, 0.16, 1.42)), Vector3(0.0, 1.16, 0.0), gold, Vector3.ZERO, 0.0, 0.22)
	for x in [-1.48, 1.48]:
		for z in [-0.48, 0.48]:
			_part(root, "CanopyPost_%s_%s" % [x, z], _box(Vector3(0.12, 2.65, 0.12)), Vector3(x, 1.35, z), wood)
	_part(root, "Canopy", _box(Vector3(3.9, 0.18, 1.85)), Vector3(0.0, 2.72, 0.0), cloth)
	_part(root, "CanopyValance", _box(Vector3(3.9, 0.42, 0.12)), Vector3(0.0, 2.42, -0.91), Color("#806078"))
	for x in [-0.9, 0.0, 0.9]:
		_part(root, "SpiritJar" + str(x), _sphere(0.22, 0.36), Vector3(x, 1.48, -0.18), Color("#83b8ad"), Vector3.ZERO, 0.5, 0.1, 0.82)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.5, 2.8, 1.35)
	collision.shape = shape
	collision.position = Vector3(0.0, 1.4, 0.0)
	root.add_child(collision)
	return root


static func create_yinsi_office_facade() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "YinsiOfficeFacade"
	var stone := Color("#48414e")
	var timber := Color("#493b3c")
	var trim := Color("#a78a65")
	var roof := Color("#252638")
	_part(root, "OfficeFoundation", _box(Vector3(10.0, 0.55, 4.8)), Vector3(0.0, 0.28, 0.0), Color("#302d39"))
	_part(root, "OfficeWall", _box(Vector3(8.8, 3.3, 3.2)), Vector3(0.0, 2.05, 0.35), stone)
	_part(root, "DoorFrame", _box(Vector3(2.5, 2.9, 0.28)), Vector3(0.0, 1.75, -1.34), timber)
	_part(root, "DoorOpening", _box(Vector3(1.8, 2.45, 0.10)), Vector3(0.0, 1.48, -1.51), Color("#171722"))
	for x in [-4.1, -2.8, 2.8, 4.1]:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.18
		pillar.bottom_radius = 0.24
		pillar.height = 3.9
		pillar.radial_segments = 10
		_part(root, "FrontPillar" + str(x), pillar, Vector3(x, 2.05, -1.55), timber, Vector3.ZERO, 0.0, 0.18)
	_part(root, "FrontBeam", _box(Vector3(9.6, 0.38, 0.48)), Vector3(0.0, 4.0, -1.52), trim, Vector3.ZERO, 0.0, 0.2)
	_part(root, "RoofLower", _box(Vector3(10.4, 0.38, 5.2)), Vector3(0.0, 4.32, 0.0), roof)
	_part(root, "RoofUpper", _box(Vector3(8.6, 0.28, 3.8)), Vector3(0.0, 4.72, 0.0), roof)
	_part(root, "RoofRidge", _box(Vector3(6.8, 0.22, 0.42)), Vector3(0.0, 4.98, 0.0), trim)
	var plaque := _box(Vector3(3.0, 0.82, 0.18))
	_part(root, "OfficePlaque", plaque, Vector3(0.0, 3.42, -1.82), Color("#30283d"))
	var sign := Label3D.new()
	sign.name = "OfficeName"
	sign.text = "陰 司 衙 門"
	sign.position = Vector3(0.0, 3.35, -1.70)
	sign.font_size = 30
	sign.outline_size = 6
	sign.modulate = Color("#e0c99d")
	root.add_child(sign)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(9.0, 4.3, 3.5)
	collision.shape = shape
	collision.position = Vector3(0.0, 2.15, 0.3)
	root.add_child(collision)
	return root


static func create_fengdu_residential_house() -> Node3D:
	# Reusable narrow-lot home for Fengdu's civilian quarter.
	var root := StaticBody3D.new()
	root.name = "FengduResidentialHouse"
	var plaster := Color("#62545a")
	var timber := Color("#382f38")
	var roof := Color("#282938")
	var bronze := Color("#987b5d")
	var window_glow := Color("#a8c9b2")
	_part(root, "StonePlinth", _box(Vector3(6.4, 0.42, 5.4)), Vector3(0.0, 0.21, 0.0), Color("#393640"))
	_part(root, "HouseBody", _box(Vector3(5.6, 3.0, 4.5)), Vector3(0.0, 1.92, 0.0), plaster)
	_part(root, "FrontDoorFrame", _box(Vector3(1.55, 2.5, 0.22)), Vector3(0.0, 1.55, -2.28), timber)
	_part(root, "FrontDoor", _box(Vector3(1.20, 2.25, 0.10)), Vector3(0.0, 1.42, -2.42), Color("#211e29"))
	for side in [-1.0, 1.0]:
		_part(root, "WindowFrame" + str(side), _box(Vector3(1.10, 1.05, 0.18)), Vector3(side * 1.82, 2.05, -2.30), timber)
		_part(root, "WindowPaper" + str(side), _box(Vector3(0.82, 0.78, 0.06)), Vector3(side * 1.82, 2.05, -2.41), window_glow, Vector3.ZERO, 0.25, 0.0, 0.72)
		_part(root, "WindowCross" + str(side), _box(Vector3(0.07, 0.88, 0.08)), Vector3(side * 1.82, 2.05, -2.47), bronze)
	for x in [-2.45, 2.45]:
		var post := _box(Vector3(0.18, 3.15, 0.20))
		_part(root, "VerandaPost" + str(x), post, Vector3(x, 1.78, -2.38), timber)
	_part(root, "VerandaBeam", _box(Vector3(5.9, 0.20, 0.34)), Vector3(0.0, 3.28, -2.40), bronze)
	_part(root, "RoofLower", _box(Vector3(6.8, 0.34, 5.8)), Vector3(0.0, 3.58, 0.0), roof)
	_part(root, "RoofUpper", _box(Vector3(5.8, 0.28, 4.8)), Vector3(0.0, 3.94, 0.0), roof)
	_part(root, "RoofRidge", _box(Vector3(4.4, 0.20, 0.34)), Vector3(0.0, 4.18, 0.0), bronze)
	for side in [-1.0, 1.0]:
		_part(root, "EaveTip" + str(side), _box(Vector3(0.55, 0.16, 0.38)), Vector3(side * 3.12, 3.62, -2.65), bronze, Vector3(0.0, 0.0, side * -0.12))
	var plaque := _box(Vector3(1.65, 0.48, 0.12))
	_part(root, "HousePlaque", plaque, Vector3(0.0, 2.92, -2.58), Color("#30283d"))
	var sign := Label3D.new()
	sign.name = "HouseSign"
	sign.text = "酆 都 民 居"
	sign.position = Vector3(0.0, 2.90, -2.66)
	sign.font_size = 20
	sign.outline_size = 5
	sign.modulate = Color("#e0c99d")
	root.add_child(sign)
	# Split the shell into wall sections so the front doorway remains passable.
	for side in [-1.0, 1.0]:
		var side_wall := CollisionShape3D.new()
		var side_shape := BoxShape3D.new()
		side_shape.size = Vector3(0.22, 3.0, 4.45)
		side_wall.shape = side_shape
		side_wall.position = Vector3(side * 2.68, 1.82, 0.0)
		root.add_child(side_wall)
	var rear_wall := CollisionShape3D.new()
	var rear_shape := BoxShape3D.new()
	rear_shape.size = Vector3(5.55, 3.0, 0.22)
	rear_wall.shape = rear_shape
	rear_wall.position = Vector3(0.0, 1.82, 2.12)
	root.add_child(rear_wall)
	for side in [-1.0, 1.0]:
		var front_wall := CollisionShape3D.new()
		var front_shape := BoxShape3D.new()
		front_shape.size = Vector3(1.95, 3.0, 0.22)
		front_wall.shape = front_shape
		front_wall.position = Vector3(side * 1.82, 1.82, -2.18)
		root.add_child(front_wall)
	var door_lintel := CollisionShape3D.new()
	var lintel_shape := BoxShape3D.new()
	lintel_shape.size = Vector3(1.55, 0.48, 0.22)
	door_lintel.shape = lintel_shape
	door_lintel.position = Vector3(0.0, 3.10, -2.18)
	root.add_child(door_lintel)
	return root


static func create_ghost_market_shop() -> Node3D:
	# A permanent two-storey shop frontage; stalls remain separate props.
	var root := StaticBody3D.new()
	root.name = "GhostMarketShop"
	var timber := Color("#4b3938")
	var plaster := Color("#574955")
	var roof := Color("#292638")
	var gold := Color("#b18a5a")
	var jade := Color("#78b6a9")
	_part(root, "ShopFoundation", _box(Vector3(7.6, 0.48, 5.8)), Vector3(0.0, 0.24, 0.0), Color("#34313d"))
	_part(root, "ShopBody", _box(Vector3(6.8, 4.5, 4.8)), Vector3(0.0, 2.70, 0.0), plaster)
	_part(root, "ShopDoor", _box(Vector3(2.05, 2.65, 0.12)), Vector3(0.0, 1.56, -2.48), Color("#201d28"))
	for side in [-1.0, 1.0]:
		_part(root, "ShopFrontPillar" + str(side), _box(Vector3(0.24, 4.2, 0.28)), Vector3(side * 3.12, 2.35, -2.55), timber)
		_part(root, "UpperWindowFrame" + str(side), _box(Vector3(1.35, 1.12, 0.16)), Vector3(side * 1.72, 3.65, -2.48), gold)
		_part(root, "UpperWindow" + str(side), _box(Vector3(1.08, 0.84, 0.07)), Vector3(side * 1.72, 3.65, -2.58), jade, Vector3.ZERO, 0.35, 0.0, 0.62)
	_part(root, "ShopColumnBase" + str(side), _box(Vector3(0.42, 0.28, 0.42)), Vector3(side * 3.12, 0.38, -2.55), gold)
	_part(root, "ShopColumnCap" + str(side), _box(Vector3(0.42, 0.28, 0.42)), Vector3(side * 3.12, 4.38, -2.55), gold)
	_part(root, "ShopSignboard", _box(Vector3(2.6, 0.72, 0.16)), Vector3(0.0, 4.42, -2.72), Color("#30283d"))
	var sign := Label3D.new()
	sign.name = "ShopName"
	sign.text = "幽 都 鬼 市"
	sign.position = Vector3(0.0, 4.40, -2.82)
	sign.font_size = 26
	sign.outline_size = 6
	sign.modulate = Color("#e5c894")
	root.add_child(sign)
	_part(root, "Awning", _box(Vector3(7.4, 0.18, 1.25)), Vector3(0.0, 2.85, -3.05), Color("#60465b"))
	_part(root, "AwningValance", _box(Vector3(7.4, 0.32, 0.12)), Vector3(0.0, 2.62, -3.64), Color("#98705f"))
	_part(root, "RoofLower", _box(Vector3(7.8, 0.34, 5.9)), Vector3(0.0, 5.05, 0.0), roof)
	_part(root, "RoofUpper", _box(Vector3(6.4, 0.28, 4.8)), Vector3(0.0, 5.40, 0.0), roof)
	_part(root, "RoofRidge", _box(Vector3(4.8, 0.20, 0.36)), Vector3(0.0, 5.66, 0.0), gold)
	# Keep a central shop entrance open; collision is split around the doorway.
	for side in [-1.0, 1.0]:
		var side_wall := CollisionShape3D.new()
		var side_shape := BoxShape3D.new()
		side_shape.size = Vector3(0.24, 4.5, 4.75)
		side_wall.shape = side_shape
		side_wall.position = Vector3(side * 3.25, 2.55, 0.0)
		root.add_child(side_wall)
	var rear_wall := CollisionShape3D.new()
	var rear_shape := BoxShape3D.new()
	rear_shape.size = Vector3(6.7, 4.5, 0.24)
	rear_wall.shape = rear_shape
	rear_wall.position = Vector3(0.0, 2.55, 2.28)
	root.add_child(rear_wall)
	for side in [-1.0, 1.0]:
		var front_wall := CollisionShape3D.new()
		var front_shape := BoxShape3D.new()
		front_shape.size = Vector3(2.30, 4.5, 0.22)
		front_wall.shape = front_shape
		front_wall.position = Vector3(side * 2.27, 2.55, -2.36)
		root.add_child(front_wall)
	var door_lintel := CollisionShape3D.new()
	var lintel_shape := BoxShape3D.new()
	lintel_shape.size = Vector3(2.05, 1.10, 0.22)
	door_lintel.shape = lintel_shape
	door_lintel.position = Vector3(0.0, 4.25, -2.36)
	root.add_child(door_lintel)
	return root


static func create_fengdu_residential_lane() -> Node3D:
	# Review composition for narrow homes, a shop frontage and a lit pedestrian lane.
	var root := Node3D.new()
	root.name = "FengduResidentialLanePreview"
	var paving := Color("#514c55")
	for index in range(5):
		_part(root, "LanePaving" + str(index), _box(Vector3(4.0, 0.14, 4.0)),
			Vector3(0.0, 0.04, -8.0 + float(index) * 4.0), paving)
	var left_house := create_fengdu_residential_house()
	left_house.position = Vector3(-7.0, 0.0, -4.0)
	root.add_child(left_house)
	var right_house := create_fengdu_residential_house()
	right_house.position = Vector3(7.0, 0.0, 0.0)
	right_house.rotation.y = PI
	root.add_child(right_house)
	var shop := create_ghost_market_shop()
	shop.position = Vector3(0.0, 0.0, -13.0)
	root.add_child(shop)
	for z in [-6.0, 2.0, 10.0]:
		var lantern := create_ghost_lantern()
		lantern.position = Vector3(0.0, 0.0, z)
		lantern.scale = Vector3.ONE * 0.72
		root.add_child(lantern)
	return root


static func create_fengdu_street_tile() -> Node3D:
	# An 8 m modular paving tile with low curbs; tiles can be rotated and tiled.
	var root := StaticBody3D.new()
	root.name = "FengduStreetTile"
	var paving := Color("#514c55")
	var curb := Color("#716875")
	var inset := Color("#393744")
	_part(root, "RoadBed", _box(Vector3(8.0, 0.22, 8.0)), Vector3(0.0, -0.11, 0.0), inset)
	_part(root, "PavingSurface", _box(Vector3(7.82, 0.12, 7.82)), Vector3(0.0, 0.06, 0.0), paving)
	for side in [-1.0, 1.0]:
		_part(root, "CurbX" + str(side), _box(Vector3(0.22, 0.28, 8.0)), Vector3(side * 3.89, 0.14, 0.0), curb)
		_part(root, "CurbZ" + str(side), _box(Vector3(8.0, 0.28, 0.22)), Vector3(0.0, 0.14, side * 3.89), curb)
	for offset in [-2.0, 0.0, 2.0]:
		_part(root, "DrainGroove" + str(offset), _box(Vector3(0.045, 0.025, 7.4)), Vector3(offset, 0.13, 0.0), Color("#77717b"))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.82, 0.18, 7.82)
	collision.shape = shape
	collision.position = Vector3(0.0, -0.02, 0.0)
	root.add_child(collision)
	return root


static func create_fengdu_residential_district() -> Node3D:
	# Compact district-scale review composition, not a production streaming chunk.
	var root := Node3D.new()
	root.name = "FengduResidentialDistrictPreview"
	# 5 x 5 modular street tiles create a broad walkable grid.
	for x_index in range(5):
		for z_index in range(5):
			var tile := create_fengdu_street_tile()
			tile.position = Vector3(-16.0 + float(x_index) * 8.0, 0.0, -16.0 + float(z_index) * 8.0)
			root.add_child(tile)
	# Residential frontage on the west and east edges.
	for z in [-10.0, 2.0, 14.0]:
		var west_house := create_fengdu_residential_house()
		west_house.position = Vector3(-21.0, 0.0, z)
		root.add_child(west_house)
		var east_house := create_fengdu_residential_house()
		east_house.position = Vector3(21.0, 0.0, z)
		east_house.rotation.y = PI
		root.add_child(east_house)
	# Permanent shops face the central market street from its far end.
	for x in [-8.0, 0.0, 8.0]:
		var shop := create_ghost_market_shop()
		shop.position = Vector3(x, 0.0, 22.0)
		shop.rotation.y = PI
		root.add_child(shop)
	# Repeated lantern rhythm marks the pedestrian route and corners.
	for x in [-12.0, 12.0]:
		for z in [-12.0, 0.0, 12.0]:
			var lantern := create_ghost_lantern()
			lantern.position = Vector3(x, 0.0, z)
			lantern.scale = Vector3.ONE * 0.78
			root.add_child(lantern)
	# A central notice stone gives the district a recognizable gathering point.
	var notice := create_soul_tombstone()
	notice.name = "DistrictNoticeStone"
	notice.position = Vector3(0.0, 0.0, -8.0)
	notice.scale = Vector3.ONE * 0.85
	root.add_child(notice)
	return root


static func create_fengdu_city_block() -> Node3D:
	# A compact review layout: fortified perimeter, gate towers, inner paving,
	# a small ghost market and the Yinsi office. This is a reusable kit preview,
	# not a replacement for the streamed production city map.
	var root := Node3D.new()
	root.name = "FengduCityBlockPreview"
	var paving := Color("#514c55")
	for x_index in range(4):
		for z_index in range(4):
			var tile := _box(Vector3(4.35, 0.16, 4.35))
			_part(root, "StreetPaving_%d_%d" % [x_index, z_index], tile,
				Vector3(-6.6 + float(x_index) * 4.4, 0.02, -6.6 + float(z_index) * 4.4), paving)
	for index in range(2):
		var north := create_fengdu_wall_segment()
		north.position = Vector3(-4.0 + float(index) * 8.0, 0.0, -9.0)
		root.add_child(north)
		var west := create_fengdu_wall_segment()
		west.position = Vector3(-9.0, 0.0, -4.0 + float(index) * 8.0)
		west.rotation.y = PI * 0.5
		root.add_child(west)
		var east := create_fengdu_wall_segment()
		east.position = Vector3(9.0, 0.0, -4.0 + float(index) * 8.0)
		east.rotation.y = PI * 0.5
		root.add_child(east)
	for x in [-9.0, 9.0]:
		for z in [-9.0, 9.0]:
			var tower := create_fengdu_watchtower()
			tower.position = Vector3(x, 0.0, z)
			root.add_child(tower)
	var office := create_yinsi_office_facade()
	office.position = Vector3(-5.2, 0.0, -5.0)
	root.add_child(office)
	var reincarnation_hall := create_reincarnation_hall()
	reincarnation_hall.position = Vector3(4.8, 0.0, -4.8)
	root.add_child(reincarnation_hall)
	var inner_gate := create_fengdu_inner_gate()
	inner_gate.position = Vector3(0.0, 0.0, 9.0)
	root.add_child(inner_gate)
	for x in [-6.0, 6.0]:
		var stall := create_ghost_market_stall()
		stall.position = Vector3(x, 0.0, 3.8)
		root.add_child(stall)
	for x in [-8.0, 8.0]:
		var lantern := create_ghost_lantern()
		lantern.position = Vector3(x, 0.0, -0.2)
		root.add_child(lantern)
	return root


static func create_fengdu_inner_gate() -> Node3D:
	# Smaller street gate; the central passage remains open.
	var root := StaticBody3D.new()
	root.name = "FengduInnerGate"
	var stone := Color("#514b5c")
	var trim := Color("#a18461")
	var roof := Color("#29283a")
	_part(root, "GateBase", _box(Vector3(10.0, 0.35, 3.2)), Vector3(0.0, 0.18, 0.0), Color("#393543"))
	for side in [-1.0, 1.0]:
		var x := side * 4.0
		_part(root, "GatePier" + str(side), _box(Vector3(1.15, 4.4, 1.55)), Vector3(x, 2.35, 0.0), stone)
		_part(root, "GatePierCap" + str(side), _box(Vector3(1.5, 0.32, 1.85)), Vector3(x, 4.72, 0.0), trim)
		var pier_collision := CollisionShape3D.new()
		var pier_shape := BoxShape3D.new()
		pier_shape.size = Vector3(1.15, 4.4, 1.55)
		pier_collision.shape = pier_shape
		pier_collision.position = Vector3(x, 2.35, 0.0)
		root.add_child(pier_collision)
	_part(root, "GateLintel", _box(Vector3(8.6, 0.82, 1.6)), Vector3(0.0, 5.0, 0.0), stone)
	_part(root, "GateRoofLower", _box(Vector3(10.8, 0.32, 3.3)), Vector3(0.0, 5.62, 0.0), roof)
	_part(root, "GateRoofUpper", _box(Vector3(8.6, 0.24, 2.5)), Vector3(0.0, 5.94, 0.0), roof)
	_part(root, "GateRoofRidge", _box(Vector3(6.8, 0.20, 0.32)), Vector3(0.0, 6.16, 0.0), trim)
	_part(root, "GatePlaque", _box(Vector3(2.8, 0.72, 0.16)), Vector3(0.0, 4.95, -0.88), Color("#332b3d"))
	var title := Label3D.new()
	title.name = "GateTitle"
	title.text = "酆 都 内 城"
	title.position = Vector3(0.0, 4.92, -0.98)
	title.font_size = 28
	title.outline_size = 6
	title.modulate = Color("#e0c99d")
	root.add_child(title)
	var lintel_collision := CollisionShape3D.new()
	var lintel_shape := BoxShape3D.new()
	lintel_shape.size = Vector3(8.6, 0.82, 1.6)
	lintel_collision.shape = lintel_shape
	lintel_collision.position = Vector3(0.0, 5.0, 0.0)
	root.add_child(lintel_collision)
	return root


static func create_reincarnation_hall() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "ReincarnationHall"
	var stone := Color("#494452")
	var timber := Color("#493b42")
	var bronze := Color("#b18c5c")
	var roof := Color("#252638")
	_part(root, "HallFoundation", _box(Vector3(8.8, 0.55, 6.8)), Vector3(0.0, 0.28, 0.0), Color("#302d39"))
	_part(root, "HallBody", _box(Vector3(7.4, 3.1, 5.0)), Vector3(0.0, 1.98, 0.0), stone)
	_part(root, "HallDoor", _box(Vector3(2.0, 2.55, 0.14)), Vector3(0.0, 1.56, -2.58), Color("#171722"))
	for x in [-3.0, -1.9, 1.9, 3.0]:
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.15
		pillar.bottom_radius = 0.20
		pillar.height = 3.7
		pillar.radial_segments = 10
		_part(root, "HallPillar" + str(x), pillar, Vector3(x, 1.95, -2.55), timber)
	_part(root, "HallBeam", _box(Vector3(8.0, 0.34, 0.38)), Vector3(0.0, 3.82, -2.55), bronze)
	_part(root, "HallRoofLower", _box(Vector3(9.4, 0.38, 7.2)), Vector3(0.0, 4.0, 0.0), roof)
	_part(root, "HallRoofUpper", _box(Vector3(7.5, 0.30, 5.5)), Vector3(0.0, 4.42, 0.0), roof)
	_part(root, "HallRoofRidge", _box(Vector3(5.6, 0.22, 0.38)), Vector3(0.0, 4.70, 0.0), bronze)
	_part(root, "WheelHalo", _sphere(0.82, 0.16), Vector3(0.0, 2.95, -2.72), Color("#86b9b4"), Vector3(PI * 0.5, 0.0, 0.0), 1.0, 0.22)
	_part(root, "WheelHub", _sphere(0.22), Vector3(0.0, 2.95, -2.84), Color("#e1c38a"), Vector3.ZERO, 1.2, 0.25)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		_part(root, "WheelSpoke" + str(index), _box(Vector3(0.08, 1.35, 0.08)),
			Vector3(sin(angle) * 0.48, 2.95 + cos(angle) * 0.48, -2.82),
			Color("#c5aa7b"), Vector3(0.0, 0.0, -angle), 0.25, 0.2)
	_part(root, "HallPlaque", _box(Vector3(3.0, 0.72, 0.16)), Vector3(0.0, 3.45, -2.78), Color("#30283d"))
	var sign := Label3D.new()
	sign.name = "HallTitle"
	sign.text = "六 道 轮 回 殿"
	sign.position = Vector3(0.0, 3.43, -2.88)
	sign.font_size = 28
	sign.outline_size = 6
	sign.modulate = Color("#e0c99d")
	root.add_child(sign)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.5, 4.0, 5.1)
	collision.shape = shape
	collision.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(collision)
	return root


static func create_fengdu_gate() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "FengduGhostGate"
	var stone := Color("#494354")
	var stone_light := Color("#62566d")
	var bronze := Color("#887451")
	var roof := Color("#252638")
	_part(root, "Foundation", _box(Vector3(14.0, 0.48, 4.6)), Vector3(0.0, 0.18, -18.0), Color("#34313f"))
	for side in [-1.0, 1.0]:
		var x: float = float(side) * 5.0
		var column := CylinderMesh.new()
		column.top_radius = 0.52
		column.bottom_radius = 0.72
		column.height = 7.4
		column.radial_segments = 12
		_part(root, "GatePillar" + str(side), column, Vector3(x, 4.05, -18.0), stone, Vector3.ZERO, 0.0, 0.08)
		_part(root, "PillarFoot" + str(side), _box(Vector3(1.65, 0.62, 1.65)), Vector3(x, 0.72, -18.0), stone_light)
		_part(root, "PillarCapital" + str(side), _box(Vector3(1.75, 0.48, 1.75)), Vector3(x, 7.72, -18.0), stone_light)
		_part(root, "PillarRune" + str(side), _box(Vector3(0.12, 3.2, 0.16)), Vector3(x, 4.2, -17.26), bronze, Vector3.ZERO, 0.22, 0.18)
		var pillar_collision := CollisionShape3D.new()
		var pillar_shape := BoxShape3D.new()
		pillar_shape.size = Vector3(1.35, 7.6, 1.35)
		pillar_collision.shape = pillar_shape
		pillar_collision.position = Vector3(x, 4.0, -18.0)
		root.add_child(pillar_collision)
	_part(root, "GateLintel", _box(Vector3(12.0, 1.45, 1.85)), Vector3(0.0, 8.25, -18.0), stone_light)
	_part(root, "UpperBeam", _box(Vector3(10.6, 0.38, 1.55)), Vector3(0.0, 9.15, -18.0), bronze, Vector3.ZERO, 0.0, 0.28)
	_part(root, "LowerRoof", _box(Vector3(14.0, 0.42, 4.4)), Vector3(0.0, 9.52, -18.0), roof, Vector3.ZERO, 0.0, 0.16)
	_part(root, "UpperRoof", _box(Vector3(10.4, 0.34, 3.2)), Vector3(0.0, 10.02, -18.0), roof, Vector3.ZERO, 0.0, 0.16)
	_part(root, "RoofRidge", _box(Vector3(8.0, 0.26, 0.42)), Vector3(0.0, 10.32, -18.0), bronze, Vector3.ZERO, 0.0, 0.32)
	for side in [-1.0, 1.0]:
		_part(root, "Eave" + str(side), _box(Vector3(2.0, 0.20, 0.42)), Vector3(side * 6.6, 9.72, -18.0), bronze, Vector3(0.0, 0.0, side * -0.16), 0.0, 0.28)
	_part(root, "GateTablet", _box(Vector3(4.2, 1.35, 0.32)), Vector3(0.0, 7.05, -16.98), Color("#30283d"), Vector3.ZERO, 0.0, 0.12)
	var tablet_text := Label3D.new()
	tablet_text.name = "GateName"
	tablet_text.text = "酆 都 鬼 门 关"
	tablet_text.position = Vector3(0.0, 7.03, -16.78)
	tablet_text.font_size = 42
	tablet_text.outline_size = 8
	tablet_text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tablet_text.modulate = Color("#d7c7e8")
	root.add_child(tablet_text)
	var lintel_collision := CollisionShape3D.new()
	var lintel_shape := BoxShape3D.new()
	lintel_shape.size = Vector3(12.0, 1.45, 1.85)
	lintel_collision.shape = lintel_shape
	lintel_collision.position = Vector3(0.0, 8.25, -18.0)
	root.add_child(lintel_collision)
	return root

static func _build_wolf(root: Node3D, hide_color: Color, bone_color: Color) -> void:
	_part(root, "Torso", _capsule(0.36, 1.45), Vector3(0.0, 0.62, 0.05), hide_color, Vector3(PI * 0.5, 0.0, 0.0))
	_part(root, "Chest", _sphere(0.37), Vector3(0.0, 0.68, -0.42), hide_color)
	_part(root, "Head", _sphere(0.29), Vector3(0.0, 0.83, -0.66), bone_color)
	_part(root, "Muzzle", _capsule(0.13, 0.48), Vector3(0.0, 0.70, -0.91), bone_color, Vector3(PI * 0.5, 0.0, 0.0))
	var jaw_pivot := Node3D.new()
	jaw_pivot.name = "JawPivot"
	jaw_pivot.position = Vector3(0.0, 0.70, -0.82)
	root.add_child(jaw_pivot)
	_part(jaw_pivot, "LowerJaw", _capsule(0.085, 0.34), Vector3(0.0, -0.08, -0.10), bone_color, Vector3(PI * 0.5, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_part(root, "Ear" + str(side), _capsule(0.075, 0.34), Vector3(side * 0.19, 1.10, -0.63), hide_color, Vector3(0.0, 0.0, side * -0.22))
		_part(root, "Eye" + str(side), _sphere(0.055), Vector3(side * 0.205, 0.88, -0.88), Color("#ffc46d"), Vector3.ZERO, 1.8)
		for leg_index in range(2):
			var front := leg_index == 0
			var leg_pivot := Node3D.new()
			leg_pivot.name = ("FrontLeg" if front else "HindLeg") + ("Left" if side < 0.0 else "Right")
			leg_pivot.position = Vector3(side * 0.25, 0.56, -0.36 if front else 0.42)
			root.add_child(leg_pivot)
			_part(leg_pivot, "LowerLeg", _capsule(0.105, 0.66), Vector3(0.0, -0.27, 0.0), hide_color)
			_part(leg_pivot, "Paw", _sphere(0.12), Vector3(0.0, -0.56, -0.045), bone_color)
	var tail_pivot := Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0.0, 0.78, 0.72)
	root.add_child(tail_pivot)
	_part(tail_pivot, "TailBase", _capsule(0.10, 0.48), Vector3(0.0, 0.16, 0.14), hide_color, Vector3(-0.58, 0.0, 0.0))
	_part(tail_pivot, "TailTip", _sphere(0.12), Vector3(0.0, 0.36, 0.28), bone_color)


static func _build_iron_beast(root: Node3D) -> void:
	var iron := Color("#59616c")
	var edge := Color("#b6a987")
	var ember := Color("#d47b45")
	_part(root, "IronCore", _capsule(0.48, 1.65), Vector3(0.0, 0.66, 0.05), iron, Vector3(PI * 0.5, 0.0, 0.0), 0.0, 0.52)
	_part(root, "ChestPlate", _box(Vector3(0.82, 0.16, 0.58)), Vector3(0.0, 0.83, -0.30), edge, Vector3(0.0, 0.0, 0.08), 0.15, 0.68)
	var skull_pivot := Node3D.new()
	skull_pivot.name = "SkullPivot"
	skull_pivot.position = Vector3(0.0, 0.90, -0.68)
	root.add_child(skull_pivot)
	_part(skull_pivot, "Skull", _sphere(0.31), Vector3.ZERO, iron, Vector3.ZERO, 0.0, 0.42)
	_part(skull_pivot, "Jaw", _box(Vector3(0.42, 0.12, 0.34)), Vector3(0.0, -0.20, -0.20), edge)
	for side in [-1.0, 1.0]:
		_part(skull_pivot, "Horn" + str(side), _capsule(0.075, 0.55), Vector3(side * 0.23, 0.30, 0.10), edge, Vector3(0.0, 0.0, side * -0.55), 0.0, 0.35)
		_part(skull_pivot, "Eye" + str(side), _sphere(0.055), Vector3(side * 0.20, 0.06, -0.23), ember, Vector3.ZERO, 2.0)
	for side in [-1.0, 1.0]:
		for leg_index in range(2):
			var front := leg_index == 0
			var leg_pivot := Node3D.new()
			leg_pivot.name = ("FrontLeg" if front else "HindLeg") + ("Left" if side < 0.0 else "Right")
			leg_pivot.position = Vector3(side * 0.30, 0.57, -0.38 if front else 0.42)
			root.add_child(leg_pivot)
			_part(leg_pivot, "IronLeg", _capsule(0.13, 0.72), Vector3(0.0, -0.27, 0.0), iron, Vector3.ZERO, 0.0, 0.3)
			_part(leg_pivot, "KneeGuard", _box(Vector3(0.30, 0.22, 0.26)), Vector3(0.0, -0.14, -0.06), edge, Vector3.ZERO, 0.0, 0.48)
			_part(leg_pivot, "IronPaw", _box(Vector3(0.30, 0.14, 0.34)), Vector3(0.0, -0.58, -0.08), edge, Vector3.ZERO, 0.0, 0.42)
	var spine_armor := Node3D.new()
	spine_armor.name = "SpineArmor"
	spine_armor.position = Vector3(0.0, 0.98, 0.10)
	root.add_child(spine_armor)
	for index in range(4):
		var plate := _box(Vector3(0.24, 0.52, 0.62))
		_part(spine_armor, "BackRib" + str(index), plate, Vector3(-0.36 + float(index) * 0.24, 0.04, 0.0), edge, Vector3(0.0, 0.0, -0.16), 0.0, 0.48)
	var tail_pivot := Node3D.new()
	tail_pivot.name = "TailPivot"
	tail_pivot.position = Vector3(0.0, 0.70, 0.76)
	root.add_child(tail_pivot)
	_part(tail_pivot, "TailArmor", _capsule(0.12, 0.62), Vector3(0.0, 0.08, 0.18), iron, Vector3(-0.62, 0.0, 0.0), 0.0, 0.42)
	_part(tail_pivot, "TailSpur", _box(Vector3(0.20, 0.18, 0.26)), Vector3(0.0, 0.25, 0.38), edge, Vector3.ZERO, 0.0, 0.5)


static func _build_warrior(root: Node3D, monster_name: String) -> void:
	var armor := Color("#7b4639") if monster_name.contains("炽战") else Color("#9b8053")
	var gold := Color("#e4bd78")
	var flame := Color("#ff7045")
	_part(root, "LegLeft", _capsule(0.13, 0.78), Vector3(-0.17, 0.38, 0.0), armor)
	_part(root, "LegRight", _capsule(0.13, 0.78), Vector3(0.17, 0.38, 0.0), armor)
	_part(root, "Torso", _capsule(0.31, 1.05), Vector3(0.0, 1.08, 0.0), armor)
	_part(root, "ChestEmblem", _box(Vector3(0.36, 0.38, 0.10)), Vector3(0.0, 1.18, -0.30), gold, Vector3(0.0, 0.0, 0.12), 0.35, 0.42)
	_part(root, "Head", _sphere(0.23), Vector3(0.0, 1.83, 0.0), Color("#c9a27d"))
	_part(root, "Helmet", _box(Vector3(0.54, 0.17, 0.42)), Vector3(0.0, 2.02, 0.0), gold, Vector3.ZERO, 0.2, 0.52)
	for side in [-1.0, 1.0]:
		_part(root, "Shoulder" + str(side), _box(Vector3(0.40, 0.28, 0.46)), Vector3(side * 0.42, 1.49, 0.0), gold, Vector3(0.0, 0.0, side * -0.12), 0.0, 0.52)
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmPivotLeft" if side < 0.0 else "ArmPivotRight"
		arm_pivot.position = Vector3(side * 0.46, 1.40, 0.0)
		root.add_child(arm_pivot)
		_part(arm_pivot, "Arm", _capsule(0.11, 0.78), Vector3(0.0, -0.38, 0.0), armor, Vector3(0.0, 0.0, side * -0.12))
		if side > 0.0:
			_part(arm_pivot, "Blade", _box(Vector3(0.10, 1.10, 0.13)), Vector3(0.24, -0.48, -0.08), gold, Vector3(0.0, 0.0, -0.12), 0.4, 0.72)
	if monster_name.contains("炽战"):
		_part(root, "FlameCrest", _capsule(0.08, 0.70), Vector3(0.0, 2.38, 0.02), flame, Vector3(0.0, 0.0, 0.0), 2.2)


static func _build_wraith(root: Node3D, aura_color: Color, core_color: Color) -> void:
	_part(root, "WraithMantle", _sphere(0.47, 1.28), Vector3(0.0, 0.86, 0.0), aura_color, Vector3.ZERO, 1.0, 0.0, 0.48)
	_part(root, "SoulCore", _sphere(0.20), Vector3(0.0, 0.94, -0.20), core_color, Vector3.ZERO, 2.2)
	_part(root, "LowerWisp", _capsule(0.18, 0.72), Vector3(0.0, 0.32, 0.12), aura_color, Vector3(0.22, 0.0, 0.0), 0.8, 0.0, 0.42)
	_part(root, "SoulSpark", _sphere(0.065), Vector3(0.0, 1.42, -0.06), core_color, Vector3.ZERO, 2.8)
	_part(root, "SoulShardLeft", _sphere(0.055), Vector3(-0.28, 0.88, 0.12), aura_color, Vector3.ZERO, 1.7)
	_part(root, "SoulShardRight", _sphere(0.055), Vector3(0.28, 0.88, 0.12), aura_color, Vector3.ZERO, 1.7)
	var orbit := TorusMesh.new()
	orbit.inner_radius = 0.55
	orbit.outer_radius = 0.60
	orbit.rings = 28
	orbit.ring_segments = 7
	_part(root, "SoulOrbit", orbit, Vector3(0.0, 0.72, 0.0), core_color, Vector3(0.72, 0.0, 0.0), 1.1)
	for side in [-1.0, 1.0]:
		_part(root, "Wisp" + str(side), _sphere(0.095), Vector3(side * 0.47, 0.60, 0.08), core_color, Vector3.ZERO, 1.8)


static func _build_fire_soul_details(root: Node3D) -> void:
	var flame := Color("#ff8750")
	var gold := Color("#ffd08a")
	for side in [-1.0, 1.0]:
		_part(root, "FlameHorn" + str(side), _capsule(0.075, 0.52), Vector3(side * 0.24, 1.30, 0.02), flame, Vector3(0.0, 0.0, side * -0.48), 2.0)
		_part(root, "FlameOrb" + str(side), _sphere(0.085), Vector3(side * 0.42, 0.66, 0.04), gold, Vector3.ZERO, 2.6)
		_part(root, "FlameTail" + str(side), _capsule(0.065, 0.42), Vector3(side * 0.25, 0.22, 0.30), flame, Vector3(side * 0.35, 0.0, side * 0.38), 1.8)
	_part(root, "FlameCrest", _sphere(0.12), Vector3(0.0, 1.56, 0.02), gold, Vector3.ZERO, 3.0)


static func _build_frost_soul_details(root: Node3D) -> void:
	var ice := Color("#a9e8ff")
	var deep_ice := Color("#5eacd6")
	for side in [-1.0, 1.0]:
		_part(root, "IceHorn" + str(side), _box(Vector3(0.13, 0.62, 0.13)), Vector3(side * 0.30, 1.27, 0.04), ice, Vector3(0.0, 0.0, side * -0.42), 0.9, 0.12)
		_part(root, "IceShard" + str(side), _box(Vector3(0.16, 0.42, 0.12)), Vector3(side * 0.42, 0.70, 0.18), deep_ice, Vector3(0.18, 0.0, side * 0.28), 0.8, 0.18)
	_part(root, "IceCrown", _box(Vector3(0.48, 0.10, 0.16)), Vector3(0.0, 1.48, 0.02), ice, Vector3.ZERO, 1.2, 0.12)
	var frost_ring := TorusMesh.new()
	frost_ring.inner_radius = 0.62
	frost_ring.outer_radius = 0.68
	frost_ring.rings = 24
	frost_ring.ring_segments = 6
	_part(root, "FrostOrbit", frost_ring, Vector3(0.0, 0.78, 0.0), ice, Vector3(0.9, 0.0, 0.0), 1.1, 0.1)


static func create_npc(npc_type: String, npc_name: String) -> Node3D:
	var model_key := _resolve_npc_model_key(npc_type)
	var root := VisualModelLibrary.instantiate_model(
		model_key,
		func() -> Node3D: return _create_procedural_npc(npc_type, npc_name)
	)
	root.name = "NPCModel_" + npc_type
	root.set_meta("npc_type", npc_type)
	root.set_meta("npc_name", npc_name)
	return root


static func _resolve_npc_model_key(npc_type: String) -> String:
	match npc_type:
		"judge":
			return "npc_judge"
		"trial_master":
			return "npc_trial_master"
		"guard":
			return "npc_guard"
		"soup_keeper":
			return "npc_soup_keeper"
		"blacksmith":
			return "npc_blacksmith"
		_:
			return "npc_generic"


static func _create_procedural_npc(npc_type: String, npc_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = "NPCModel_" + npc_type
	var robe := Color("#315d68")
	var trim := Color("#9bd8ce")
	var skin := Color("#d5b69a")
	var hair := Color("#25232c")
	match npc_type:
		"judge":
			robe = Color("#55416f")
			trim = Color("#b99be8")
		"trial_master":
			robe = Color("#713e37")
			trim = Color("#e5a16c")
		"guard":
			robe = Color("#465568")
			trim = Color("#a9c5d9")
		"soup_keeper":
			robe = Color("#315d68")
			trim = Color("#9bd8ce")
		"blacksmith":
			robe = Color("#51433a")
			trim = Color("#e09a55")
		_:
			robe = Color("#746044")
			trim = Color("#e6c77d")
	# Layered robe silhouette, with a visible waist sash and front panel.
	var robe_mesh := CylinderMesh.new()
	robe_mesh.top_radius = 0.25
	robe_mesh.bottom_radius = 0.48
	robe_mesh.height = 1.48
	robe_mesh.radial_segments = 16
	_part(root, "LayeredRobe", robe_mesh, Vector3(0.0, 0.78, 0.0), robe)
	_part(root, "InnerCollar", _box(Vector3(0.34, 0.34, 0.10)), Vector3(0.0, 1.39, -0.20), trim)
	_part(root, "WaistSash", _box(Vector3(0.72, 0.12, 0.48)), Vector3(0.0, 1.03, 0.0), trim)
	_part(root, "FrontRobePanel", _box(Vector3(0.22, 0.74, 0.08)), Vector3(0.0, 0.66, -0.245), robe.lightened(0.12))
	_part(root, "Neck", _capsule(0.105, 0.25), Vector3(0.0, 1.54, 0.0), skin)
	_part(root, "Head", _sphere(0.245), Vector3(0.0, 1.83, 0.0), skin)
	_part(root, "HairCap", _sphere(0.265, 0.30), Vector3(0.0, 2.015, 0.015), hair)
	# Broad sleeves and hands make the NPC readable from the third-person camera.
	for side in [-1.0, 1.0]:
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmPivotLeft" if side < 0.0 else "ArmPivotRight"
		arm_pivot.position = Vector3(side * 0.40, 1.48, -0.01)
		root.add_child(arm_pivot)
		_part(arm_pivot, "Sleeve", _capsule(0.145, 0.72), Vector3(0.0, -0.28, 0.0), robe, Vector3(0.0, 0.0, side * -0.42))
		_part(arm_pivot, "Hand", _sphere(0.09), Vector3(side * 0.17, -0.59, -0.01), skin)
	if npc_type == "soup_keeper" or npc_name == "孟婆":
		# Jade hair ornament and a steaming bowl identify the reincarnation guide.
		_part(root, "HairBun", _sphere(0.14), Vector3(0.20, 2.12, 0.02), hair)
		_part(root, "JadeHairPin", _box(Vector3(0.08, 0.42, 0.08)), Vector3(0.19, 2.12, -0.03), trim, Vector3(0.0, 0.0, -0.25), 0.45)
		var bowl := CylinderMesh.new()
		bowl.top_radius = 0.19
		bowl.bottom_radius = 0.12
		bowl.height = 0.12
		_part(root, "ForgetfulnessBowl", bowl, Vector3(0.43, 1.02, -0.10), Color("#83c9bd"), Vector3.ZERO, 0.65, 0.22)
		_part(root, "BowlMist", _sphere(0.075), Vector3(0.43, 1.16, -0.10), Color("#b6fff0"), Vector3.ZERO, 1.5, 0.0, 0.42)
	elif npc_type == "blacksmith":
		# Heavy leather apron, tool loops and a broad hammer make the smith readable at distance.
		_part(root, "SmithApron", _box(Vector3(0.62, 0.78, 0.14)), Vector3(0.0, 0.78, -0.29), Color("#8a5b37"), Vector3.ZERO, 0.0, 0.15)
		_part(root, "ApronBib", _box(Vector3(0.46, 0.30, 0.08)), Vector3(0.0, 1.22, -0.34), Color("#a87343"), Vector3.ZERO, 0.0, 0.12)
		for tool_x in [-0.19, 0.0, 0.19]:
			_part(root, "ToolLoop" + str(tool_x), _box(Vector3(0.07, 0.16, 0.06)), Vector3(tool_x, 0.55, -0.38), Color("#d4a66c"), Vector3.ZERO, 0.0, 0.25)
		_part(root, "HammerHandle", _capsule(0.045, 0.82), Vector3(0.62, 1.12, -0.04), Color("#795338"), Vector3(0.0, 0.0, -0.65))
		_part(root, "HammerHead", _box(Vector3(0.42, 0.20, 0.24)), Vector3(0.82, 1.47, -0.04), Color("#9ca5aa"), Vector3(0.0, 0.0, -0.65), 0.0, 0.55)
		_part(root, "SmithWristGuard", _box(Vector3(0.20, 0.18, 0.22)), Vector3(0.48, 1.05, -0.08), Color("#72533d"), Vector3.ZERO, 0.0, 0.22)
	elif npc_type == "judge":
		# Tall winged official hat, court tablet and seal-like chest emblem.
		_part(root, "JudgeCrownBase", _box(Vector3(0.62, 0.16, 0.24)), Vector3(0.0, 2.14, 0.0), trim, Vector3.ZERO, 0.25, 0.3)
		_part(root, "JudgeHat", _box(Vector3(0.54, 0.30, 0.42)), Vector3(0.0, 2.34, 0.02), Color("#292436"), Vector3.ZERO, 0.0, 0.18)
		for side in [-1.0, 1.0]:
			_part(root, "JudgeHatWing" + str(side), _box(Vector3(0.56, 0.10, 0.16)), Vector3(side * 0.48, 2.24, 0.0), Color("#292436"), Vector3(0.0, 0.0, side * -0.04), 0.0, 0.12)
		_part(root, "CrownFinial", _sphere(0.09), Vector3(0.0, 2.53, 0.0), Color("#e9d4ff"), Vector3.ZERO, 0.55)
		_part(root, "CourtTablet", _box(Vector3(0.24, 0.62, 0.09)), Vector3(0.38, 1.08, -0.30), Color("#bda77e"), Vector3(0.0, 0.0, -0.12), 0.0, 0.18)
		_part(root, "TabletSeal", _sphere(0.075), Vector3(0.38, 1.12, -0.36), Color("#9d4d52"), Vector3.ZERO, 0.2, 0.1)
	elif npc_type == "trial_master" or npc_type == "guard":
		_part(root, "ShoulderLeft", _box(Vector3(0.42, 0.25, 0.48)), Vector3(-0.43, 1.48, 0.0), trim, Vector3(0.0, 0.0, 0.10), 0.0, 0.35)
		_part(root, "ShoulderRight", _box(Vector3(0.42, 0.25, 0.48)), Vector3(0.43, 1.48, 0.0), trim, Vector3(0.0, 0.0, -0.10), 0.0, 0.35)
		_part(root, "ChestEmblem", _box(Vector3(0.20, 0.30, 0.08)), Vector3(0.0, 1.30, -0.25), trim, Vector3.ZERO, 0.25)
		if npc_type == "guard":
			# Helmet crest, face guard and spear establish a military silhouette.
			_part(root, "GuardHelmet", _sphere(0.30, 0.34), Vector3(0.0, 2.08, 0.0), Color("#394653"), Vector3.ZERO, 0.0, 0.42)
			_part(root, "HelmetCrest", _box(Vector3(0.10, 0.36, 0.12)), Vector3(0.0, 2.39, 0.02), Color("#b36b55"), Vector3.ZERO, 0.2, 0.22)
			_part(root, "FaceGuard", _box(Vector3(0.40, 0.13, 0.12)), Vector3(0.0, 1.76, -0.22), Color("#71818b"), Vector3.ZERO, 0.0, 0.55)
			_part(root, "SpearShaft", _capsule(0.035, 1.95), Vector3(0.82, 1.05, 0.10), Color("#8b7658"))
			_part(root, "SpearHead", _capsule(0.07, 0.38), Vector3(0.82, 2.18, 0.10), trim, Vector3.ZERO, 0.2, 0.4)
		else:
			# Trial guide carries a bright jade token rather than a judge's tablet.
			_part(root, "TrialShoulderMantle", _box(Vector3(0.92, 0.12, 0.54)), Vector3(0.0, 1.58, 0.02), Color("#9b5147"), Vector3.ZERO, 0.0, 0.12)
			_part(root, "TrialTokenCord", _capsule(0.025, 0.48), Vector3(0.25, 1.12, -0.31), Color("#d6a16c"))
			_part(root, "TrialToken", _box(Vector3(0.26, 0.34, 0.08)), Vector3(0.25, 0.91, -0.34), Color("#8cc8b5"), Vector3.ZERO, 0.65, 0.28)
	else:
		# Civilian/vendor fallback: hood scarf and a small shoulder basket, unlike officials.
		_part(root, "CivilianHood", _sphere(0.28, 0.20), Vector3(0.0, 2.04, 0.04), Color("#51463b"))
		_part(root, "CivilianScarf", _box(Vector3(0.48, 0.13, 0.34)), Vector3(0.0, 1.55, -0.02), Color("#c49a62"))
		_part(root, "ShoulderBasket", _box(Vector3(0.42, 0.52, 0.38)), Vector3(-0.48, 1.12, 0.18), Color("#8b6a43"), Vector3.ZERO, 0.0, 0.08)
		_part(root, "BasketRim", _box(Vector3(0.48, 0.08, 0.42)), Vector3(-0.48, 1.40, 0.18), Color("#c39a62"), Vector3.ZERO, 0.0, 0.12)
	return root


static func create_player_humanoid() -> Node3D:
	var root := VisualModelLibrary.instantiate_model(
		"player_humanoid",
		func() -> Node3D: return _create_procedural_player_humanoid()
	)
	root.name = "PlayerHumanoid"
	root.set_meta("visual_archetype", "player_humanoid")
	return root


static func _create_procedural_player_humanoid() -> Node3D:
	var root := Node3D.new()
	root.name = "PlayerHumanoidPrototype"
	var robe := Color("#34445e")
	var robe_light := Color("#536783")
	var leather := Color("#594538")
	var trim := Color("#c4a36a")
	var skin := Color("#d2ad91")
	var hair := Color("#24232d")
	# Legs and boots are children of hip pivots so locomotion rotates around joints.
	for side in [-1.0, 1.0]:
		var leg_pivot := Node3D.new()
		leg_pivot.name = "LegPivotLeft" if side < 0.0 else "LegPivotRight"
		leg_pivot.position = Vector3(side * 0.17, 0.82, 0.0)
		root.add_child(leg_pivot)
		_part(leg_pivot, "Trouser", _capsule(0.13, 0.78), Vector3(0.0, -0.19, 0.02), robe)
		_part(leg_pivot, "Boot", _box(Vector3(0.22, 0.16, 0.38)), Vector3(0.0, -0.40, -0.10), leather)
	var coat := CylinderMesh.new()
	coat.top_radius = 0.25
	coat.bottom_radius = 0.43
	coat.height = 0.92
	coat.radial_segments = 12
	_part(root, "TravelCoat", coat, Vector3(0.0, 1.08, 0.0), robe)
	_part(root, "InnerChest", _box(Vector3(0.36, 0.56, 0.12)), Vector3(0.0, 1.17, -0.22), robe_light)
	_part(root, "WaistBelt", _box(Vector3(0.70, 0.12, 0.48)), Vector3(0.0, 0.78, 0.0), leather)
	_part(root, "BeltBuckle", _box(Vector3(0.13, 0.15, 0.06)), Vector3(0.0, 0.78, -0.255), trim, Vector3.ZERO, 0.12, 0.25)
	_part(root, "Neck", _capsule(0.10, 0.22), Vector3(0.0, 1.60, 0.0), skin)
	_part(root, "Head", _sphere(0.235), Vector3(0.0, 1.82, 0.0), skin)
	_part(root, "Hair", _sphere(0.255, 0.30), Vector3(0.0, 2.00, 0.025), hair)
	_part(root, "HairTail", _capsule(0.075, 0.44), Vector3(0.0, 1.68, 0.23), hair, Vector3(-0.18, 0.0, 0.0))
	_part(root, "Headband", _box(Vector3(0.48, 0.055, 0.31)), Vector3(0.0, 1.91, -0.02), trim, Vector3.ZERO, 0.10, 0.25)
	for side in [-1.0, 1.0]:
		_part(root, "Shoulder" + str(side), _box(Vector3(0.38, 0.22, 0.40)), Vector3(side * 0.36, 1.43, 0.0), robe_light, Vector3(0.0, 0.0, side * -0.10))
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmPivotLeft" if side < 0.0 else "ArmPivotRight"
		arm_pivot.position = Vector3(side * 0.40, 1.43, 0.0)
		root.add_child(arm_pivot)
		_part(arm_pivot, "Sleeve", _capsule(0.105, 0.72), Vector3(0.0, -0.23, 0.0), robe_light, Vector3(0.0, 0.0, side * -0.10))
		_part(arm_pivot, "Hand", _sphere(0.085), Vector3(side * 0.03, -0.58, -0.01), skin)
	_part(root, "BackScabbard", _box(Vector3(0.12, 0.92, 0.18)), Vector3(-0.28, 1.05, 0.19), leather, Vector3(0.0, 0.0, -0.22))
	_part(root, "ScabbardGuard", _box(Vector3(0.42, 0.07, 0.10)), Vector3(-0.28, 1.43, 0.19), trim, Vector3(0.0, 0.0, -0.22))
	# Layered robe panels and restrained jade fittings give the silhouette
	# more readable depth without increasing the collision capsule.
	_part(root, "OuterRobeFront", _box(Vector3(0.24, 0.72, 0.075)), Vector3(0.12, 0.83, -0.235), robe_light, Vector3(0.0, 0.0, -0.035))
	_part(root, "OuterRobeLeft", _box(Vector3(0.20, 0.68, 0.07)), Vector3(-0.22, 0.82, -0.205), robe, Vector3(0.0, 0.0, 0.045))
	_part(root, "HemTrim", _box(Vector3(0.72, 0.10, 0.44)), Vector3(0.0, 0.62, 0.0), trim, Vector3.ZERO, 0.08, 0.18)
	_part(root, "JadeBuckle", _sphere(0.075), Vector3(0.0, 0.80, -0.29), Color("#75b9a1"), Vector3.ZERO, 0.35, 0.18)
	_part(root, "CollarLeft", _box(Vector3(0.16, 0.34, 0.09)), Vector3(-0.10, 1.48, -0.20), trim, Vector3(0.0, 0.0, -0.32), 0.08, 0.18)
	_part(root, "CollarRight", _box(Vector3(0.16, 0.34, 0.09)), Vector3(0.10, 1.48, -0.20), robe_light, Vector3(0.0, 0.0, 0.32))
	_part(root, "HairTopKnot", _sphere(0.105), Vector3(0.0, 2.20, 0.02), hair)
	_part(root, "JadeHairPin", _box(Vector3(0.42, 0.045, 0.06)), Vector3(0.0, 2.12, 0.02), Color("#78bca5"), Vector3(0.0, 0.0, 0.04), 0.16, 0.3)
	_part(root, "ShoulderMantle", _box(Vector3(0.86, 0.12, 0.48)), Vector3(0.0, 1.54, 0.04), robe, Vector3.ZERO)
	_part(root, "SwordHilt", _capsule(0.045, 0.30), Vector3(-0.39, 1.56, 0.22), leather, Vector3(0.0, 0.0, -0.22))
	_part(root, "SwordPommel", _sphere(0.065), Vector3(-0.43, 1.70, 0.25), trim, Vector3.ZERO, 0.12, 0.25)

	# Stable sockets let equipment visuals be replaced independently of the body mesh.
	var right_arm := root.get_node("ArmPivotRight") as Node3D
	var left_arm := root.get_node("ArmPivotLeft") as Node3D
	_add_equipment_socket(right_arm, "EquipmentWeaponSocket", Vector3(0.03, -0.58, -0.06))
	_add_equipment_socket(root, "EquipmentHeadSocket", Vector3(0.0, 2.08, 0.0))
	_add_equipment_socket(root, "EquipmentChestSocket", Vector3(0.0, 1.20, -0.24))
	_add_equipment_socket(root, "EquipmentLegsSocket", Vector3(0.0, 0.58, -0.22))
	_add_equipment_socket(root, "EquipmentBootsSocket", Vector3(0.0, 0.18, -0.06))
	_add_equipment_socket(root, "EquipmentBackSocket", Vector3(0.0, 1.28, 0.24))
	_add_equipment_socket(root, "EquipmentAccessorySocket", Vector3(0.20, 0.82, -0.30))
	_add_equipment_socket(left_arm, "EquipmentOffhandSocket", Vector3(-0.03, -0.58, -0.06))
	# Keep the visible humanoid close to the 1.8 m collision capsule.
	root.scale = Vector3.ONE * 0.88
	return root


static func _add_equipment_socket(root: Node3D, socket_name: String, socket_position: Vector3) -> void:
	var socket := Node3D.new()
	socket.name = socket_name
	socket.position = socket_position
	socket.set_meta("equipment_socket", true)
	root.add_child(socket)


static func create_fengdu_civic_plaza() -> Node3D:
	# Walkable civic square connecting residential, market and administrative streets.
	var root := Node3D.new()
	root.name = "FengduCivicPlaza"
	var paving := Color("#57515b")
	var border := Color("#393642")
	var floor_body := StaticBody3D.new()
	floor_body.name = "PlazaWalkableGround"
	_part(floor_body, "PlazaFoundation", _box(Vector3(28.0, 0.24, 28.0)), Vector3(0.0, -0.12, 0.0), border)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(28.0, 0.24, 28.0)
	floor_collision.shape = floor_shape
	floor_collision.position = Vector3(0.0, -0.12, 0.0)
	floor_body.add_child(floor_collision)
	root.add_child(floor_body)
	for x_index in range(7):
		for z_index in range(7):
			_part(root, "Paving_%d_%d" % [x_index, z_index], _box(Vector3(3.92, 0.08, 3.92)), Vector3(-12.0 + float(x_index) * 4.0, 0.04, -12.0 + float(z_index) * 4.0), paving)
	# Four open approaches connect the square to the street grid.
	for side in [-1.0, 1.0]:
		_part(root, "ApproachX" + str(side), _box(Vector3(3.8, 0.06, 4.0)), Vector3(side * 15.0, 0.035, 0.0), Color("#625a62"))
		_part(root, "ApproachZ" + str(side), _box(Vector3(4.0, 0.06, 3.8)), Vector3(0.0, 0.035, side * 15.0), Color("#625a62"))
	# Low boundary stones frame corners without closing entrances.
	for side in [-1.0, 1.0]:
		for offset in [-7.0, 7.0]:
			_part(root, "BoundaryX_%s_%s" % [side, offset], _box(Vector3(0.55, 0.42, 5.0)), Vector3(side * 13.35, 0.21, offset), border)
			_part(root, "BoundaryZ_%s_%s" % [side, offset], _box(Vector3(5.0, 0.42, 0.55)), Vector3(offset, 0.21, side * 13.35), border)
	_part(root, "NoticeDais", _box(Vector3(4.8, 0.32, 4.8)), Vector3(0.0, 0.16, 0.0), border)
	var notice := create_soul_tombstone()
	notice.name = "CivicNoticeStone"
	notice.position = Vector3(0.0, 0.32, 0.0)
	notice.scale = Vector3.ONE * 1.15
	root.add_child(notice)
	for x in [-10.0, 10.0]:
		for z in [-10.0, 10.0]:
			var lantern := create_ghost_lantern()
			lantern.position = Vector3(x, 0.0, z)
			lantern.scale = Vector3.ONE * 0.72
			root.add_child(lantern)
	# Placement-only markers; server systems must own actual NPC spawning and patrol.
	var npc_specs := [
		{"name": "PlazaGuardWest", "role": "guard", "at": Vector3(-9.0, 0.0, 0.0), "patrol": 0},
		{"name": "PlazaGuardEast", "role": "guard", "at": Vector3(9.0, 0.0, 0.0), "patrol": 1},
		{"name": "PlazaNoticeClerk", "role": "civilian", "at": Vector3(0.0, 0.0, 4.0), "patrol": -1},
		{"name": "PlazaGuide", "role": "trial_master", "at": Vector3(0.0, 0.0, -5.0), "patrol": -1}
	]
	for spec in npc_specs:
		var marker := Marker3D.new()
		marker.name = spec["name"]
		marker.position = spec["at"]
		marker.set_meta("npc_role", spec["role"])
		marker.set_meta("patrol_order", spec["patrol"])
		marker.set_meta("placement_only", true)
		root.add_child(marker)
	return root


static func create_fengdu_residential_interior() -> Node3D:
	# Compact single-storey interior shell. Openings are left clear in both mesh and collision.
	var root := Node3D.new()
	root.name = "FengduResidentialInterior"
	var stone := Color("#514b50")
	var plaster := Color("#76665b")
	var timber := Color("#3e302c")
	var trim := Color("#a88a60")
	# Interior footprint: 8m wide x 10m deep. Floor collision is independent of decor.
	var floor_body := StaticBody3D.new()
	floor_body.name = "InteriorWalkableFloor"
	_part(floor_body, "InteriorFloorVisual", _box(Vector3(8.0, 0.20, 10.0)), Vector3(0.0, -0.10, 0.0), stone)
	var floor_hit := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8.0, 0.20, 10.0)
	floor_hit.shape = floor_shape
	floor_hit.position = Vector3(0.0, -0.10, 0.0)
	floor_body.add_child(floor_hit)
	root.add_child(floor_body)
	# Back and side walls are continuous; front wall is split around a 1.8m doorway.
	var wall_specs := [
		{"name":"BackWall", "size":Vector3(8.0, 2.8, 0.28), "at":Vector3(0.0, 1.4, 4.86)},
		{"name":"WestWall", "size":Vector3(0.28, 2.8, 10.0), "at":Vector3(-3.86, 1.4, 0.0)},
		{"name":"EastWall", "size":Vector3(0.28, 2.8, 10.0), "at":Vector3(3.86, 1.4, 0.0)},
		{"name":"FrontWallLeft", "size":Vector3(3.1, 2.8, 0.28), "at":Vector3(-2.45, 1.4, -4.86)},
		{"name":"FrontWallRight", "size":Vector3(3.1, 2.8, 0.28), "at":Vector3(2.45, 1.4, -4.86)},
		{"name":"DoorLintel", "size":Vector3(1.8, 0.45, 0.28), "at":Vector3(0.0, 2.575, -4.86)}
	]
	for spec in wall_specs:
		var body := StaticBody3D.new()
		body.name = str(spec["name"])
		_part(body, "WallVisual", _box(spec["size"]), spec["at"], plaster)
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = spec["size"]
		hit.shape = shape
		hit.position = spec["at"]
		body.add_child(hit)
		root.add_child(body)
	# Structural timber frame and exposed ceiling beams.
	for x in [-3.55, 3.55]:
		for z in [-4.55, 4.55]:
			_part(root, "FramePost_%s_%s" % [x, z], _box(Vector3(0.22, 2.65, 0.22)), Vector3(x, 1.32, z), timber)
	for z in [-3.0, 0.0, 3.0]:
		_part(root, "CeilingBeam" + str(z), _box(Vector3(7.5, 0.16, 0.22)), Vector3(0.0, 2.72, z), timber)
	# Basic furnishings leave a 1.8m-wide central circulation lane.
	_part(root, "LowTable", _box(Vector3(1.5, 0.16, 0.85)), Vector3(-1.65, 0.55, 0.25), timber)
	for x in [-2.15, -1.15]:
		for z in [-0.05, 0.55]:
			_part(root, "TableLeg_%s_%s" % [x, z], _box(Vector3(0.10, 0.52, 0.10)), Vector3(x, 0.26, z), timber)
	_part(root, "SleepingPlatform", _box(Vector3(2.2, 0.35, 1.35)), Vector3(2.25, 0.22, 2.55), timber)
	_part(root, "SleepingMat", _box(Vector3(2.0, 0.12, 1.18)), Vector3(2.25, 0.45, 2.55), Color("#78645e"))
	_part(root, "StorageChest", _box(Vector3(1.1, 0.82, 0.72)), Vector3(-2.65, 0.41, 3.55), timber)
	# Interaction anchors are data only; gameplay interaction remains server-authoritative.
	var anchors := [
		{"name":"ResidentTalkPoint", "at":Vector3(0.0, 0.0, -2.6), "kind":"resident_dialogue"},
		{"name":"StorageInspectPoint", "at":Vector3(-1.65, 0.0, 2.45), "kind":"storage_inspect"},
		{"name":"RestPoint", "at":Vector3(1.15, 0.0, 1.1), "kind":"rest"}
	]
	for spec in anchors:
		var marker := Marker3D.new()
		marker.name = spec["name"]
		marker.position = spec["at"]
		marker.set_meta("interaction_kind", spec["kind"])
		marker.set_meta("placement_only", true)
		root.add_child(marker)
	return root



static func create_ghost_market_shop_interior() -> Node3D:
	# Walkable 12m x 14m shop interior. Gameplay transactions remain server-authoritative.
	var root := Node3D.new()
	root.name = "GhostMarketShopInterior"
	var stone := Color("#514a55")
	var timber := Color("#493633")
	var dark_wood := Color("#30272c")
	var bronze := Color("#a8875c")
	var jade := Color("#79b9a9")
	var warm_glow := Color("#e0b77b")

	# Floor has its own collision, independent from furniture.
	var floor_body := StaticBody3D.new()
	floor_body.name = "ShopWalkableFloor"
	_part(floor_body, "ShopFloorVisual", _box(Vector3(12.0, 0.20, 14.0)), Vector3(0.0, -0.10, 0.0), stone)
	var floor_hit := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(12.0, 0.20, 14.0)
	floor_hit.shape = floor_shape
	floor_hit.position = Vector3(0.0, -0.10, 0.0)
	floor_body.add_child(floor_hit)
	root.add_child(floor_body)

	# Four collision-backed walls, with a 2.2m front entrance.
	var wall_specs := [
		{"name":"RearWall", "size":Vector3(12.0, 3.6, 0.28), "at":Vector3(0.0, 1.8, 6.86)},
		{"name":"WestWall", "size":Vector3(0.28, 3.6, 14.0), "at":Vector3(-5.86, 1.8, 0.0)},
		{"name":"EastWall", "size":Vector3(0.28, 3.6, 14.0), "at":Vector3(5.86, 1.8, 0.0)},
		{"name":"FrontWallLeft", "size":Vector3(4.8, 3.6, 0.28), "at":Vector3(-3.6, 1.8, -6.86)},
		{"name":"FrontWallRight", "size":Vector3(4.8, 3.6, 0.28), "at":Vector3(3.6, 1.8, -6.86)},
		{"name":"EntranceLintel", "size":Vector3(2.4, 0.55, 0.28), "at":Vector3(0.0, 3.325, -6.86)}
	]
	for spec in wall_specs:
		var wall_body := StaticBody3D.new()
		wall_body.name = str(spec["name"])
		_part(wall_body, "WallVisual", _box(spec["size"]), spec["at"], Color("#65545a"))
		var wall_hit := CollisionShape3D.new()
		var wall_shape := BoxShape3D.new()
		wall_shape.size = spec["size"]
		wall_hit.shape = wall_shape
		wall_hit.position = spec["at"]
		wall_body.add_child(wall_hit)
		root.add_child(wall_body)

	# Ceiling joists and hanging lamps establish the shop's interior scale.
	for z in [-4.8, -1.6, 1.6, 4.8]:
		_part(root, "CeilingJoist" + str(z), _box(Vector3(11.4, 0.16, 0.22)), Vector3(0.0, 3.48, z), dark_wood)
	for x in [-3.6, 3.6]:
		var lantern := create_ghost_lantern()
		lantern.name = "InteriorLantern" + str(x)
		lantern.position = Vector3(x, 0.0, 0.0)
		lantern.scale = Vector3.ONE * 0.52
		root.add_child(lantern)

	# Main counter at the back; the customer side remains open.
	var counter := StaticBody3D.new()
	counter.name = "MerchantCounter"
	_part(counter, "CounterBody", _box(Vector3(5.0, 1.0, 0.9)), Vector3(0.0, 0.55, 3.65), timber)
	_part(counter, "CounterTop", _box(Vector3(5.25, 0.16, 1.05)), Vector3(0.0, 1.13, 3.65), bronze, Vector3.ZERO, 0.0, 0.24)
	var counter_hit := CollisionShape3D.new()
	var counter_shape := BoxShape3D.new()
	counter_shape.size = Vector3(5.0, 1.0, 0.9)
	counter_hit.shape = counter_shape
	counter_hit.position = Vector3(0.0, 0.55, 3.65)
	counter.add_child(counter_hit)
	root.add_child(counter)

	# Two side shelves leave a 3m central aisle and are solid to player movement.
	for side in [-1.0, 1.0]:
		var shelf := StaticBody3D.new()
		shelf.name = "DisplayShelf" + str(side)
		_part(shelf, "ShelfBase", _box(Vector3(1.0, 0.22, 5.0)), Vector3(side * 4.65, 0.14, 0.2), dark_wood)
		for level in [0, 1, 2]:
			var y := 0.72 + float(level) * 0.88
			_part(shelf, "ShelfBoard" + str(level), _box(Vector3(0.92, 0.12, 4.8)), Vector3(side * 4.65, y, 0.2), timber)
		for z in [-2.0, 0.2, 2.4]:
			_part(shelf, "ShelfUpright" + str(z), _box(Vector3(0.12, 2.7, 0.14)), Vector3(side * 4.65, 1.35, z), bronze)
		var shelf_hit := CollisionShape3D.new()
		var shelf_shape := BoxShape3D.new()
		shelf_shape.size = Vector3(1.0, 2.8, 5.0)
		shelf_hit.shape = shelf_shape
		shelf_hit.position = Vector3(side * 4.65, 1.4, 0.2)
		shelf.add_child(shelf_hit)
		root.add_child(shelf)

		# Stylized jars and sealed soul-scrolls are visual stock, not inventory items.
		for item_index in range(4):
			var item_z := -1.65 + float(item_index) * 1.15
			var jar := _sphere(0.20, 0.34)
			_part(root, "StockJar_%s_%d" % [side, item_index], jar, Vector3(side * 4.65, 0.92, item_z), jade, Vector3.ZERO, 0.45, 0.12, 0.86)
			_part(root, "StockSeal_%s_%d" % [side, item_index], _box(Vector3(0.30, 0.08, 0.12)), Vector3(side * 4.65, 1.42, item_z), warm_glow, Vector3.ZERO, 0.18, 0.18)

	# Low central display plinths sit outside the clear customer route.
	for side in [-1.0, 1.0]:
		var plinth := StaticBody3D.new()
		plinth.name = "DisplayPlinth" + str(side)
		_part(plinth, "PlinthBody", _box(Vector3(1.35, 0.72, 1.0)), Vector3(side * 2.35, 0.36, -1.0), dark_wood)
		_part(plinth, "PlinthTop", _box(Vector3(1.48, 0.12, 1.12)), Vector3(side * 2.35, 0.78, -1.0), bronze, Vector3.ZERO, 0.0, 0.28)
		var plinth_hit := CollisionShape3D.new()
		var plinth_shape := BoxShape3D.new()
		plinth_shape.size = Vector3(1.35, 0.72, 1.0)
		plinth_hit.shape = plinth_shape
		plinth_hit.position = Vector3(side * 2.35, 0.36, -1.0)
		plinth.add_child(plinth_hit)
		root.add_child(plinth)
		_part(root, "DisplayRelic" + str(side), _sphere(0.25), Vector3(side * 2.35, 1.05, -1.0), warm_glow, Vector3.ZERO, 0.9, 0.22)

	# Merchant, customer and interaction anchors are placement metadata only.
	var anchors := [
		{"name":"MerchantStandPoint", "at":Vector3(0.0, 0.0, 4.45), "kind":"merchant_stand"},
		{"name":"ShopTradePoint", "at":Vector3(0.0, 0.0, 2.45), "kind":"shop_trade"},
		{"name":"ShopBrowseWest", "at":Vector3(-2.0, 0.0, -3.4), "kind":"shop_browse"},
		{"name":"ShopBrowseEast", "at":Vector3(2.0, 0.0, -3.4), "kind":"shop_browse"}
	]
	for spec in anchors:
		var marker := Marker3D.new()
		marker.name = spec["name"]
		marker.position = spec["at"]
		marker.set_meta("interaction_kind", spec["kind"])
		marker.set_meta("placement_only", true)
		root.add_child(marker)

	root.set_meta("interior_dimensions", Vector3(12.0, 3.6, 14.0))
	root.set_meta("clear_central_aisle_width", 3.0)
	root.set_meta("transactions_server_authoritative", true)
	return root
