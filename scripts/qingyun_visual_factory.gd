extends RefCounted
## Original procedural Qingyun architecture and vegetation.
## Stylized Chinese xianxia visual blockouts; replaceable by licensed GLB assets later.

static func _mat(color: Color, metallic: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.78
	material.metallic = metallic
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material

static func _box(parent: Node3D, name: String, size: Vector3, position: Vector3, color: Color, rotation: Vector3 = Vector3.ZERO, metallic: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.rotation = rotation
	instance.material_override = _mat(color, metallic)
	parent.add_child(instance)
	return instance

static func _cylinder(parent: Node3D, name: String, top: float, bottom: float, height: float, position: Vector3, color: Color, sides: int = 12) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = sides
	instance.mesh = mesh
	instance.position = position
	instance.material_override = _mat(color)
	parent.add_child(instance)
	return instance

static func _label(parent: Node3D, name: String, value: String, position: Vector3, color: Color, font_size: int = 42) -> void:
	var label := Label3D.new()
	label.name = name
	label.text = value
	label.position = position
	label.font_size = font_size
	label.outline_size = 8
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	parent.add_child(label)

static func _pillar_collision(parent: Node3D, name: String, position: Vector3, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.name = name
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = position
	parent.add_child(collision)

static func create_mountain_gate() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "QingyunMountainGate"
	var stone := Color("#777e78")
	var pale_stone := Color("#a5a18d")
	var timber := Color("#573d32")
	var roof := Color("#263f3a")
	var jade := Color("#91b9a4")
	_box(root, "GateFoundation", Vector3(15.0, 0.48, 4.2), Vector3(0.0, 0.24, -22.0), Color("#555e58"))
	_box(root, "FoundationTrim", Vector3(13.6, 0.18, 4.5), Vector3(0.0, 0.56, -22.0), pale_stone)
	for side in [-1.0, 1.0]:
		var x := side * 5.1
		_cylinder(root, "GatePillar_" + str(side), 0.43, 0.62, 6.2, Vector3(x, 3.7, -22.0), stone, 14)
		_box(root, "PillarFoot_" + str(side), Vector3(1.55, 0.52, 1.55), Vector3(x, 0.92, -22.0), pale_stone)
		_box(root, "PillarCapital_" + str(side), Vector3(1.55, 0.42, 1.55), Vector3(x, 6.72, -22.0), pale_stone)
		_box(root, "PillarInset_" + str(side), Vector3(0.12, 2.8, 0.16), Vector3(x, 3.55, -21.34), jade, Vector3.ZERO, 0.12)
		_pillar_collision(root, "PillarCollision_" + str(side), Vector3(x, 3.65, -22.0), Vector3(1.3, 6.6, 1.3))
	_box(root, "MainLintel", Vector3(12.0, 1.0, 1.45), Vector3(0.0, 6.65, -22.0), timber)
	_box(root, "LintelGoldTrim", Vector3(11.5, 0.14, 1.52), Vector3(0.0, 7.12, -22.0), Color("#c3a66f"), Vector3.ZERO, 0.22)
	_box(root, "PlaqueFrame", Vector3(4.7, 1.48, 0.34), Vector3(0.0, 5.72, -21.12), Color("#3b5147"))
	_box(root, "PlaqueInset", Vector3(4.3, 1.16, 0.12), Vector3(0.0, 5.72, -20.91), Color("#253b35"))
	_label(root, "GateInscription", "青 云 宗", Vector3(0.0, 5.57, -20.79), Color("#e5d2a1"), 46)
	# Two-layer tiled roof silhouette, with raised eaves and ridge ornaments.
	_box(root, "LowerRoofCore", Vector3(14.8, 0.42, 4.7), Vector3(0.0, 7.62, -22.0), roof)
	_box(root, "LowerRoofRidge", Vector3(10.0, 0.24, 0.42), Vector3(0.0, 7.91, -22.0), Color("#b39461"), Vector3.ZERO, 0.28)
	for side in [-1.0, 1.0]:
		_box(root, "LowerEave_" + str(side), Vector3(2.1, 0.24, 4.9), Vector3(side * 6.4, 7.5, -22.0), roof, Vector3(0.0, 0.0, side * -0.12))
		_cylinder(root, "RidgeFinial_" + str(side), 0.04, 0.18, 0.72, Vector3(side * 6.6, 7.88, -22.0), Color("#c3a66f"), 8)
	_box(root, "UpperRoofCore", Vector3(10.4, 0.38, 3.2), Vector3(0.0, 8.25, -22.0), Color("#304a43"))
	_box(root, "UpperRoofRidge", Vector3(7.2, 0.22, 0.36), Vector3(0.0, 8.52, -22.0), Color("#c3a66f"), Vector3.ZERO, 0.25)
	_box(root, "RoofSpine", Vector3(0.42, 0.46, 3.4), Vector3(0.0, 8.5, -22.0), Color("#9e8054"))
	_pillar_collision(root, "LintelCollision", Vector3(0.0, 6.65, -22.0), Vector3(12.0, 1.0, 1.45))
	return root

static func create_sect_hall() -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "QingyunSectHall"
	root.position = Vector3(-23.0, 0.0, -55.0)
	var stone := Color("#777d72")
	var timber := Color("#68483a")
	var wall := Color("#c4b99e")
	var roof := Color("#263b36")
	_box(root, "HallPlatform", Vector3(24.0, 1.0, 15.0), Vector3(0.0, 0.5, 0.0), stone)
	_box(root, "PlatformUpperStep", Vector3(21.0, 0.42, 13.0), Vector3(0.0, 1.18, 0.0), Color("#aaa38f"))
	_box(root, "HallBody", Vector3(17.0, 6.0, 9.0), Vector3(0.0, 4.2, -0.2), wall)
	_box(root, "FrontShadow", Vector3(12.0, 4.7, 0.22), Vector3(0.0, 4.0, -4.82), timber)
	_box(root, "MainDoor", Vector3(3.0, 4.1, 0.18), Vector3(0.0, 3.45, -4.98), Color("#49352e"))
	for side in [-1.0, 1.0]:
		for z in [-3.8, 3.6]:
			_cylinder(root, "HallColumn_%s_%s" % [side, z], 0.24, 0.30, 5.6, Vector3(side * 7.7, 3.9, z), timber, 12)
		_box(root, "Window_%s" % side, Vector3(1.8, 1.65, 0.18), Vector3(side * 5.1, 4.3, -4.88), Color("#344c45"))
	_box(root, "HallEave", Vector3(22.0, 0.5, 13.0), Vector3(0.0, 7.35, -0.2), roof)
	_box(root, "HallRoofUpper", Vector3(17.0, 0.42, 10.0), Vector3(0.0, 7.95, -0.2), Color("#304d43"))
	_box(root, "HallRidge", Vector3(12.0, 0.28, 0.48), Vector3(0.0, 8.25, -0.2), Color("#c3a66f"), Vector3.ZERO, 0.25)
	for side in [-1.0, 1.0]:
		_box(root, "HallEaveTip_" + str(side), Vector3(2.2, 0.24, 3.0), Vector3(side * 9.6, 7.48, -0.2), roof, Vector3(0.0, 0.0, side * -0.16))
	_box(root, "HallSign", Vector3(5.2, 1.35, 0.25), Vector3(0.0, 6.15, -5.08), Color("#2e453b"))
	_label(root, "HallInscription", "青 云 大 殿", Vector3(0.0, 5.98, -5.24), Color("#e4d0a1"), 42)
	# Keep the central doorway open; collide only with the side and rear walls.
	_pillar_collision(root, "HallLeftWallCollision", Vector3(-7.55, 4.2, -0.2), Vector3(1.0, 6.0, 9.0))
	_pillar_collision(root, "HallRightWallCollision", Vector3(7.55, 4.2, -0.2), Vector3(1.0, 6.0, 9.0))
	_pillar_collision(root, "HallRearWallCollision", Vector3(0.0, 4.2, 4.1), Vector3(16.0, 6.0, 0.8))
	return root

static func create_pine(tree_height: float = 7.0, tree_color: Color = Color("#294b3d")) -> Node3D:
	var root := Node3D.new()
	root.name = "QingyunPine"
	var trunk_height := tree_height * 0.48
	_cylinder(root, "Trunk", 0.16, 0.28, trunk_height, Vector3(0.0, trunk_height * 0.5, 0.0), Color("#514638"), 9)
	for layer in range(3):
		var cone := MeshInstance3D.new()
		cone.name = "PineCanopy_" + str(layer)
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = tree_height * (0.27 - float(layer) * 0.045)
		mesh.height = tree_height * 0.48
		mesh.radial_segments = 9
		cone.mesh = mesh
		cone.position = Vector3(0.0, trunk_height * 0.58 + float(layer) * tree_height * 0.19, 0.0)
		cone.material_override = _mat(tree_color.darkened(float(layer) * 0.07))
		root.add_child(cone)
	return root
