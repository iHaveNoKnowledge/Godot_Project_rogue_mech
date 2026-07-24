extends Node

## AudioManager autoload — manages all audio playback, volume, SFX pooling.

# Volume levels (linear 0.0-1.0)
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var music_volume: float = 0.6
var ambient_volume: float = 0.5

# SFX pool
const SFX_POOL_SIZE = 16
var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_2d_pool: Array[AudioStreamPlayer] = []

# Music crossfade
var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var current_music: AudioStreamPlayer

# Procedural sound buffers
var _sound_cache: Dictionary = {}


func _ready() -> void:
	_setup_pools()
	_setup_music_players()
	_generate_sounds()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _setup_pools() -> void:
	for i in SFX_POOL_SIZE:
		var player_3d = AudioStreamPlayer3D.new()
		player_3d.name = "SFX3D_%d" % i
		player_3d.bus = "SFX"
		add_child(player_3d)
		sfx_pool.append(player_3d)

	for i in 8:
		var player_2d = AudioStreamPlayer.new()
		player_2d.name = "SFX2D_%d" % i
		player_2d.bus = "SFX"
		add_child(player_2d)
		sfx_2d_pool.append(player_2d)


func _setup_music_players() -> void:
	music_player_a = AudioStreamPlayer.new()
	music_player_a.name = "MusicA"
	music_player_a.bus = "Music"
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.name = "MusicB"
	music_player_b.bus = "Music"
	add_child(music_player_b)

	current_music = music_player_a


func _generate_sounds() -> void:
	# Beam Rifle: sine sweep 200->800Hz
	_sound_cache["beam_rifle"] = _gen_sine_sweep(200.0, 800.0, 0.15, 0.3)
	# Machine Gun: short noise burst
	_sound_cache["machine_gun"] = _gen_noise_burst(0.05, 0.2)
	# Missile: deep sine + noise
	_sound_cache["missile"] = _gen_sine_sweep(100.0, 60.0, 0.3, 0.5)
	# Shotgun: noise burst
	_sound_cache["shotgun"] = _gen_noise_burst(0.1, 0.4)
	# Melee: sine chop
	_sound_cache["melee"] = _gen_sine_chop(400.0, 0.08, 0.3)
	# Impact: short noise
	_sound_cache["impact"] = _gen_noise_burst(0.03, 0.15)
	# Armor break: crack
	_sound_cache["armor_break"] = _gen_crack(0.12, 0.4)
	# Explosion: long noise swell
	_sound_cache["explosion"] = _gen_explosion(0.4, 0.6)
	# UI click
	_sound_cache["ui_click"] = _gen_sine_tone(800.0, 0.05, 0.15)
	# UI confirm
	_sound_cache["ui_confirm"] = _gen_sine_tone(1200.0, 0.08, 0.2)
	# Footstep
	_sound_cache["footstep"] = _gen_noise_burst(0.04, 0.08)
	# Dash
	_sound_cache["dash"] = _gen_sine_sweep(300.0, 600.0, 0.1, 0.2)


# --- Sound Generation Helpers ---

func _gen_sine_sweep(freq_start: float, freq_end: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit mono

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var progress = float(i) / num_samples
		var freq = lerp(freq_start, freq_end, progress)
		var sample = sin(TAU * freq * t) * volume * 32767
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = 1.0 - (t / duration)  # Decay
		var sample = (randf() * 2.0 - 1.0) * volume * envelope * 32767
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_sine_tone(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = 1.0 - (t / duration)
		var sample = sin(TAU * freq * t) * volume * envelope * 32767
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_sine_chop(freq: float, duration: float, volume: float) -> AudioStreamWAV:
	return _gen_sine_tone(freq, duration, volume)


func _gen_crack(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 20.0)
		var sample = (randf() * 2.0 - 1.0) * volume * envelope * 32767
		# Add a sine component for metallic feel
		sample += sin(TAU * 1200.0 * t) * volume * 0.3 * envelope * 32767
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_explosion(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		# Swell then decay
		var envelope = (t / duration) * exp(-t * 3.0)
		var sample = (randf() * 2.0 - 1.0) * volume * envelope * 32767
		sample += sin(TAU * 80.0 * t) * volume * 0.5 * envelope * 32767
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# --- Public API ---

func play_sfx(sound_name: String, pos: Vector3 = Vector3.ZERO, volume_db: float = 0.0, bus: String = "SFX") -> void:
	if not _sound_cache.has(sound_name):
		return

	var stream = _sound_cache[sound_name]
	var player = _get_free_3d_player()
	if player == null:
		return

	player.stream = stream
	player.global_position = pos
	player.volume_db = volume_db
	player.bus = bus
	player.play()


func play_sfx_2d(sound_name: String, volume_db: float = 0.0, bus: String = "SFX") -> void:
	if not _sound_cache.has(sound_name):
		return

	var stream = _sound_cache[sound_name]
	var player = _get_free_2d_player()
	if player == null:
		return

	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus
	player.play()


func play_weapon_sfx(weapon_type: int, pos: Vector3) -> void:
	match weapon_type:
		0: play_sfx("beam_rifle", pos)
		1: play_sfx("machine_gun", pos)
		2: play_sfx("shotgun", pos)
		3: play_sfx("missile", pos)
		4: play_sfx("melee", pos)


func play_impact(pos: Vector3) -> void:
	play_sfx("impact", pos, -5.0)


func play_armor_break(pos: Vector3) -> void:
	play_sfx("armor_break", pos, 0.0)


func play_explosion(pos: Vector3) -> void:
	play_sfx("explosion", pos, 3.0)


func play_footstep(pos: Vector3) -> void:
	play_sfx("footstep", pos, -10.0, "Movement")


func play_dash(pos: Vector3) -> void:
	play_sfx("dash", pos, -3.0, "Movement")


func play_ui_click() -> void:
	play_sfx_2d("ui_click", -5.0, "UI")


func play_ui_confirm() -> void:
	play_sfx_2d("ui_confirm", 0.0, "UI")


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(linear, 0.001, 1.0)))


func _get_free_3d_player() -> AudioStreamPlayer3D:
	for player in sfx_pool:
		if not player.playing:
			return player
	# Steal oldest
	var oldest = sfx_pool[0]
	for player in sfx_pool:
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	oldest.stop()
	return oldest


func _get_free_2d_player() -> AudioStreamPlayer:
	for player in sfx_2d_pool:
		if not player.playing:
			return player
	var oldest = sfx_2d_pool[0]
	for player in sfx_2d_pool:
		if player.get_playback_position() > oldest.get_playback_position():
			oldest = player
	oldest.stop()
	return oldest
