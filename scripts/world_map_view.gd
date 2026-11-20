extends Control

const WorldMapProjection = preload("res://scripts/world_map_projection.gd")

## Full-world map canvas. All coordinates are world X/Z meters and use the shared projection.

signal marker_selected(kind: String, marker_id: String, marker_name: String)
signal world_position_selected(world_position: Vector3)
signal atlas_region_selected(region_id: String, region_name: String, description: String)
signal city_district_selected(district_id: String, district_name: String, description: String)

var world_id := ""
var map_mode := "local"
var atlas_data: Dictionary = {}
var city_data: Dictionary = {}
var _selected_city_id := ""
var _selected_atlas_id := ""
var world_bounds := Vector4(-120.0, 120.0, -120.0, 120.0)
var region_data: Array = []
var water_data: Array = []
var landmark_data: Array = []
var exploration_points: Array = []
var npc_points: Array = []
var monster_points: Array = []
var player_position := Vector3.ZERO
var navigation_target: Dictionary = {}

var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _drag_origin := Vector2.ZERO
var _pan_origin := Vector2.ZERO
var _left_press_origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom = clampf(_zoom * 1.15, 0.65, 3.5)
			queue_redraw()
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom = clampf(_zoom / 1.15, 0.65, 3.5)
			queue_redraw()
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT or mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			if mouse_event.pressed:
				_dragging = true
				_drag_origin = mouse_event.position
				_pan_origin = _pan
			else:
				_dragging = false
			accept_event()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_left_press_origin = mouse_event.position
			elif mouse_event.position.distance_to(_left_press_origin) <= 6.0:
				_select_at(mouse_event.position)
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_pan = _pan_origin + motion.position - _drag_origin
		queue_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0b1420"), true)
	if map_mode == "underworld_atlas":
		_draw_underworld_atlas()
		return
	if map_mode == "fengdu_city":
		_draw_fengdu_city_plan()
		return
	var map_rect := _map_rect()
	if map_rect.size.x <= 0.0 or map_rect.size.y <= 0.0:
		return
	draw_rect(map_rect, Color("#101e2a"), true)
	var scale := _pixels_per_meter(map_rect)
	var map_center := map_rect.get_center() + _pan
	var top_left := _world_to_canvas(Vector2(world_bounds.x, world_bounds.w), map_center, scale)
	var bottom_right := _world_to_canvas(Vector2(world_bounds.y, world_bounds.z), map_center, scale)
	var bounds_rect := Rect2(top_left, bottom_right - top_left).abs()
	draw_rect(bounds_rect, Color("#34485a"), true)
	_draw_grid(bounds_rect, map_center, scale)
	_draw_regions(map_center, scale, map_rect)
	_draw_water(map_center, scale, map_rect)
	_draw_landmarks(map_center, scale, map_rect)
	_draw_live_markers(map_center, scale, map_rect)
	_draw_navigation(map_center, scale, map_rect)
	_draw_player(map_center, scale, map_rect)
	draw_rect(map_rect, Color("#62788b"), false, 1.4)
	draw_string(ThemeDB.fallback_font, Vector2(14.0, 20.0), _world_title(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#e0c58f"))
	draw_string(ThemeDB.fallback_font, Vector2(14.0, size.y - 10.0), "滚轮缩放 · 右键/中键拖动 · 点击地图设定导航", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color("#91a5b6"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 14.0, 20.0), "比例 %.2fx" % _zoom, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 11, Color("#91a5b6"))


func _draw_underworld_atlas() -> void:
	var map_rect := _map_rect()
	draw_rect(map_rect, Color("#101a26"), true)
	draw_rect(map_rect, Color("#62788b"), false, 1.4)
	draw_string(ThemeDB.fallback_font, Vector2(14.0, 20.0), "冥界总览 · 示意地理关系（非实际坐标比例）", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#e0c58f"))
	var nodes: Array = atlas_data.get("nodes", [])
	var links: Array = atlas_data.get("links", [])
	for link_variant in links:
		if not link_variant is Dictionary:
			continue
		var link: Dictionary = link_variant
		var from_node := _find_atlas_node(nodes, str(link.get("from", "")))
		var to_node := _find_atlas_node(nodes, str(link.get("to", "")))
		if from_node.is_empty() or to_node.is_empty():
			continue
		var from_point := _atlas_to_canvas(from_node.get("position", []), map_rect)
		var to_point := _atlas_to_canvas(to_node.get("position", []), map_rect)
		draw_line(from_point, to_point, Color("#718294", 0.58), 2.0)
		var mid := (from_point + to_point) * 0.5
		draw_string(ThemeDB.fallback_font, mid + Vector2(4.0, -4.0), str(link.get("label", "")), HORIZONTAL_ALIGNMENT_LEFT, 130.0, 9, Color("#91a5b6"))
	for node_variant in nodes:
		if not node_variant is Dictionary:
			continue
		var node: Dictionary = node_variant
		var position_data: Array = node.get("position", [])
		var size_data: Array = node.get("size", [])
		if position_data.size() < 2 or size_data.size() < 2:
			continue
		var center := _atlas_to_canvas(position_data, map_rect)
		var scale := _atlas_scale(map_rect)
		var rect_size := Vector2(float(size_data[0]), float(size_data[1])) * scale
		var node_rect := Rect2(center - rect_size * 0.5, rect_size)
		if node_rect.size.x < 4.0 or node_rect.size.y < 4.0:
			continue
		var kind := str(node.get("kind", "region"))
		var fill := _atlas_kind_color(kind)
		draw_rect(node_rect, fill, true)
		draw_rect(node_rect, Color("#f0d7a0") if str(node.get("id", "")) == _selected_atlas_id else fill.lightened(0.55), false, 2.2 if str(node.get("id", "")) == _selected_atlas_id else 1.2)
		var title_size := 12 if node_rect.size.x >= 100.0 else 10
		var title_y := node_rect.position.y + minf(19.0, node_rect.size.y * 0.42)
		draw_string(ThemeDB.fallback_font, Vector2(node_rect.position.x + 7.0, title_y), str(node.get("name", "区域")), HORIZONTAL_ALIGNMENT_LEFT, maxf(30.0, node_rect.size.x - 12.0), title_size, Color("#f1e7d6"))
		if node_rect.size.y >= 34.0:
			draw_string(ThemeDB.fallback_font, Vector2(node_rect.position.x + 7.0, title_y + 15.0), str(node.get("distance", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(30.0, node_rect.size.x - 12.0), 9, Color("#c1cbd4"))
	draw_string(ThemeDB.fallback_font, Vector2(14.0, size.y - 10.0), "点击区域查看设定 · 滚轮缩放 · 右键/中键拖动 · 示意连线不代表可直接通行", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("#91a5b6"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 14.0, 20.0), "比例 %.2fx" % _zoom, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 11, Color("#91a5b6"))


func _draw_fengdu_city_plan() -> void:
	var map_rect := _map_rect()
	draw_rect(map_rect, Color("#171b20"), true)
	draw_rect(map_rect, Color("#62788b"), false, 1.4)
	draw_string(ThemeDB.fallback_font, Vector2(14.0, 20.0), "酆都天城 · 城区规划示意（非实际比例）", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, Color("#e0c58f"))
	var center := map_rect.get_center() + _pan
	var scale := _city_scale(map_rect)
	var moat_size: Array = city_data.get("moat_size", [820.0, 650.0])
	var wall_size: Array = city_data.get("wall_size", [760.0, 590.0])
	var moat_extent := Vector2(float(moat_size[0]), float(moat_size[1])) * scale
	var wall_extent := Vector2(float(wall_size[0]), float(wall_size[1])) * scale
	var moat_rect := Rect2(center - moat_extent * 0.5, moat_extent)
	var wall_rect := Rect2(center - wall_extent * 0.5, wall_extent)
	draw_rect(moat_rect, Color("#28505b"), false, 9.0)
	draw_rect(wall_rect, Color("#9b8664"), false, 7.0)
	var inner_extent := wall_extent * 0.72
	draw_rect(Rect2(center - inner_extent * 0.5, inner_extent), Color("#8d795d", 0.48), false, 1.5)
	var north := center + Vector2(0.0, -wall_extent.y * 0.5)
	var south := center + Vector2(0.0, wall_extent.y * 0.5)
	var west := center + Vector2(-wall_extent.x * 0.5, 0.0)
	var east := center + Vector2(wall_extent.x * 0.5, 0.0)
	draw_line(north, south, Color("#8e806b", 0.34), 7.0)
	draw_line(west, east, Color("#8e806b", 0.34), 7.0)
	var nodes: Array = city_data.get("nodes", [])
	for road_variant in city_data.get("roads", []):
		if not road_variant is Dictionary:
			continue
		var road: Dictionary = road_variant
		var from_node := _find_atlas_node(nodes, str(road.get("from", "")))
		var to_node := _find_atlas_node(nodes, str(road.get("to", "")))
		if from_node.is_empty() or to_node.is_empty():
			continue
		draw_line(_city_to_canvas(from_node.get("position", []), map_rect), _city_to_canvas(to_node.get("position", []), map_rect), Color("#b39a70", 0.55), maxf(2.0, 5.0 * scale))
	for node_variant in nodes:
		if not node_variant is Dictionary:
			continue
		var node: Dictionary = node_variant
		var node_rect := _city_node_rect(node, map_rect)
		if node_rect.size.x < 5.0 or node_rect.size.y < 5.0:
			continue
		var fill := _city_kind_color(str(node.get("kind", "district")))
		draw_rect(node_rect, fill, true)
		var selected := str(node.get("id", "")) == _selected_city_id
		draw_rect(node_rect, Color("#f4d69a") if selected else fill.lightened(0.48), false, 2.4 if selected else 1.0)
		var title_y := node_rect.position.y + minf(17.0, node_rect.size.y * 0.52)
		draw_string(ThemeDB.fallback_font, Vector2(node_rect.position.x + 4.0, title_y), str(node.get("name", "城区")), HORIZONTAL_ALIGNMENT_CENTER, maxf(18.0, node_rect.size.x - 8.0), 10 if node_rect.size.x > 58.0 else 8, Color("#f4ead9"))
	draw_string(ThemeDB.fallback_font, Vector2(14.0, size.y - 10.0), "护城河 · 城墙 · 四方城门 · 九大功能区 · 点击城区查看职责 · 滚轮缩放 / 右键拖动", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Color("#b0bdc6"))
	draw_string(ThemeDB.fallback_font, Vector2(size.x - 14.0, 20.0), "比例 %.2fx" % _zoom, HORIZONTAL_ALIGNMENT_RIGHT, -1.0, 11, Color("#91a5b6"))


func _city_scale(map_rect: Rect2) -> float:
	return minf(map_rect.size.x / 900.0, map_rect.size.y / 740.0) * _zoom


func _city_to_canvas(position_data: Array, map_rect: Rect2) -> Vector2:
	if position_data.size() < 2:
		return map_rect.get_center() + _pan
	return map_rect.get_center() + _pan + Vector2(float(position_data[0]), -float(position_data[1])) * _city_scale(map_rect)


func _city_node_rect(node: Dictionary, map_rect: Rect2) -> Rect2:
	var position_data: Array = node.get("position", [])
	var size_data: Array = node.get("size", [])
	if position_data.size() < 2 or size_data.size() < 2:
		return Rect2()
	var extent := Vector2(float(size_data[0]), float(size_data[1])) * _city_scale(map_rect)
	return Rect2(_city_to_canvas(position_data, map_rect) - extent * 0.5, extent)


func _city_kind_color(kind: String) -> Color:
	match kind:
		"palace":
			return Color("#80633d")
		"court":
			return Color("#665044")
		"admin":
			return Color("#455d72")
		"sacred":
			return Color("#67558b")
		"market":
			return Color("#79613c")
		"residential":
			return Color("#52674f")
		"military":
			return Color("#74434a")
		"transport":
			return Color("#3f6870")
		"gate":
			return Color("#766c5c")
		_:
			return Color("#46596b")


func _select_fengdu_city_at(mouse_position: Vector2) -> void:
	var map_rect := _map_rect()
	for node_variant in city_data.get("nodes", []):
		if not node_variant is Dictionary:
			continue
		var node: Dictionary = node_variant
		if _city_node_rect(node, map_rect).has_point(mouse_position):
			_selected_city_id = str(node.get("id", ""))
			var details := "职能：" + str(node.get("authority", "城市管理"))
			details += " · 危险 " + str(node.get("danger_level", 0)) + "/10"
			details += "\n" + str(node.get("access", ""))
			details += "\n" + str(node.get("description", ""))
			city_district_selected.emit(_selected_city_id, str(node.get("name", "城区")), details)
			queue_redraw()
			return


func _atlas_scale(map_rect: Rect2) -> float:
	return minf(map_rect.size.x / 420.0, map_rect.size.y / 390.0) * _zoom


func _atlas_to_canvas(position_data: Array, map_rect: Rect2) -> Vector2:
	if position_data.size() < 2:
		return map_rect.get_center()
	var scale := _atlas_scale(map_rect)
	return map_rect.get_center() + _pan + Vector2(float(position_data[0]), float(position_data[1])) * Vector2(scale, -scale)


func _atlas_node_rect(node: Dictionary, map_rect: Rect2) -> Rect2:
	var position_data: Array = node.get("position", [])
	var size_data: Array = node.get("size", [])
	if position_data.size() < 2 or size_data.size() < 2:
		return Rect2()
	var center := _atlas_to_canvas(position_data, map_rect)
	var extent := Vector2(float(size_data[0]), float(size_data[1])) * _atlas_scale(map_rect)
	return Rect2(center - extent * 0.5, extent)


func _find_atlas_node(nodes: Array, node_id: String) -> Dictionary:
	for node_variant in nodes:
		if node_variant is Dictionary and str(node_variant.get("id", "")) == node_id:
			return node_variant
	return {}


func _atlas_kind_color(kind: String) -> Color:
	match kind:
		"capital":
			return Color("#6f5540", 0.96)
		"river":
			return Color("#355d78", 0.94)
		"sacred", "divine":
			return Color("#67558b", 0.96)
		"hell":
			return Color("#873e3c", 0.96)
		"blood_sea":
			return Color("#842c43", 0.97)
		"wilderness":
			return Color("#53634d", 0.94)
		_:
			return Color("#46596b", 0.94)


func _select_underworld_atlas_at(mouse_position: Vector2) -> void:
	var map_rect := _map_rect()
	for node_variant in atlas_data.get("nodes", []):
		if not node_variant is Dictionary:
			continue
		var node: Dictionary = node_variant
		if _atlas_node_rect(node, map_rect).has_point(mouse_position):
			_selected_atlas_id = str(node.get("id", ""))
			var details := "权柄：" + str(node.get("authority", "未知")) + " · " + str(node.get("distance", ""))
			details += " · 危险 " + str(node.get("danger_level", 0)) + "/10"
			details += "\n" + str(node.get("access", ""))
			details += "\n" + str(node.get("description", ""))
			atlas_region_selected.emit(
				_selected_atlas_id,
				str(node.get("name", "区域")),
				details
			)
			queue_redraw()
			return


func _map_rect() -> Rect2:
	return Rect2(Vector2(12.0, 30.0), Vector2(maxf(1.0, size.x - 24.0), maxf(1.0, size.y - 58.0)))


func _pixels_per_meter(map_rect: Rect2) -> float:
	var width_m := maxf(1.0, world_bounds.y - world_bounds.x)
	var depth_m := maxf(1.0, world_bounds.w - world_bounds.z)
	return minf(map_rect.size.x / width_m, map_rect.size.y / depth_m) * _zoom


func _world_to_canvas(world_xz: Vector2, map_center: Vector2, scale: float) -> Vector2:
	return WorldMapProjection.world_to_map(
		Vector3(world_xz.x, 0.0, world_xz.y),
		Vector3.ZERO,
		map_center,
		Vector2(scale, scale)
	)


func _draw_grid(bounds_rect: Rect2, map_center: Vector2, scale: float) -> void:
	var step := 20.0
	if _zoom >= 2.0:
		step = 10.0
	for x in range(int(ceil(world_bounds.x / step)), int(floor(world_bounds.y / step)) + 1):
		var px := _world_to_canvas(Vector2(float(x) * step, 0.0), map_center, scale).x
		draw_line(Vector2(px, bounds_rect.position.y), Vector2(px, bounds_rect.end.y), Color("#26394a", 0.55), 1.0)
	for z in range(int(ceil(world_bounds.z / step)), int(floor(world_bounds.w / step)) + 1):
		var py := _world_to_canvas(Vector2(0.0, float(z) * step), map_center, scale).y
		draw_line(Vector2(bounds_rect.position.x, py), Vector2(bounds_rect.end.x, py), Color("#26394a", 0.55), 1.0)


func _draw_regions(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	var palette := [Color("#476c78", 0.24), Color("#80694b", 0.22), Color("#65577c", 0.24), Color("#52765b", 0.22)]
	for index in range(region_data.size()):
		var region_variant: Variant = region_data[index]
		if not region_variant is Dictionary:
			continue
		var region: Dictionary = region_variant
		var bounds_list: Array = region.get("bounds", [])
		for bounds_variant in bounds_list:
			if not bounds_variant is Array or bounds_variant.size() < 4:
				continue
			var bounds: Array = bounds_variant
			var a := _world_to_canvas(Vector2(float(bounds[0]), float(bounds[3])), map_center, scale)
			var b := _world_to_canvas(Vector2(float(bounds[1]), float(bounds[2])), map_center, scale)
			var area := Rect2(a, b - a).abs().intersection(clip_rect)
			if area.size.x < 2.0 or area.size.y < 2.0:
				continue
			draw_rect(area, palette[index % palette.size()], true)
			draw_rect(area, Color("#8ca3b3", 0.32), false, 1.0)
			if area.size.x > 52.0 and area.size.y > 20.0:
				draw_string(ThemeDB.fallback_font, area.position + Vector2(5.0, 15.0), str(region.get("name", "区域")), HORIZONTAL_ALIGNMENT_LEFT, maxf(40.0, area.size.x - 8.0), 10, Color("#b6c4ce", 0.9))


func _draw_water(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	for water_variant in water_data:
		if not water_variant is Dictionary:
			continue
		var water: Dictionary = water_variant
		var center_data: Array = water.get("center", [])
		var size_data: Array = water.get("size", [])
		if center_data.size() < 2 or size_data.size() < 2:
			continue
		var center := Vector2(float(center_data[0]), float(center_data[1]))
		var half_size := Vector2(float(size_data[0]), float(size_data[1])) * 0.5
		var a := _world_to_canvas(center - half_size, map_center, scale)
		var b := _world_to_canvas(center + half_size, map_center, scale)
		var area := Rect2(a, b - a).abs().intersection(clip_rect)
		if area.size.x < 1.0 or area.size.y < 1.0:
			continue
		var tint := Color("#5b7797", 0.64) if str(water.get("id", "")) == "forgotten_river" else Color("#8d354d", 0.72)
		draw_rect(area, tint, true)
		draw_rect(area, tint.lightened(0.22), false, 1.0)


func _draw_landmarks(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	for landmark_variant in landmark_data:
		if not landmark_variant is Dictionary:
			continue
		var landmark: Dictionary = landmark_variant
		var pos_data: Array = landmark.get("position", [])
		if pos_data.size() < 3:
			continue
		var point := _world_to_canvas(Vector2(float(pos_data[0]), float(pos_data[2])), map_center, scale)
		if not clip_rect.has_point(point):
			continue
		var color := Color(str(landmark.get("color", "#c5a7ed")))
		var diamond := PackedVector2Array([point + Vector2(0.0, -6.0), point + Vector2(6.0, 0.0), point + Vector2(0.0, 6.0), point + Vector2(-6.0, 0.0)])
		draw_colored_polygon(diamond, color)
		draw_string(ThemeDB.fallback_font, point + Vector2(9.0, -5.0), str(landmark.get("name", "地标")), HORIZONTAL_ALIGNMENT_LEFT, 150.0, 11, Color("#e2e8ed"))


func _draw_live_markers(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	for point_variant in exploration_points:
		if not point_variant is Dictionary:
			continue
		var point: Dictionary = point_variant
		var world_point := Vector2(float(point.get("position_x", 0.0)), float(point.get("position_z", 0.0)))
		var canvas_point := _world_to_canvas(world_point, map_center, scale)
		if not clip_rect.has_point(canvas_point):
			continue
		# Do not reveal undiscovered POI positions on the world map.
		# The server remains authoritative for discovery; this is presentation-only fog.
		if not bool(point.get("discovered", false)):
			continue
		draw_circle(canvas_point, 4.5, Color("#91a0ad"))
		var danger := int(point.get("danger_level", 0))
		if danger >= 7:
			draw_arc(canvas_point, 8.0, 0.0, TAU, 20, Color("#e16c6c", 0.9), 1.5)
	for npc_variant in npc_points:
		if not npc_variant is Dictionary:
			continue
		var npc: Dictionary = npc_variant
		var npc_point := _world_to_canvas(Vector2(float(npc.get("position_x", 0.0)), float(npc.get("position_z", 0.0))), map_center, scale)
		if clip_rect.has_point(npc_point):
			draw_circle(npc_point, 4.0, Color("#63d6c5"))
	for monster_variant in monster_points:
		if not monster_variant is Dictionary:
			continue
		var monster: Dictionary = monster_variant
		var monster_point := _world_to_canvas(Vector2(float(monster.get("x", 0.0)), float(monster.get("z", 0.0))), map_center, scale)
		if clip_rect.has_point(monster_point):
			draw_colored_polygon(PackedVector2Array([monster_point + Vector2(0.0, -5.0), monster_point + Vector2(5.0, 4.0), monster_point + Vector2(-5.0, 4.0)]), Color("#e16c6c"))


func _draw_navigation(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	if navigation_target.is_empty():
		return
	var target := _world_to_canvas(Vector2(float(navigation_target.get("x", 0.0)), float(navigation_target.get("z", 0.0))), map_center, scale)
	var player := _world_to_canvas(Vector2(player_position.x, player_position.z), map_center, scale)
	if clip_rect.has_point(player) and clip_rect.has_point(target):
		draw_line(player, target, Color("#f4d27f", 0.72), 2.0)
	if clip_rect.has_point(target):
		draw_circle(target, 8.0, Color("#f4d27f", 0.18))
		draw_arc(target, 9.0, 0.0, TAU, 28, Color("#f4d27f"), 2.0)


func _draw_player(map_center: Vector2, scale: float, clip_rect: Rect2) -> void:
	var point := _world_to_canvas(Vector2(player_position.x, player_position.z), map_center, scale)
	if not clip_rect.has_point(point):
		return
	draw_circle(point, 7.0, Color("#f2e8d6"))
	draw_arc(point, 11.0, 0.0, TAU, 28, Color("#e0c58f"), 1.5)


func _select_at(mouse_position: Vector2) -> void:
	var map_rect := _map_rect()
	if not map_rect.has_point(mouse_position):
		return
	if map_mode == "underworld_atlas":
		_select_underworld_atlas_at(mouse_position)
		return
	if map_mode == "fengdu_city":
		_select_fengdu_city_at(mouse_position)
		return
	var scale := _pixels_per_meter(map_rect)
	var map_center := map_rect.get_center() + _pan
	var best_distance := 14.0
	var best_kind := ""
	var best_id := ""
	var best_name := ""
	for point_variant in exploration_points:
		if not point_variant is Dictionary:
			continue
		var point_data: Dictionary = point_variant
		if not bool(point_data.get("discovered", false)):
			continue
		var exploration_canvas_point := _world_to_canvas(Vector2(float(point_data.get("position_x", 0.0)), float(point_data.get("position_z", 0.0))), map_center, scale)
		var distance := exploration_canvas_point.distance_to(mouse_position)
		if distance < best_distance:
			best_distance = distance
			best_kind = "exploration"
			best_id = str(point_data.get("id", ""))
			best_name = str(point_data.get("name", "探索点"))
			
	for npc_variant in npc_points:
		if not npc_variant is Dictionary:
			continue
		var npc_data: Dictionary = npc_variant
		var npc_point := _world_to_canvas(Vector2(float(npc_data.get("position_x", 0.0)), float(npc_data.get("position_z", 0.0))), map_center, scale)
		var npc_distance := npc_point.distance_to(mouse_position)
		if npc_distance < best_distance:
			best_distance = npc_distance
			best_kind = "npc"
			best_id = str(npc_data.get("id", ""))
			best_name = str(npc_data.get("name", "NPC"))
	for monster_variant in monster_points:
		if not monster_variant is Dictionary:
			continue
		var monster_data: Dictionary = monster_variant
		var monster_point := _world_to_canvas(Vector2(float(monster_data.get("x", 0.0)), float(monster_data.get("z", 0.0))), map_center, scale)
		var monster_distance := monster_point.distance_to(mouse_position)
		if monster_distance < best_distance:
			best_distance = monster_distance
			best_kind = "monster"
			best_id = str(monster_data.get("id", ""))
			best_name = str(monster_data.get("name", "妖兽"))
	for landmark_variant in landmark_data:
		if not landmark_variant is Dictionary:
			continue
		var landmark: Dictionary = landmark_variant
		var pos_data: Array = landmark.get("position", [])
		if pos_data.size() < 3:
			continue
		var landmark_canvas_point := _world_to_canvas(Vector2(float(pos_data[0]), float(pos_data[2])), map_center, scale)
		var distance := landmark_canvas_point.distance_to(mouse_position)
		if distance < best_distance:
			best_distance = distance
			best_kind = "landmark"
			best_id = str(landmark.get("id", ""))
			best_name = str(landmark.get("name", "地标"))
	if not best_id.is_empty():
		marker_selected.emit(best_kind, best_id, best_name)
	else:
		var world := WorldMapProjection.map_to_world(mouse_position, Vector3.ZERO, map_center, Vector2(scale, scale))
		if WorldMapProjection.world_xz_in_bounds(world, world_bounds.x, world_bounds.y, world_bounds.z, world_bounds.w):
			world_position_selected.emit(world)


func _world_title() -> String:
	if map_mode == "underworld_atlas":
		return "冥界总览"
	if map_mode == "fengdu_city":
		return "酆都天城"
	match world_id:
		"underworld_fengdu":
			return "冥界 · 酆都"
		"qingyun_human":
			return "青云界 · 人界"
		"myriad_demon":
			return "万妖界"
		_:
			return "世界地图"
