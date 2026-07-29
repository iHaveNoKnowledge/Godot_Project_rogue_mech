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

# Music crossfade & playlists
@export var grunt_tracks: Array[AudioStream] = []
@export var ace_tracks: Array[AudioStream] = []
@export var boss_tracks: Array[AudioStream] = []

var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var current_music: AudioStreamPlayer
var current_music_category: String = ""
var current_track: AudioStream = null

var _music_tween: Tween = null
var _procedural_music_cache: Dictionary = {}

# Procedural sound buffers
var _sound_cache: Dictionary = {}


func _ready() -> void:
	_setup_pools()
	_setup_music_players()
	_generate_sounds()
	_auto_scan_music_folders()
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
	music_player_a.volume_db = linear_to_db(music_volume)
	add_child(music_player_a)

	music_player_b = AudioStreamPlayer.new()
	music_player_b.name = "MusicB"
	music_player_b.bus = "Music"
	music_player_b.volume_db = -80.0
	add_child(music_player_b)

	current_music = music_player_a


func _generate_sounds() -> void:
	# Beam Rifle: sine sweep 200->800Hz
	_sound_cache["beam_rifle"] = preload("res://resources/audio/sfx/beamrifle01.wav")
	# Machine Gun: short noise burst
	_sound_cache["machine_gun"] = preload("res://resources/audio/sfx/machine_gun01.wav")
	# Missile: deep sine + noise
	_sound_cache["missile"] = preload("res://resources/audio/sfx/missile01.wav")
	# Shotgun: noise burst
	_sound_cache["shotgun"] = preload("res://resources/audio/sfx/Dense_heavy_combat_s_#1-1782744878871.wav")
	# Melee: sine chop
	_sound_cache["melee"] = _gen_sine_chop(400.0, 0.08, 0.3)
	# Impact: short noise
	_sound_cache["impact"] = preload("res://resources/audio/sfx/impact01.wav")
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
		2: play_sfx("missile", pos)
		3: play_sfx("shotgun", pos)
		4: play_sfx("melee", pos)


func play_weapon_sfx_with_override(weapon: WeaponPart, pos: Vector3) -> void:
	if weapon.fire_sfx != null:
		# Custom sound override — play directly from stream
		var player = _get_free_3d_player()
		if player == null:
			return
		player.stream = weapon.fire_sfx
		player.global_position = pos
		player.volume_db = 0.0
		player.bus = "SFX"
		player.play()
	else:
		# Fallback to type default
		play_weapon_sfx(weapon.weapon_type, pos)


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


# --- Combat Music & Playlists ---

func _auto_scan_music_folders() -> void:
	if grunt_tracks.is_empty():
		grunt_tracks = _scan_music_directory("res://resources/audio/music/grunt")
	if ace_tracks.is_empty():
		ace_tracks = _scan_music_directory("res://resources/audio/music/ace")
	if boss_tracks.is_empty():
		boss_tracks = _scan_music_directory("res://resources/audio/music/boss")


func _scan_music_directory(dir_path: String) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return streams
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and not file_name.ends_with(".import"):
				var ext = file_name.get_extension().to_lower()
				if ext in ["ogg", "mp3", "wav"]:
					var full_path = dir_path.path_join(file_name)
					var stream = load(full_path) as AudioStream
					if stream:
						streams.append(stream)
			file_name = dir.get_next()
	return streams


func play_combat_music(category: String, fade_time: float = 1.5, force_restart: bool = false) -> void:
	category = category.to_lower()
	if not force_restart and current_music_category == category and current_music.playing:
		return

	_auto_scan_music_folders()

	var pool: Array[AudioStream] = []
	match category:
		"ace":
			pool = ace_tracks
		"boss":
			pool = boss_tracks
		_:
			category = "grunt"
			pool = grunt_tracks

	var stream_to_play: AudioStream = null
	if not pool.is_empty():
		var available = pool.duplicate()
		if available.size() > 1 and current_track != null:
			available.erase(current_track)
		available.shuffle()
		stream_to_play = available[0]
	else:
		if not _procedural_music_cache.has(category):
			_procedural_music_cache[category] = _gen_procedural_combat_track(category)
		stream_to_play = _procedural_music_cache[category]

	if stream_to_play == null:
		return

	current_music_category = category
	current_track = stream_to_play
	_crossfade_to_stream(stream_to_play, fade_time)


func stop_music(fade_time: float = 1.0) -> void:
	current_music_category = ""
	current_track = null
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	_music_tween = create_tween()
	_music_tween.tween_property(current_music, "volume_db", -80.0, fade_time)
	_music_tween.tween_callback(func(): current_music.stop())


func _crossfade_to_stream(new_stream: AudioStream, fade_time: float) -> void:
	var next_player: AudioStreamPlayer = music_player_b if current_music == music_player_a else music_player_a
	var target_volume_db = linear_to_db(music_volume)

	next_player.stream = new_stream
	next_player.volume_db = -80.0
	next_player.play()

	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()

	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(current_music, "volume_db", -80.0, fade_time)
	_music_tween.tween_property(next_player, "volume_db", target_volume_db, fade_time)

	var old_player = current_music
	current_music = next_player

	var cleanup_tween = create_tween()
	cleanup_tween.tween_interval(fade_time)
	cleanup_tween.tween_callback(func(): old_player.stop())


func _gen_procedural_combat_track(category: String) -> AudioStreamWAV:
	var sample_rate = 22050
	var bpm = 120.0
	var duration = 4.0
	if category == "ace":
		bpm = 150.0
		duration = 3.2
	elif category == "boss":
		bpm = 100.0
		duration = 4.8

	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var beat_duration = 60.0 / bpm

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var beat = fmod(t, beat_duration) / beat_duration
		var sample = 0.0

		match category:
			"grunt":
				if beat < 0.15:
					sample += sin(TAU * (120.0 - beat * 400.0) * t) * 0.4
				var bass_freq = 65.0
				if fmod(t, beat_duration * 2.0) > beat_duration:
					bass_freq = 82.4
				sample += sin(TAU * bass_freq * t) * 0.25
				if fmod(t, beat_duration * 0.5) / (beat_duration * 0.5) < 0.08:
					sample += (randf() * 2.0 - 1.0) * 0.1

			"ace":
				var notes = [130.81, 155.56, 196.0, 233.08]
				var note_idx = int(t / (beat_duration * 0.25)) % notes.size()
				var sub_beat = fmod(t, beat_duration * 0.25) / (beat_duration * 0.25)
				if sub_beat < 0.6:
					sample += sin(TAU * notes[note_idx] * t) * 0.25
				sample += sin(TAU * 55.0 * t) * 0.3
				var bar_beat = fmod(t, beat_duration * 4.0) / beat_duration
				if (bar_beat >= 1.0 and bar_beat < 1.15) or (bar_beat >= 3.0 and bar_beat < 3.15):
					sample += (randf() * 2.0 - 1.0) * 0.25

			"boss":
				var boss_freq = 41.2
				if fmod(t, beat_duration * 4.0) > beat_duration * 2.0:
					boss_freq = 38.89
				sample += sin(TAU * boss_freq * t) * 0.45
				sample += sin(TAU * (boss_freq * 2.0) * t) * 0.2
				if beat < 0.2:
					sample += (randf() * 2.0 - 1.0) * exp(-beat * 15.0) * 0.3

		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = num_samples
	return stream


func _get_free_3d_player() -> AudioStreamPlayer3D:
	for player in sfx_pool:
		if not player.playing:
			return player
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
