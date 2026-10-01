extends Node

## Verifies the mecha joint/piston actuator SFX contract:
##   - "dash" and "mecha_actuator" resolve to real playable voices,
##   - those voices are NOT the UI click,
##   - play_mecha_actuator() routes through the POSITIONAL 3D pool (a mech body
##     sound) positioned where the mech is, never through the 2D UI pool,
##   - play_dash() routes a positional voice too.
## NOTE: the dash/actuator voice is now a bank of MP3 variants picked at
## random per play, so stream-format and single-stream identity checks from
## the WAV era are gone; the contract tested is the audible/routing one.
## Run: godot --headless --path . res://tests/mecha_actuator_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("ACTUATOR OK: " + name)
	else:
		_fails += 1
		printerr("ACTUATOR FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame

	var am := AudioManager
	_check(am != null, "AudioManager autoload is available")

	# 1. Both movement voices resolve to real streams.
	var actuator: AudioStream = am._pick_stream("mecha_actuator")
	var dash: AudioStream = am._pick_stream("dash")
	_check(actuator != null, "mecha_actuator voice exists")
	_check(dash != null, "dash voice exists")

	# 2. The actuator voice is NOT the UI click sound.
	var ui_click: AudioStream = am._pick_stream("ui_click")
	_check(ui_click != null, "ui_click voice exists")
	_check(actuator != ui_click, "actuator voice is not the UI click stream")

	# 3. play_mecha_actuator routes a voice through the POSITIONAL 3D pool,
	#    positioned where the mech is, and never through the 2D UI pool.
	am.sfx_pool[0].stop()
	am.play_mecha_actuator(Vector3(1, 2, 3))
	var played: AudioStream = am.sfx_pool[0].stream
	_check(played != null, "play_mecha_actuator plays a voice")
	_check(played != ui_click, "played actuator voice is not the UI click")
	_check(am.sfx_pool[0].global_position.distance_to(Vector3(1, 2, 3)) < 0.001,
		"actuator is positioned at the mech")
	var leaked_to_ui := false
	for p in am.sfx_2d_pool:
		if p.playing and p.stream == played:
			leaked_to_ui = true
	_check(not leaked_to_ui, "actuator plays as positional 3D, never through the 2D UI pool")
	am.sfx_pool[0].stop()

	# 4. play_dash routes a positional voice too.
	am.play_dash(Vector3.ZERO)
	_check(am.sfx_pool[0].stream != null, "play_dash plays a voice")
	_check(am.sfx_pool[0].stream != ui_click, "dash voice is not the UI click")
	am.sfx_pool[0].stop()

	print("MECHA_ACTUATOR_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)
