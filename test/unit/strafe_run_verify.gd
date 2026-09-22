extends Node
## STRAFE RUN VERIFY — sideways motion must read as running, not shuffling.
##
## Regression for: robot strafes sideways but legs only abduct (roll) with no
## fore-aft stride and arms hang frozen.
##
## Covers:
##  1. calc_strafe_leg math: swing has roll + forward thigh + lift, stance
##     pushes back, knees never hyperextend.
##  2. L/R crossover: phases offset by PI give opposite thigh signs (scissor).
##  3. End-to-end pure strafe: legs gain fore-aft swing (rotation.x), torso
##     banks AND leans forward, arms pump instead of hanging at zero.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("STRAFE_RUN OK: " + name)
	else:
		_fails += 1
		printerr("STRAFE_RUN FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	_test_strafe_math()
	_test_crossover_scissor()
	await _test_pure_strafe_run_pose()
	print("STRAFE_RUN_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("STRAFE_RUN_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_STRAFE_RUN_TESTS_PASSED")
		get_tree().quit(0)


func _test_strafe_math() -> void:
	# Sample off the mid-swing zero-crossing: t=0.75 of swing, t=0.75 of stance.
	var swing_out := MechaWalkingSystem.calc_strafe_leg(PI * 0.75, true)
	_check(swing_out["roll"] > 0.0, "swing abducts outward (roll=%.2f deg)" % rad_to_deg(swing_out["roll"]))
	_check(float(swing_out.get("thigh", 0.0)) > deg_to_rad(10.0), "swing drives thigh forward for crossover (thigh=%.1f deg)" % rad_to_deg(swing_out.get("thigh", 0.0)))
	_check(swing_out["lift"] > 0.1, "swing has step lift (lift=%.3f)" % swing_out["lift"])
	_check(swing_out["shin"] <= 0.001, "swing knee flexes backwards (shin=%.1f deg)" % rad_to_deg(swing_out["shin"]))
	var stance := MechaWalkingSystem.calc_strafe_leg(PI * 1.75, true)
	_check(float(stance.get("thigh", 0.0)) < deg_to_rad(-10.0), "stance pushes thigh back (thigh=%.1f deg)" % rad_to_deg(stance.get("thigh", 0.0)))
	_check(stance["lift"] == 0.0, "stance foot stays planted (lift=0)")


func _test_crossover_scissor() -> void:
	# Same as update_legs: L/R phases offset by PI must alternate fore-aft.
	var left := MechaWalkingSystem.calc_strafe_leg(PI * 0.75, false)
	var right := MechaWalkingSystem.calc_strafe_leg(PI * 0.75 + PI, true)
	var tl: float = left.get("thigh", 0.0)
	var tr: float = right.get("thigh", 0.0)
	_check(signf(tl) != signf(tr), "L/R thighs scissor opposite (L=%.1f R=%.1f deg)" % [rad_to_deg(tl), rad_to_deg(tr)])


func _make_mecha() -> CharacterBody3D:
	var mecha := CharacterBody3D.new()
	add_child(mecha)
	var body := Node3D.new()
	body.name = "Body"
	mecha.add_child(body)
	var head := Node3D.new()
	head.name = "Head"
	mecha.add_child(head)
	var arm_l := Node3D.new()
	arm_l.name = "ArmLeft"
	mecha.add_child(arm_l)
	var fore_l := Node3D.new()
	fore_l.name = "ForearmLeft"
	arm_l.add_child(fore_l)
	var arm_r := Node3D.new()
	arm_r.name = "ArmRight"
	mecha.add_child(arm_r)
	var fore_r := Node3D.new()
	fore_r.name = "ForearmRight"
	arm_r.add_child(fore_r)
	var leg_l := Node3D.new()
	leg_l.name = "LegLeft"
	mecha.add_child(leg_l)
	var shin_l := Node3D.new()
	shin_l.name = "ShinLeft"
	leg_l.add_child(shin_l)
	var leg_r := Node3D.new()
	leg_r.name = "LegRight"
	mecha.add_child(leg_r)
	var shin_r := Node3D.new()
	shin_r.name = "ShinRight"
	leg_r.add_child(shin_r)
	return mecha


func _test_pure_strafe_run_pose() -> void:
	var mecha := _make_mecha()
	var walk := MechaWalkingSystem.new()
	mecha.add_child(walk)
	var joints := MechaWalkingSystem.build_joints(mecha)
	walk.is_moving = true
	walk.bob_timer = 1.2
	mecha.velocity = Vector3(10, 0, 0)
	var max_swing := 0.0
	var max_diff := 0.0
	var max_arm := 0.0
	for i in range(40):
		walk.update_bob(0.05, mecha, joints, 0.15)
		walk.update_legs(0.05, mecha, joints)
		var leg_l: Node3D = joints["leg_left"]
		var leg_r: Node3D = joints["leg_right"]
		max_swing = maxf(max_swing, maxf(absf(leg_l.rotation.x), absf(leg_r.rotation.x)))
		max_diff = maxf(max_diff, absf(leg_l.rotation.x - leg_r.rotation.x))
		var arm_l: Node3D = joints["arm_left"]
		var arm_r: Node3D = joints["arm_right"]
		max_arm = maxf(max_arm, maxf(absf(arm_l.rotation.x), absf(arm_r.rotation.x)))
		await get_tree().process_frame
	var leg_l: Node3D = joints["leg_left"]
	var leg_r: Node3D = joints["leg_right"]
	var body: Node3D = joints["body_mesh"]
	_check(max_swing > deg_to_rad(5.0), "pure strafe strides fore-aft (peak leg swing=%.1f deg)" % rad_to_deg(max_swing))
	_check(max_diff > deg_to_rad(5.0), "L/R legs alternate, not glued together (peak diff=%.1f deg)" % rad_to_deg(max_diff))
	_check(body.rotation.z < 0.0, "torso banks into right strafe (bank=%.1f deg)" % rad_to_deg(body.rotation.z))
	_check(body.rotation.x < 0.0, "torso leans forward driving into strafe-run (pitch=%.1f deg)" % rad_to_deg(body.rotation.x))
	_check(max_arm > deg_to_rad(3.0), "arms pump during strafe-run (peak=%.1f deg)" % rad_to_deg(max_arm))
	mecha.queue_free()
	await get_tree().process_frame
