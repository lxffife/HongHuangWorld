extends Control
## Lightweight live minimap. Coordinates are supplied by the authoritative world
## snapshot/entities; the player remains centered and nearby markers move around it.

signal marker_selected(kind: String, marker_id: String, marker_name: String)

var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var world_radius: float = 55.0
var exploration_points: Array = []
var npc_points: Array = []
var monster_points: Array = []
var navigation_target: Dictionary = {}
var _redraw_elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.40
	var best_distance := 13.0
	var best_kind := ""
	var best_id := ""
	var best_name := ""
	for exploration_item in exploration_points:
		if not exploration_item is Dictionary:
			continue
		var point: Dictionary = exploration_item
		var point_pos := _map_point(float(point.get("position_x", 0.0)), float(point.get("position_z", 0.0)), center, radius)
		if not Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(point_pos):
			continue
		var exploration_distance := point_pos.distance_to(mouse_event.position)
		if exploration_distance < best_distance:
			best_distance = exploration_distance
			best_kind = "exploration"
			best_id = str(point.get("id", ""))
			best_name = str(point.get("name", "探索点"))
	for npc_item in npc_points:
		if not npc_item is Dictionary:
			continue
		var npc: Dictionary = npc_item
		var npc_pos := _map_point(float(npc.get("position_x", 0.0)), float(npc.get("position_z", 0.0)), center, radius)
		if not Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(npc_pos):
			continue
		var npc_distance := npc_pos.distance_to(mouse_event.position)
		if npc_distance < best_distance:
			best_distance = npc_distance
			best_kind = "npc"
			best_id = str(npc.get("id", ""))
			best_name = str(npc.get("name", "NPC"))
	for monster_item in monster_points:
		if not monster_item is Dictionary:
			continue
		var monster: Dictionary = monster_item
		var monster_pos := _map_point(float(monster.get("x", 0.0)), float(monster.get("z", 0.0)), center, radius)
		if not Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(monster_pos):
			continue
		var monster_distance := monster_pos.distance_to(mouse_event.position)
		if monster_distance < best_distance:
			best_distance = monster_distance
			best_kind = "monster"
			best_id = str(monster.get("id", ""))
			best_name = str(monster.get("name", "怪物"))
	if not best_id.is_empty():
		marker_selected.emit(best_kind, best_id, best_name)
		accept_event()

func _process(delta: float) -> void:
	_redraw_elapsed += delta
	if _redraw_elapsed >= 0.12:
		_redraw_elapsed = 0.0
		queue_redraw()

func _map_point(world_x: float, world_z: float, center: Vector2, radius: float) -> Vector2:
	var scale := radius / maxf(world_radius, 1.0)
	return center + Vector2(world_x - player_position.x, world_z - player_position.z) * scale * Vector2(1.0, -1.0)

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color("#0a1420", 0.96), true)
	draw_rect(bounds, Color("#425466"), false, 1.4)
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.40
	for step in range(-2, 3):
		var offset := float(step) * radius * 0.5
		draw_line(Vector2(center.x + offset, center.y - radius), Vector2(center.x + offset, center.y + radius), Color("#27394a", 0.75), 1.0)
		draw_line(Vector2(center.x - radius, center.y + offset), Vector2(center.x + radius, center.y + offset), Color("#27394a", 0.75), 1.0)
	draw_arc(center, radius, 0.0, TAU, 48, Color("#526a7c", 0.9), 1.2, true)
	draw_line(Vector2(center.x, center.y - radius), Vector2(center.x, center.y + radius), Color("#354b5c", 0.65), 1.0)
	draw_line(Vector2(center.x - radius, center.y), Vector2(center.x + radius, center.y), Color("#354b5c", 0.65), 1.0)
	for exploration_item in exploration_points:
		if not exploration_item is Dictionary:
			continue
		var point: Dictionary = exploration_item
		var exploration_pos := _map_point(float(point.get("position_x", 0.0)), float(point.get("position_z", 0.0)), center, radius)
		if not Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(exploration_pos):
			continue
		var discovered := bool(point.get("discovered", false))
		draw_circle(exploration_pos, 3.0, Color("#8b9aa7") if discovered else Color("#e4b967"))
		if str(navigation_target.get("id", "")) == str(point.get("id", "")) and navigation_target.get("kind", "") == "exploration":
			draw_arc(exploration_pos, 7.0, 0.0, TAU, 24, Color("#f4d27f"), 1.8)
	for npc_item in npc_points:
		if not npc_item is Dictionary:
			continue
		var npc: Dictionary = npc_item
		var npc_pos := _map_point(float(npc.get("position_x", 0.0)), float(npc.get("position_z", 0.0)), center, radius)
		if Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(npc_pos):
			draw_circle(npc_pos, 3.5, Color("#63d6c5"))
			if str(navigation_target.get("id", "")) == str(npc.get("id", "")) and navigation_target.get("kind", "") == "npc":
				draw_arc(npc_pos, 7.0, 0.0, TAU, 24, Color("#f4d27f"), 1.8)
	for monster_item in monster_points:
		if not monster_item is Dictionary:
			continue
		var monster: Dictionary = monster_item
		var monster_pos := _map_point(float(monster.get("x", 0.0)), float(monster.get("z", 0.0)), center, radius)
		if Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(monster_pos):
			draw_circle(monster_pos, 3.0, Color("#e16c6c"))
			if str(navigation_target.get("id", "")) == str(monster.get("id", "")) and navigation_target.get("kind", "") == "monster":
				draw_arc(monster_pos, 7.0, 0.0, TAU, 24, Color("#f4d27f"), 1.8)
	if not navigation_target.is_empty():
		var target_point := _map_point(float(navigation_target.get("x", 0.0)), float(navigation_target.get("z", 0.0)), center, radius)
		if Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(target_point):
			draw_line(center, target_point, Color("#f4d27f", 0.8), 1.4)
	var player_triangle := PackedVector2Array([
		center + Vector2(0.0, -8.0).rotated(-player_yaw),
		center + Vector2(-6.0, 6.0).rotated(-player_yaw),
		center + Vector2(6.0, 6.0).rotated(-player_yaw)
	])
	draw_colored_polygon(player_triangle, Color("#f2e8d6"))
	draw_string(ThemeDB.fallback_font, Vector2(5.0, 13.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("#a9bac7"))
