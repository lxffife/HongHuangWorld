extends Node3D
## Macro-scale underworld geography review. This is a planning overview, not a streamed runtime world.
const FENGDU_SCENE := preload("res://scenes/FengduCityLayoutPreview.tscn")

const FENGDU_CENTER := Vector3(-112.0, 0.0, 8.0)
const BLOOD_SEA_CENTER := Vector3(132.0, 0.0, 10.0)
const HELL_GATE_CENTER := Vector3(8.0, -1.0, -142.0)

func _ready() -> void:
	_build_atmosphere()
	_build_continent()
	_build_fengdu_region()
	_build_forget_river()
	_build_blood_sea_region()
	_build_hell_region()
	_build_routes_and_signs()


func _build_atmosphere() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#090b14")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9b9aaf")
	env.ambient_light_energy = 0.58
	env.fog_enabled = true
	env.fog_light_color = Color("#38313f")
	env.fog_density = 0.0018
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -24.0, 0.0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.name = "UnderworldMacroOverviewCamera"
	camera.position = Vector3(0.0, 310.0, 390.0)
	camera.fov = 52.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -20.0), Vector3.UP)
	camera.current = true


func _build_continent() -> void:
	_add_box("UnderworldLandmass", Vector3(440.0, 4.0, 390.0), Vector3(0.0, -3.0, -35.0), Color("#242630"))
	_add_box("OuterWastes", Vector3(420.0, 0.4, 370.0), Vector3(0.0, -0.8, -35.0), Color("#34313a"))
	for index in range(24):
		var x := -190.0 + float((index * 47) % 380)
		var z := -205.0 + float((index * 71) % 340)
		_add_rock(Vector3(x, 0.0, z), 1.5 + float(index % 4) * 0.8)


func _build_fengdu_region() -> void:
	var city := FENGDU_SCENE.instantiate()
	city.name = "FengduInnerCityPreview"
	city.position = FENGDU_CENTER
	city.scale = Vector3.ONE * 1.15
	add_child(city)
	_add_ring("FengduOuterDefenceRing", FENGDU_CENTER + Vector3(0.0, 0.05, 0.0), 58.0, 1.8, Color("#665a62"))
	_add_sign("酆都城 · 冥界主城", FENGDU_CENTER + Vector3(0.0, 24.0, 0.0), 38)
	_add_sign("内城 / 外城 / 城防区", FENGDU_CENTER + Vector3(0.0, 12.0, 64.0), 18)


func _build_forget_river() -> void:
	# The river skirts Fengdu's outer territory; it is not the Blood Sea.
	var river_points := [
		Vector3(-178.0, -0.25, 74.0), Vector3(-150.0, -0.22, 96.0),
		Vector3(-116.0, -0.20, 102.0), Vector3(-82.0, -0.22, 92.0),
		Vector3(-50.0, -0.25, 72.0)
	]
	for index in range(river_points.size() - 1):
		var midpoint := (river_points[index] + river_points[index + 1]) * 0.5
		var direction := river_points[index + 1] - river_points[index]
		var segment := _add_box("WangchuanRiverSegment", Vector3(18.0, 0.35, direction.length()), midpoint, Color("#536d78"))
		segment.look_at(midpoint + direction, Vector3.UP)
		segment.material_override = _material(Color("#536d78"), 0.42)
	_add_sign("忘川 · 不与血海混为一体", Vector3(-116.0, 3.0, 112.0), 20)


func _build_blood_sea_region() -> void:
	_add_disc("BloodSea", BLOOD_SEA_CENTER, 68.0, Color("#4d1725"), -0.2)
	_add_disc("BloodSeaInnerCurrent", BLOOD_SEA_CENTER + Vector3(0.0, 0.12, 0.0), 39.0, Color("#762337"), -0.2)
	_add_ring("BloodSeaShore", BLOOD_SEA_CENTER, 70.0, 2.6, Color("#8b4b50"))
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var radius := 49.0 + float(index % 3) * 5.0
		var rock_at := BLOOD_SEA_CENTER + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_add_rock(rock_at, 3.0 + float(index % 4))
	_add_minghe_sanctuary(BLOOD_SEA_CENTER + Vector3(92.0, 0.0, -18.0))
	_add_sign("幽冥血海 · 冥河老祖道场", BLOOD_SEA_CENTER + Vector3(0.0, 15.0, -78.0), 34)
	_add_sign("远离酆都城的独立禁地", BLOOD_SEA_CENTER + Vector3(0.0, 8.0, 78.0), 20)


func _add_minghe_sanctuary(at: Vector3) -> void:
	_add_box("MingheSanctuaryBase", Vector3(30.0, 2.0, 24.0), at + Vector3(0.0, 1.0, 0.0), Color("#332a36"))
	_add_box("MingheSanctuaryHall", Vector3(19.0, 10.0, 14.0), at + Vector3(0.0, 7.0, 0.0), Color("#572533"))
	_add_box("MingheSanctuaryRoof", Vector3(24.0, 2.0, 18.0), at + Vector3(0.0, 13.0, 0.0), Color("#211d2a"))
	for x in [-10.0, 10.0]:
		_add_box("BloodPillar", Vector3(2.0, 12.0, 2.0), at + Vector3(x, 7.0, -8.0), Color("#763044"))
	_add_sign("冥河道场", at + Vector3(0.0, 19.0, 0.0), 24)


func _build_hell_region() -> void:
	var plateau := _add_disc("EighteenHellsPlateau", HELL_GATE_CENTER, 58.0, Color("#30242d"), -1.0)
	plateau.rotation.x = 0.0
	_add_ring("HellOuterRim", HELL_GATE_CENTER, 52.0, 3.2, Color("#72504e"))
	_add_disc("HellAbyss", HELL_GATE_CENTER + Vector3(0.0, 0.25, 0.0), 26.0, Color("#100d16"), -1.0)
	_add_ring("HellAbyssRim", HELL_GATE_CENTER, 28.0, 2.0, Color("#a24b3f"))
	_add_hell_gate(HELL_GATE_CENTER + Vector3(0.0, 0.0, 36.0))
	_add_sign("十八层地狱 · 独立刑狱区域", HELL_GATE_CENTER + Vector3(0.0, 19.0, -62.0), 32)
	_add_sign("入口关隘 / 分层狱道 / 终审深层", HELL_GATE_CENTER + Vector3(0.0, 8.0, 65.0), 18)


func _add_hell_gate(at: Vector3) -> void:
	_add_box("HellGateLeftPillar", Vector3(4.0, 18.0, 4.0), at + Vector3(-10.0, 9.0, 0.0), Color("#4a3438"))
	_add_box("HellGateRightPillar", Vector3(4.0, 18.0, 4.0), at + Vector3(10.0, 9.0, 0.0), Color("#4a3438"))
	_add_box("HellGateLintel", Vector3(25.0, 4.0, 5.0), at + Vector3(0.0, 19.0, 0.0), Color("#6e4546"))
	_add_box("HellGateDarkness", Vector3(12.0, 14.0, 0.4), at + Vector3(0.0, 8.0, -2.2), Color("#0a0910"))


func _build_routes_and_signs() -> void:
	_add_route("FengduToBloodSeaRoad", Vector3(-52.0, -0.45, 4.0), Vector3(58.0, -0.45, 10.0), 5.5, Color("#77665b"))
	_add_route("FengduToHellRoad", Vector3(-92.0, -0.42, -55.0), Vector3(4.0, -0.42, -112.0), 5.0, Color("#655b60"))
	_add_sign("酆都至血海：远距离荒原道路", Vector3(5.0, 2.0, 22.0), 18)
	_add_sign("酆都至地狱入口：幽冥古道", Vector3(-56.0, 2.0, -82.0), 18)
	_add_sign("冥界区域关系总览 · 非实际比例地图", Vector3(0.0, 22.0, 205.0), 30)


func _add_route(node_name: String, start: Vector3, finish: Vector3, width: float, color: Color) -> void:
	var midpoint := (start + finish) * 0.5
	var delta := finish - start
	var road := _add_box(node_name, Vector3(width, 0.45, delta.length()), midpoint, color)
	road.look_at(finish, Vector3.UP)


func _add_box(node_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = _material(color)
	add_child(node)
	return node


func _add_disc(node_name: String, at: Vector3, radius: float, color: Color, y_offset: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.6
	mesh.radial_segments = 64
	node.mesh = mesh
	node.position = at + Vector3(0.0, y_offset, 0.0)
	node.material_override = _material(color, 0.22)
	add_child(node)
	return node


func _add_ring(node_name: String, at: Vector3, radius: float, thickness: float, color: Color) -> void:
	var ring := MeshInstance3D.new()
	ring.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius
	mesh.rings = 64
	mesh.ring_segments = 12
	ring.mesh = mesh
	ring.position = at + Vector3(0.0, 0.25, 0.0)
	ring.material_override = _material(color, 0.18)
	add_child(ring)


func _add_rock(at: Vector3, scale_value: float) -> void:
	var rock := MeshInstance3D.new()
	rock.name = "UnderworldRock"
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	rock.mesh = mesh
	rock.position = at
	rock.scale = Vector3(scale_value * 1.4, scale_value * 0.7, scale_value)
	rock.rotation_degrees = Vector3(float(int(at.x) % 17), float(int(at.z) % 31), 0.0)
	rock.material_override = _material(Color("#45404a"))
	add_child(rock)


func _add_sign(value: String, at: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = size
	label.outline_size = 8
	label.modulate = Color("#e4d0b0")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material
