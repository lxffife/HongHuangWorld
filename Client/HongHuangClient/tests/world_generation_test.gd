extends SceneTree

const WorldMapCatalog = preload("res://scripts/world_map_catalog.gd")
const WorldChunkStreamerScript = preload("res://scripts/world_chunk_streamer.gd")
const FengduCityBuilder = preload("res://scripts/fengdu_city_builder.gd")
const FengduNavigation = preload("res://scripts/fengdu_navigation.gd")
const FengduWorldLayout = preload("res://scripts/fengdu_world_layout.gd")
const FengduGraybox = preload("res://scripts/fengdu_graybox.gd")
const HellFloorBuilder = preload("res://scripts/underworld_hell_floor_builder.gd")


func _initialize() -> void:
	call_deferred("_run_world_generation_tests")


func _run_world_generation_tests() -> void:
	_test_world_bounds_and_hell_catalog()
	_test_chunk_streaming()
	_test_fengdu_city_blockout()
	_test_fengdu_navigation()
	_test_hell_floor_blockout()
	print("WORLD_GENERATION_TESTS_OK")
	quit(0)


func _test_world_bounds_and_hell_catalog() -> void:
	var bounds := WorldMapCatalog.get_world_bounds("underworld_fengdu")
	assert(bounds == Vector4(-100.0, 100.0, -100.0, 100.0))
	assert(WorldMapCatalog.resolve_region_name("underworld_fengdu", Vector3(0.0, 0.0, -81.0)) == "酆都皇城")
	assert(WorldMapCatalog.resolve_region_name("underworld_fengdu", Vector3(22.0, 0.0, -40.0)) == "万魂鬼市")
	var fengdu_waters := WorldMapCatalog.get_water_bodies("underworld_fengdu")
	assert(fengdu_waters.size() == 1)
	assert(str(fengdu_waters[0].get("id", "")) == "forgotten_river")
	var blood_sea := WorldMapCatalog.get_underworld_atlas_node("blood_sea")
	assert(str(blood_sea.get("authority", "")) == "冥河老祖 · 阿修罗诸王")
	assert(str(blood_sea.get("distance", "")) == "极遥远的冥界远域")
	var hell_layers := WorldMapCatalog.get_eighteen_hell_layers()
	assert(hell_layers.size() == 18)
	for index in range(hell_layers.size()):
		var layer: Dictionary = hell_layers[index]
		assert(int(layer.get("floor", 0)) == index + 1)
		assert(not str(layer.get("name", "")).is_empty())
		assert(not str(layer.get("environment", "")).is_empty())
		assert(not str(layer.get("hazard", "")).is_empty())
		assert(not str(layer.get("objective", "")).is_empty())
		assert(not str(layer.get("reward_theme", "")).is_empty())


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
	assert(city.get_node_or_null("EastWall_-1.0") is StaticBody3D)
	assert(city.get_node_or_null("WestWall_1.0") is StaticBody3D)
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
	assert(WorldMapCatalog.resolve_hell_floor_number("underworld_hell_99") == 0)
	assert(WorldMapCatalog.resolve_region_name("underworld_hell_18", Vector3.ZERO) == "十八层地狱 · 第 18 层")
	var floor_scene := HellFloorBuilder.build(18)
	assert(str(floor_scene.get_meta("hell_floor_id", "")) == "hell_18")
	assert(floor_scene.get_node_or_null("EntrancePortal") is Node3D)
	assert(floor_scene.get_node_or_null("TrialExitPortal") is Node3D)
	assert(floor_scene.get_node_or_null("GuardianDais") is MeshInstance3D)
	assert(floor_scene.get_node_or_null("ArenaWallX_-1.0") is StaticBody3D)
	floor_scene.free()


func _test_fengdu_navigation() -> void:
	var network := FengduNavigation.build_city_network(WorldMapCatalog.get_fengdu_city_plan())
	var validation := FengduNavigation.validate_network(network)
	assert(bool(validation.get("valid", false)))
	assert(int(validation.get("node_count", 0)) == 15)
	assert(int(validation.get("edge_count", 0)) == 11)

	var open_route := FengduNavigation.find_path(network, "imperial_palace", "north_gate")
	assert(bool(open_route.get("found", false)))
	assert(open_route.get("node_ids", []).has("north_gate"))

	var closed_route := FengduNavigation.find_path(network, "imperial_palace", "north_gate", {"closed_gates": ["north_gate"]})
	assert(not bool(closed_route.get("found", false)))
	assert(str(closed_route.get("reason", "")) == "unreachable")

	var alternate_route := FengduNavigation.find_path(network, "ghost_registry", "ghost_market", {"blocked_edge_ids": ["city_road_05"]})
	assert(bool(alternate_route.get("found", false)))

	var narrow_route := FengduNavigation.find_path(network, "imperial_palace", "north_gate", {"minimum_width": 13.0})
	assert(not bool(narrow_route.get("found", false)))

	var nearest := FengduNavigation.find_nearest_node(network, Vector3(0.0, 0.0, -81.36), ["palace", "court"])
	assert(bool(nearest.get("found", false)))
	assert(str(nearest.get("node_id", "")) == "imperial_palace")

	var restricted_network: Dictionary = network.duplicate(true)
	for edge_variant in restricted_network.get("edges", []):
		var edge: Dictionary = edge_variant
		if str(edge.get("gate_id", "")) == "north_gate":
			edge["required_access"] = "north_gate_pass"
	var denied_route := FengduNavigation.find_path(restricted_network, "imperial_palace", "north_gate")
	assert(not bool(denied_route.get("found", false)))
	var permitted_route := FengduNavigation.find_path(restricted_network, "imperial_palace", "north_gate", {"access_tags": ["north_gate_pass"]})
	assert(bool(permitted_route.get("found", false)))

	var district_route := FengduNavigation.find_path_to_district(
		network, Vector3(0.0, 0.0, -81.36), "ghost_market",
		[{"id": "market_main_entry", "district_id": "ghost_market", "navigation_node_id": "ghost_market", "service": "trade"}]
	)
	assert(bool(district_route.get("found", false)))
	assert(str(district_route.get("destination_service", "")) == "trade")

	var disabled_network: Dictionary = network.duplicate(true)
	for node_variant in disabled_network.get("nodes", []):
		var node: Dictionary = node_variant
		if str(node.get("id", "")) == "imperial_palace":
			node["enabled"] = false
	var disabled_nearest := FengduNavigation.find_nearest_node(disabled_network, Vector3(0.0, 0.0, -81.36), ["palace", "court"])
	assert(str(disabled_nearest.get("node_id", "")) != "imperial_palace")

	# The playable 1.9 km graybox uses the canonical meter-scale layout graph,
	# not the separate 256 m city-plan prototype graph above.
	var playable_network: Dictionary = FengduWorldLayout.get_navigation_network()
	var playable_validation := FengduNavigation.validate_network(playable_network)
	assert(bool(playable_validation.get("valid", false)))
	var expected_gate_edges := {
		"road.gate.north": "north_heaven_gate",
		"road.gate.south": "south_ghost_gate",
		"road.gate.east": "east_mystic_gate",
		"road.gate.west": "west_dark_gate"
	}
	var gate_edge_count := 0
	for edge_variant in playable_network.get("edges", []):
		var edge: Dictionary = edge_variant
		var edge_id := str(edge.get("id", ""))
		if expected_gate_edges.has(edge_id):
			gate_edge_count += 1
			assert(str(edge.get("gate_id", "")) == str(expected_gate_edges[edge_id]))
	assert(gate_edge_count == 4)
	var playable_open_route := FengduNavigation.find_path(playable_network, "junction.center", "gate.north")
	assert(bool(playable_open_route.get("found", false)))
	var playable_closed_route := FengduNavigation.find_path(
		playable_network, "junction.center", "gate.north", {"closed_gates": ["north_heaven_gate"]}
	)
	assert(not bool(playable_closed_route.get("found", false)))
	var other_gate_route := FengduNavigation.find_path(playable_network, "junction.center", "gate.south", {"closed_gates": ["north_heaven_gate"]})
	assert(bool(other_gate_route.get("found", false)))

	# Exercise the actual large-graybox adapter: local gate state must feed its public route API.
	var gate_adapter := Node3D.new()
	gate_adapter.set_script(FengduGraybox)
	gate_adapter.call("_build_activity_registry")
	assert(bool(gate_adapter.call("set_local_gate_state", "north_heaven_gate", false)))
	var adapter_north_route: Dictionary = gate_adapter.call(
		"get_navigation_route_between_positions", Vector3.ZERO, Vector3(0.0, 0.0, 96.0)
	)
	assert(not bool(adapter_north_route.get("found", false)))
	var adapter_south_route: Dictionary = gate_adapter.call(
		"get_navigation_route_between_positions", Vector3.ZERO, Vector3(0.0, 0.0, -96.0)
	)
	assert(bool(adapter_south_route.get("found", false)))
	assert(not bool(gate_adapter.call("set_local_gate_state", "unknown_gate", false)))
	gate_adapter.free()
