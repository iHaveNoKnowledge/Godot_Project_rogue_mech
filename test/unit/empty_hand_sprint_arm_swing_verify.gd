extends Node
## EMPTY-HAND SPRINT ARM-SWING VERIFY (regression guard).
##
## A live mech (real controller + animation stack, AI sprint command,
## grounded) with truly empty hands must sustain locomotion arm swing, with
## left/right in phase opposition and no weapon layer owning the arms.
## A rifle control proves the test can detect pinning (armed arms hold).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SWING OK: " + name)
	else:
		_fails += 1
		printerr("SWING FAIL: " + name)


func _range_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	return a.max() - a.min()


func _ready() -> void:
	await get_tree().process_frame
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.14)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)
	var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	# Empty-hand GAME state: manager present, both hands null.
	var wm := Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	wm.name = "WeaponManager"
	mech.add_child(wm)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var armL := mech.get_node_or_null("ArmLeft") as Node3D
	var armR := mech.get_node_or_null("ArmRight") as Node3D
	var foreL := mech.get_node_or_null("ArmLeft/ForearmLeft") as Node3D
	var ma = mech.get_node_or_null("MechaAnimation")
	mech.set("cmd_world_direction", Vector3(0, 0, -1))
	await _test_empty_swing(mech, ma, wm, armL, armR, foreL)
	await _test_rifle_control(mech, ma, wm, armL, armR)
	print("EMPTY_HAND_SPRINT_ARM_SWING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("EMPTY_HAND_SPRINT_ARM_SWING_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_EMPTY_HAND_SPRINT_ARM_SWING_TESTS_PASSED")
		get_tree().quit(0)


func _test_empty_swing(mech: CharacterBody3D, ma, wm: Node3D, armL: Node3D, armR: Node3D, foreL: Node3D) -> void:
	wm.set("left_hand", null)
	wm.set("right_hand", null)
	var sL := []
	var sR := []
	for i in range(150):
		await get_tree().physics_frame
		sL.append(armL.rotation.x)
		sR.append(armR.rotation.x)
	_check(_range_of(sL) > 0.25, "empty sprint sustains left arm swing (range %.3f)" % _range_of(sL))
	_check(_range_of(sR) > 0.25, "empty sprint sustains right arm swing (range %.3f)" % _range_of(sR))
	# Phase opposition: demeaned signs disagree most frames.
	var meanL: float = (sL.max() + sL.min()) * 0.5
	var meanR: float = (sR.max() + sR.min()) * 0.5
	var disagree := 0
	for i in range(sL.size()):
		if signf(sL[i] - meanL) != signf(sR[i] - meanR):
			disagree += 1
	_check(float(disagree) / float(sL.size()) > 0.55, "arms alternate in phase opposition (%.0f%%)" % (100.0 * disagree / sL.size()))
	_check(absf(float(ma.get("_handling_l"))) < 0.01 and absf(float(ma.get("_handling_r"))) < 0.01, "no handling layer owns empty-hand arms")
	var fvals := []
	for i in range(30):
		await get_tree().physics_frame
		fvals.append(foreL.rotation.x)
	_check(_range_of(fvals) > 0.03, "forearms participate in swing (range %.3f)" % _range_of(fvals))


func _test_rifle_control(mech: CharacterBody3D, ma, wm: Node3D, armL: Node3D, armR: Node3D) -> void:
	# Control: the same rig MUST pin when armed (guards a vacuous pass).
	var rifle := WeaponPart.new()
	wm.set("right_hand", rifle)
	for i in range(60):
		await get_tree().physics_frame
	_check(absf(rad_to_deg((armR.rotation as Vector3).x) - 57.0) < 4.0, "armed control pins right arm to rifle hold (%.1f deg)" % rad_to_deg((armR.rotation as Vector3).x))
	_check(absf(float(ma.get("_handling_r"))) > 0.9, "handling owns the armed hand")
	mech.queue_free()
	await get_tree().process_frame
