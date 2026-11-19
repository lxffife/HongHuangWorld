extends RefCounted
## Procedural, replaceable visual blockouts for the Underworld bestiary.
## Keep gameplay/network state in world_scene.gd; this file only builds presentation.

static func create_monster(monster_name: String, monster_level: int) -> Node3D:
	var root := Node3D.new()
	root.name = "MonsterVisual"
	var archetype := _resolve_archetype(monster_name)
	root.set_meta("visual_archetype", archetype)
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
		_:
			_build_wraith(root, Color("#668fc7"), Color("#c1e1ff"))
	var level_scale := clampf(1.0 + float(maxi(monster_level - 1, 0)) * 0.018, 1.0, 1.32)
	root.scale = Vector3.ONE * level_scale
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



static func create_fengdu_gate() -> Node3D:
	var root := StaticBody3D.new()
	root.name = "FengduGhostGate"
	var stone := Color("#494354")
	var stone_light := Color("#62566d")
	var bronze := Color("#887451")
	var roof := Color("#252638")
	_part(root, "Foundation", _box(Vector3(14.0, 0.48, 4.6)), Vector3(0.0, 0.18, -18.0), Color("#34313f"))
	for side in [-1.0, 1.0]:
		var x := side * 5.0
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
	for side in [-1.0, 1.0]:
		_part(root, "Ear" + str(side), _capsule(0.075, 0.34), Vector3(side * 0.19, 1.10, -0.63), hide_color, Vector3(0.0, 0.0, side * -0.22))
		_part(root, "Eye" + str(side), _sphere(0.055), Vector3(side * 0.205, 0.88, -0.88), Color("#ffc46d"), Vector3.ZERO, 1.8)
		for z in [-0.36, 0.42]:
			_part(root, "Leg" + str(side) + str(z), _capsule(0.105, 0.66), Vector3(side * 0.25, 0.30, z), hide_color)
	_part(root, "Tail", _capsule(0.10, 0.72), Vector3(0.0, 0.78, 0.76), hide_color, Vector3(-0.65, 0.0, 0.0))


static func _build_iron_beast(root: Node3D) -> void:
	var iron := Color("#59616c")
	var edge := Color("#b6a987")
	var ember := Color("#d47b45")
	_part(root, "IronCore", _capsule(0.48, 1.65), Vector3(0.0, 0.66, 0.05), iron, Vector3(PI * 0.5, 0.0, 0.0), 0.0, 0.52)
	_part(root, "ChestPlate", _box(Vector3(0.82, 0.16, 0.58)), Vector3(0.0, 0.83, -0.30), edge, Vector3(0.0, 0.0, 0.08), 0.15, 0.68)
	_part(root, "Skull", _sphere(0.31), Vector3(0.0, 0.90, -0.68), iron, Vector3.ZERO, 0.0, 0.42)
	_part(root, "Jaw", _box(Vector3(0.42, 0.12, 0.34)), Vector3(0.0, 0.70, -0.88), edge)
	for side in [-1.0, 1.0]:
		_part(root, "Horn" + str(side), _capsule(0.075, 0.55), Vector3(side * 0.23, 1.20, -0.58), edge, Vector3(0.0, 0.0, side * -0.55), 0.0, 0.35)
		_part(root, "Eye" + str(side), _sphere(0.055), Vector3(side * 0.20, 0.96, -0.91), ember, Vector3.ZERO, 2.0)
		for z in [-0.38, 0.42]:
			_part(root, "Leg" + str(side) + str(z), _capsule(0.13, 0.72), Vector3(side * 0.30, 0.32, z), iron, Vector3.ZERO, 0.0, 0.3)
	for index in range(3):
		var plate := _box(Vector3(0.22, 0.52, 0.72))
		_part(root, "BackRib" + str(index), plate, Vector3(-0.30 + float(index) * 0.30, 1.02, 0.12), edge, Vector3(0.0, 0.0, -0.16), 0.0, 0.48)


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
		_part(root, "Arm" + str(side), _capsule(0.11, 0.78), Vector3(side * 0.46, 1.02, 0.0), armor, Vector3(0.0, 0.0, side * -0.12))
	_part(root, "Blade", _box(Vector3(0.10, 1.10, 0.13)), Vector3(0.70, 0.86, -0.08), gold, Vector3(0.0, 0.0, -0.12), 0.4, 0.72)
	if monster_name.contains("炽战"):
		_part(root, "FlameCrest", _capsule(0.08, 0.70), Vector3(0.0, 2.38, 0.02), flame, Vector3(0.0, 0.0, 0.0), 2.2)


static func _build_wraith(root: Node3D, aura_color: Color, core_color: Color) -> void:
	_part(root, "WraithMantle", _sphere(0.47, 1.28), Vector3(0.0, 0.86, 0.0), aura_color, Vector3.ZERO, 1.0, 0.0, 0.48)
	_part(root, "SoulCore", _sphere(0.20), Vector3(0.0, 0.94, -0.20), core_color, Vector3.ZERO, 2.2)
	_part(root, "LowerWisp", _capsule(0.18, 0.72), Vector3(0.0, 0.32, 0.12), aura_color, Vector3(0.22, 0.0, 0.0), 0.8, 0.0, 0.42)
	var orbit := TorusMesh.new()
	orbit.inner_radius = 0.55
	orbit.outer_radius = 0.60
	orbit.rings = 28
	orbit.ring_segments = 7
	_part(root, "SoulOrbit", orbit, Vector3(0.0, 0.72, 0.0), core_color, Vector3(0.72, 0.0, 0.0), 1.1)
	for side in [-1.0, 1.0]:
		_part(root, "Wisp" + str(side), _sphere(0.095), Vector3(side * 0.47, 0.60, 0.08), core_color, Vector3.ZERO, 1.8)


static func create_npc(npc_type: String, npc_name: String) -> Node3D:
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
		_part(root, "Sleeve" + str(side), _capsule(0.145, 0.72), Vector3(side * 0.40, 1.20, -0.01), robe, Vector3(0.0, 0.0, side * -0.42))
		_part(root, "Hand" + str(side), _sphere(0.09), Vector3(side * 0.57, 0.91, -0.02), skin)
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
	elif npc_type == "judge":
		_part(root, "JudgeCrownBase", _box(Vector3(0.62, 0.16, 0.24)), Vector3(0.0, 2.14, 0.0), trim, Vector3.ZERO, 0.25, 0.3)
		_part(root, "CrownFinial", _sphere(0.09), Vector3(0.0, 2.29, 0.0), Color("#e9d4ff"), Vector3.ZERO, 0.55)
	elif npc_type == "trial_master" or npc_type == "guard":
		_part(root, "ShoulderLeft", _box(Vector3(0.42, 0.25, 0.48)), Vector3(-0.43, 1.48, 0.0), trim, Vector3(0.0, 0.0, 0.10), 0.0, 0.35)
		_part(root, "ShoulderRight", _box(Vector3(0.42, 0.25, 0.48)), Vector3(0.43, 1.48, 0.0), trim, Vector3(0.0, 0.0, -0.10), 0.0, 0.35)
		_part(root, "ChestEmblem", _box(Vector3(0.20, 0.30, 0.08)), Vector3(0.0, 1.30, -0.25), trim, Vector3.ZERO, 0.25)
		if npc_type == "guard":
			_part(root, "SpearShaft", _capsule(0.035, 1.95), Vector3(0.82, 1.05, 0.10), Color("#8b7658"))
			_part(root, "SpearHead", _capsule(0.07, 0.38), Vector3(0.82, 2.18, 0.10), trim, Vector3.ZERO, 0.2, 0.4)
	return root


static func create_player_humanoid() -> Node3D:
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
	return root
