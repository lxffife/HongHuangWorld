extends Node
## Original runtime-synthesized placeholder audio. No third-party recordings or copyrighted music.
## Replace individual cues with reviewed CC0 files later without changing gameplay call sites.

const SAMPLE_RATE := 22050
const CONFIG_PATH := "user://honghuang_audio.cfg"
const BUS_NAMES := ["Music", "SFX", "UI"]

var _cache: Dictionary = {}
var _volumes := {"Master": 0.85, "Music": 0.55, "SFX": 0.8, "UI": 0.75}
var _muted := false

const CUES := {
	"attack": {"duration": 0.24, "start": 210.0, "end": 95.0, "noise": 0.42, "gain": 0.30, "wave": "sweep"},
	"hit": {"duration": 0.16, "start": 115.0, "end": 55.0, "noise": 0.70, "gain": 0.38, "wave": "impact"},
	"heavy_hit": {"duration": 0.34, "start": 78.0, "end": 38.0, "noise": 0.82, "gain": 0.48, "wave": "impact"},
	"monster_attack": {"duration": 0.30, "start": 145.0, "end": 62.0, "noise": 0.62, "gain": 0.34, "wave": "growl"},
	"death": {"duration": 0.58, "start": 360.0, "end": 72.0, "noise": 0.24, "gain": 0.28, "wave": "fall"},
	"spell": {"duration": 0.42, "start": 440.0, "end": 880.0, "noise": 0.12, "gain": 0.24, "wave": "magic"},
	"pickup": {"duration": 0.18, "start": 660.0, "end": 990.0, "noise": 0.04, "gain": 0.20, "wave": "chime"},
	"ui": {"duration": 0.075, "start": 520.0, "end": 420.0, "noise": 0.02, "gain": 0.13, "wave": "tone"},
	"warning": {"duration": 0.28, "start": 220.0, "end": 180.0, "noise": 0.10, "gain": 0.26, "wave": "warning"},
	"footstep": {"duration": 0.10, "start": 90.0, "end": 48.0, "noise": 0.72, "gain": 0.16, "wave": "step"}
}

func _ready() -> void:
	_ensure_buses()
	_load_settings()
	_apply_volumes()

func _ensure_buses() -> void:
	for bus_name in BUS_NAMES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	_muted = bool(config.get_value("audio", "muted", false))
	for bus_name in ["Master", "Music", "SFX", "UI"]:
		_volumes[bus_name] = clampf(float(config.get_value("audio", bus_name, _volumes[bus_name])), 0.0, 1.0)

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "muted", _muted)
	for bus_name in _volumes:
		config.set_value("audio", bus_name, _volumes[bus_name])
	config.save(CONFIG_PATH)

func _apply_volumes() -> void:
	AudioServer.set_bus_mute(0, _muted)
	for bus_name in _volumes:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var volume := float(_volumes[bus_name])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))
		AudioServer.set_bus_mute(index, _muted or volume <= 0.001)

func set_volume(bus_name: String, value: float) -> void:
	if not _volumes.has(bus_name):
		return
	_volumes[bus_name] = clampf(value, 0.0, 1.0)
	_apply_volumes()
	_save_settings()

func get_volume(bus_name: String) -> float:
	return float(_volumes.get(bus_name, 0.0))

func set_muted(value: bool) -> void:
	_muted = value
	_apply_volumes()
	_save_settings()

func is_muted() -> bool:
	return _muted

func play_ui(cue: String = "ui", pitch_scale: float = 1.0) -> void:
	_play(cue, "UI", null, Vector3.ZERO, pitch_scale)

func play_combat(cue: String = "attack", pitch_scale: float = 1.0) -> void:
	_play(cue, "SFX", null, Vector3.ZERO, pitch_scale)

func play_world(cue: String, world_position: Vector3, pitch_scale: float = 1.0, max_distance: float = 28.0) -> void:
	_play(cue, "SFX", null, world_position, pitch_scale, max_distance)

func _play(cue: String, bus_name: String, _unused: Node, world_position: Vector3, pitch_scale: float, max_distance: float = 28.0) -> void:
	if _muted or not CUES.has(cue):
		return
	var stream: AudioStreamWAV = _cache.get(cue)
	if stream == null:
		stream = _build_stream(cue)
		_cache[cue] = stream
	if world_position != Vector3.ZERO:
		var spatial := AudioStreamPlayer3D.new()
		spatial.stream = stream
		spatial.bus = bus_name
		spatial.pitch_scale = clampf(pitch_scale, 0.65, 1.5)
		spatial.max_distance = max_distance
		spatial.unit_size = 5.0
		add_child(spatial)
		spatial.global_position = world_position
		spatial.finished.connect(spatial.queue_free)
		spatial.play()
	else:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = bus_name
		player.pitch_scale = clampf(pitch_scale, 0.65, 1.5)
		add_child(player)
		player.finished.connect(player.queue_free)
		player.play()

func _build_stream(cue: String) -> AudioStreamWAV:
	var profile: Dictionary = CUES[cue]
	var duration := float(profile["duration"])
	var sample_count := maxi(1, int(SAMPLE_RATE * duration))
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var start_frequency := float(profile["start"])
	var end_frequency := float(profile["end"])
	var noise_amount := float(profile["noise"])
	var gain := float(profile["gain"])
	var wave := str(profile["wave"])
	var phase := 0.0
	for index in range(sample_count):
		var t := float(index) / float(sample_count)
		var envelope := pow(maxf(0.0, 1.0 - t), 1.8)
		if wave == "chime" or wave == "magic":
			envelope *= minf(1.0, t * 18.0)
		var frequency := lerpf(start_frequency, end_frequency, t)
		phase += TAU * frequency / float(SAMPLE_RATE)
		var tone := sin(phase)
		var overtone := sin(phase * (2.01 if wave == "chime" else 1.48)) * 0.28
		var noise := randf_range(-1.0, 1.0) * noise_amount
		var sample := clampf((tone * (1.0 - noise_amount * 0.45) + overtone + noise) * envelope * gain, -1.0, 1.0)
		data.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream
