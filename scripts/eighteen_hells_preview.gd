extends Node3D
## Eighteen-layer vertical dungeon blockout. The names/order are a game adaptation,
## not a claim that all folk traditions share one canonical list.

const LAYER_NAMES := [
	"第一层 · 拔舌狱", "第二层 · 剪刀狱", "第三层 · 铁树狱",
	"第四层 · 孽镜狱", "第五层 · 蒸笼狱", "第六层 · 铜柱狱",
	"第七层 · 刀山狱", "第八层 · 冰山狱", "第九层 · 油锅狱",
	"第十层 · 牛坑狱", "第十一层 · 石压狱", "第十二层 · 舂臼狱",
	"第十三层 · 血池狱", "第十四层 · 枉死狱", "第十五层 · 磔刑狱",
	"第十六层 · 火山狱", "第十七层 · 石磨狱", "第十八层 · 刀锯狱"
]
const LEVEL_HEIGHT := 5.0
const RADIUS := 21.0
const PLATFORM_SIZE := 18.0

func _ready() -> void:
	_build_environment()
	_build_layers()
	_build_entry_and_finale()
	_build_route_markers()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#08080e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8c8797")
	env.ambient_light_energy = 0.48
	env.fog_enabled = true
	env.fog_light_color = Color("#322b38")
	env.fog_density = 0.0025
	world.environment = env
	add_child(world)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -28.0, 0.0)
	light.light_energy = 0.9
	light.shadow_enabled = true
	add_child(light)

	var camera := Camera3D.new()
	camera.name = "HellSpiralOverviewCamera"
	camera.position = Vector3(88.0, 48.0, 88.0)
	camera.fov = 58.0
	add_child(camera)
	camera.look_at(Vector3(0.0, -42.0, 0.0), Vector3.UP)
	camera.current = true


func _layer_position(index: int) -> Vector3:
	var angle := deg_to_rad(float(index) * 38.0 - 90.0)
	return Vector3(cos(angle) * RADIUS, -float(index) * LEVEL_HEIGHT, sin(angle) * RADIUS)


func _layer_color(index: int) -> Color:
	var palettes := [
		Color("#51404c"), Color("#51434a"), Color("#4a493d"),
		Color("#45434e"), Color("#57433b"), Color("#554039"),
		Color("#5a3b3d"), Color("#40505b"), Color("#694331"),
		Color("#514337"), Color("#4b4650"), Color("#51424a"),
		Color("#633443"), Color("#46414d"), Color("#5a3d46"),
		Color("#713c2d"), Color("#49434d"), Color("#663b36")
	]
	return palettes[index % palettes.size()]


func _build_layers() -> void:
	for index in range(LAYER_NAMES.size()):
		var center := _layer_position(index)
		var tint := _layer_color(index)
		_add_platform(index, center, tint)
		_add_layer_gate(index, center, tint)
		_add_label(LAYER_NAMES[index], center + Vector3(0.0, 5.4, 0.0), 20)
		if index > 0:
			_add_connector(index - 1, index)
		if (index + 1) % 3 == 0 and index < 17:
			_add_checkpoint(index, center)


func _add_platform(index: int, center: Vector3, tint: Color) -> void:
	_add_box("HellLayer_%02d_Floor" % (index + 1), Vector3(PLATFORM_SIZE, 1.0, PLATFORM_SIZE), center, tint)
	_add_box("HellLayer_%02d_Inset" % (index + 1), Vector3(PLATFORM_SIZE - 3.0, 0.18, PLATFORM_SIZE - 3.0), center + Vector3(0.0, 0.6, 0.0), tint.lightened(0.12))
	for side in [-1.0, 1.0]:
		_add_box("HellLayer_%02d_Pillar" % (index + 1), Vector3(1.2, 4.0, 1.2), center + Vector3(side * 7.4, 2.5, side * 7.4), Color("#292632"))


func _add_layer_gate(index: int, center: Vector3, tint: Color) -> void:
	var gate_at := center + Vector3(0.0, 2.2, -7.0)
	_add_box("HellGate_%02d_Left" % (index + 1), Vector3(1.2, 4.5, 1.0), gate_at + Vector3(-3.0, 0.0, 0.0), tint.darkened(0.32))
	_add_box("HellGate_%02d_Right" % (index + 1), Vector3(1.2, 4.5, 1.0), gate_at + Vector3(3.0, 0.0, 0.0), tint.darkened(0.32))
	_add_box("HellGate_%02d_Lintel" % (index + 1), Vector3(7.2, 1.0, 1.2), gate_at + Vector3(0.0, 2.2, 0.0), tint.lightened(0.2))


func _add_connector(from_index: int, to_index: int) -> void:
	var start := _layer_position(from_index) + Vector3(0.0, -0.7, 0.0)
	var finish := _layer_position(to_index) + Vector3(0.0, 0.7, 0.0)
	var midpoint := (start + finish) * 0.5
	var delta := finish - start
	var ramp := _add_box("HellSpiralRamp_%02d" % to_index, Vector3(4.2, 0.65, delta.length()), midpoint, Color("#39313b"))
	ramp.look_at(finish, Vector3.UP)
	var rail_left := _add_box("HellRampRailL_%02d" % to_index, Vector3(0.35, 1.2, delta.length()), midpoint + Vector3(-2.2, 0.6, 0.0), Color("#65515a"))
	var rail_right := _add_box("HellRampRailR_%02d" % to_index, Vector3(0.35, 1.2, delta.length()), midpoint + Vector3(2.2, 0.6, 0.0), Color("#65515a"))
	rail_left.look_at(finish, Vector3.UP)
	rail_right.look_at(finish, Vector3.UP)


func _add_checkpoint(index: int, center: Vector3) -> void:
	var altar_at := center + Vector3(0.0, 1.2, 5.0)
	_add_box("HellCheckpoint_%02d" % (index + 1), Vector3(4.0, 1.0, 4.0), altar_at, Color("#9a7955"))
	_add_label("镇魂驿 · 安全节点", altar_at + Vector3(0.0, 3.0, 0.0), 13)


func _build_entry_and_finale() -> void:
	var entry := _layer_position(0)
	_add_box("HellEntranceThreshold", Vector3(15.0, 1.5, 8.0), entry + Vector3(0.0, 1.0, 13.0), Color("#766052"))
	_add_label("入口 · 试炼登记与队伍整备", entry + Vector3(0.0, 8.0, 20.0), 18)

	var final_center := _layer_position(17) + Vector3(0.0, -4.0, 0.0)
	_add_box("FinalJudgmentArena", Vector3(34.0, 1.4, 34.0), final_center, Color("#32242d"))
	_add_ring("FinalArenaSeal", final_center + Vector3(0.0, 0.9, 0.0), 13.0, 1.0, Color("#b65b4d"))
	_add_box("FinalJudgmentThrone", Vector3(10.0, 8.0, 5.0), final_center + Vector3(0.0, 5.0, -10.0), Color("#50323a"))
	_add_label("终审深层 · 首领战与通关出口", final_center + Vector3(0.0, 13.0, 0.0), 20)


func _build_route_markers() -> void:
	for index in range(0, 18, 3):
		var at := _layer_position(index)
		_add_ring("LayerSeal_%02d" % (index + 1), at + Vector3(0.0, 0.68, 0.0), 6.0, 0.22, Color("#a88b69"))
	_add_label("十八层地狱 · 垂直螺旋关卡总览", Vector3(0.0, 12.0, 0.0), 30)
	_add_label("建议流程：入口 → 18 层试炼 → 每三层安全节点 → 终审首领 → 通关出口", Vector3(0.0, 5.0, 0.0), 16)


func _add_box(node_name: String, size: Vector3, at: Vector3, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = _material(tint)
	add_child(node)
	return node


func _add_ring(node_name: String, at: Vector3, radius: float, thickness: float, tint: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius
	mesh.rings = 48
	mesh.ring_segments = 10
	node.mesh = mesh
	node.position = at
	node.material_override = _material(tint, 0.32)
	add_child(node)


func _add_label(value: String, at: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = size
	label.outline_size = 7
	label.modulate = Color("#ead6b5")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _material(tint: Color, glow: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.9
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = tint
		material.emission_energy_multiplier = glow
	return material
