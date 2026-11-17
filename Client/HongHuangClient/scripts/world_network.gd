extends Node
class_name HHWorldNetwork

signal welcomed(snapshot: Dictionary)
signal rejected(reason: String)
signal disconnected
signal connection_error(message: String)
signal entities_updated(entities: Array)
signal player_joined(player: Dictionary)
signal player_left(character_id: String)
signal combat_event(event: Dictionary)
signal pickup_event(event: Dictionary)

const BUILD := "0.1.0"
const EXTENSION_PATH := "res://bin/honghuang_native_net.gdextension"

var transport: Node
var expected_ticket := ""
var hello_sent := false
var world_ready := false
var heartbeat_timer: Timer
var heartbeat_watchdog_timer: Timer
var last_heartbeat_ack_msec := 0

func _ready() -> void:
	if not ClassDB.class_exists("EnetClient"):
		var load_status: int = GDExtensionManager.load_extension(EXTENSION_PATH)
		if load_status != 0 and not ClassDB.class_exists("EnetClient"):
			connection_error.emit("原生 ENet 扩展加载失败，状态码：" + str(load_status) + "。请先编译 Client/NativeNet。")
			return
	if not ClassDB.class_exists("EnetClient"):
		connection_error.emit("扩展已加载但没有注册 EnetClient 类。")
		return
	var instance: Variant = ClassDB.instantiate("EnetClient")
	if not (instance is Node):
		connection_error.emit("无法创建 EnetClient 原生节点。")
		return
	transport = instance
	add_child(transport)
	transport.connected.connect(_on_connected)
	transport.connection_failed.connect(func(): connection_error.emit("无法连接世界服务器，请检查 UDP 地址、防火墙和服务状态。"))
	transport.disconnected.connect(_on_disconnected)
	transport.frame_received.connect(_on_frame_received)

func connect_with_ticket(host: String, port: int, ticket: String) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	if ticket.is_empty() or ticket.length() > 128:
		return ERR_INVALID_PARAMETER
	expected_ticket = ticket
	hello_sent = false
	var error: Error = transport.connect_to_host(host, port)
	if error != OK:
		connection_error.emit("ENet 连接初始化失败，错误码：" + str(error))
		return error
	return OK

func _on_connected() -> void:
	var frame := HHProtocolCodec.encode_client_hello(expected_ticket, BUILD)
	if frame.is_empty():
		rejected.emit("ClientHello 编码失败。")
		transport.disconnect_from_host()
		return
	var error: Error = transport.send_frame(frame)
	if error != OK:
		connection_error.emit("发送 ClientHello 失败，错误码：" + str(error))
		transport.disconnect_from_host()
		return
	hello_sent = true

func is_world_ready() -> bool:
	return world_ready

func send_input(move_x: float, move_z: float, sequence: int, jump: bool = false) -> Error:
	if not world_ready or transport == null:
		return ERR_UNCONFIGURED
	var payload := JSON.stringify({
		"sequence": sequence,
		"move_x": clampf(move_x, -1.0, 1.0),
		"move_z": clampf(move_z, -1.0, 1.0),
		"jump": jump
	}).to_utf8_buffer()
	var frame := HHProtocolCodec.encode_frame(HHProtocolCodec.MessageType.INPUT_COMMAND, payload)
	if frame.is_empty():
		return ERR_INVALID_DATA
	return transport.send_frame(frame, false)

func send_attack(target_entity_id: String) -> Error:
	if not world_ready or transport == null or target_entity_id.is_empty() or target_entity_id.length() > 96:
		return ERR_INVALID_PARAMETER
	var payload := JSON.stringify({"target_entity_id": target_entity_id}).to_utf8_buffer()
	var frame := HHProtocolCodec.encode_frame(HHProtocolCodec.MessageType.ATTACK_COMMAND, payload)
	if frame.is_empty():
		return ERR_INVALID_DATA
	return transport.send_frame(frame)


func send_pickup(drop_id: String) -> Error:
	if not world_ready or transport == null or drop_id.is_empty() or drop_id.length() > 64:
		return ERR_INVALID_PARAMETER
	var payload := JSON.stringify({"drop_id": drop_id}).to_utf8_buffer()
	var frame := HHProtocolCodec.encode_frame(HHProtocolCodec.MessageType.PICKUP_COMMAND, payload)
	if frame.is_empty():
		return ERR_INVALID_DATA
	return transport.send_frame(frame)

func _on_frame_received(bytes: PackedByteArray) -> void:
	var decoded := HHProtocolCodec.decode_frame(bytes)
	if not decoded.get("ok", false):
		rejected.emit("收到无效协议帧：" + str(decoded.get("error", "unknown")))
		transport.disconnect_from_host()
		return
	var message_type := int(decoded.get("type", 0))
	var payload: PackedByteArray = decoded.get("payload", PackedByteArray())
	match message_type:
		HHProtocolCodec.MessageType.SERVER_WELCOME:
			if not hello_sent:
				rejected.emit("收到未预期的 ServerWelcome。")
				transport.disconnect_from_host()
				return
			var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if parsed is Dictionary and parsed.has("character_id") and parsed.has("world_id") and parsed.has("instance_id"):
				world_ready = true
				last_heartbeat_ack_msec = Time.get_ticks_msec()
				_start_heartbeat()
				welcomed.emit(parsed)
			else:
				rejected.emit("ServerWelcome 缺少角色或世界快照字段。")
				transport.disconnect_from_host()
		HHProtocolCodec.MessageType.SERVER_REJECT:
			var parsed_reject: Variant = JSON.parse_string(payload.get_string_from_utf8())
			var reason := str(parsed_reject.get("reason", "世界服务器拒绝进入。")) if parsed_reject is Dictionary else payload.get_string_from_utf8()
			rejected.emit(reason)
			transport.disconnect_from_host()
		HHProtocolCodec.MessageType.HEARTBEAT_ACK:
			last_heartbeat_ack_msec = Time.get_ticks_msec()
		HHProtocolCodec.MessageType.ENTITY_SNAPSHOT:
			var snapshot: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if snapshot is Dictionary and snapshot.get("entities", []) is Array:
				entities_updated.emit(snapshot.get("entities", []))
		HHProtocolCodec.MessageType.PLAYER_JOINED:
			var joined: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if joined is Dictionary and not str(joined.get("character_id", "")).is_empty():
				player_joined.emit(joined)
			else:
				rejected.emit("收到无效的 PlayerJoined 事件。")
		HHProtocolCodec.MessageType.PLAYER_LEFT:
			var left: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if left is Dictionary and not str(left.get("character_id", "")).is_empty():
				player_left.emit(str(left.get("character_id", "")))
			else:
				rejected.emit("收到无效的 PlayerLeft 事件。")
		HHProtocolCodec.MessageType.COMBAT_EVENT:
			var combat: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if combat is Dictionary:
				combat_event.emit(combat)
			else:
				rejected.emit("收到无效的 CombatEvent。")
		HHProtocolCodec.MessageType.PICKUP_EVENT:
			var pickup: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if pickup is Dictionary:
				pickup_event.emit(pickup)
			else:
				rejected.emit("收到无效的 PickupEvent。")
		_:
			rejected.emit("收到未知服务端消息类型：" + str(message_type))
			transport.disconnect_from_host()

func _start_heartbeat() -> void:
	if heartbeat_timer == null:
		heartbeat_timer = Timer.new()
		heartbeat_timer.wait_time = 10.0
		heartbeat_timer.one_shot = false
		heartbeat_timer.timeout.connect(_send_heartbeat)
		add_child(heartbeat_timer)
	if heartbeat_watchdog_timer == null:
		heartbeat_watchdog_timer = Timer.new()
		heartbeat_watchdog_timer.wait_time = 5.0
		heartbeat_watchdog_timer.one_shot = false
		heartbeat_watchdog_timer.timeout.connect(_check_heartbeat_timeout)
		add_child(heartbeat_watchdog_timer)
	heartbeat_timer.start()
	heartbeat_watchdog_timer.start()

func _check_heartbeat_timeout() -> void:
	if not world_ready or last_heartbeat_ack_msec <= 0:
		return
	if Time.get_ticks_msec() - last_heartbeat_ack_msec <= 30000:
		return
	world_ready = false
	connection_error.emit("世界服务器超过 30 秒未响应心跳，正在断开连接以便重新连接。")
	if transport != null:
		transport.disconnect_from_host()

func _send_heartbeat() -> void:
	if transport == null or not transport.is_connected_to_server():
		return
	var frame := HHProtocolCodec.encode_frame(HHProtocolCodec.MessageType.HEARTBEAT, PackedByteArray())
	var error: Error = transport.send_frame(frame)
	if error != OK:
		connection_error.emit("发送心跳失败，错误码：" + str(error))

func _on_disconnected() -> void:
	world_ready = false
	if heartbeat_timer != null:
		heartbeat_timer.stop()
	if heartbeat_watchdog_timer != null:
		heartbeat_watchdog_timer.stop()
	disconnected.emit()

func close() -> void:
	if heartbeat_timer != null:
		heartbeat_timer.stop()
	if heartbeat_watchdog_timer != null:
		heartbeat_watchdog_timer.stop()
	if transport != null:
		transport.disconnect_from_host()
