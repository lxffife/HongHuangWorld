extends Node3D
## Standalone review scene for the walkable ghost-market shop interior.

const VisualFactory = preload("res://scripts/underworld_visual_factory.gd")


func _ready() -> void:
	var interior := VisualFactory.create_ghost_market_shop_interior()
	interior.name = "GhostMarketShopInteriorKit"
	add_child(interior)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	key_light.light_energy = 1.1
	add_child(key_light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.8, 1.5)
	fill.light_color = Color("#d6b58a")
	fill.light_energy = 1.0
	fill.omni_range = 18.0
	add_child(fill)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#211d29")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a49486")
	environment.ambient_light_energy = 0.72
	world.environment = environment
	add_child(world)

	var camera := Camera3D.new()
	camera.position = Vector3(15.5, 12.0, -17.5)
	camera.fov = 58.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
