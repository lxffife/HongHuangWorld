extends RefCounted
## Deterministic city-road routing over FengduWorldLayout's stable graph.
## This is a logical planner; NavigationAgent3D remains responsible for physical movement.


static func validate_network(network: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var node_ids: Dictionary = {}
	for node in network.get("nodes", []):
		var node_id := str(node.get("id", ""))
		if node_id == "":
			errors.append("node_missing_id")
		elif node_ids.has(node_id):
			errors.append("duplicate_node:" + node_id)
		else:
			node_ids[node_id] = true
	var edge_ids: Dictionary = {}
	for edge in network.get("edges", []):
		var edge_id := str(edge.get("id", ""))
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if edge_id == "":
			errors.append("edge_missing_id")
		elif edge_ids.has(edge_id):
			errors.append("duplicate_edge:" + edge_id)
		else:
			edge_ids[edge_id] = true
		if not node_ids.has(from_id) or not node_ids.has(to_id):
			errors.append("edge_endpoint_missing:" + edge_id)
		if from_id == to_id:
			errors.append("self_loop:" + edge_id)
	for route in network.get("routes", []):
		var waypoints: Array = route.get("waypoints", [])
		for index in range(maxi(waypoints.size() - 1, 0)):
			var from_id := str(waypoints[index])
			var to_id := str(waypoints[index + 1])
			var connected := false
			for edge in network.get("edges", []):
				if str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id:
					connected = true
					break
				if bool(edge.get("two_way", false)) and str(edge.get("from", "")) == to_id and str(edge.get("to", "")) == from_id:
					connected = true
					break
			if not node_ids.has(from_id) or not node_ids.has(to_id) or not connected:
				errors.append("route_segment_disconnected:" + str(route.get("id", "unknown")))
	return {
		"valid": errors.is_empty(),
		"node_count": node_ids.size(),
		"edge_count": edge_ids.size(),
		"route_count": network.get("routes", []).size(),
		"errors": errors
	}


static func find_nearest_node(network: Dictionary, world_position: Vector3, allowed_kinds: Array = []) -> Dictionary:
	var best_node: Dictionary = {}
	var best_distance := INF
	for node in network.get("nodes", []):
		if not bool(node.get("enabled", true)):
			continue
		if not allowed_kinds.is_empty() and str(node.get("kind", "")) not in allowed_kinds:
			continue
		var node_position: Vector3 = node.get("position", Vector3.ZERO)
		var distance := world_position.distance_to(node_position)
		if distance < best_distance:
			best_distance = distance
			best_node = node
	if best_node.is_empty():
		return {"found": false, "node_id": "", "distance": INF}
	return {"found": true, "node_id": str(best_node.get("id", "")), "distance": best_distance}


static func build_city_network(city_plan: Dictionary) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var node_kinds: Dictionary = {}
	for entry_variant in city_plan.get("nodes", []):
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant
		var node_id := str(entry.get("id", ""))
		var position_data: Array = entry.get("position", [])
		if node_id.is_empty() or position_data.size() < 2:
			continue
		var world_position := Vector3(float(position_data[0]) * 0.12, 0.0, -float(position_data[1]) * 0.12 - 60.0)
		var kind := str(entry.get("kind", "district"))
		node_kinds[node_id] = kind
		nodes.append({"id": node_id, "name": str(entry.get("name", node_id)), "kind": kind, "position": world_position, "enabled": true})

	var edges: Array[Dictionary] = []
	var edge_index := 0
	for road_variant in city_plan.get("roads", []):
		if not road_variant is Dictionary:
			continue
		var road: Dictionary = road_variant
		var from_id := str(road.get("from", ""))
		var to_id := str(road.get("to", ""))
		if not node_kinds.has(from_id) or not node_kinds.has(to_id):
			continue
		var is_gate := str(node_kinds[from_id]) == "gate" or str(node_kinds[to_id]) == "gate"
		var edge: Dictionary = {
			"id": "city_road_%02d" % edge_index,
			"from": from_id,
			"to": to_id,
			"two_way": true,
			"width": 12.0 if is_gate else 8.0,
			"kind": "gate" if is_gate else "road",
			"enabled": true
		}
		if is_gate:
			edge["gate_id"] = from_id if str(node_kinds[from_id]) == "gate" else to_id
		edges.append(edge)
		edge_index += 1
	return {"nodes": nodes, "edges": edges, "routes": []}


static func find_path(network: Dictionary, start_node_id: String, goal_node_id: String, options: Dictionary = {}) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	for node in network.get("nodes", []):
		var node_id := str(node.get("id", ""))
		if node_id != "" and bool(node.get("enabled", true)):
			nodes_by_id[node_id] = node
	if not nodes_by_id.has(start_node_id) or not nodes_by_id.has(goal_node_id):
		return _failed_path("unknown_node")
	if start_node_id == goal_node_id:
		var same_node: Dictionary = nodes_by_id[start_node_id]
		return {"found": true, "reason": "", "node_ids": [start_node_id], "points": [same_node.get("position", Vector3.ZERO)], "distance": 0.0}

	var distances: Dictionary = {}
	var previous: Dictionary = {}
	var unvisited: Dictionary = {}
	for node_id in nodes_by_id.keys():
		distances[node_id] = INF
		unvisited[node_id] = true
	distances[start_node_id] = 0.0

	while not unvisited.is_empty():
		var current_id := ""
		var current_distance := INF
		for candidate_id in unvisited.keys():
			var candidate_distance := float(distances.get(candidate_id, INF))
			if candidate_distance < current_distance:
				current_distance = candidate_distance
				current_id = str(candidate_id)
		if current_id == "" or current_distance == INF:
			break
		if current_id == goal_node_id:
			break
		unvisited.erase(current_id)
		var current_node: Dictionary = nodes_by_id[current_id]
		var current_position: Vector3 = current_node.get("position", Vector3.ZERO)
		for edge in network.get("edges", []):
			if not _edge_is_traversable(edge, options):
				continue
			var from_id := str(edge.get("from", ""))
			var to_id := str(edge.get("to", ""))
			var neighbor_id := ""
			if from_id == current_id:
				neighbor_id = to_id
			elif bool(edge.get("two_way", false)) and to_id == current_id:
				neighbor_id = from_id
			if neighbor_id == "" or not unvisited.has(neighbor_id) or not nodes_by_id.has(neighbor_id):
				continue
			var neighbor_node: Dictionary = nodes_by_id[neighbor_id]
			var neighbor_position: Vector3 = neighbor_node.get("position", Vector3.ZERO)
			var edge_length := current_position.distance_to(neighbor_position)
			var width := maxf(float(edge.get("width", 1.0)), 1.0)
			var width_penalty := 1.0 + (4.0 / width) * 0.08
			var edge_cost := maxf(float(edge.get("cost_multiplier", 1.0)), 0.1)
			var candidate_total := current_distance + edge_length * width_penalty * edge_cost
			if candidate_total < float(distances.get(neighbor_id, INF)):
				distances[neighbor_id] = candidate_total
				previous[neighbor_id] = current_id
		unvisited.erase(current_id)

	if not previous.has(goal_node_id):
		return _failed_path("unreachable")
	var reversed_ids: Array[String] = [goal_node_id]
	var cursor := goal_node_id
	while cursor != start_node_id:
		if not previous.has(cursor):
			return _failed_path("broken_predecessor_chain")
		cursor = str(previous[cursor])
		reversed_ids.append(cursor)
	reversed_ids.reverse()
	var points: Array[Vector3] = []
	for node_id in reversed_ids:
		var node: Dictionary = nodes_by_id[node_id]
		points.append(node.get("position", Vector3.ZERO))
	return {
		"found": true,
		"reason": "",
		"node_ids": reversed_ids,
		"points": points,
		"distance": float(distances[goal_node_id])
	}


static func find_path_from_position(network: Dictionary, origin: Vector3, goal_node_id: String, options: Dictionary = {}) -> Dictionary:
	var nearest := find_nearest_node(network, origin)
	if not bool(nearest.get("found", false)):
		return _failed_path("no_navigation_nodes")
	var result := find_path(network, str(nearest["node_id"]), goal_node_id, options)
	result["origin_node_id"] = str(nearest["node_id"])
	result["origin_connector_distance"] = float(nearest["distance"])
	return result


static func find_path_to_district(network: Dictionary, origin: Vector3, district_id: String, entrances: Array, options: Dictionary = {}) -> Dictionary:
	for entrance in entrances:
		if str(entrance.get("district_id", "")) != district_id:
			continue
		var goal_node_id := str(entrance.get("navigation_node_id", ""))
		var result := find_path_from_position(network, origin, goal_node_id, options)
		result["destination_district_id"] = district_id
		result["destination_entry_id"] = str(entrance.get("id", ""))
		result["destination_service"] = str(entrance.get("service", ""))
		return result
	return _failed_path("unknown_district")


static func _edge_is_traversable(edge: Dictionary, options: Dictionary) -> bool:
	if not bool(edge.get("enabled", true)):
		return false
	var blocked_edges: Array = options.get("blocked_edge_ids", [])
	if str(edge.get("id", "")) in blocked_edges:
		return false
	var gate_id := str(edge.get("gate_id", ""))
	var closed_gates: Array = options.get("closed_gates", [])
	if not gate_id.is_empty() and gate_id in closed_gates:
		return false
	var required_access := str(edge.get("required_access", ""))
	if not required_access.is_empty():
		var access_tags: Array = options.get("access_tags", [])
		if required_access not in access_tags:
			return false
	var minimum_width := float(options.get("minimum_width", 0.0))
	if float(edge.get("width", INF)) < minimum_width:
		return false
	return true


static func _failed_path(reason: String) -> Dictionary:
	return {"found": false, "reason": reason, "node_ids": [], "points": [], "distance": INF}
