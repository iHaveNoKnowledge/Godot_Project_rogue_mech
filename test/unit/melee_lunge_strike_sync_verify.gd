extends Node
## MELEE LUNGE-STRIKE SYNC VERIFY.
##
## The thrust must complete ON the swing's first strike contact instead of
## finishing (and recovering) before it. Drives the full production path
## (WeaponManager._melee_attack on a live mech), observes the strike itself
## (pending-hit cleared so the live loop cannot consume the edge first),
## and records root displacement per physics frame.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LUNGESYNC OK: " + name)
	else:
		_fails += 1
		printerr("LUNGESYNC FAIL: " + name)


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
	var cam := Camera3D.new()
	cam.position = mech.global_position + Vector3(0, 6.0, 10.0)
	add_child(cam)
	cam.look_at(mech.global_position + Vector3(0, 1.0, -20.0))
	cam.make_current()
	var wm := Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	wm.name = "WeaponManager"
	mech.add_child(wm)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blade: WeaponPart = load("res://resources/mech/stock/weapon_heat_blade.tres")
	var anim = mech.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator")
	_check(animator != null, "action animator present")
	var z0: float = mech.global_position.z
	wm._melee_attack("right", blade)
	# Observe the strike edge ourselves: clear the pending hit so the live
	# per-frame consumer cannot eat it first (single-stepping preserved).
	wm.set("_pending_melee", {})
	var t := 0.0
	var strike_t := -1.0
	var max_fwd := 0.0
	var t_max_fwd := 0.0
	while t < 2.0:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if animator.poll_strike() and strike_t < 0.0:
			strike_t = t
		var fwd: float = z0 - mech.global_position.z
		if fwd > max_fwd:
			max_fwd = fwd
			t_max_fwd = t
	print("LUNGESYNC strike_t=%.3f thrust_end_t=%.3f max_lunge=%.3f" % [strike_t, t_max_fwd, max_fwd])
	_check(strike_t > 0.05, "strike observed on the swing (t=%.3f)" % strike_t)
	# Heat blade: range 5.2, Standard reach 1.6 -> lunge distance 3.6.
	_check(absf(max_fwd - 3.6) < 0.25, "lunge distance preserved (%.3f ~= 3.6)" % max_fwd)
	# Thrust must complete AT contact, not finish-then-recover before it.
	# Legacy fixed timing ended at ~0.12s; strike lands ~0.33s.
	_check(t_max_fwd >= 0.20, "thrust completes at strike phase, not instantly (t=%.3f)" % t_max_fwd)
	_check(absf(t_max_fwd - strike_t) < 0.12, "thrust end coincides with strike (dt=%.3f)" % absf(t_max_fwd - strike_t))
	mech.queue_free()
	cam.queue_free()
	await get_tree().process_frame
	print("MELEE_LUNGE_STRIKE_SYNC_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MELEE_LUNGE_STRIKE_SYNC_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_LUNGE_STRIKE_SYNC_TESTS_PASSED")
		get_tree().quit(0)
