extends RefCounted
class_name HHProtocolCodec

const MAGIC := 0x48485731
const VERSION := 1
const MAX_PAYLOAD := 64 * 1024

enum MessageType {
	CLIENT_HELLO = 1,
	SERVER_WELCOME = 2,
	SERVER_REJECT = 3,
	HEARTBEAT = 4,
	HEARTBEAT_ACK = 5,
	INPUT_COMMAND = 10,
	ENTITY_SNAPSHOT = 11,
	PLAYER_JOINED = 12,
	PLAYER_LEFT = 13,
}

static func _u16(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 8) & 0xff, value & 0xff])

static func _u32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 0xff, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff])

static func encode_frame(message_type: int, payload: PackedByteArray) -> PackedByteArray:
	if payload.size() > MAX_PAYLOAD:
		push_error("Protocol payload exceeds 64 KiB")
		return PackedByteArray()
	var frame := PackedByteArray()
	frame.append_array(_u32(MAGIC))
	frame.append_array(_u16(VERSION))
	frame.append_array(_u16(message_type))
	frame.append_array(_u32(payload.size()))
	frame.append_array(payload)
	return frame

static func _encode_string(value: String, max_bytes: int) -> PackedByteArray:
	var bytes := value.to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > max_bytes or bytes.size() > 65535:
		return PackedByteArray()
	var result := _u16(bytes.size())
	result.append_array(bytes)
	return result

static func encode_client_hello(ticket: String, client_build: String) -> PackedByteArray:
	var ticket_bytes := _encode_string(ticket, 128)
	var build_bytes := _encode_string(client_build, 64)
	if ticket_bytes.is_empty() or build_bytes.is_empty():
		push_error("Invalid ClientHello ticket or build string")
		return PackedByteArray()
	var payload := ticket_bytes
	payload.append_array(build_bytes)
	return encode_frame(MessageType.CLIENT_HELLO, payload)

static func decode_frame(frame: PackedByteArray) -> Dictionary:
	if frame.size() < 12:
		return {"ok": false, "error": "frame header truncated"}
	var magic := (int(frame[0]) << 24) | (int(frame[1]) << 16) | (int(frame[2]) << 8) | int(frame[3])
	var version := (int(frame[4]) << 8) | int(frame[5])
	var message_type := (int(frame[6]) << 8) | int(frame[7])
	var payload_size := (int(frame[8]) << 24) | (int(frame[9]) << 16) | (int(frame[10]) << 8) | int(frame[11])
	if magic != MAGIC:
		return {"ok": false, "error": "invalid frame magic"}
	if version != VERSION:
		return {"ok": false, "error": "unsupported protocol version"}
	if payload_size < 0 or payload_size > MAX_PAYLOAD or frame.size() != 12 + payload_size:
		return {"ok": false, "error": "invalid payload length"}
	return {"ok": true, "version": version, "type": message_type, "payload": frame.slice(12)}
