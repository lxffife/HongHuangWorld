extends Node
class_name HHWorldNetwork

signal welcomed(snapshot: Dictionary)
signal rejected(reason: String)
signal disconnected
signal connection_error(message: String)

const BUILD := "0.1.0"

var transport: Node
var expected_snapshot: Dictionary = {}
var hello_sent := false

func _ready() -> void:
	if not ClassDB.class_exists("EnetClient"):
		connection_error.emit("原生 ENet 扩展未加载。请先编译 Client/NativeNet 并将动态库放入客户端 bin 目录。")
		return
	transport = ClassDB.instantiate("EnetClient")
	add_child(transport)
	transport.connected.connect(_on_connected)
	transport.connection_failed.connect(func(): connection_error.emit("无法连接世界服务器。"))
	transport.disconnected.connect(func(): disconnected.emit())
	transport.frame_received.connect(_on_frame_received)

func connect_with_ticket(host: String, port: int, ticket: String) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	var error: Error = transport.connect_to_host(host, port)
	if error != OK:
		connection_error.emit("ENet 连接初始化失败，错误码：" + str(error))
		return error
	expected_snapshot = {"ticket": ticket}
	hello_sent = false
	return OK

func _on_connected() -> void:
	var ticket := str(expected_snapshot.get("ticket", ""))
	var frame := HHProtocolCodec.encode_client_hello(ticket, BUILD)
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
			var parsed: Variant = JSON.parse_string(payload.get_string_from_utf8())
			if parsed is Dictionary:
				welcomed.emit(parsed)
			else:
				rejected.emit("ServerWelcome 内容不是有效 JSON。")
				transport.disconnect_from_host()
		HHProtocolCodec.MessageType.SERVER_REJECT:
			var parsed_reject: Variant = JSON.parse_string(payload.get_string_from_utf8())
			var reason := str(parsed_reject.get("reason", "世界服务器拒绝进入。")) if parsed_reject is Dictionary else payload.get_string_from_utf8()
			rejected.emit(reason)
			transport.disconnect_from_host()
		HHProtocolCodec.MessageType.HEARTBEAT_ACK:
			pass
		_:
			rejected.emit("收到未知服务端消息类型：" + str(message_type))
			transport.disconnect_from_host()

func close() -> void:
	if transport != null:
		transport.disconnect_from_host()
