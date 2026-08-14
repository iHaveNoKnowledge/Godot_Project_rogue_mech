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
@export var menu_tracks: Array[AudioStream] = []
@export var intermission_tracks: Array[AudioStream] = []
@export var hangar_tracks: Array[AudioStream] = []
@export var grunt_tracks: Array[AudioStream] = []
@export var ace_tracks: Array[AudioStream] = []
@export var boss_tracks: Array[AudioStream] = []

var music_player_a: AudioStreamPlayer
var music_player_b: AudioStreamPlayer
var current_music: AudioStreamPlayer
var current_music_category: String = ""
var current_track: AudioStream = null

# While true, every battle-related sound (combat music + SFX) is suppressed.
# The combat intro overlay toggles this while the mech drops in from the sky, so
# the loading screen is silent and the battle audio only comes back on reveal.
var combat_muted: bool = false

var _music_tween: Tween = null
var _procedural_music_cache: Dictionary = {}

# Remembers the intermission track (and its playback position) when combat
# music takes over, so returning to the board resumes the SAME song instead of
# restarting a fresh random one every time a turn ends.
var _saved_intermission_track: AudioStream = null
var _saved_intermission_pos: float = 0.0

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
	_sound_cache["beam_rifle"] = preload("res://resources/audio/sfx/beam_fire_01.wav")
	_sound_cache["machine_gun"] = preload("res://resources/audio/sfx/machine_gun01.wav")
	_sound_cache["missile"] = preload("res://resources/audio/sfx/missile01.wav")
	_sound_cache["shotgun"] = preload("res://resources/audio/sfx/Dense_heavy_combat_s_#1-1782744878871.wav")
	_sound_cache["armor_break"] = _gen_crack(0.12, 0.4)
	_sound_cache["explosion"] = _gen_explosion(0.4, 0.6)
	# UI sounds prefer real files dropped in res://resources/audio/ui/ and fall
	# back to procedurally generated tones when no file exists.
	var ui_click := _load_ui_sound("click")
	_sound_cache["ui_click"] = ui_click if ui_click != null else _gen_sine_tone(800.0, 0.05, 0.15)
	var ui_confirm := _load_ui_sound("confirm")
	_sound_cache["ui_confirm"] = ui_confirm if ui_confirm != null else _gen_sine_tone(1200.0, 0.08, 0.2)
	# Distinct celebratory cue for REGISTER: a frame assembles and takes over as
	# the player's piloted mech (assembly clunk -> power-up sweep -> two-note
	# confirm chime), so it reads as an event, not just another button confirm.
	_sound_cache["mech_register"] = _gen_mech_register()
	_sound_cache["footstep"] = _gen_noise_burst(0.04, 0.08)
	_sound_cache["dash"] = _gen_sine_sweep(300.0, 600.0, 0.1, 0.2)
	# New movement & impact SFX
	_sound_cache["jump"] = _gen_sine_sweep(150.0, 450.0, 0.15, 0.25)
	_sound_cache["land"] = _gen_sine_tone(70.0, 0.18, 0.4)
	_sound_cache["roller_skate"] = _gen_sine_sweep(400.0, 250.0, 0.08, 0.15)
	_sound_cache["reload_complete"] = _gen_sine_sweep(1400.0, 1800.0, 0.1, 0.3)

	# Multiple variants per hit: random one is picked each play.
	_sound_cache["impact"] = [
		preload("res://resources/audio/sfx/impact01.wav"),
		_gen_pitch_variant(preload("res://resources/audio/sfx/impact01.wav"), 0.88),
		_gen_pitch_variant(preload("res://resources/audio/sfx/impact01.wav"), 1.14),
	]
	_sound_cache["beam_hit"] = [
		_gen_sine_sweep(1200.0, 300.0, 0.1, 0.3),
		_gen_sine_sweep(1050.0, 260.0, 0.11, 0.3),
		_gen_sine_sweep(1350.0, 340.0, 0.09, 0.28),
	]
	_sound_cache["kinetic_hit"] = [
		_gen_crack(0.06, 0.35),
		_gen_crack(0.05, 0.3),
		_gen_crack(0.07, 0.38),
	]
	_sound_cache["explosive_hit"] = [
		_gen_explosion(0.25, 0.5),
		_gen_explosion(0.3, 0.5),
		_gen_explosion(0.22, 0.46),
	]
	_sound_cache["melee"] = [
		_gen_sine_chop(400.0, 0.08, 0.3),
		preload("res://resources/audio/sfx/melee_hit02.wav"),
		preload("res://resources/audio/sfx/melee_hit01.wav"),
	]
	# Per-weapon melee SFX: a distinct voice per weapon family so a bare-fist
	# thud, a knife slash, and a heat-blade ring each read differently.
	_sound_cache["fist_swing"] = _gen_fist_swing()
	_sound_cache["fist_thud"] = _gen_fist_thud()
	_sound_cache["knife_swing"] = _gen_knife_swing()
	_sound_cache["knife_hit"] = _gen_knife_hit()
	_sound_cache["blade_swing"] = _gen_blade_swing()
	_sound_cache["blade_ring"] = _gen_blade_ring()
	# AI melee attackers have no WeaponPart to dispatch on, so they get their
	# own positional voices: a low brute whoosh for enemy swings, the player's
	# blade voice for ally swings, and the generic melee cache for both on hit.
	_sound_cache["enemy_melee_swing"] = _gen_enemy_melee_swing()
	# Pile Bunker: explosive shell-driven punch
	_sound_cache["pile_bunker_fire"] = _gen_pile_bunker_fire()
	_sound_cache["pile_bunker_hit"] = _gen_pile_bunker_hit()

	# Enemy attack telegraph warning (rising alert) — tells the pilot a hostile
	# mech is about to open fire so they can react before the shot lands.
	_sound_cache["enemy_warning"] = [
		_gen_sine_sweep(600.0, 1100.0, 0.28, 0.35),
		_gen_sine_sweep(640.0, 1180.0, 0.26, 0.32),
		_gen_sine_sweep(580.0, 1050.0, 0.3, 0.38),
	]
	# Direct hit cue when the player's own mech takes damage.
	_sound_cache["player_hit"] = [
		_gen_crack(0.07, 0.5),
		_gen_crack(0.06, 0.45),
		_gen_crack(0.08, 0.55),
	]


# --- Sound Generation Helpers ---

func _load_ui_sound(base_name: String) -> AudioStream:
	# Drop click.wav / click.ogg / click.mp3 (etc.) into res://resources/audio/ui/
	# to override the generated UI tones.
	var dir_path := "res://resources/audio/ui"
	if not DirAccess.dir_exists_absolute(dir_path):
		return null
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return null
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var base := file_name.get_basename()
			if base.to_lower() == base_name.to_lower():
				var ext := file_name.get_extension().to_lower()
				if ext in ["wav", "ogg", "mp3"]:
					var stream := load(dir_path.path_join(file_name)) as AudioStream
					if stream != null:
						return stream
		file_name = dir.get_next()
	return null


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


func _gen_mech_register() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.5
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0
		if t < 0.12:
			# Assembly clunk: falling hydraulic thump + metallic ring + hiss.
			var clunk_env = exp(-t * 30.0)
			sample += sin(TAU * lerp(170.0, 40.0, t / 0.12) * t) * 0.55 * clunk_env
			sample += sin(TAU * 740.0 * t) * 0.2 * clunk_env
			sample += (randf() * 2.0 - 1.0) * 0.08 * clunk_env
		elif t < 0.28:
			# Reactor power-up: rising whine (pilot transfer spools up).
			var p = (t - 0.12) / 0.16
			var sweep_env = sin(PI * p)
			sample += sin(TAU * lerp(200.0, 820.0, p) * t) * 0.3 * sweep_env
			sample += sin(TAU * lerp(100.0, 410.0, p) * t) * 0.12 * sweep_env
		else:
			# Bright two-note confirm chime — the transfer is complete.
			var local = t - 0.28
			var first_note = local < 0.1
			var note := 660.0 if first_note else 990.0
			var local_t: float = local if first_note else (local - 0.1)
			var chime_env = exp(-local_t * 14.0)
			sample += sin(TAU * note * local_t) * 0.28 * chime_env
			sample += sin(TAU * note * 2.0 * local_t) * 0.08 * chime_env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_pile_bunker_fire() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.4
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var attack = minf(t / 0.004, 1.0)
		var envelope = attack * exp(-t * 9.0)
		# Massive sub-bass hydraulic slam with falling pitch — the deepest voice
		# in the melee set so the pile reads as THE heavy weapon.
		var thump_freq = lerp(115.0, 28.0, t / duration)
		var sample = sin(TAU * thump_freq * t) * 0.7 * envelope
		# Mechanical shell-chamber clunk: a mid knock with a hard, sharp attack.
		sample += sin(TAU * 340.0 * t) * 0.3 * attack * exp(-t * 26.0)
		# Hydraulic gas hiss
		sample += (randf() * 2.0 - 1.0) * 0.1 * envelope
		# Deep barrel ring after the slam — 900Hz, lower and slower than the
		# blade's bright 1750Hz ring, so the pile keeps its own register.
		var release = maxf(0.0, (t - 0.18) / 0.22)
		if release > 0.0:
			sample += sin(TAU * 900.0 * t) * 0.2 * release * exp(-(t - 0.18) * 8.0)
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_pile_bunker_hit() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.45
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var attack = minf(t / 0.003, 1.0)
		var envelope = attack * exp(-t * 9.0)
		# Massive sub-boom with falling pitch — the deepest voice in the melee set.
		var boom_freq = lerp(120.0, 26.0, t / duration)
		var sample = sin(TAU * boom_freq * t) * 0.75 * envelope
		# Heavy resonant clang, kept well BELOW the blade's 1750Hz ring: a 520Hz
		# fundamental with a beating 1040Hz overtone that rings out long.
		var clang_env = attack * exp(-t * 6.5)
		sample += sin(TAU * 520.0 * t) * 0.32 * clang_env
		sample += sin(TAU * 1040.0 * t) * 0.16 * clang_env
		# Gritty front-loaded impact noise
		sample += (randf() * 2.0 - 1.0) * 0.2 * attack * exp(-t * 30.0)
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# --- Per-weapon melee SFX generators ---
# Fist swing: a short, soft air-whoosh from a bare-fist punch.
func _gen_fist_swing() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.08
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 30.0)
		var freq = lerp(340.0, 90.0, t / duration)
		var sample = sin(TAU * freq * t) * 0.22 * env
		sample += (randf() * 2.0 - 1.0) * 0.05 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Fist thud: a muffled, low-impact thump when the punch lands.
func _gen_fist_thud() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.14
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var attack = minf(t / 0.004, 1.0)
		var env = attack * exp(-t * 22.0)
		var freq = lerp(130.0, 45.0, t / duration)
		var sample = sin(TAU * freq * t) * 0.55 * env
		sample += sin(TAU * 180.0 * t) * 0.15 * env
		sample += (randf() * 2.0 - 1.0) * 0.06 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Knife swing: a fast, sharp high slash.
func _gen_knife_swing() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.06
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 25.0)
		var freq = lerp(1900.0, 480.0, t / duration)
		var sample = sin(TAU * freq * t) * 0.18 * env
		sample += (randf() * 2.0 - 1.0) * 0.04 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Knife hit: a crisp, bright crack as the blade bites.
func _gen_knife_hit() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.07
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 30.0)
		var sample = (randf() * 2.0 - 1.0) * 0.4 * env
		sample += sin(TAU * 1600.0 * t) * 0.25 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Blade swing: a broad whoosh with a faint metallic ring tail.
func _gen_blade_swing() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.1
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 22.0)
		var freq = lerp(720.0, 210.0, t / duration)
		var sample = sin(TAU * freq * t) * 0.2 * env
		sample += (randf() * 2.0 - 1.0) * 0.05 * env
		var release = maxf(0.0, (t - 0.06) / 0.04)
		if release > 0.0:
			sample += sin(TAU * 2600.0 * t) * 0.08 * release * exp(-(t - 0.06) * 18.0)
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Blade ring: a resonant metallic ring as the blade connects (fundamental +
# bright overtone with a long decay).
func _gen_blade_ring() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.35
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 9.0)
		var sample = sin(TAU * 1750.0 * t) * 0.4 * env
		sample += sin(TAU * 3500.0 * t) * 0.18 * env
		sample += (randf() * 2.0 - 1.0) * 0.03 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


# Enemy melee swing: a low, gritty brute whoosh — clearly heavier than the
# player's voices so an enemy RUSHER reads as a big swipe.
func _gen_enemy_melee_swing() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.16
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var env = exp(-t * 18.0)
		var freq = lerp(260.0, 70.0, t / duration)
		var sample = sin(TAU * freq * t) * 0.3 * env
		sample += (randf() * 2.0 - 1.0) * 0.16 * env
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_pitch_variant(source: AudioStreamWAV, pitch_ratio: float) -> AudioStreamWAV:
	if source == null:
		return null
	var src_data = source.data
	if src_data.size() == 0:
		return source
	var src_count = src_data.size() / 2
	var out_count = int(float(src_count) / pitch_ratio)
	if out_count <= 0:
		return source

	var data = PackedByteArray()
	data.resize(out_count * 2)
	for i in range(out_count):
		var src_index = float(i) * pitch_ratio
		var i0 = int(src_index)
		var frac = src_index - i0
		var i1 = mini(i0 + 1, src_count - 1)
		var s0 = int(src_data[i0 * 2]) | (int(src_data[i0 * 2 + 1]) << 8)
		if s0 >= 0x8000:
			s0 -= 0x10000
		var s1 = int(src_data[i1 * 2]) | (int(src_data[i1 * 2 + 1]) << 8)
		if s1 >= 0x8000:
			s1 -= 0x10000
		var sample = lerpf(s0, s1, frac)
		var val = int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = source.mix_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


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

func _pick_stream(sound_name: String) -> AudioStream:
	if not _sound_cache.has(sound_name):
		return null
	var entry = _sound_cache[sound_name]
	if entry is Array and not entry.is_empty():
		return entry[randi() % entry.size()]
	return entry


## Plays a cached sound. `pitch_jitter` randomizes the pitch in a small band
## (e.g. 0.06 = 94%-106%) so repeated hits don't sound identical; players are
## pooled and reused, so every play resets pitch_scale to 1.0 when not jittering.
func play_sfx(sound_name: String, pos: Vector3 = Vector3.ZERO, volume_db: float = 0.0, bus: String = "SFX", pitch_jitter: float = 0.0) -> void:
	if combat_muted:
		return
	var stream = _pick_stream(sound_name)
	if stream == null:
		return

	var player = _get_free_3d_player()
	if player == null:
		return

	player.stream = stream
	player.global_position = pos
	player.volume_db = volume_db
	player.bus = bus
	if pitch_jitter > 0.0:
		player.pitch_scale = randf_range(maxf(1.0 - pitch_jitter, 0.5), 1.0 + pitch_jitter)
	else:
		player.pitch_scale = 1.0
	player.play()


func play_sfx_2d(sound_name: String, volume_db: float = 0.0, bus: String = "SFX") -> void:
	if combat_muted:
		return
	var stream = _pick_stream(sound_name)
	if stream == null:
		return

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
		1: play_sfx("machine_gun", pos, -8.0)
		2: play_sfx("missile", pos)
		3: play_sfx("shotgun", pos)
		4: play_sfx("melee", pos)


func play_weapon_sfx_with_override(weapon: WeaponPart, pos: Vector3) -> void:
	if combat_muted:
		return
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


func play_pile_bunker_fire(pos: Vector3) -> void:
	play_sfx("pile_bunker_fire", pos, 2.0)


func play_pile_bunker_hit(pos: Vector3) -> void:
	play_sfx("pile_bunker_hit", pos, 2.0)


# Per-weapon melee swing voice: fist whoosh / knife slash / blade whoosh+ring.
# Honors a custom fire_sfx override first (same as play_weapon_sfx_with_override).
# Swing pitch jitters a little more than the hit (rapid knife repeats benefit
# most), so repeated swings don't sound identical.
const MELEE_SWING_PITCH_JITTER: float = 0.06
const MELEE_HIT_PITCH_JITTER: float = 0.05


func play_melee_swing(weapon: WeaponPart, pos: Vector3) -> void:
	if combat_muted:
		return
	if weapon.fire_sfx != null:
		var player = _get_free_3d_player()
		if player == null:
			return
		player.stream = weapon.fire_sfx
		player.global_position = pos
		player.volume_db = 0.0
		player.bus = "SFX"
		player.pitch_scale = randf_range(maxf(1.0 - MELEE_SWING_PITCH_JITTER, 0.5), 1.0 + MELEE_SWING_PITCH_JITTER)
		player.play()
		return
	play_sfx(_melee_sfx_name(weapon, false), pos, 0.0, "SFX", MELEE_SWING_PITCH_JITTER)


# Per-weapon melee hit voice: fist thud / knife crack / blade ring.
func play_melee_hit(weapon: WeaponPart, pos: Vector3) -> void:
	if combat_muted:
		return
	play_sfx(_melee_sfx_name(weapon, true), pos, -1.0, "SFX", MELEE_HIT_PITCH_JITTER)


# Positional melee voices for AI melee attackers (no WeaponPart to dispatch on):
# the enemy RUSHER swings with a low brute whoosh, allies slash with the same
# blade voice as the player, and both play the generic melee hit on a connect.
func play_enemy_melee_swing(pos: Vector3) -> void:
	if combat_muted:
		return
	play_sfx("enemy_melee_swing", pos, -4.0, "SFX", 0.05)


func play_ally_melee_swing(pos: Vector3) -> void:
	if combat_muted:
		return
	play_sfx("blade_swing", pos, -4.0, "SFX", 0.06)


func play_npc_melee_hit(pos: Vector3) -> void:
	if combat_muted:
		return
	play_sfx("melee", pos, -3.0, "SFX", 0.05)


# Maps a melee weapon to its SFX cache key. Exposed for headless tests.
func _melee_sfx_name(weapon: WeaponPart, is_hit: bool) -> String:
	var name := weapon.weapon_name.to_lower() if weapon else ""
	if name.contains("fist"):
		return "fist_thud" if is_hit else "fist_swing"
	if name.contains("knife"):
		return "knife_hit" if is_hit else "knife_swing"
	if name.contains("blade"):
		return "blade_ring" if is_hit else "blade_swing"
	return "melee"


func play_armor_break(pos: Vector3) -> void:
	play_sfx("armor_break", pos, 0.0)


func play_explosion(pos: Vector3) -> void:
	play_sfx("explosion", pos, 3.0)


func play_footstep(pos: Vector3) -> void:
	play_sfx("footstep", pos, -10.0, "Movement")


func play_dash(pos: Vector3) -> void:
	play_sfx("dash", pos, -3.0, "Movement")


func play_jump(pos: Vector3) -> void:
	play_sfx("jump", pos, -4.0, "Movement")


func play_land(pos: Vector3) -> void:
	play_sfx("land", pos, -2.0, "Movement")


func play_roller_skate(pos: Vector3) -> void:
	play_sfx("roller_skate", pos, -6.0, "Movement")


func play_impact_by_type(damage_type: String, pos: Vector3) -> void:
	match damage_type.to_lower():
		"beam", "energy":
			play_sfx("beam_hit", pos, -2.0)
		"explosive":
			play_sfx("explosive_hit", pos, 1.0)
		"melee":
			play_sfx("melee", pos, 0.0)
		_:
			play_sfx("kinetic_hit", pos, -3.0)


func play_ui_click() -> void:
	play_sfx_2d("ui_click", -5.0, "UI")


# Rising alert played on the enemy right as it starts its attack telegraph, so
# the pilot hears the hostile charging up before the shot.
func play_enemy_warning(pos: Vector3) -> void:
	play_sfx("enemy_warning", pos, -2.0)


# Loud, unmistakable cue when the player's mech takes a hit.
func play_player_hit() -> void:
	play_sfx_2d("player_hit", 0.0, "SFX")


func play_ui_confirm() -> void:
	play_sfx_2d("ui_confirm", 0.0, "UI")


# Distinct cue when REGISTER assembles a frame and it becomes the player's
# piloted mech — assembly clunk, power-up sweep, two-note confirm chime.
func play_mech_register() -> void:
	play_sfx_2d("mech_register", 0.0, "UI")


func play_reload_complete() -> void:
	play_sfx_2d("reload_complete", 2.0, "UI")


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(linear, 0.001, 1.0)))


# --- Combat Music & Playlists ---

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


func play_menu_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	if not force_restart and current_music_category == "menu" and current_music.playing:
		return

	# Leaving the board for the menu ends the board session: the next run must
	# start a fresh intermission song, not resume the old run's track.
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
	current_track = stream_to_play
	_crossfade_to_stream(stream_to_play, fade_time)


func play_intermission_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	if not force_restart and current_music_category == "intermission" and current_music.playing:
		return

	_auto_scan_music_folders()

	var stream_to_play: AudioStream = null
	var resume_pos := 0.0
	if _saved_intermission_track != null and not force_restart:
		# Resume the exact track (and position) that was playing when the player
		# left for combat, instead of picking a new random song from the start.
		stream_to_play = _saved_intermission_track
		resume_pos = _saved_intermission_pos
	elif not intermission_tracks.is_empty():
		var available = intermission_tracks.duplicate()
		if available.size() > 1 and current_track != null:
			available.erase(current_track)
		available.shuffle()
		stream_to_play = available[0]
	else:
		if not _procedural_music_cache.has("intermission"):
			_procedural_music_cache["intermission"] = _gen_procedural_intermission_track()
		stream_to_play = _procedural_music_cache["intermission"]

	if stream_to_play == null:
		return

	current_music_category = "intermission"
	current_track = stream_to_play
	_crossfade_to_stream(stream_to_play, fade_time)
	if resume_pos > 0.0:
		current_music.seek(resume_pos)
	_saved_intermission_track = null
	_saved_intermission_pos = 0.0


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
	current_track = stream_to_play
	_crossfade_to_stream(stream_to_play, fade_time)


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

	# The board was playing intermission music: remember where it was so the
	# track keeps flowing when the player returns from combat.
	if current_music_category == "intermission" and current_music.playing:
		_saved_intermission_track = current_track
		_saved_intermission_pos = current_music.get_playback_position()

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


# Mutes/unmutes every battle-related sound while the combat intro overlay is up.
# Combat music keeps playing underneath (so it is already there on reveal) but is
# held at silence, and SFX play calls are dropped entirely until unmuted.
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


func _crossfade_to_stream(new_stream: AudioStream, fade_time: float) -> void:
	var next_player: AudioStreamPlayer = music_player_b if current_music == music_player_a else music_player_a
	var target_volume_db = linear_to_db(music_volume)
	if combat_muted:
		target_volume_db = -80.0

	# Music tracks must loop forever. Imported files (e.g. hangar MP3) usually
	# come in with loop=false, so a track would play once and then go silent.
	_enable_looping(new_stream)

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

		# Deep ambient synth pad
		sample += sin(TAU * 55.0 * t) * 0.3
		sample += sin(TAU * 110.0 * t + sin(t * 0.5)) * 0.15

		# Ambient Sci-Fi arpeggio notes
		var notes = [220.0, 261.63, 329.63, 392.0, 440.0]
		var note_idx = int(t / (beat_duration * 0.5)) % notes.size()
		var sub_beat = fmod(t, beat_duration * 0.5) / (beat_duration * 0.5)
		var env = exp(-sub_beat * 3.0)
		sample += sin(TAU * notes[note_idx] * t) * 0.12 * env

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


func _gen_procedural_intermission_track() -> AudioStreamWAV:
	var sample_rate = 22050
	var bpm = 70.0
	var duration = 6.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var beat_duration = 60.0 / bpm

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0

		# Calm travel drone — softer than the menu, forward-looking.
		sample += sin(TAU * 65.0 * t) * 0.25
		sample += sin(TAU * 130.0 * t + sin(t * 0.4)) * 0.12

		# Sparse planning arpeggio (pentatonic, wide spacing).
		var notes = [196.0, 261.63, 329.63, 392.0, 587.33]
		var note_idx = int(t / (beat_duration * 1.0)) % notes.size()
		var sub_beat = fmod(t, beat_duration * 1.0) / (beat_duration * 1.0)
		if sub_beat < 0.15:
			sample += sin(TAU * notes[note_idx] * t) * 0.14 * exp(-sub_beat * 6.0)

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


func _gen_procedural_hangar_track() -> AudioStreamWAV:
	var sample_rate = 22050
	var bpm = 90.0
	var duration = 5.0
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)

	var beat_duration = 60.0 / bpm

	for i in range(num_samples):
		var t = float(i) / sample_rate
		var sample = 0.0

		# Garage Bass Drone
		sample += sin(TAU * 48.0 * t) * 0.35
		sample += sin(TAU * 96.0 * t + sin(t * 0.8)) * 0.15

		# Workshop Mechanical Chime
		var notes = [196.0, 246.94, 293.66, 392.0]
		var note_idx = int(t / (beat_duration * 1.0)) % notes.size()
		var sub_beat = fmod(t, beat_duration * 1.0) / (beat_duration * 1.0)
		if sub_beat < 0.2:
			sample += sin(TAU * notes[note_idx] * t) * 0.18 * exp(-sub_beat * 8.0)

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
