extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running deflect_guard_verify ---")
	await _verify_deflect_guard_mechanics()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_deflect_guard_mechanics() -> void:
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	mecha.add_to_group("mecha")
	add_child(mecha)

	var combat := Node.new()
	combat.name = "MechaCombat"
	combat.set_script(preload("res://scripts/mecha/mecha_combat.gd"))
	mecha.add_child(combat)
	await get_tree().process_frame

	# 1. Idle state
	_check(not combat.is_guarding, "not guarding by default")
	_check(combat.get_guard_damage_mitigation() == 1.0, "normal damage (1.0) when not guarding")

	# 2. Deflect Window (Just Guard)
	combat.start_guard()
	_check(combat.is_guarding, "guard active after start_guard()")
	_check(combat.is_deflect_active(), "deflect window active immediately after raising guard")
	_check(combat.get_guard_damage_mitigation() <= 0.1, "near-zero damage taken during deflect window")

	var deflect_event_fired: bool = false
	var conn = func(_pos: Vector3, _perfect: bool):
		deflect_event_fired = true
	EventBus.deflect_triggered.connect(conn)

	combat.trigger_deflect()
	_check(deflect_event_fired, "deflect_triggered event emitted")
	EventBus.deflect_triggered.disconnect(conn)

	# 3. Sustained Guard (after deflect window passes)
	combat.guard_time = 0.5 # past 0.18s deflect window
	_check(not combat.is_deflect_active(), "deflect window expired after 0.5s")
	_check(is_equal_approx(combat.get_guard_damage_mitigation(), 0.35), "sustained guard provides 65% damage mitigation (factor 0.35)")

	combat.stop_guard()
	_check(not combat.is_guarding, "guard stopped after stop_guard()")

	mecha.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All deflect_guard_verify tests passed.")
		get_tree().quit(0)
	else:
		print("deflect_guard_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
