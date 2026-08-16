extends Node

## Verifies the mecha joint/piston actuator SFX:
##   - the "dash" and "mecha_actuator" cache voices exist as valid non-empty
##     16-bit WAVs and share ONE mechanical stream,
##   - that stream is NOT the UI click (pressing Ctrl/roller in battle must no
##     longer sound like a button click),
##   - the actuator voice is low-frequency machinery (few zero crossings in its
##     tail), clearly distinct from the high 800Hz UI click,
##   - play_dash() and play_mecha_actuator() both route to that stream on the
##     Movement bus, positioned where the mech is.
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

	# 1. Both movement voices exist in the cache.
	_check(am._sound_cache.has("dash"), "cache has the dash voice")
	_check(am._sound_cache.has("mecha_actuator"), "cache has the mecha_actuator voice")

	# 2. They are valid non-empty 16-bit 22050Hz WAVs.
	for key in ["dash", "mecha_actuator"]:
		var stream: AudioStreamWAV = am._sound_cache[key]
		var ok := stream != null and stream.data.size() > 500 and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050
		_check(ok, "%s is a non-empty 16-bit 22050Hz WAV" % key)

	# 3. Dash and roller actuation share ONE mechanical voice.
	_check(am._sound_cache["dash"] == am._sound_cache["mecha_actuator"],
		"dash and mecha_actuator share the same stream")

	# 4. The actuator is NOT the UI click sound.
	var actuator: AudioStreamWAV = am._sound_cache["mecha_actuator"]
	var ui_click: AudioStream = am._sound_cache["ui_click"]
	_check(actuator != ui_click, "actuator voice is not the UI click stream")

	# 5. It is low-frequency machinery: over the decay tail the 800Hz UI click
	#    crosses zero far more often than the actuator's sub-thump.
	var actuator_tail := _zero_crossings(actuator, 0.5, 1.0)
	var click_tail := _zero_crossings(ui_click as AudioStreamWAV, 0.5, 1.0)
	_check(actuator_tail < click_tail * 0.5,
		"actuator rings deeper than the UI click (%d vs %d crossings)" % [actuator_tail, click_tail])

	# 6. play_mecha_actuator routes to the actuator stream through the POSITIONAL
	#    3D pool (a mech body sound), not the 2D pool the UI click uses.
	am.sfx_pool[0].stop()
	am.play_mecha_actuator(Vector3(1, 2, 3))
	_check(am.sfx_pool[0].stream == actuator, "play_mecha_actuator plays the actuator voice")
	_check(am.sfx_pool[0].global_position.distance_to(Vector3(1, 2, 3)) < 0.001,
		"actuator is positioned at the mech")
	var leaked_to_ui := false
	for p in am.sfx_2d_pool:
		if p.playing and p.stream == actuator:
			leaked_to_ui = true
	_check(not leaked_to_ui, "actuator plays as positional 3D, never through the 2D UI pool")
	am.sfx_pool[0].stop()

	# 7. play_dash routes to the same mechanical voice.
	am.play_dash(Vector3.ZERO)
	_check(am.sfx_pool[0].stream == actuator, "play_dash plays the actuator voice too")

	print("MECHA_ACTUATOR_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# Counts zero crossings of a 16-bit WAV stream between two fractions of its
# length — a rough spectral proxy (fewer crossings = lower-frequency content).
func _zero_crossings(stream: AudioStreamWAV, from_frac: float, to_frac: float) -> int:
	if stream == null or stream.data.size() < 32:
		return 0
	var data := stream.data
	var from := int(from_frac * data.size() / 2)
	var to := int(to_frac * data.size() / 2)
	var crossings := 0
	var prev := 0
	for i in range(from, to):
		var v: int = data[i * 2] | (data[i * 2 + 1] << 8)
		if v >= 32768:
			v -= 65536
		if i > from and ((prev < 0 and v >= 0) or (prev >= 0 and v < 0)):
			crossings += 1
		prev = v
	return crossings
