extends SceneTree

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const WorldChunkStreamerScript = preload("res://scripts/world_chunk_streamer.gd")
const FengduCityBuilder = preload("res://scripts/fengdu_city_builder.gd")
const HellFloorBuilder = preload("res://scripts/underworld_hell_floor_builder.gd")


func _initialize() -> void:
	call_deferred("_run_world_generation_tests")


func _run_world_generation_tests() -> void:
	_test_world_bounds_and_hell_catalog()
	_test_chunk_streaming()
	_test_fengdu_city_blockout()
	_test_hell_floor_blockout()
	print("WORLD_GENERATION_TESTS_OK")
	quit(0)


func _test_world_bounds_and_hell_catalog() -> void:
	var bounds := WorldMapCatalog.get_world_bounds("underworld_fengdu")
	assert(bounds == Vector4(-100.0, 100.0, -100.0, 100.0))
	var hell_layers := WorldMapCatalog.get_eighteen_hell_layers()
	assert(hell_layers.size() == 18)
	for index in range(hell_layers.size()):
		var layer: Dictionary = hell_layers[index]
		assert(int(layer.get("floor", 0)) == index + 1)
		assert(not str(layer.get("name", "")).is_empty())


func _test_chunk_streaming() -> void:
	var host := Node3D.new()
	get_root().add_child(host)
	var streamer := Node3D.new()
	streamer.set_script(WorldChunkStreamerScript)
	streamer.call("configure", "underworld_fengdu", 48.0, 1)
	host.add_child(streamer)
	streamer.call("update_streaming", Vector3.ZERO)
	assert(int(streamer.call("get_loaded_chunk_count")) == 9)
	assert(streamer.get_node_or_null("GroundChunk_2_2") is StaticBody3D)
	streamer.call("update_streaming", Vector3(99.0, 0.0, 99.0))
	assert(int(streamer.call("get_loaded_chunk_count")) == 4)
	assert(streamer.get_node_or_null("GroundChunk_4_4") is StaticBody3D)
	host.free()


func _test_fengdu_city_blockout() -> void:
	var city := FengduCityBuilder.build()
	assert(city.get_node_or_null("District_imperial_palace") is StaticBody3D)
	assert(city.get_node_or_null("District_ghost_market") is StaticBody3D)
	assert(city.get_node_or_null("District_residential_quarter") is StaticBody3D)
	assert(city.get_node_or_null("SouthWall_-1.0") is StaticBody3D)
	assert(city.get_node_or_null("NorthWall_1.0") is StaticBody3D)
	var palace := city.get_node("District_imperial_palace")
	assert(palace.get_node_or_null("CollisionShape3D") is CollisionShape3D)
	assert(city.get_node_or_null("Road_imperial_palace_ten_kings_manors") is MeshInstance3D)
	city.free()


func _test_hell_floor_blockout() -> void:
	var floor_data := WorldMapCatalog.get_hell_floor_data(18)
	assert(not floor_data.is_empty())
	assert(str(floor_data.get("environment", "")) == "abyss")
	assert(not str(floor_data.get("objective", "")).is_empty())
	assert(WorldMapCatalog.resolve_hell_floor_number("underworld_hell_18") == 18)
	assert(WorldMapCatalog.resolve_hell_floor_number("underworld_hell_invalid") == 0)
	assert(WorldMapCatalog.resolve_region_name("underworld_hell_18", Vector3.ZERO) == "十八层地狱 · 第 18 层")
	var floor_scene := HellFloorBuilder.build(18)
	assert(str(floor_scene.get_meta("hell_floor_id", "")) == "hell_18")
	assert(floor_scene.get_node_or_null("EntrancePortal") is Node3D)
	assert(floor_scene.get_node_or_null("TrialExitPortal") is Node3D)
	assert(floor_scene.get_node_or_null("GuardianDais") is MeshInstance3D)
	assert(floor_scene.get_node_or_null("ArenaWallX_-1.0") is StaticBody3D)
	floor_scene.free()
