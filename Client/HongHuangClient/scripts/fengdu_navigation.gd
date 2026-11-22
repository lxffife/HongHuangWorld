extends RefCounted
## Deterministic city-road routing over FengduWorldLayout's stable graph.
## This is a logical planner; NavigationAgent3D remains responsible for physical movement.


static func find_nearest_node(network: Dictionary, world_position: Vector3, allowed_kinds: Array = []) -> Dictionary:
	var best_node: Dictionary = {}
	var best_distance := INF
	for node in network.get("nodes", []):
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


static func find_path(network: Dictionary, start_node_id: String, goal_node_id: String) -> Dictionary:
	var nodes_by_id: Dictionary = {}
	for node in network.get("nodes", []):
		var node_id := str(node.get("id", ""))
		if node_id != "":
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
			var candidate_total := current_distance + edge_length * width_penalty
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


static func find_path_from_position(network: Dictionary, origin: Vector3, goal_node_id: String) -> Dictionary:
	var nearest := find_nearest_node(network, origin)
	if not bool(nearest.get("found", false)):
		return _failed_path("no_navigation_nodes")
	var result := find_path(network, str(nearest["node_id"]), goal_node_id)
	result["origin_node_id"] = str(nearest["node_id"])
	result["origin_connector_distance"] = float(nearest["distance"])
	return result


static func find_path_to_district(network: Dictionary, origin: Vector3, district_id: String, entrances: Array) -> Dictionary:
	for entrance in entrances:
		if str(entrance.get("district_id", "")) != district_id:
			continue
		var goal_node_id := str(entrance.get("navigation_node_id", ""))
		var result := find_path_from_position(network, origin, goal_node_id)
		result["destination_district_id"] = district_id
		result["destination_entry_id"] = str(entrance.get("id", ""))
		result["destination_service"] = str(entrance.get("service", ""))
		return result
	return _failed_path("unknown_district")


static func _failed_path(reason: String) -> Dictionary:
	return {"found": false, "reason": reason, "node_ids": [], "points": [], "distance": INF}
