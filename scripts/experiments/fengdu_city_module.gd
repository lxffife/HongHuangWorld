extends Node3D
## Reusable procedural blockout module for Fengdu districts and city props.

signal player_entered(module_data: Dictionary)
signal player_exited(module_data: Dictionary)

var module_data: Dictionary = {}
var module_kind := "district"
var district_kind := "admin"
var _materials: Dictionary = {}
var _player_nearby := false
var _patrol_origin := Vector3.ZERO
var _patrol_time := 0.0


func configure(data: Dictionary) -> void:
	module_data = data.duplicate(true)
	module_kind = str(module_data.get("module_kind", "district"))
	district_kind = str(module_data.get("kind", "admin"))


func _ready() -> void:
	_create_materials()
	match module_kind:
		"district":
			_build_district()
		"guard":
			_build_guard()
		"watchtower":
			_build_watchtower()
		"gatehouse":
			_build_gatehouse()


func _process(delta: float) -> void:
	if module_kind != "guard":
		return
	_patrol_time += delta
	position.x = _patrol_origin.x + sin(_patrol_time * 0.48) * 7.0
	rotation.y = sin(_patrol_time * 0.48) * 0.22


func _create_materials() -> void:
	_materials = {
		"palace": _material("#8a6842"),
		"court": _material("#69534a"),
		"admin": _material("#526577"),
		"sacred": _material("#716092"),
		"market": _material("#967044"),
		"residential": _material("#596d57"),
		"military": _material("#754750"),
		"transport": _material("#4d7477"),
		"gate": _material("#55404b"),
		"stone": _material("#777078"),
		"roof": _material("#493743"),
		"sign": _material("#b89b70"),
		"lantern": _emissive("#7aa5dc", "#416fae", 2.2),
		"guard": _material("#596477")
	}


func _material(hex: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(hex)
	result.roughness = 0.84
	return result


func _emissive(hex: String, glow: String, energy: float) -> StandardMaterial3D:
	var result := _material(hex)
	result.emission_enabled = true
	result.emission = Color(glow)
	result.emission_energy_multiplier = energy
	return result


func _build_district() -> void:
	var title := str(module_data.get("name", "城区"))
	var kind := district_kind
	var material_key := kind if _materials.has(kind) else "admin"
	var main_width := 220.0
	var main_depth := 164.0
	var main_height := 76.0
	match kind:
		"palace":
			main_width = 250.0
			main_depth = 190.0
			main_height = 100.0
		"court":
			main_width = 142.0
			main_depth = 106.0
			main_height = 48.0
		"sacred":
			main_width = 170.0
			main_depth = 120.0
			main_height = 62.0
		"market":
			main_width = 116.0
			main_depth = 82.0
			main_height = 34.0
		"residential":
			main_width = 108.0
			main_depth = 76.0
			main_height = 30.0
		"military":
			main_width = 150.0
			main_depth = 108.0
			main_height = 44.0
		"transport":
			main_width = 132.0
			main_depth = 94.0
			main_height = 38.0
		"admin":
			main_width = 126.0
			main_depth = 92.0
			main_height = 42.0

	_add_box("MainHall", Vector3(main_width, main_height, main_depth), Vector3(0.0, main_height * 0.5, 0.0), material_key, true)
	_add_roof("MainHallRoof", Vector3(main_width + 24.0, 12.0, main_depth + 24.0), Vector3(0.0, main_height + 6.0, 0.0), "roof")
	_add_box("MainHallUpperTier", Vector3(main_width * 0.58, 20.0, main_depth * 0.58), Vector3(0.0, main_height + 15.0, 0.0), material_key, true)
	_add_roof("UpperTierRoof", Vector3(main_width * 0.64, 8.0, main_depth * 0.64), Vector3(0.0, main_height + 29.0, 0.0), "roof")

	if kind == "palace":
		_build_palace_courtyard(main_width, main_depth, main_height, material_key)
	elif kind == "market":
		_build_market_street()
	elif kind == "residential":
		_build_residential_lane()
	elif kind == "military":
		_build_barracks()
	elif kind == "transport":
		_build_waystation()
	else:
		_build_office_wings(main_width, main_depth, main_height, material_key)

	_add_box("DistrictForecourt", Vector3(main_width + 92.0, 0.5, 58.0), Vector3(0.0, 0.3, main_depth * 0.5 + 52.0), "stone", false)
	_add_box("FrontSteps", Vector3(main_width * 0.72, 3.0, 20.0), Vector3(0.0, 1.5, main_depth * 0.5 + 12.0), "stone", true)
	_add_nameplate(title, Vector3(0.0, main_height + 50.0, -main_depth * 0.5 - 12.0))
	_build_interaction_zone(Vector3(0.0, 0.0, main_depth * 0.5 + 62.0))


func _build_palace_courtyard(width: float, depth: float, height: float, material_key: String) -> void:
	for side in [-1.0, 1.0]:
		var wing := Vector3(78.0, 34.0, 72.0)
		var p := Vector3(side * 174.0, 17.0, 74.0)
		_add_box("PalaceWing_" + str(side), wing, p, material_key, true)
		_add_roof("PalaceWingRoof_" + str(side), wing + Vector3(16.0, 8.0, 16.0), p + Vector3.UP * 21.0, "roof")
		_add_box("PalaceSideWall_" + str(side), Vector3(12.0, 22.0, 250.0), Vector3(side * 270.0, 11.0, 8.0), "stone", true)
	_add_box("ImperialTerrace", Vector3(590.0, 4.0, 420.0), Vector3(0.0, 2.0, 100.0), "stone", true)
	for i in range(5):
		var offset := (float(i) - 2.0) * 74.0
		_add_box("PalacePillar_%d" % i, Vector3(12.0, 32.0, 12.0), Vector3(offset, 16.0, depth * 0.5 + 42.0), "sign", true)
	_add_box("ImperialAudiencePlatform", Vector3(width + 140.0, 5.0, 62.0), Vector3(0.0, 2.5, depth * 0.5 + 90.0), "sign", true)


func _build_office_wings(width: float, depth: float, height: float, material_key: String) -> void:
	for side in [-1.0, 1.0]:
		var wing := Vector3(width * 0.46, height * 0.48, depth * 0.58)
		var p := Vector3(side * (width * 0.72), wing.y * 0.5, depth * 0.58)
		_add_box("SideOffice_" + str(side), wing, p, material_key, true)
		_add_roof("SideOfficeRoof_" + str(side), wing + Vector3(12.0, 6.0, 12.0), p + Vector3.UP * (wing.y * 0.5 + 3.0), "roof")
	_add_box("OfficeSideCourt", Vector3(width * 1.9, 0.5, 44.0), Vector3(0.0, 0.3, depth * 0.5 + 56.0), "stone", false)


func _build_market_street() -> void:
	_add_box("MarketStreet", Vector3(30.0, 0.4, 300.0), Vector3(0.0, 0.25, 110.0), "stone", false)
	for row in range(3):
		for column in range(4):
			var shop_x_positions := [-132.0, -72.0, 72.0, 132.0]
			var x := float(shop_x_positions[column])
			var z := 18.0 + float(row) * 78.0
			var size := Vector3(42.0, 17.0 + float((row + column) % 2) * 5.0, 48.0)
			var p := Vector3(x, size.y * 0.5, z)
			_add_box("MarketShop_%d_%d" % [row, column], size, p, "market", true)
			_add_roof("MarketAwning_%d_%d" % [row, column], Vector3(48.0, 5.0, 54.0), p + Vector3.UP * (size.y * 0.5 + 2.5), "roof")
			_add_box("ShopSign_%d_%d" % [row, column], Vector3(20.0, 5.0, 1.5), p + Vector3(0.0, 4.0, 25.0), "sign", false)
	for side in [-1.0, 1.0]:
		_add_box("MarketArcade_" + str(side), Vector3(10.0, 20.0, 300.0), Vector3(side * 190.0, 10.0, 110.0), "court", true)


func _build_residential_lane() -> void:
	_add_box("ResidentialLane", Vector3(26.0, 0.4, 260.0), Vector3(0.0, 0.25, 90.0), "stone", false)
	for row in range(3):
		for side in [-1.0, 1.0]:
			var p := Vector3(side * 62.0, 0.0, -12.0 + float(row) * 96.0)
			var size := Vector3(42.0, 22.0 + float(row % 2) * 5.0, 54.0)
			_add_box("SoulResidence_%d_%s" % [row, side], size, p + Vector3.UP * size.y * 0.5, "residential", true)
			_add_roof("ResidenceRoof_%d_%s" % [row, side], size + Vector3(8.0, 6.0, 8.0), p + Vector3.UP * (size.y + 3.0), "roof")
			_add_box("ResidenceDoor_%d_%s" % [row, side], Vector3(8.0, 13.0, 1.0), p + Vector3(0.0, 6.5, 27.6), "gate", false)
	for i in range(3):
		_add_box("CommunityLantern_%d" % i, Vector3(3.0, 12.0, 3.0), Vector3(0.0, 6.0, float(i) * 82.0), "lantern", false)


func _build_barracks() -> void:
	for row in range(2):
		for column in range(3):
			var x := (float(column) - 1.0) * 58.0
			var z := 52.0 + float(row) * 76.0
			_add_box("Barracks_%d_%d" % [row, column], Vector3(42.0, 22.0, 52.0), Vector3(x, 11.0, z), "military", true)
	_add_box("DrillYard", Vector3(250.0, 0.4, 150.0), Vector3(0.0, 0.25, 190.0), "stone", false)
	for i in range(4):
		_add_box("WeaponRack_%d" % i, Vector3(22.0, 7.0, 4.0), Vector3(-90.0 + float(i) * 60.0, 3.5, 200.0), "gate", false)


func _build_waystation() -> void:
	_add_box("WaystationPlatform", Vector3(260.0, 1.0, 70.0), Vector3(0.0, 0.5, 140.0), "stone", true)
	for i in range(3):
		var x := (float(i) - 1.0) * 78.0
		_add_box("SoulCarriageBay_%d" % i, Vector3(58.0, 20.0, 62.0), Vector3(x, 10.0, 235.0), "transport", true)
		_add_roof("CarriageRoof_%d" % i, Vector3(66.0, 7.0, 70.0), Vector3(x, 23.5, 235.0), "roof")


func _build_interaction_zone(local_position: Vector3) -> void:
	var area := Area3D.new()
	area.name = "DistrictInteractionArea"
	area.position = local_position
	area.collision_layer = 0
	area.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 14.0
	shape_node.shape = shape
	area.add_child(shape_node)
	area.body_entered.connect(_on_area_body_entered)
	area.body_exited.connect(_on_area_body_exited)
	add_child(area)


func _on_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("fengdu_player"):
		_player_nearby = true
		player_entered.emit(module_data)


func _on_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("fengdu_player"):
		_player_nearby = false
		player_exited.emit(module_data)


func _add_nameplate(text_value: String, local_position: Vector3) -> void:
	var label := Label3D.new()
	label.name = "DistrictNameplate"
	label.text = text_value
	label.position = local_position
	label.font_size = 52
	label.pixel_size = 0.025
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("#f0dfbd")
	add_child(label)


func _build_guard() -> void:
	_patrol_origin = position
	var body := MeshInstance3D.new()
	body.name = "GuardBody"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.62
	body_mesh.height = 2.25
	body.mesh = body_mesh
	body.position.y = 1.12
	body.material_override = _materials["guard"]
	add_child(body)
	var helmet := MeshInstance3D.new()
	helmet.name = "GuardHelmet"
	var helmet_mesh := SphereMesh.new()
	helmet_mesh.radius = 0.58
	helmet_mesh.height = 0.62
	helmet.mesh = helmet_mesh
	helmet.position = Vector3(0.0, 2.25, 0.0)
	helmet.material_override = _materials["gate"]
	add_child(helmet)
	var spear := MeshInstance3D.new()
	var spear_mesh := BoxMesh.new()
	spear_mesh.size = Vector3(0.12, 3.8, 0.12)
	spear.mesh = spear_mesh
	spear.position = Vector3(0.9, 1.9, 0.0)
	spear.material_override = _materials["sign"]
	add_child(spear)
	var label := Label3D.new()
	label.text = str(module_data.get("name", "巡逻阴兵"))
	label.position = Vector3(0.0, 3.3, 0.0)
	label.font_size = 28
	label.pixel_size = 0.02
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("#d8c9ad")
	add_child(label)


func _build_watchtower() -> void:
	_add_box("TowerBase", Vector3(32.0, 54.0, 32.0), Vector3(0.0, 27.0, 0.0), "wall", true)
	_add_box("TowerUpper", Vector3(44.0, 14.0, 44.0), Vector3(0.0, 61.0, 0.0), "gate", true)
	_add_roof("TowerRoof", Vector3(54.0, 8.0, 54.0), Vector3(0.0, 72.0, 0.0), "roof")


func _build_gatehouse() -> void:
	var title := str(module_data.get("name", "城门"))
	_add_box("GateLeftPillar", Vector3(34.0, 72.0, 38.0), Vector3(-62.0, 36.0, 0.0), "gate", true)
	_add_box("GateRightPillar", Vector3(34.0, 72.0, 38.0), Vector3(62.0, 36.0, 0.0), "gate", true)
	_add_box("GateLintel", Vector3(164.0, 18.0, 38.0), Vector3(0.0, 76.0, 0.0), "gate", true)
	_add_nameplate(title, Vector3(0.0, 98.0, -24.0))


func _add_roof(node_name: String, size: Vector3, p: Vector3, material_key: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = p
	mesh.material_override = _materials[material_key]
	add_child(mesh)


func _add_box(node_name: String, size: Vector3, p: Vector3, material_key: String, with_collision: bool) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = p
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _materials[material_key]
	root.add_child(visual)
	if with_collision:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		body.add_child(collision)
		root.add_child(body)
	add_child(root)
