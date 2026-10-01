extends Node3D

## Standing Posture & Stance verify.
## Uses counted checks + exit code (never bare assert(), which is stripped
## in release builds and aborts without accounting).
## Environment per the hatch_piston_kneel_verify convention: a static ground
## the mech can fall onto (FootIK needs a floor to plant feet), physics-frame
## settling, and an explicit set_kneeling(false) — the occupancy wiring kneels
## any empty mech, which would otherwise override every stance under test.
## Expectations follow the CURRENT pose tables in mecha_animation.gd
## (_update_combat_idle_posture), not the pre-d01b964 26deg crouch.

var _checks := 0
var _fails := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("POSTURE OK: " + name)
	else:
		_fails += 1
		printerr("POSTURE FAIL: " + name)


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 3, 120)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)


func _settle(anim: Node, mode: String, frames: int) -> void:
	anim.set_stance_mode(mode)
	for i in range(frames):
		await get_tree().process_frame


func _report(tag: String, leg_l: Node3D, shin_l: Node3D, body: Node3D, foot_l: Node3D) -> void:
	print("%s Measurements:" % tag)
	print("  - Thigh Pitch (local): %.2f deg" % rad_to_deg(leg_l.rotation.x))
	print("  - Shin Pitch (local): %.2f deg" % rad_to_deg(shin_l.rotation.x))
	print("  - Shin Pitch (global): %.2f deg" % rad_to_deg(shin_l.global_rotation.x))
	print("  - Body Tilt: %.2f deg" % rad_to_deg(body.rotation.x))
	print("  - Foot Pitch (global): %.2f deg" % rad_to_deg(foot_l.global_rotation.x))


func _ready() -> void:
	print("--- BEGIN TEST: Standing Posture & Stance Verify ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loadable")
	if mecha_scene == null:
		_finish()
		return

	_make_ground()
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	mecha.position = Vector3(0, 10, 0)
	add_child(mecha)

	# Let the mech fall onto the ground so FootIK has a floor.
	var frames := 0
	while not mecha.is_on_floor() and frames < 180:
		await get_tree().physics_frame
		frames += 1
	_check(mecha.is_on_floor(), "mech landed on the ground")

	var anim = mecha.get_node_or_null("MechaAnimation")
	_check(anim != null, "MechaAnimation node exists")

	var leg_l = mecha.get_node_or_null("LegLeft")
	var shin_l = mecha.get_node_or_null("LegLeft/ShinLeft")
	var body = mecha.get_node_or_null("Body")
	var foot_l = mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	_check(leg_l != null and shin_l != null and body != null and foot_l != null,
		"Limb nodes exist (LegLeft/ShinLeft/Body/FootLeft)")

	if anim == null or leg_l == null or shin_l == null or body == null or foot_l == null:
		_finish()
		return

	# An unoccupied test mech kneels by default (occupancy wiring); standing
	# posture tests need the kneel cleared or it overrides every stance.
	anim.set_kneeling(false)

	# 1. Combat Crouch (default stance): Kenbu hero pose — slight torso
	#    forward lean, mild knee bend, feet planted flat by FootIK.
	await _settle(anim, "combat_crouch", 120)
	_report("Combat Crouch", leg_l, shin_l, body, foot_l)
	_check(absf(rad_to_deg(leg_l.rotation.x) - 8.0) < 2.0, "Combat crouch thigh mild bend (~8 deg)")
	_check(absf(rad_to_deg(shin_l.rotation.x) + 18.0) < 2.0, "Combat crouch shin counter-fold (~-18 deg)")
	_check(absf(rad_to_deg(body.rotation.x) + 4.0) < 1.5, "Combat crouch torso slight forward lean (~-4 deg)")
	_check(absf(rad_to_deg(foot_l.global_rotation.x)) < 6.0, "Combat crouch foot planted flat")

	# 2. Upright Formal: parade stance — everything vertical.
	await _settle(anim, "upright_formal", 120)
	_report("Upright Formal", leg_l, shin_l, body, foot_l)
	_check(absf(rad_to_deg(leg_l.rotation.x)) < 1.0, "Upright formal thigh vertical")
	_check(absf(rad_to_deg(shin_l.rotation.x)) < 1.0, "Upright formal shin vertical")
	_check(absf(rad_to_deg(body.rotation.x)) < 1.0, "Upright formal body vertical")
	_check(absf(rad_to_deg(foot_l.global_rotation.x)) < 6.0, "Upright formal foot planted flat")

	# 3. Wide Squat: heavy siege stance — deep symmetric bend with a
	#    deliberate -3 deg torso lean (by design in the pose table).
	await _settle(anim, "wide_squat", 120)
	_report("Wide Squat", leg_l, shin_l, body, foot_l)
	_check(absf(rad_to_deg(leg_l.rotation.x) - 32.0) < 2.0, "Wide squat thigh deep bend (~32 deg)")
	_check(absf(rad_to_deg(shin_l.rotation.x) + 32.0) < 2.0, "Wide squat shin counter-fold (~-32 deg)")
	_check(absf(rad_to_deg(body.rotation.x) + 3.0) < 1.5, "Wide squat torso siege lean (~-3 deg)")
	_check(absf(rad_to_deg(foot_l.global_rotation.x)) < 6.0, "Wide squat foot planted flat")

	_finish()


func _finish() -> void:
	print("STANDING_POSTURE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("STANDING_POSTURE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("=== ALL STANDING POSTURE VERIFICATION TESTS PASSED (100%) ===")
		get_tree().quit(0)
