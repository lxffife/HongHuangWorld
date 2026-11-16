extends Node

func _ready() -> void:
	print("HongHuangClient bootstrap ready")

func _start_world_connection(host: String, port: int, ticket: String) -> void:
	if world_network != null and is_instance_valid(world_network):
		world_network.close()
		world_network.queue_free()
	world_network = HHWorldNetwork.new()
	add_child(world_network)
	world_network.welcomed.connect(_on_world_welcomed)
	world_network.rejected.connect(func(reason: String): _set_status("进入世界失败：" + reason))
	world_network.connection_error.connect(func(message: String): _set_status(message))
	world_network.disconnected.connect(func(): _set_status("与世界服务器的连接已断开。"))
	var error := world_network.connect_with_ticket(host, port, ticket)
	if error != OK:
		_set_status("世界网络连接初始化失败，错误码：" + str(error))

func _on_world_welcomed(snapshot: Dictionary) -> void:
	_set_status("世界服务器验证成功！\\n角色：" + str(snapshot.get("name", "")) +
		"\\n世界：" + str(snapshot.get("world_id", "")) +
		"\\n角色 ID：" + str(snapshot.get("character_id", "")) +
		"\\n初始位置：" + str(snapshot.get("position_x", 0.0)) + ", " +
		str(snapshot.get("position_y", 0.0)) + ", " + str(snapshot.get("position_z", 0.0)) +
		"\\n\\n网络握手已完成；游戏场景、移动同步和 AOI 尚在开发。")
