class_name MusicManager
extends Node
## -----------------------------------------------------------------------
## MUSIC MANAGER — playlists, crossfade, procedural tracks.
##
## Extracted from AudioManager so music concerns live in one focused file.
## Composed as a child node of AudioManager; all play_*_music calls route
## through this manager.
## -----------------------------------------------------------------------

# Volume (linear 0.0–1.0), kept in sync by AudioManager.set_music_volume().
var music_volume: float = 0.6

# Playlist arrays (populated by _auto_scan_music_folders).
@export var menu_tracks: Array[AudioStream] = []
@export var intermission_tracks: Array[AudioStream] = []
@export var hangar_tracks: Array[AudioStream] = []
@export var grunt_tracks: Array[AudioStream] = []
@export var ace_tracks: Array[AudioStream] = []
@export var boss_tracks: Array[AudioStream] = []
## Biome-exclusive battle tracks (desert only — e.g. Iron March on the Dunes).
## Rolled as an alternative pick when the battle biome is desert.
@export var desert_tracks: Array[AudioStream] = []

## Chance (0.0–1.0) that a desert-biome battle plays a desert-exclusive
## track instead of the normal grunt/ace pick. Boss/war keep their identity.
const DESERT_EXCLUSIVE_CHANCE: float = 0.5

# A/B crossfade players
var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var current_music: AudioStreamPlayer
var current_music_category: String = ""
var current_track: AudioStream = null

## Saved intermission state for resume-after-combat.
var _saved_intermission_track: AudioStream = null
var _saved_intermission_pos: float = 0.0

var _music_tween: Tween = null
var _stop_tween: Tween = null
var _procedural_music_cache: Dictionary = {}

## Set by AudioManager — when true music is held at silence.
var combat_muted: bool = false


# ═══════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════

func setup() -> void:
	_setup_music_players()
	_auto_scan_music_folders()


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


# ═══════════════════════════════════════════════════════════════════════
# PLAYLIST SCANNING
# ═══════════════════════════════════════════════════════════════════════

func _auto_scan_music_folders() -> void:
	if menu_tracks.is_empty():
		menu_tracks = _scan_music_directory("res://resources/audio/music/menu")
	if intermission_tracks.is_empty():
		intermission_tracks = _scan_music_directory("res://resources/audio/music/intermission")
	if hangar_tracks.is_empty():
		hangar_tracks = _scan_music_directory("res://resources/audio/music/hangar")
	if grunt_tracks.is_empty():
		grunt_tracks = _scan_music_directory("res://resources/audio/music/grunt")
	if ace_tracks.is_empty():
		ace_tracks = _scan_music_directory("res://resources/audio/music/ace")
	if boss_tracks.is_empty():
		boss_tracks = _scan_music_directory("res://resources/audio/music/boss")
	if desert_tracks.is_empty():
		desert_tracks = _scan_music_directory("res://resources/audio/music/desert")


func _scan_music_directory(dir_path: String) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return result
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			if ext in ["wav", "ogg", "mp3"]:
				var stream := load(dir_path.path_join(file_name)) as AudioStream
				if stream != null:
					result.append(stream)
		file_name = dir.get_next()
	return result


# ═══════════════════════════════════════════════════════════════════════
# MUSIC PLAYBACK
# ═══════════════════════════════════════════════════════════════════════

func play_menu_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	if not force_restart and current_music_category == "menu" and current_music.playing:
		return
	_saved_intermission_track = null
	_saved_intermission_pos = 0.0
	_auto_scan_music_folders()
	var stream_to_play: AudioStream = null
	if not menu_tracks.is_empty():
		var available = menu_tracks.duplicate()
		if available.size() > 1 and current_track != null:
			available.erase(current_track)
		available.shuffle()
		stream_to_play = available[0]
	else:
		if not _procedural_music_cache.has("menu"):
			_procedural_music_cache["menu"] = _gen_procedural_menu_track()
		stream_to_play = _procedural_music_cache["menu"]
	if stream_to_play == null:
		return
	current_music_category = "menu"
	_crossfade_to_stream(stream_to_play, fade_time)


func play_intermission_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	if not force_restart and current_music_category == "intermission" and current_music.playing:
		return
	_auto_scan_music_folders()
	var stream_to_play: AudioStream = null
	if _saved_intermission_track != null:
		stream_to_play = _saved_intermission_track
		_saved_intermission_track = null
	elif not intermission_tracks.is_empty():
		var available = intermission_tracks.duplicate()
		available.shuffle()
		stream_to_play = available[0]
	else:
		if not _procedural_music_cache.has("intermission"):
			_procedural_music_cache["intermission"] = _gen_procedural_intermission_track()
		stream_to_play = _procedural_music_cache["intermission"]
	if stream_to_play == null:
		return
	current_music_category = "intermission"
	_crossfade_to_stream(stream_to_play, fade_time)


func play_hangar_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	if not force_restart and current_music_category == "hangar" and current_music.playing:
		return
	_auto_scan_music_folders()
	var stream_to_play: AudioStream = null
	if not hangar_tracks.is_empty():
		var available = hangar_tracks.duplicate()
		if available.size() > 1 and current_track != null:
			available.erase(current_track)
		available.shuffle()
		stream_to_play = available[0]
	else:
		if not _procedural_music_cache.has("hangar"):
			_procedural_music_cache["hangar"] = _gen_procedural_hangar_track()
		stream_to_play = _procedural_music_cache["hangar"]
	if stream_to_play == null:
		return
	current_music_category = "hangar"
	_crossfade_to_stream(stream_to_play, fade_time)


func play_combat_music(category: String, fade_time: float = 1.5, force_restart: bool = false, biome: String = "") -> void:
	if not force_restart and current_music_category == category and current_music.playing:
		return
	# Save intermission state so return_to_board resumes the same track.
	if current_music_category == "intermission" and current_music != null and current_music.playing:
		_saved_intermission_track = current_music.stream
		_saved_intermission_pos = current_music.get_playback_position()
	_auto_scan_music_folders()
	var stream_to_play: AudioStream = _pick_combat_stream(category, biome)
	if stream_to_play == null:
		return
	current_music_category = category
	_crossfade_to_stream(stream_to_play, fade_time)


## Picks the combat stream WITHOUT playing it (testable selection logic).
## Desert biome + grunt/ace: rolls DESERT_EXCLUSIVE_CHANCE for a
## desert-exclusive track; boss/war and other biomes use normal playlists.
func _pick_combat_stream(category: String, biome: String = "") -> AudioStream:
	_auto_scan_music_folders()
	if biome.to_lower() == "desert" and (category == "grunt" or category == "ace"):
		if not desert_tracks.is_empty() and randf() < DESERT_EXCLUSIVE_CHANCE:
			var exclusive = desert_tracks.duplicate()
			if exclusive.size() > 1 and current_track != null:
				exclusive.erase(current_track)
			exclusive.shuffle()
			return exclusive[0]
	var tracks: Array[AudioStream] = []
	match category:
		"grunt":
			tracks = grunt_tracks
		"ace":
			tracks = ace_tracks
		"boss":
			tracks = boss_tracks
		_:
			tracks = grunt_tracks
	if not tracks.is_empty():
		var available = tracks.duplicate()
		if available.size() > 1 and current_track != null:
			available.erase(current_track)
		available.shuffle()
		return available[0]
	if not _procedural_music_cache.has(category):
		_procedural_music_cache[category] = _gen_procedural_combat_track(category)
	return _procedural_music_cache[category]


func stop_music(fade_time: float = 1.0) -> void:
	current_music_category = ""
	if current_music == null:
		return
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	if _stop_tween and _stop_tween.is_valid():
		_stop_tween.kill()
	var player := current_music
	current_music = null
	_stop_tween = create_tween()
	_stop_tween.tween_property(player, "volume_db", -80.0, fade_time)
	_stop_tween.tween_callback(player.stop)


func set_combat_muted(muted: bool) -> void:
	if combat_muted == muted:
		return
	combat_muted = muted
	if muted:
		if _music_tween and _music_tween.is_valid():
			_music_tween.kill()
		music_player_a.volume_db = -80.0
		music_player_b.volume_db = -80.0
	else:
		if _music_tween and _music_tween.is_valid():
			_music_tween.kill()
		if current_music and current_music.playing and current_music_category != "":
			current_music.volume_db = -80.0
			_music_tween = create_tween()
			_music_tween.tween_property(current_music, "volume_db", linear_to_db(music_volume), 0.8)


func set_music_volume(linear: float) -> void:
	music_volume = linear
	if current_music and current_music.playing and not combat_muted:
		current_music.volume_db = linear_to_db(linear)


# ═══════════════════════════════════════════════════════════════════════
# CROSSFADE
# ═══════════════════════════════════════════════════════════════════════

func _crossfade_to_stream(new_stream: AudioStream, fade_time: float) -> void:
	var next_player: AudioStreamPlayer = music_player_b if current_music == music_player_a else music_player_a
	var target_volume_db = linear_to_db(music_volume)
	if combat_muted:
		target_volume_db = -80.0
	_enable_looping(new_stream)
	next_player.stream = new_stream
	next_player.volume_db = -80.0
	next_player.play()
	if _music_tween and _music_tween.is_valid():
		_music_tween.kill()
	var old_player := current_music
	_music_tween = create_tween().set_parallel(true)
	if old_player != null:
		_music_tween.tween_property(old_player, "volume_db", -80.0, fade_time)
	_music_tween.tween_property(next_player, "volume_db", target_volume_db, fade_time)
	current_music = next_player
	current_track = new_stream
	if old_player != null:
		var cleanup_tween = create_tween()
		cleanup_tween.tween_interval(fade_time)
		cleanup_tween.tween_callback(old_player.stop)


func _enable_looping(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.data.size() / (stream.format + 1)) if stream.format == AudioStreamWAV.FORMAT_8_BITS else int(stream.data.size() / 2)


# ═══════════════════════════════════════════════════════════════════════
# PROCEDURAL TRACK GENERATION
# ═══════════════════════════════════════════════════════════════════════

func _gen_procedural_menu_track() -> AudioStreamWAV:
	var sample_rate = 22050
	var bpm = 80.0
	var duration = 6.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	var beat_duration = 60.0 / bpm
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0
		# Deep pad drone
		sample += sin(TAU * 55.0 * t) * 0.15
		sample += sin(TAU * 82.5 * t) * 0.08
		# Rhythmic pulse on beat
		var beat_pos = fmod(t, beat_duration) / beat_duration
		var beat_env = exp(-beat_pos * 12.0)
		sample += sin(TAU * 110.0 * t) * 0.12 * beat_env
		# Hi-hat on off-beat
		var half_beat_pos = fmod(t + beat_duration * 0.5, beat_duration) / beat_duration
		var hat_env = exp(-half_beat_pos * 25.0)
		sample += (randf() * 2.0 - 1.0) * 0.06 * hat_env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	return stream


func _gen_procedural_intermission_track() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 8.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0
		# Warm pad
		sample += sin(TAU * 65.0 * t) * 0.12
		sample += sin(TAU * 98.0 * t) * 0.06
		# Slow melody
		var note_freq = 220.0 * pow(2.0, floor(fmod(t * 0.5, 4.0)) / 12.0)
		sample += sin(TAU * note_freq * t) * 0.08 * (0.5 + 0.5 * sin(TAU * 0.25 * t))
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	return stream


func _gen_procedural_hangar_track() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 6.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	var bpm = 90.0
	var beat_duration = 60.0 / bpm
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0
		sample += sin(TAU * 73.4 * t) * 0.1
		var beat_pos = fmod(t, beat_duration) / beat_duration
		var kick = exp(-beat_pos * 15.0)
		sample += sin(TAU * 55.0 * t) * 0.15 * kick
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	return stream


func _gen_procedural_combat_track(category: String) -> AudioStreamWAV:
	var sample_rate = 22050
	var bpm := 140.0
	match category:
		"ace":
			bpm = 160.0
		"boss":
			bpm = 180.0
		_:
			bpm = 140.0
	var duration = 4.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	var beat_duration = 60.0 / bpm
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0
		# Bass
		sample += sin(TAU * 55.0 * t) * 0.18
		# Kick
		var beat_pos = fmod(t, beat_duration) / beat_duration
		var kick = exp(-beat_pos * 18.0)
		sample += sin(TAU * lerp(80.0, 30.0, beat_pos) * t) * 0.2 * kick
		# Snare on 2 and 4
		var half_beat = fmod(t, beat_duration * 0.5) / (beat_duration * 0.5)
		var snare_pos = fmod(t + beat_duration * 0.5, beat_duration) / beat_duration
		var snare = exp(-snare_pos * 20.0)
		sample += (randf() * 2.0 - 1.0) * 0.12 * snare
		# Hi-hat
		var hh_env = exp(-half_beat * 30.0)
		sample += (randf() * 2.0 - 1.0) * 0.05 * hh_env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	return stream
