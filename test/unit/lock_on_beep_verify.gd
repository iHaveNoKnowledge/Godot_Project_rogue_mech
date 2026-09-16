extends Node
## LOCK-ON BEEP VERIFY — MissileLockOnSystem calls
## AudioManager.play_lock_on_beep(stack), which crashed with
## "Nonexistent function 'play_lock_on_beep' in base 'Node'".
## Asserts the facade delegate exists, runs without error, and the
## ComfyUI-generated file is picked over the procedural fallback.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BEEP OK: " + name)
	else:
		_fails += 1
		printerr("BEEP FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	var mgr = load("res://scripts/autoload/audio_manager.gd").new()
	add_child(mgr)
	await get_tree().process_frame

	_check(mgr.has_method("play_lock_on_beep"), "AudioManager delegates play_lock_on_beep")
	# The exact crashing call shape from missile_lock_on_system.gd:149.
	mgr.play_lock_on_beep(1)
	mgr.play_lock_on_beep(5)
	mgr.play_lock_on_beep(8)
	await get_tree().process_frame
	_check(true, "play_lock_on_beep runs without error for stacks 1/5/8")

	var picked = mgr._pick_stream("lock_on_beep")
	_check(picked != null, "lock_on_beep stream cached")
	if picked:
		_check("lock_on_beep" in picked.resource_path, "ComfyUI file picked over procedural fallback (%s)" % picked.resource_path)

	mgr.queue_free()
	print("LOCKON_BEEP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("LOCKON_BEEP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_LOCKON_BEEP_TESTS_PASSED")
		get_tree().quit(0)
