extends Node
## GAIT SPEED SYNC VERIFY — gait rate and stride must track ground speed.
## Regression for: run animation churning fast while the mech moves slowly.
## Covers:
##  1. bob_timer advances slower at low speed than at sprint.
##  2. Leg swing amplitude shrinks at low speed (no sprint goose-step).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GAIT_SYNC OK: " + name)
	else:
		_fails += 1
		printerr("GAIT_SYNC FAIL: " + name)


func _make_rig() -> Array:
	var mecha := CharacterBody3D.new()
	add_child(mecha)
	var walk := MechaWalkingSystem.new()
	mecha.add_child(walk)
	var leg_l := Node3D.new()
	leg_l.name = "LegLeft"
	var leg_r := Node3D.new()
	leg_r.name = "LegRight"
	var shin_l := Node3D.new()
	shin_l.name = "ShinLeft"
	var shin_r := Node3D.new()
	shin_r.name = "ShinRight"
	leg_l.add_child(shin_l)
	leg_r.add_child(shin_r)
	mecha.add_child(leg_l)
	mecha.add_child(leg_r)
	var body := Node3D.new()
	body.name = "Body"
	var head := Node3D.new()
	head.name = "Head"
	mecha.add_child(body)
	mecha.add_child(head)
	var joints := MechaWalkingSystem.build_joints(mecha)
	return [mecha, walk, joints]


func _ready() -> void:
	await get_tree().process_frame

	var parts_slow := _make_rig()
	var mecha_s: CharacterBody3D = parts_slow[0]
	var walk_s: MechaWalkingSystem = parts_slow[1]
	var joints_s: Dictionary = parts_slow[2]
	var parts_fast := _make_rig()
	var mecha_f: CharacterBody3D = parts_fast[0]
	var walk_f: MechaWalkingSystem = parts_fast[1]
	var joints_f: Dictionary = parts_fast[2]

	walk_s.is_moving = true
	walk_f.is_moving = true
	mecha_s.velocity = Vector3(0, 0, -1.5)
	mecha_f.velocity = Vector3(0, 0, -10.0)

	var peak_swing_slow := 0.0
	var peak_swing_fast := 0.0
	for i in range(120):
		walk_s.update_bob(0.016, mecha_s, joints_s, 0.15)
		walk_s.update_legs(0.016, mecha_s, joints_s)
		walk_f.update_bob(0.016, mecha_f, joints_f, 0.15)
		walk_f.update_legs(0.016, mecha_f, joints_f)
		var leg_s: Node3D = joints_s["leg_left"]
		var leg_f: Node3D = joints_f["leg_left"]
		peak_swing_slow = maxf(peak_swing_slow, absf(leg_s.rotation.x))
		peak_swing_fast = maxf(peak_swing_fast, absf(leg_f.rotation.x))
		await get_tree().process_frame

	_check(walk_s.bob_timer < walk_f.bob_timer,
		"slow walk advances gait slower (slow=%.2f fast=%.2f)" % [walk_s.bob_timer, walk_f.bob_timer])
	_check(peak_swing_slow < peak_swing_fast,
		"slow walk takes shorter strides (slow=%.1fdeg fast=%.1fdeg)" % [rad_to_deg(peak_swing_slow), rad_to_deg(peak_swing_fast)])
	_check(peak_swing_slow < deg_to_rad(30.0),
		"slow walk never goose-steps (peak=%.1fdeg)" % rad_to_deg(peak_swing_slow))

	mecha_s.queue_free()
	mecha_f.queue_free()
	print("GAIT_SPEED_SYNC_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GAIT_SPEED_SYNC_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_GAIT_SPEED_SYNC_TESTS_PASSED")
		get_tree().quit(0)
