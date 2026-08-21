class_name SfxManager
extends Node
## -----------------------------------------------------------------------
## SFX MANAGER — sound-effect pool, procedural generation, playback.
##
## Extracted from AudioManager so SFX concerns live in one focused file.
## Composed as a child node of AudioManager; all play_sfx* calls route
## through this manager.
## -----------------------------------------------------------------------

const POOL_SIZE_3D := 16
const POOL_SIZE_2D := 8

## Rate-limit for the metallic armor-hit clank (seconds).
const MECH_HIT_COOLDOWN := 0.06
## Roller-dash pitch range.
const ROLLER_PITCH_MIN := 0.75
const ROLLER_PITCH_MAX := 1.9

var sfx_pool: Array[AudioStreamPlayer3D] = []
var sfx_2d_pool: Array[AudioStreamPlayer] = []
var _sound_cache: Dictionary = {}
var _last_mech_hit_time := -1.0
var _roller_player: AudioStreamPlayer3D = null
var _roller_pitch: float = ROLLER_PITCH_MIN

## Set by AudioManager — when true all SFX play calls are dropped.
var combat_muted: bool = false


# ═══════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════

func setup() -> void:
	_setup_pools()
	_generate_sounds()


func _setup_pools() -> void:
	for i in POOL_SIZE_3D:
		var player = AudioStreamPlayer3D.new()
		player.name = "SFX3D_%d" % i
		player.bus = "SFX"
		player.unit_size = 22.0
		player.max_db = 2.0
		player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(player)
		sfx_pool.append(player)

	for i in POOL_SIZE_2D:
		var player = AudioStreamPlayer.new()
		player.name = "SFX2D_%d" % i
		player.bus = "SFX"
		add_child(player)
		sfx_2d_pool.append(player)


# ═══════════════════════════════════════════════════════════════════════
# SOUND CACHE & GENERATION
# ═══════════════════════════════════════════════════════════════════════

func _generate_sounds() -> void:
	_sound_cache["beam_rifle"] = preload("res://resources/audio/sfx/beam_fire_01.wav")
	_sound_cache["machine_gun"] = preload("res://resources/audio/sfx/machine_gun01.wav")
	_sound_cache["machine_gun_light"] = preload("res://resources/audio/sfx/machine_gun02.wav")
	_sound_cache["missile"] = preload("res://resources/audio/sfx/missile01.wav")
	_sound_cache["shotgun"] = preload("res://resources/audio/sfx/Dense_heavy_combat_s_#1-1782744878871.wav")
	_sound_cache["armor_break"] = _gen_armor_shatter()
	_sound_cache["explosion"] = _gen_war_explosion(0.65, 0.9)
	var ui_click := _load_ui_sound("click")
	_sound_cache["ui_click"] = ui_click if ui_click != null else _gen_tactical_ui_click()
	var ui_confirm := _load_ui_sound("confirm")
	_sound_cache["ui_confirm"] = ui_confirm if ui_confirm != null else _gen_tactical_ui_confirm()
	_sound_cache["mech_register"] = _gen_mech_register()
	var footstep_file: Variant = _load_sfx_file("footstep")
	_sound_cache["footstep"] = footstep_file if footstep_file != null else _gen_mech_footstep()
	var actuator := _gen_actuator()
	_sound_cache["dash"] = actuator
	_sound_cache["mecha_actuator"] = actuator
	_sound_cache["jump"] = _gen_mech_jump()
	_sound_cache["land"] = _gen_mech_land()
	_sound_cache["roller_skate"] = _gen_roller_skate_grunt()
	var roller_file: Variant = _load_sfx_file("roller_dash")
	_sound_cache["roller_dash"] = roller_file if roller_file != null else _gen_roller_loop()
	_sound_cache["reload_complete"] = _gen_heavy_reload_complete()
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
		_gen_crack(0.08, 0.6),
		_gen_crack(0.07, 0.55),
		_gen_crack(0.09, 0.65),
	]
	_sound_cache["explosive_hit"] = [
		_gen_war_explosion(0.45, 0.75),
		_gen_war_explosion(0.5, 0.8),
		_gen_war_explosion(0.42, 0.7),
	]
	_sound_cache["melee"] = [
		_gen_sine_chop(400.0, 0.08, 0.3),
		preload("res://resources/audio/sfx/melee_hit02.wav"),
		preload("res://resources/audio/sfx/melee_hit01.wav"),
	]
	_sound_cache["fist_swing"] = _gen_fist_swing()
	_sound_cache["fist_thud"] = _gen_fist_thud()
	_sound_cache["knife_swing"] = _gen_knife_swing()
	_sound_cache["knife_hit"] = _gen_knife_hit()
	_sound_cache["blade_swing"] = _gen_blade_swing()
	_sound_cache["blade_ring"] = _gen_blade_ring()
	_sound_cache["enemy_melee_swing"] = _gen_enemy_melee_swing()
	_sound_cache["pile_bunker_fire"] = _gen_pile_bunker_fire()
	_sound_cache["pile_bunker_hit"] = _gen_pile_bunker_hit()
	_sound_cache["shield_block"] = [
		_gen_shield_block(1520.0),
		_gen_shield_block(1180.0),
		_gen_shield_block(1860.0),
	]
	_sound_cache["shield_break"] = _gen_shield_break()
	_sound_cache["enemy_retreat"] = _gen_retreat_alert()
	_sound_cache["enemy_warning"] = [
		_gen_sine_sweep(600.0, 1100.0, 0.28, 0.35),
		_gen_sine_sweep(640.0, 1180.0, 0.26, 0.32),
		_gen_sine_sweep(580.0, 1050.0, 0.3, 0.38),
	]
	_sound_cache["player_hit"] = [
		_gen_crack(0.07, 0.5),
		_gen_crack(0.06, 0.45),
		_gen_crack(0.08, 0.55),
	]
	var mech_hit := _gen_mech_armor_hit()
	_sound_cache["mech_armor_hit"] = [
		mech_hit,
		_gen_pitch_variant(mech_hit, 0.82),
		_gen_pitch_variant(mech_hit, 1.2),
	]


# ═══════════════════════════════════════════════════════════════════════
# FILE LOADING HELPERS
# ═══════════════════════════════════════════════════════════════════════

func _load_ui_sound(base_name: String) -> AudioStream:
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


## Loads a sound (or all its numbered variants) from resources/audio/sfx.
## Variants follow the pattern "<name>.<ext>" plus optional numbered copies
## like "footstep_2.wav", "footstep03.ogg" — when several exist they are
## returned as an Array so playback randomly rotates through them.
func _load_sfx_file(base_name: String) -> Variant:
	var variants := _load_sfx_variants(base_name)
	if variants.is_empty():
		return null
	return variants[0] if variants.size() == 1 else variants


func _load_sfx_variants(base_name: String) -> Array:
	var dir_path := "res://resources/audio/sfx"
	var found: Dictionary = {}
	if not DirAccess.dir_exists_absolute(dir_path):
		return []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var ext := file_name.get_extension().to_lower()
			var index := _variant_index(file_name.get_basename(), base_name)
			if index >= 0 and ext in ["wav", "ogg", "mp3"] and not found.has(index):
				var stream := load(dir_path.path_join(file_name)) as AudioStream
				if stream != null:
					found[index] = stream
		file_name = dir.get_next()
	var streams: Array = []
	var indexes := found.keys()
	indexes.sort()
	for index in indexes:
		streams.append(found[index])
	return streams


static func _variant_index(file_base: String, base_name: String) -> int:
	var f := file_base.to_lower()
	var b := base_name.to_lower()
	if f == b:
		return 0
	if not f.begins_with(b):
		return -1
	var suffix := f.substr(b.length())
	if not suffix.is_empty() and suffix[0] in ["_", "-"]:
		suffix = suffix.substr(1)
	if suffix.is_valid_int():
		return maxi(1, int(suffix))
	return -1


# ═══════════════════════════════════════════════════════════════════════
# PLAYER POOL
# ═══════════════════════════════════════════════════════════════════════

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


# ═══════════════════════════════════════════════════════════════════════
# PLAYBACK
# ═══════════════════════════════════════════════════════════════════════

func _pick_stream(sound_name: String) -> AudioStream:
	if not _sound_cache.has(sound_name):
		return null
	var entry = _sound_cache[sound_name]
	if entry is Array and not entry.is_empty():
		return entry[randi() % entry.size()]
	return entry


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
		0: play_sfx("beam_rifle", pos, -2.0)
		1: play_sfx("machine_gun", pos, -2.5)
		2: play_sfx("missile", pos, -1.0)
		3: play_sfx("shotgun", pos, -0.5)
		4: play_sfx("melee", pos, 0.0)


func play_weapon_sfx_with_override(weapon: WeaponPart, pos: Vector3) -> void:
	if combat_muted:
		return
	if weapon != null and weapon.fire_sfx != null:
		var player = _get_free_3d_player()
		if player == null:
			return
		player.stream = weapon.fire_sfx
		player.global_position = pos
		player.volume_db = -1.5
		player.bus = "SFX"
		player.play()
	elif weapon != null and weapon.weapon_type == WeaponPart.WeaponType.MACHINE_GUN:
		var wname := weapon.weapon_name.to_lower()
		if weapon.damage <= 4.5 or wname.contains("light") or wname.contains("gatling"):
			play_sfx("machine_gun_light", pos, -2.0)
		else:
			play_sfx("machine_gun", pos, -2.5)
	elif weapon != null:
		play_weapon_sfx(weapon.weapon_type, pos)


func play_impact(pos: Vector3) -> void:
	play_sfx("impact", pos, -1.0)


func play_mech_hit(pos: Vector3, volume_db: float = 0.0) -> void:
	if combat_muted:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_mech_hit_time < MECH_HIT_COOLDOWN:
		return
	_last_mech_hit_time = now
	play_sfx("mech_armor_hit", pos, volume_db, "SFX", 0.06)


func play_pile_bunker_fire(pos: Vector3) -> void:
	play_sfx("pile_bunker_fire", pos, 0.5)


func play_pile_bunker_hit(pos: Vector3) -> void:
	play_sfx("pile_bunker_hit", pos, 0.5)


func play_melee_swing(weapon: WeaponPart, pos: Vector3) -> void:
	play_sfx(_melee_sfx_name(weapon, false), pos, 1.0)


func play_melee_hit(weapon: WeaponPart, pos: Vector3) -> void:
	play_sfx(_melee_sfx_name(weapon, true), pos, 1.0)


func play_enemy_melee_swing(pos: Vector3) -> void:
	play_sfx("enemy_melee_swing", pos, 0.0)


func play_ally_melee_swing(pos: Vector3) -> void:
	play_sfx("blade_swing", pos, 0.0)


func play_npc_melee_hit(pos: Vector3) -> void:
	play_sfx("melee", pos, 0.0)


func _melee_sfx_name(weapon: WeaponPart, is_hit: bool) -> String:
	var wtype: int = weapon.weapon_type
	if wtype == 4:
		return "fist_thud" if is_hit else "fist_swing"
	if wtype == 5:
		return "knife_hit" if is_hit else "knife_swing"
	if wtype == 6:
		return "blade_ring" if is_hit else "blade_swing"
	return "melee"


func play_armor_break(pos: Vector3) -> void:
	play_sfx("armor_break", pos, 2.0)


func play_shield_block(pos: Vector3) -> void:
	play_sfx("shield_block", pos, 0.0)


func play_shield_break(pos: Vector3) -> void:
	play_sfx("shield_break", pos, 1.0)


func play_explosion(pos: Vector3) -> void:
	play_sfx("explosion", pos, 2.0)


func play_footstep(pos: Vector3) -> void:
	play_sfx("footstep", pos, -8.0, "Movement")


func play_dash(pos: Vector3) -> void:
	play_sfx("dash", pos, -3.0, "Movement")


func play_mecha_actuator(pos: Vector3) -> void:
	play_sfx("mecha_actuator", pos, -3.0, "Movement")


func play_jump(pos: Vector3) -> void:
	play_sfx("jump", pos, -2.0, "Movement")


func play_land(pos: Vector3) -> void:
	play_sfx("land", pos, -2.0, "Movement")


func play_roller_skate(pos: Vector3) -> void:
	play_sfx("roller_skate", pos, -6.0, "Movement")


func play_impact_by_type(damage_type: String, pos: Vector3) -> void:
	match damage_type.to_lower():
		"beam", "energy":
			play_sfx("beam_hit", pos, 1.0)
		"explosive":
			play_sfx("explosive_hit", pos, 3.0)
		"melee":
			play_sfx("melee", pos, 1.5)
		_:
			play_sfx("kinetic_hit", pos, 1.0)


func play_ui_click() -> void:
	play_sfx_2d("ui_click", -5.0, "UI")


func play_enemy_warning(pos: Vector3) -> void:
	play_sfx("enemy_warning", pos, -2.0)


func play_enemy_retreat(pos: Vector3) -> void:
	play_sfx("enemy_retreat", pos, -1.0)


func play_player_hit() -> void:
	play_sfx_2d("player_hit", 0.0, "SFX")


func play_ui_confirm() -> void:
	play_sfx_2d("ui_confirm", 0.0, "UI")


func play_mech_register() -> void:
	play_sfx_2d("mech_register", 0.0, "UI")


func play_reload_start(pos: Vector3 = Vector3.ZERO) -> void:
	play_sfx_2d("ui_click", -3.0, "UI")


func play_reload_complete() -> void:
	play_sfx_2d("reload_complete", 2.0, "UI")


func play_sfx_by_name(sound_name: String, pos: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> void:
	play_sfx(sound_name, pos, volume_db)


# ═══════════════════════════════════════════════════════════════════════
# ROLLER-DASH LOOP
# ═══════════════════════════════════════════════════════════════════════

func _ensure_roller_player() -> AudioStreamPlayer3D:
	if _roller_player == null:
		_roller_player = AudioStreamPlayer3D.new()
		_roller_player.name = "RollerLoop"
		_roller_player.bus = "Movement"
		add_child(_roller_player)
	return _roller_player


func update_roller_dash(pos: Vector3, speed_ratio: float) -> void:
	if combat_muted:
		stop_roller_dash()
		return
	var player := _ensure_roller_player()
	if player.stream == null:
		player.stream = _pick_stream("roller_dash")
	if player.stream == null:
		return
	player.global_position = pos
	var target := lerpf(ROLLER_PITCH_MIN, ROLLER_PITCH_MAX, clampf(speed_ratio, 0.0, 1.0))
	_roller_pitch = lerpf(_roller_pitch, target, 0.25)
	player.pitch_scale = _roller_pitch
	if not player.playing:
		player.play()


func stop_roller_dash() -> void:
	_roller_pitch = ROLLER_PITCH_MIN
	if _roller_player != null and _roller_player.playing:
		_roller_player.stop()


# ═══════════════════════════════════════════════════════════════════════
# PROCEDURAL SOUND GENERATION
# ═══════════════════════════════════════════════════════════════════════

func _gen_sine_sweep(freq_start: float, freq_end: float, duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
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


func _gen_roller_loop() -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := int(0.5 * sample_rate)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t := float(i) / sample_rate
		var win := sin(PI * float(i) / num_samples)
		var hum := sin(TAU * 150.0 * t) * 0.5 + sin(TAU * 300.0 * t) * 0.25
		var hiss := (randf() * 2.0 - 1.0) * win * 0.35
		var sample := (hum * 0.5 + hiss) * 0.5 * 32767
		var val := int(clamp(sample, -32767, 32767))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = num_samples
	return stream


func _gen_noise_burst(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = 1.0 - (t / duration)
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
			var clunk_env = exp(-t * 30.0)
			sample += sin(TAU * lerp(170.0, 40.0, t / 0.12) * t) * 0.55 * clunk_env
			sample += sin(TAU * 740.0 * t) * 0.2 * clunk_env
			sample += (randf() * 2.0 - 1.0) * 0.08 * clunk_env
		elif t < 0.28:
			var p = (t - 0.12) / 0.16
			var sweep_env = sin(PI * p)
			sample += sin(TAU * lerp(200.0, 820.0, p) * t) * 0.3 * sweep_env
			sample += sin(TAU * lerp(100.0, 410.0, p) * t) * 0.12 * sweep_env
		else:
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
		var thump_freq = lerp(115.0, 28.0, t / duration)
		var sample = sin(TAU * thump_freq * t) * 0.7 * envelope
		sample += sin(TAU * 340.0 * t) * 0.3 * attack * exp(-t * 26.0)
		sample += (randf() * 2.0 - 1.0) * 0.1 * envelope
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
		var boom_freq = lerp(120.0, 26.0, t / duration)
		var sample = sin(TAU * boom_freq * t) * 0.75 * envelope
		var clang_env = attack * exp(-t * 6.5)
		sample += sin(TAU * 520.0 * t) * 0.32 * clang_env
		sample += sin(TAU * 1040.0 * t) * 0.16 * clang_env
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


func _gen_fist_swing() -> AudioStreamWAV:
	return _gen_noise_burst(0.1, 0.35)


func _gen_fist_thud() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.18
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 22.0)
		var sample = sin(TAU * lerp(90.0, 35.0, t / duration) * t) * 0.6 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.15 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_knife_swing() -> AudioStreamWAV:
	return _gen_sine_sweep(2200.0, 800.0, 0.08, 0.25)


func _gen_knife_hit() -> AudioStreamWAV:
	return _gen_sine_sweep(3000.0, 600.0, 0.06, 0.35)


func _gen_blade_swing() -> AudioStreamWAV:
	return _gen_sine_sweep(1800.0, 600.0, 0.12, 0.3)


func _gen_blade_ring() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.35
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 7.0)
		var sample = sin(TAU * 1750.0 * t) * 0.4 * envelope
		sample += sin(TAU * 3500.0 * t) * 0.1 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_enemy_melee_swing() -> AudioStreamWAV:
	return _gen_noise_burst(0.15, 0.3)


func _gen_shield_block(ring_freq: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.2
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 18.0)
		var sample = sin(TAU * ring_freq * t) * 0.35 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.1 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_shield_break() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.5
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 8.0)
		var sample = sin(TAU * lerp(2000.0, 200.0, t / duration) * t) * 0.4 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.25 * envelope
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
	if source == null or source.data.is_empty():
		return source
	var new_rate := int(source.mix_rate * pitch_ratio)
	var new_stream := AudioStreamWAV.new()
	new_stream.data = source.data
	new_stream.format = source.format
	new_stream.mix_rate = new_rate
	new_stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return new_stream


func _gen_mech_footstep() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.2
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 18.0)
		var sample = sin(TAU * lerp(80.0, 25.0, t / duration) * t) * 0.5 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.2 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_mech_jump() -> AudioStreamWAV:
	return _gen_sine_sweep(80.0, 400.0, 0.15, 0.4)


func _gen_mech_land() -> AudioStreamWAV:
	return _gen_sine_sweep(400.0, 60.0, 0.2, 0.5)


func _gen_war_explosion(duration: float, volume: float) -> AudioStreamWAV:
	var sample_rate = 22050
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 6.0)
		var sample = sin(TAU * lerp(200.0, 30.0, t / duration) * t) * 0.6 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.3 * envelope
		var val = int(clamp(sample * volume * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_explosion(duration: float, volume: float) -> AudioStreamWAV:
	return _gen_war_explosion(duration, volume)


func _gen_armor_shatter() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.4
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 10.0)
		var sample = sin(TAU * lerp(1200.0, 200.0, t / duration) * t) * 0.3 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.4 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_tactical_ui_click() -> AudioStreamWAV:
	return _gen_sine_tone(880.0, 0.04, 0.15)


func _gen_tactical_ui_confirm() -> AudioStreamWAV:
	return _gen_sine_sweep(660.0, 1320.0, 0.08, 0.2)


func _gen_heavy_reload_complete() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.3
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 12.0)
		var sample = sin(TAU * lerp(400.0, 800.0, t / duration) * t) * 0.3 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.1 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_roller_skate_grunt() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.12
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 20.0)
		var sample = sin(TAU * lerp(120.0, 60.0, t / duration) * t) * 0.4 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.15 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_crack(duration: float, volume: float) -> AudioStreamWAV:
	return _gen_noise_burst(duration, volume)


func _gen_mech_armor_hit() -> AudioStreamWAV:
	var sample_rate = 22050
	var duration = 0.12
	var num_samples = int(duration * sample_rate)
	var data = PackedByteArray()
	data.resize(num_samples * 2)
	for i in range(num_samples):
		var t = float(i) / sample_rate
		var envelope = exp(-t * 25.0)
		var sample = sin(TAU * lerp(2000.0, 800.0, t / duration) * t) * 0.3 * envelope
		sample += (randf() * 2.0 - 1.0) * 0.15 * envelope
		var val = int(clamp(sample * 32767.0, -32767.0, 32767.0))
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _gen_actuator() -> AudioStreamWAV:
	return _gen_sine_sweep(150.0, 50.0, 0.1, 0.35)


func _gen_retreat_alert() -> AudioStreamWAV:
	return _gen_sine_sweep(1100.0, 400.0, 0.3, 0.3)
