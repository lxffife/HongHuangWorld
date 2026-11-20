extends Control
## Lightweight live minimap. Coordinates are supplied by the authoritative world
## snapshot/entities; the player remains centered and nearby markers move around it.

var player_position: Vector3 = Vector3.ZERO
var player_yaw: float = 0.0
var world_radius: float = 55.0
var exploration_points: Array = []
var npc_points: Array = []
var monster_points: Array = []
var _redraw_elapsed: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)

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
	for item in exploration_points:
		if not item is Dictionary:
			continue
		var point: Dictionary = item
		var p := _map_point(float(point.get("position_x", 0.0)), float(point.get("position_z", 0.0)), center, radius)
		if not Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(p):
			continue
		var discovered := bool(point.get("discovered", false))
		draw_circle(p, 3.0, Color("#8b9aa7") if discovered else Color("#e4b967"))
	for item in npc_points:
		if not item is Dictionary:
			continue
		var npc: Dictionary = item
		var p := _map_point(float(npc.get("position_x", 0.0)), float(npc.get("position_z", 0.0)), center, radius)
		if Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(p):
			draw_circle(p, 3.5, Color("#63d6c5"))
	for item in monster_points:
		if not item is Dictionary:
			continue
		var monster: Dictionary = item
		var p := _map_point(float(monster.get("x", 0.0)), float(monster.get("z", 0.0)), center, radius)
		if Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)).has_point(p):
			draw_circle(p, 3.0, Color("#e16c6c"))
	var player_triangle := PackedVector2Array([
		center + Vector2(0.0, -8.0).rotated(-player_yaw),
		center + Vector2(-6.0, 6.0).rotated(-player_yaw),
		center + Vector2(6.0, 6.0).rotated(-player_yaw)
	])
	draw_colored_polygon(player_triangle, Color("#f2e8d6"))
	draw_string(ThemeDB.fallback_font, Vector2(5.0, 13.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("#a9bac7"))
