extends Node3D
## Side-by-side visual review scene for the first three runtime hell-floor builders.
## This scene is for art/layout inspection; it does not connect to the trial server.

const HellFloorBuilder = preload("res://scripts/underworld_hell_floor_builder.gd")
const FLOOR_TITLES := [
	"第一层 · 拔舌地狱",
	"第二层 · 剪刀地狱",
	"第三层 · 铁树地狱"
]

func _ready() -> void:
	_build_environment()
	_build_floor_row()


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#080b13")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#aaa1b4")
	environment.ambient_light_energy = 0.72
	environment.fog_enabled = true
	environment.fog_light_color = Color("#39313f")
	environment.fog_density = 0.0009
	world.environment = environment
	add_child(world)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -26.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(0.0, 26.0, 18.0)
	fill_light.light_color = Color("#8e9eb8")
	fill_light.light_energy = 1.1
	fill_light.omni_range = 110.0
	add_child(fill_light)

	var camera := Camera3D.new()
	camera.name = "HellFirstThreeReviewCamera"
	camera.position = Vector3(0.0, 108.0, 168.0)
	camera.fov = 58.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, -2.0), Vector3.UP)
	camera.current = true


func _build_floor_row() -> void:
	for floor_number in range(1, 4):
		var offset_x := float(floor_number - 2) * 70.0
		var floor_root: Node3D = HellFloorBuilder.build(floor_number)
		floor_root.position = Vector3(offset_x, 0.0, 0.0)
		floor_root.name = "ReviewFloor_%02d" % floor_number
		add_child(floor_root)
		_add_title(FLOOR_TITLES[floor_number - 1], Vector3(offset_x, 23.0, 0.0))
		_add_subtitle(_objective_for_floor(floor_number), Vector3(offset_x, 17.0, 0.0))


func _objective_for_floor(floor_number: int) -> String:
	var objectives := [
		"找出三份互相矛盾的证词",
		"修复被剪断的因果线",
		"穿越铁树刑阵并解救被困亡魂"
	]
	return objectives[floor_number - 1]


func _add_title(value: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = 34
	label.outline_size = 8
	label.modulate = Color("#f0d6a8")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)


func _add_subtitle(value: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = value
	label.position = at
	label.font_size = 19
	label.outline_size = 6
	label.modulate = Color("#c4cbd5")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
