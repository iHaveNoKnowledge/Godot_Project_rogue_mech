extends Node
## FOOT GROUND CONTACT VERIFY (heavy tactical mecha leg pass)
##
## Root causes of the floating feet:
##  1. Nothing ever counter-rotated the Foot: it rigidly followed the shin,
##     so any thigh/shin pitch (idle crouch, gait swing) tilted the sole and
##     lifted heel/toe off the ground. Fixed by ankle compensation in
##     MechaFootIK (foot stays level while the leg articulates above it).
##  2. The idle combat crouch bends the knees with no hip drop, shortening
##     the legs ~0.03 and hovering the feet. Fixed with a matching drop.
##
## Covers:
##  1. ankle_compensation() pure math (flat-foot angles, roll, zero case).
##  2. End-to-end: bent leg + flat ground -> foot converges to level.
##  3. FootIK structure: rays, Foot pivots resolved, enabled by default.
##  4. Proportion guard: torso/body pivot untouched.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("FOOT OK: " + name)
	else:
		_fails += 1
		printerr("FOOT FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_test_compensation_math()
	await _test_end_to_end_leveling()
	await _test_structure()

	print("FOOT_GROUND_CONTACT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("FOOT_GROUND_CONTACT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_FOOT_GROUND_CONTACT_TESTS_PASSED")
		get_tree().quit(0)


# --- 1. pure compensation math ----------------------------------------------

func _test_compensation_math() -> void:
	var c0 := MechaFootIK.ankle_compensation(0.0, 0.0, 0.0, 0.0)
	_check(c0.is_equal_approx(Vector2.ZERO), "straight leg needs no compensation")
	# Idle crouch: thigh +8 deg, shin -18 deg -> ankle must pitch +10 deg.
	var c1 := MechaFootIK.ankle_compensation(deg_to_rad(8.0), deg_to_rad(-18.0), 0.0, 0.0)
	_check(absf(c1.x - deg_to_rad(10.0)) < 0.0001, "crouch pitch compensated (+10 deg, got %.3f)" % rad_to_deg(c1.x))
	_check(absf(c1.y) < 0.0001, "crouch needs no roll compensation")
	# Sprint swing: thigh -55 deg, knee -48 deg -> ankle +103 deg (clamped later).
	var c2 := MechaFootIK.ankle_compensation(deg_to_rad(-55.0), deg_to_rad(-48.0), 0.0, 0.0)
	_check(absf(c2.x - deg_to_rad(103.0)) < 0.01, "swing pitch compensated (+103 deg pre-clamp)")
	# Strafe abduction roll is countered too.
	var c3 := MechaFootIK.ankle_compensation(0.0, 0.0, deg_to_rad(-7.0), 0.0)
	_check(absf(c3.y - deg_to_rad(7.0)) < 0.0001, "stance roll compensated (+7 deg)")


# --- 2. end-to-end foot leveling ---------------------------------------------

func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.14)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _test_end_to_end_leveling() -> void:
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads")
	_make_ground()
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var foot_ik = mecha.get_node_or_null("FootIKSystem")
	_check(foot_ik != null, "FootIKSystem exists")
	if foot_ik == null:
		mecha.queue_free()
		return

	var leg = mecha.get_node_or_null("LegLeft")
	var shin = mecha.get_node_or_null("LegLeft/ShinLeft")
	var foot = mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	_check(leg != null and shin != null and foot != null, "THIGH > SHIN > FOOT chain exists (Leg/Shin/FootLeft)")
	if leg == null or shin == null or foot == null:
		mecha.queue_free()
		return

	# Bend the leg like the idle crouch, keep the mecha level, ground flat.
	leg.rotation = Vector3(deg_to_rad(8.0), 0, 0)
	shin.rotation = Vector3(deg_to_rad(-18.0), 0, 0)
	foot.quaternion = Quaternion.IDENTITY
	foot_ik.ik_weight = 1.0
	# Converge the smoothing slerp (~2 s at 60 fps).
	for i in range(150):
		foot_ik._apply_ankle_alignment(foot, Vector3.UP, 1.0 / 60.0, true, leg, shin)
	# Foot-local pitch must cancel thigh + shin so the sole is level in the
	# mecha frame: foot.x + leg.x + shin.x ~= 0.
	var total: float = foot.rotation.x + leg.rotation.x + shin.rotation.x
	_check(absf(total) < 0.03, "bent leg leaves the sole level (residual %.2f deg)" % rad_to_deg(total))

	# Deep knee bend must clamp inside the mechanical ankle range, never snap.
	leg.rotation = Vector3(deg_to_rad(-55.0), 0, 0)
	shin.rotation = Vector3(deg_to_rad(-48.0), 0, 0)
	for i in range(150):
		foot_ik._apply_ankle_alignment(foot, Vector3.UP, 1.0 / 60.0, true, leg, shin)
	_check(absf(foot.rotation.x) <= deg_to_rad(45.0) + 0.01, "ankle clamps at +-45 deg under deep bend (got %.1f)" % rad_to_deg(foot.rotation.x))

	mecha.queue_free()


# --- 3. structure + proportion guard ------------------------------------------

func _test_structure() -> void:
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_make_ground()
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().physics_frame

	var foot_ik = mecha.get_node_or_null("FootIKSystem")
	_check(foot_ik.enabled, "FootIK enabled by default")
	_check(foot_ik.ray_left != null and foot_ik.ray_right != null, "ground raycasts exist for both feet")
	_check(foot_ik.foot_left != null and foot_ik.foot_right != null, "FootIK resolved both Foot ankle pivots")
	_check(foot_ik.shin_left != null and foot_ik.shin_right != null, "FootIK resolved both shins")
	# Left/right ankle pivots symmetrical.
	var fl = mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	var fr = mecha.get_node_or_null("LegRight/ShinRight/FootRight")
	_check(fl != null and fr != null, "both ankle pivots exist")
	if fl != null and fr != null:
		_check(absf(fl.position.x + fr.position.x) < 0.001 and absf(fl.position.y - fr.position.y) < 0.001, "ankle pivots symmetrical L/R")
	# Proportion guard: torso is the fixed reference (idle stance may ease
	# the hips down ~0.03, so allow that envelope).
	var body = mecha.get_node_or_null("Body")
	_check(body != null and absf(body.position.x) < 0.001 and absf(body.position.z) < 0.001 and body.position.y <= 3.841 and body.position.y >= 3.79, "Body pivot untouched (idle envelope)")

	mecha.queue_free()
