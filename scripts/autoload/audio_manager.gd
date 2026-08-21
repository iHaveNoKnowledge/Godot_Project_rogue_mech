extends Node
## -----------------------------------------------------------------------
## AUDIO MANAGER — autoload singleton that delegates to focused child nodes.
##
##   AudioManager.sfx   (SfxManager)   — SFX pool, procedural sounds, playback
##   AudioManager.music (MusicManager) — playlists, crossfade, procedural tracks
##
## All existing `AudioManager.play_*()` calls continue to work unchanged.
## New code should prefer the child managers directly.
## -----------------------------------------------------------------------

var sfx: SfxManager
var music: MusicManager

## Shared mute flag — suppresses all battle audio during the intro overlay.
var combat_muted: bool = false

# Volume levels (linear 0.0–1.0), synced to children.
var master_volume: float = 1.0
var sfx_volume: float = 0.8
var music_volume: float = 0.6
var ambient_volume: float = 0.5

const ROLLER_PITCH_MIN := SfxManager.ROLLER_PITCH_MIN
const ROLLER_PITCH_MAX := SfxManager.ROLLER_PITCH_MAX

var current_music_category: String:
	get: return music.current_music_category if music else ""

var current_track: AudioStream:
	get: return music.current_track if music else null


func _ready() -> void:
	_setup_audio_buses()

	# Create child managers.
	sfx = SfxManager.new()
	sfx.name = "SfxManager"
	add_child(sfx)
	sfx.setup()

	music = MusicManager.new()
	music.name = "MusicManager"
	add_child(music)
	music.setup()

	process_mode = Node.PROCESS_MODE_ALWAYS


# ═══════════════════════════════════════════════════════════════════════
# AUDIO BUS SETUP
# ═══════════════════════════════════════════════════════════════════════

func _setup_audio_buses() -> void:
	var sfx_idx := AudioServer.get_bus_index("SFX")
	if sfx_idx == -1:
		AudioServer.add_bus()
		sfx_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_idx, "SFX")
		AudioServer.set_bus_send(sfx_idx, "Master")

	var music_idx := AudioServer.get_bus_index("Music")
	if music_idx == -1:
		AudioServer.add_bus()
		music_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(music_idx, "Music")
		AudioServer.set_bus_send(music_idx, "Master")

	# Attach dynamic compressor to SFX bus for punchy, heavy war sound without squashing peaks.
	var has_compressor := false
	for i in range(AudioServer.get_bus_effect_count(sfx_idx)):
		if AudioServer.get_bus_effect(sfx_idx, i) is AudioEffectCompressor:
			has_compressor = true
			break
	if not has_compressor:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -6.0
		comp.ratio = 2.0
		comp.attack_us = 500.0
		comp.release_ms = 80.0
		comp.gain = 2.0
		AudioServer.add_bus_effect(sfx_idx, comp)

	# Master limiter to prevent clipping on heavy layered explosions.
	var has_limiter := false
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		for i in range(AudioServer.get_bus_effect_count(master_idx)):
			if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
				has_limiter = true
				break
		if not has_limiter:
			var lim := AudioEffectLimiter.new()
			lim.threshold_db = -1.0
			lim.ceiling_db = 0.0
			lim.soft_clip_db = 2.0
			lim.soft_clip_ratio = 10.0
			AudioServer.add_bus_effect(master_idx, lim)

	# Movement bus for footsteps, roller, dash — routed to SFX.
	var mov_idx := AudioServer.get_bus_index("Movement")
	if mov_idx == -1:
		AudioServer.add_bus()
		mov_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(mov_idx, "Movement")
		AudioServer.set_bus_send(mov_idx, "SFX")

	# UI bus for click/confirm tones — routed to SFX.
	var ui_idx := AudioServer.get_bus_index("UI")
	if ui_idx == -1:
		AudioServer.add_bus()
		ui_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(ui_idx, "UI")
		AudioServer.set_bus_send(ui_idx, "SFX")


# ═══════════════════════════════════════════════════════════════════════
# SHARED VOLUME CONTROL
# ═══════════════════════════════════════════════════════════════════════

func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx = AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamp(linear, 0.001, 1.0)))


# ═══════════════════════════════════════════════════════════════════════
# COMBAT MUTE (shared between SFX and Music)
# ═══════════════════════════════════════════════════════════════════════

func set_combat_muted(muted: bool) -> void:
	if combat_muted == muted:
		return
	combat_muted = muted
	sfx.combat_muted = muted
	music.set_combat_muted(muted)


# ═══════════════════════════════════════════════════════════════════════
# DELEGATED SFX CALLS (backward-compatible facade)
# ═══════════════════════════════════════════════════════════════════════

func play_sfx(sound_name: String, pos: Vector3 = Vector3.ZERO, volume_db: float = 0.0, bus: String = "SFX", pitch_jitter: float = 0.0) -> void:
	sfx.play_sfx(sound_name, pos, volume_db, bus, pitch_jitter)

func play_sfx_2d(sound_name: String, volume_db: float = 0.0, bus: String = "SFX") -> void:
	sfx.play_sfx_2d(sound_name, volume_db, bus)

func play_weapon_sfx(weapon_type: int, pos: Vector3) -> void:
	sfx.play_weapon_sfx(weapon_type, pos)

func play_weapon_sfx_with_override(weapon: WeaponPart, pos: Vector3) -> void:
	sfx.play_weapon_sfx_with_override(weapon, pos)

func play_impact(pos: Vector3) -> void:
	sfx.play_impact(pos)

func play_mech_hit(pos: Vector3, volume_db: float = -1.0) -> void:
	sfx.play_mech_hit(pos, volume_db)

func play_pile_bunker_fire(pos: Vector3) -> void:
	sfx.play_pile_bunker_fire(pos)

func play_pile_bunker_hit(pos: Vector3) -> void:
	sfx.play_pile_bunker_hit(pos)

func play_melee_swing(weapon: WeaponPart, pos: Vector3) -> void:
	sfx.play_melee_swing(weapon, pos)

func play_melee_hit(weapon: WeaponPart, pos: Vector3) -> void:
	sfx.play_melee_hit(weapon, pos)

func play_enemy_melee_swing(pos: Vector3) -> void:
	sfx.play_enemy_melee_swing(pos)

func play_ally_melee_swing(pos: Vector3) -> void:
	sfx.play_ally_melee_swing(pos)

func play_npc_melee_hit(pos: Vector3) -> void:
	sfx.play_npc_melee_hit(pos)

func play_armor_break(pos: Vector3) -> void:
	sfx.play_armor_break(pos)

func play_shield_block(pos: Vector3) -> void:
	sfx.play_shield_block(pos)

func play_shield_break(pos: Vector3) -> void:
	sfx.play_shield_break(pos)

func play_explosion(pos: Vector3) -> void:
	sfx.play_explosion(pos)

func play_footstep(pos: Vector3) -> void:
	sfx.play_footstep(pos)

func play_dash(pos: Vector3) -> void:
	sfx.play_dash(pos)

func play_mecha_actuator(pos: Vector3) -> void:
	sfx.play_mecha_actuator(pos)

func play_jump(pos: Vector3) -> void:
	sfx.play_jump(pos)

func play_land(pos: Vector3) -> void:
	sfx.play_land(pos)

func play_roller_skate(pos: Vector3) -> void:
	sfx.play_roller_skate(pos)

func play_impact_by_type(damage_type: String, pos: Vector3) -> void:
	sfx.play_impact_by_type(damage_type, pos)

func play_ui_click() -> void:
	sfx.play_ui_click()

func play_enemy_warning(pos: Vector3) -> void:
	sfx.play_enemy_warning(pos)

func play_enemy_retreat(pos: Vector3) -> void:
	sfx.play_enemy_retreat(pos)

func play_player_hit() -> void:
	sfx.play_player_hit()

func play_ui_confirm() -> void:
	sfx.play_ui_confirm()

func play_mech_register() -> void:
	sfx.play_mech_register()

func play_reload_start(pos: Vector3 = Vector3.ZERO) -> void:
	sfx.play_reload_start(pos)

func play_reload_complete() -> void:
	sfx.play_reload_complete()

func play_sfx_by_name(sound_name: String, pos: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> void:
	sfx.play_sfx_by_name(sound_name, pos, volume_db)

func update_roller_dash(pos: Vector3, speed_ratio: float) -> void:
	sfx.update_roller_dash(pos, speed_ratio)

func stop_roller_dash() -> void:
	sfx.stop_roller_dash()


# ═══════════════════════════════════════════════════════════════════════
# DELEGATED MUSIC CALLS (backward-compatible facade)
# ═══════════════════════════════════════════════════════════════════════

func play_menu_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	music.play_menu_music(fade_time, force_restart)

func play_intermission_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	music.play_intermission_music(fade_time, force_restart)

func play_hangar_music(fade_time: float = 1.5, force_restart: bool = false) -> void:
	music.play_hangar_music(fade_time, force_restart)

func play_combat_music(category: String, fade_time: float = 1.5, force_restart: bool = false) -> void:
	music.play_combat_music(category, fade_time, force_restart)

func stop_music(fade_time: float = 1.0) -> void:
	music.stop_music(fade_time)


# ═══════════════════════════════════════════════════════════════════════
# TEST & COMPATIBILITY HELPERS
# ═══════════════════════════════════════════════════════════════════════

var sfx_pool: Array[AudioStreamPlayer3D]:
	get: return sfx.sfx_pool if sfx else []

var sfx_2d_pool: Array[AudioStreamPlayer]:
	get: return sfx.sfx_2d_pool if sfx else []

func _pick_stream(sound_name: String) -> AudioStream:
	return sfx._pick_stream(sound_name) if sfx else null

func _get_free_3d_player() -> AudioStreamPlayer3D:
	return sfx._get_free_3d_player() if sfx else null

func _get_free_2d_player() -> AudioStreamPlayer:
	return sfx._get_free_2d_player() if sfx else null
