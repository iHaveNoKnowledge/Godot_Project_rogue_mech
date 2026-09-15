extends Node

## Headless verification of cockpit hatch open/close SFX:
##   1. AudioManager caches hatch_open + hatch_close streams
##      (dropped files hatch_open/hatch_close.* or procedural fallback).
##   2. play_hatch_open/close exist on AudioManager + SfxManager and
##      actually start a 3D pool player with the cached stream.
##   3. combat_muted suppresses hatch SFX.
##   4. PartMeshManager.set_cockpit_open() triggers the matching hatch
##      sound (open -> hatch_open, close -> hatch_close).
## Run: godot --headless --path . res://tests/hatch_sfx_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("HATCH_OK: " + name)
	else:
		_fails += 1
		printerr("HATCH_FAIL: " + name)


func _player_with(stream: AudioStream) -> AudioStreamPlayer3D:
	for pl in AudioManager.sfx.sfx_pool:
		if pl.playing and pl.stream == stream:
			return pl
	return null


func _ready() -> void:
	await get_tree().process_frame

	var open_stream: Variant = AudioManager.sfx._sound_cache.get("hatch_open")
	var close_stream: Variant = AudioManager.sfx._sound_cache.get("hatch_close")
	_check(open_stream is AudioStream, "hatch_open cache entry is an AudioStream")
	_check(close_stream is AudioStream, "hatch_close cache entry is an AudioStream")
	_check(AudioManager.has_method("play_hatch_open"), "AudioManager exposes play_hatch_open()")
	_check(AudioManager.has_method("play_hatch_close"), "AudioManager exposes play_hatch_close()")
	_check(AudioManager.sfx.has_method("play_hatch_open"), "SfxManager exposes play_hatch_open()")
	_check(AudioManager.sfx.has_method("play_hatch_close"), "SfxManager exposes play_hatch_close()")

	AudioManager.play_hatch_open(Vector3(0, 2, 0))
	await get_tree().process_frame
	_check(_player_with(open_stream) != null, "play_hatch_open starts a 3D player with hatch_open stream")

	AudioManager.play_hatch_close(Vector3(0, 2, 0))
	await get_tree().process_frame
	_check(_player_with(close_stream) != null, "play_hatch_close starts a 3D player with hatch_close stream")

	# combat_muted suppresses hatch SFX.
	for pl in AudioManager.sfx.sfx_pool:
		pl.stop()
	AudioManager.combat_muted = true
	AudioManager.play_hatch_open(Vector3.ZERO)
	await get_tree().process_frame
	_check(_player_with(open_stream) == null, "combat_muted suppresses hatch_open")
	AudioManager.combat_muted = false

	# Wiring: toggling the cockpit plays the matching sound.
	var mecha = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame
	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists on MechaBase")
	if pmm != null:
		pmm.initialize_slot("body", null, false)
		for pl in AudioManager.sfx.sfx_pool:
			pl.stop()
		pmm.set_cockpit_open(true, false)
		await get_tree().process_frame
		_check(_player_with(open_stream) != null, "set_cockpit_open(true) plays hatch_open")
		for pl in AudioManager.sfx.sfx_pool:
			pl.stop()
		pmm.set_cockpit_open(false, false)
		await get_tree().process_frame
		_check(_player_with(close_stream) != null, "set_cockpit_open(false) plays hatch_close")
	mecha.queue_free()

	print("HATCH_SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)
