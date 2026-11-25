extends Node3D
## Standalone visual review scene for the Fengdu residential/ghost-market kit.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")


func _ready() -> void:
	var lane := VisualFactory.create_fengdu_residential_lane()
	lane.name = "ResidentialLaneKit"
	add_child(lane)

	var key_light := DirectionalLight3D.new()
	key_light.name = "ReviewKeyLight"
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_energy = 1.15
	add_child(key_light)

	var fill_light := OmniLight3D.new()
	fill_light.name = "WarmFill"
	fill_light.position = Vector3(0.0, 7.0, 8.0)
	fill_light.light_color = Color("#9bb8c5")
	fill_light.light_energy = 0.65
	fill_light.omni_range = 32.0
	add_child(fill_light)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#87909f")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.name = "ReviewCamera"
	camera.position = Vector3(23.0, 18.0, 27.0)
	camera.fov = 52.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 2.0, -1.0), Vector3.UP)
