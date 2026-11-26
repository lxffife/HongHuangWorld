extends Node3D
## Standalone interior collision and circulation review scene.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")


func _ready() -> void:
	var interior := VisualFactory.create_fengdu_residential_interior()
	interior.name = "ResidentialInteriorKit"
	add_child(interior)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	add_child(key_light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.5, 0.0)
	fill.light_color = Color("#d6b58a")
	fill.light_energy = 0.8
	fill.omni_range = 15.0
	add_child(fill)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#24212a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#9b8d80")
	environment.ambient_light_energy = 0.7
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(12.5, 10.5, -14.0)
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
