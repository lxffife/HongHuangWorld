extends RefCounted

## Creates the world sky, ambient lighting, fog and directional key light.
## Environment setup is separate from gameplay scene orchestration.
static func build(world_id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WorldEnvironmentRig"
	var is_underworld := world_id == "underworld_fengdu"
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	if is_underworld:
		sky_material.sky_top_color = Color("#080d20")
		sky_material.sky_horizon_color = Color("#382b4d")
		sky_material.ground_bottom_color = Color("#080b14")
		sky_material.ground_horizon_color = Color("#241d32")
	else:
		sky_material.sky_top_color = Color("#142b49")
		sky_material.sky_horizon_color = Color("#d3a878")
		sky_material.ground_bottom_color = Color("#182333")
		sky_material.ground_horizon_color = Color("#a58b6b")
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#66708f") if is_underworld else Color("#9fb4d0")
	environment.ambient_light_energy = 0.32 if is_underworld else 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("#51445f") if is_underworld else Color("#9ba9b8")
	environment.fog_density = 0.012 if is_underworld else 0.0018
	world_environment.environment = environment
	root.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 0.42 if is_underworld else 1.35
	sun.light_color = Color("#9a8abf") if is_underworld else Color("#fff0d2")
	sun.shadow_enabled = true
	root.add_child(sun)
	return root
