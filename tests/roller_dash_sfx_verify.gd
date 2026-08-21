extends Node

## Headless verification of the roller-dash pitch-bending SFX:
##   1. AudioManager caches a roller_dash loop (dropped file or generated hum)
##      that wraps forward so it can hum continuously.
##   2. update_roller_dash() plays it on the dedicated roller player and the
##      pitch BENDS up with speed toward ROLLER_PITCH_MAX.
##   3. stop_roller_dash() cuts the loop, and combat_muted suppresses it too.
##   4. A real mecha_controller freed by a scene swap stops the loop via
##      _exit_tree() so no ghost hum keeps looping on the autoload.
## Run: godot --headless --path . res://tests/roller_dash_sfx_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ROLLER_OK: " + name)
	else:
		_fails += 1
		printerr("ROLLER_FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame

	var loop: Variant = AudioManager.sfx._sound_cache.get("roller_dash")
	_check(loop is AudioStream, "roller_dash cache entry is an AudioStream")
	if loop is AudioStreamWAV:
		_check(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD, "generated roller loop wraps (LOOP_FORWARD)")
	_check(AudioManager.has_method("update_roller_dash"), "AudioManager exposes update_roller_dash()")
	_check(AudioManager.has_method("stop_roller_dash"), "AudioManager exposes stop_roller_dash()")

	AudioManager.stop_roller_dash()
	AudioManager.update_roller_dash(Vector3.ZERO, 0.0)
	var p: AudioStreamPlayer3D = AudioManager.sfx._roller_player
	_check(p != null and p.playing, "update_roller_dash starts the dedicated roller loop")
	_check(p != null and p.stream == loop, "roller player uses the roller_dash stream")

	if p != null:
		var slow_pitch := p.pitch_scale
		# Bend it: a handful of fast updates at full speed must glide upward.
		for i in range(12):
			AudioManager.update_roller_dash(Vector3(10, 0, 10), 1.0)
		var fast_pitch := p.pitch_scale
		_check(fast_pitch > slow_pitch, "pitch bends upward with speed (%.2f -> %.2f)" % [slow_pitch, fast_pitch])
		_check(fast_pitch <= AudioManager.ROLLER_PITCH_MAX + 0.01,
			"fast pitch stays at/below ROLLER_PITCH_MAX (%.2f)" % fast_pitch)

	AudioManager.stop_roller_dash()
	_check(p == null or not p.playing, "stop_roller_dash cuts the roller loop")

	# combat_muted suppresses the loop even while rolling.
	AudioManager.combat_muted = true
	AudioManager.update_roller_dash(Vector3.ZERO, 0.8)
	_check(p == null or not p.playing, "combat_muted suppresses the roller loop")
	AudioManager.combat_muted = false

	await _verify_mech_exit_stops_loop()

	print("ROLLER_DASH_SFX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_mech_exit_stops_loop() -> void:
	var mech = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	await get_tree().process_frame
	AudioManager.update_roller_dash(mech.global_position, 0.5)
	var p: AudioStreamPlayer3D = AudioManager.sfx._roller_player
	_check(p != null and p.playing, "roller loop plays while the mech rolls")
	mech.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(p == null or not p.playing, "freeing the mech stops the roller loop (_exit_tree)")