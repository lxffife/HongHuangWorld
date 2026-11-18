extends Node
class_name HHChatNetwork

signal connected
signal disconnected
signal connection_error(message: String)
signal message_received(message: Dictionary)
signal history_received(channel: String, messages: Array)
signal send_failed(reason: String)

const SOCKET_PATH := "/api/v1/chat/socket"
const HEARTBEAT_INTERVAL := 20.0
const RECONNECT_DELAY := 4.0

var socket := WebSocketPeer.new()
var socket_url := ""
var http_base_url := ""
var access_token := ""
var reconnect_timer: Timer
var heartbeat_timer: Timer
var manually_closed := false
var connecting := false
var was_open := false
var connection_generation := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reconnect_timer = Timer.new()
	reconnect_timer.one_shot = true
	reconnect_timer.wait_time = RECONNECT_DELAY
	reconnect_timer.timeout.connect(_connect_socket)
	add_child(reconnect_timer)
	heartbeat_timer = Timer.new()
	heartbeat_timer.one_shot = false
	heartbeat_timer.wait_time = HEARTBEAT_INTERVAL
	heartbeat_timer.timeout.connect(_send_heartbeat)
	add_child(heartbeat_timer)

func connect_chat(api_base: String, token: String) -> Error:
	if token.is_empty():
		return ERR_UNAUTHORIZED
	var base := api_base.strip_edges().trim_suffix("/")
	if base.begins_with("https://"):
		socket_url = "wss://" + base.trim_prefix("https://") + SOCKET_PATH
	elif base.begins_with("http://"):
		socket_url = "ws://" + base.trim_prefix("http://") + SOCKET_PATH
	else:
		return ERR_INVALID_PARAMETER
	if reconnect_timer != null:
		reconnect_timer.stop()
	if heartbeat_timer != null:
		heartbeat_timer.stop()
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close(1000, "refresh chat world binding")
	socket = WebSocketPeer.new()
	connecting = false
	was_open = false
	connection_generation += 1
	http_base_url = base
	access_token = token
	manually_closed = false
	_connect_socket()
	return OK

func _connect_socket() -> void:
	if manually_closed or socket_url.is_empty() or access_token.is_empty():
		return
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN or connecting:
		return
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 65536
	socket.outbound_buffer_size = 65536
	var headers := PackedStringArray(["Authorization: Bearer " + access_token])
	var error: Error = socket.connect_to_url(socket_url, TLSOptions.client(), PackedStringArray(), headers)
	if error != OK:
		connecting = false
		connection_error.emit("聊天连接初始化失败：" + str(error))
		_schedule_reconnect()
		return
	connecting = true

func _process(_delta: float) -> void:
	if socket == null:
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if connecting:
			connecting = false
			was_open = true
			connection_generation += 1
			reconnect_timer.stop()
			heartbeat_timer.start()
			connected.emit()
		while socket.get_available_packet_count() > 0:
			var packet := socket.get_packet()
			if socket.get_packet_error() != OK:
				connection_error.emit("读取聊天消息失败。")
				continue
			var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if parsed is Dictionary:
				message_received.emit(parsed)
	elif state == WebSocketPeer.STATE_CLOSED:
		if connecting or was_open:
			connecting = false
			was_open = false
			heartbeat_timer.stop()
			disconnected.emit()
			if not manually_closed:
				connection_error.emit("聊天服务器连接已断开，稍后自动重试。")
			_schedule_reconnect()

func fetch_history(channel: String, limit: int = 50) -> void:
	if channel not in ["world", "cross_world"] or access_token.is_empty() or http_base_url.is_empty():
		return
	var request := HTTPRequest.new()
	request.timeout = 10.0
	request.set_meta("chat_channel", channel)
	request.set_meta("generation", connection_generation)
	request.request_completed.connect(_on_history_request_completed.bind(request))
	add_child(request)
	var headers := PackedStringArray(["Authorization: Bearer " + access_token])
	var url := http_base_url + "/api/v1/chat/messages?channel=" + channel.uri_encode() + "&limit=" + str(clampi(limit, 1, 100))
	var error := request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		connection_error.emit("聊天历史请求失败：" + str(error))

func _on_history_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest) -> void:
	var channel := str(request.get_meta("chat_channel", ""))
	var generation := int(request.get_meta("generation", -1))
	request.queue_free()
	if generation != connection_generation:
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		connection_error.emit("聊天历史暂时无法获取（HTTP " + str(response_code) + "）")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary) or not (parsed.get("items", []) is Array):
		connection_error.emit("聊天历史响应格式错误。")
		return
	history_received.emit(channel, parsed.get("items", []))

func send_message(channel: String, content: String, client_message_id: String) -> Error:
	if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	if channel not in ["world", "cross_world"] or content.strip_edges().is_empty() or content.length() > 200 or client_message_id.is_empty():
		return ERR_INVALID_PARAMETER
	var payload := {
		"type": "send",
		"client_message_id": client_message_id,
		"channel": channel,
		"content": content.strip_edges()
	}
	return socket.send_text(JSON.stringify(payload))

func _send_heartbeat() -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var error := socket.send_text(JSON.stringify({"type": "ping"}))
		if error != OK:
			connection_error.emit("聊天心跳发送失败：" + str(error))

func _schedule_reconnect() -> void:
	if manually_closed or socket_url.is_empty() or reconnect_timer == null:
		return
	if reconnect_timer.is_stopped():
		reconnect_timer.start()

func close_chat() -> void:
	manually_closed = true
	connecting = false
	was_open = false
	if reconnect_timer != null:
		reconnect_timer.stop()
	if heartbeat_timer != null:
		heartbeat_timer.stop()
	if socket != null and socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close(1000, "client leaving chat")
