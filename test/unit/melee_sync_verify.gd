extends Node
## MELEE SYNC VERIFY — one input = one authoritative attack lifecycle.
##
## Regression for the overlapping-melee bug (instant same-frame damage +
## restartable swing + no hit-window ownership):
##  A. Animator lifecycle (unit): strike/complete fire exactly once per
##     swing from the clip's own arm motion; restart retires the old swing.
##  B. Live wiring on mecha_base: _melee_attack deals NO same-frame damage;
##     the enemy is hit exactly once, after swing start, at strike time;
##     a second swing hits exactly once more; locomotion resumes after.
##  C. Ownership: mid-swing the swing fully owns attack bones; after
##     completion the base owns them again (no snap, no double pose).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("MELEE_SYNC OK: " + name)
	else:
		_fails += 1
		printerr("MELEE_SYNC FAIL: " + name)


class MockEnemy:
	extends Node3D
	var hits: Array = []

	func take_damage_at_point(damage: float, _point: Vector3, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})

	func take_damage(damage: float, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_test_animator_lifecycle()
	await _test_live_wiring()
	print("MELEE_SYNC_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("MELEE_SYNC_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_MELEE_SYNC_TESTS_PASSED")
		get_tree().quit(0)


func _test_animator_lifecycle() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)
	_check(MechaActionAnimator.has_af_clips(), "AF sword clips cached")
	_check(animator.play_af_melee("right", 1), "step 1 starts")
	_check(animator.attack_id == 1, "first swing gets attack_id 1")
	_check(animator.strike_times.size() == 1, "single slash has exactly 1 strike")
	var t0: float = float(animator.strike_times[0])
	_check(t0 > 0.1 and t0 < animator.anim_length, "strike sits mid-swing (t=%.2f len=%.2f)" % [t0, animator.anim_length])

	var strikes := 0
	var strike_at := -1.0
	var completes := 0
	for i in range(240):
		animator.update(1.0 / 60.0)
		if animator.poll_strike():
			strikes += 1
			strike_at = animator.anim_time
		if animator.poll_attack_complete():
			completes += 1
	_check(strikes == 1, "exactly 1 strike per swing (got %d)" % strikes)
	_check(strike_at > 0.1, "strike fires after swing start, never on input frame (t=%.2f)" % strike_at)
	_check(completes == 1, "exactly 1 completion per swing")
	_check(not animator.is_melee_active(), "swing releases ownership when done")
	var snap: Dictionary = animator.telemetry_snapshot()
	_check(snap.get("attack_id") == 1 and snap.get("strikes_total") == 1 and snap.get("strikes_fired") == 1,
		"telemetry reports the finished lifecycle")

	# Combo clip carries one strike per hit of the 3-hit take.
	animator.play_af_melee("right", 2)
	_check(animator.attack_id == 2, "combo swing gets attack_id 2")
	_check(animator.strike_times.size() == animator.strike_times.size() and animator.strike_times.size() >= 1,
		"combo clip exposes its strikes (%d)" % animator.strike_times.size())
	var combo_strikes := 0
	var combo_done := 0
	for i in range(400):
		animator.update(1.0 / 60.0)
		if animator.poll_strike():
			combo_strikes += 1
		if animator.poll_attack_complete():
			combo_done += 1
	_check(combo_strikes == animator.strike_times.size(), "combo fires all its strikes, no more (%d)" % combo_strikes)
	_check(combo_done == 1, "combo completes exactly once")

	# Restart mid-swing retires the old swing: new id, fresh strike budget.
	animator.play_af_melee("right", 1)
	var first_id: int = animator.attack_id
	for i in range(10):
		animator.update(1.0 / 60.0)
	animator.poll_strike()
	animator.play_af_melee("right", 1)
	_check(animator.attack_id == first_id + 1, "restart mints a new attack_id")
	var late_strikes := 0
	var late_done := 0
	for i in range(240):
		animator.update(1.0 / 60.0)
		if animator.poll_strike():
			late_strikes += 1
		if animator.poll_attack_complete():
			late_done += 1
	_check(late_strikes == 1, "restarted swing strikes exactly once (no leftover from retired swing)")
	_check(late_done == 1, "restarted swing completes exactly once")

	# Ownership: mid-swing the swing fully owns the arm; after completion
	# the base owns it again (apply writes nothing at blend 0). Sweep is
	# rest-relative now, so measure peak motion across the whole swing
	# (late-swing deltas settle back near rest by design).
	var joints := _make_joints()
	animator.play_af_melee("right", 1)
	var peak_arm := 0.0
	for i in range(120):
		animator.update(1.0 / 60.0)
		(joints["arm_right"] as Node3D).rotation = Vector3.ZERO
		animator.apply_to_joints(joints, 1.0)
		peak_arm = maxf(peak_arm, absf((joints["arm_right"] as Node3D).rotation.x))
	_check(peak_arm > deg_to_rad(10.0), "mid-swing owns the attack arm (peak %.1f deg)" % rad_to_deg(peak_arm))
	for i in range(240):
		animator.update(1.0 / 60.0)
		animator.poll_strike()
		animator.poll_attack_complete()
	(joints["arm_right"] as Node3D).rotation = Vector3(0.5, 0, 0)
	animator.apply_to_joints(joints, 1.0)
	_check(absf((joints["arm_right"] as Node3D).rotation.x - 0.5) < 0.0001, "after completion the base owns the arm again")


func _test_live_wiring() -> void:
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base loads")
	if mecha_scene == null:
		return
	_make_ground()
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	add_child(mecha)
	var cam := Camera3D.new()
	# High behind, aimed far past the enemy: the center ray must never clip
	# the mech's own capsule (a self-hit would turn dir back toward +Z and
	# face the mech away from the target).
	cam.position = mecha.global_position + Vector3(0, 6.0, 10.0)
	add_child(cam)
	cam.look_at(mecha.global_position + Vector3(0, 1.0, -20.0))
	cam.make_current()
	await get_tree().physics_frame
	await _settle(mecha)
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		wm = Node3D.new()
		wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
		wm.name = "WeaponManager"
		mecha.add_child(wm)
		await get_tree().process_frame
	_check(wm != null, "WeaponManager present")
	var anim = mecha.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator") if anim != null else null
	_check(animator != null, "action animator present")

	var enemy := MockEnemy.new()
	enemy.add_to_group("enemy")
	mecha.add_child(enemy)
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	await get_tree().physics_frame

	var blade := WeaponPart.new()
	blade.weapon_name = "Test Blade"
	blade.weapon_type = WeaponPart.WeaponType.MELEE
	blade.damage = 10.0
	blade.range_distance = 4.0
	blade.impact = 0.0

	# ONE input: no same-frame damage (the old bug), swing starts.
	var start_frame := Engine.get_physics_frames()
	wm._melee_attack("right", blade)
	_check(enemy.hits.is_empty(), "no same-frame damage on input (deferred to strike)")
	_check(animator.is_melee_active(), "swing owns the lifecycle after input")
	var swing_id: int = animator.attack_id

	# Play out the swing through the live physics loop.
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 1, "exactly 1 hit per swing (got %d)" % enemy.hits.size())
	if enemy.hits.size() == 1:
		_check(int(enemy.hits[0]["frame"]) > start_frame + 3, "hit lands after swing start, at strike (f+%d)" % (int(enemy.hits[0]["frame"]) - start_frame))
		_check(float(enemy.hits[0]["damage"]) > 0.0, "hit carries damage")
	_check(not animator.is_melee_active(), "swing released after completion")

	# Second input = second lifecycle, still exactly one hit each.
	animator.last_attack_time_ms = 0
	wm._melee_attack("right", blade)
	_check(animator.attack_id == swing_id + 1, "second input mints a new attack")
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 2, "two swings = two hits, no duplication (got %d)" % enemy.hits.size())

	# Locomotion resumes: drive forward again (120 frames like the ingame
	# cadence checks, so the mech re-accelerates from the post-attack stop)
	# and the legs keep striding with the animator idle. The camera is freed
	# first: with a camera present the player-driven controller decays any
	# test-set velocity toward zero input (same reason clip_ingame runs
	# camera-less), which would park the mech at idle stance.
	cam.queue_free()
	await get_tree().physics_frame
	mecha.velocity = Vector3(0, 0, -6.0)
	var samples: Array = []
	var leg: Node3D = mecha.get_node_or_null("LegLeft")
	var anim2 = mecha.get_node_or_null("MechaAnimation")
	for i in range(120):
		mecha.velocity = Vector3(0, mecha.velocity.y, -6.0)
		await get_tree().physics_frame
		if leg != null:
			samples.append(leg.rotation.x)
	if samples.size() > 2:
		_check(_range_of(samples) > deg_to_rad(2.0), "run resumes after attack (leg range=%.1f deg)" % rad_to_deg(_range_of(samples)))

	await _test_start_conditions(mecha, wm, blade, enemy)
	await _test_rapid_spam(mecha, wm, blade, enemy)
	_test_telemetry_sequence()


## Attacks from idle / walk / sprint stay synchronized: one hit per swing
## at strike time in every locomotion state (camera re-added: _melee_attack
## needs one for its aim ray; the enemy rides the mech so range is constant).
func _test_start_conditions(mecha: CharacterBody3D, wm: Node, blade: WeaponPart, enemy: MockEnemy) -> void:
	# Same self-hit-proof framing as the main camera: high behind, aimed
	# far past the enemy.
	var cam := Camera3D.new()
	cam.position = mecha.global_position + Vector3(0, 6.0, 10.0)
	add_child(cam)
	cam.look_at(mecha.global_position + Vector3(0, 1.0, -20.0))
	cam.make_current()
	await get_tree().physics_frame
	var anim = mecha.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator")
	for speed in [0.0, -3.0, -8.0]:
		enemy.hits.clear()
		animator.last_attack_time_ms = 0
		enemy.global_position = mecha.global_position + Vector3(0, 0, -3.0)
		mecha.velocity = Vector3(0, 0, speed)
		wm._melee_attack("right", blade)
		for i in range(5):
			animator.update(1.0 / 60.0)
		for i in range(150):
			if speed != 0.0:
				mecha.velocity = Vector3(0, mecha.velocity.y, speed)
			await get_tree().physics_frame
		_check(enemy.hits.size() == 1, "attack from speed %.0f hits exactly once (got %d)" % [speed, enemy.hits.size()])
	# Camera stays alive for the spam section below (it needs the aim ray).


## Four inputs inside one windup: four starts, but only the final swing can
## ever strike — no phantom hits, no stacking, combo chaining untouched.
func _test_rapid_spam(mecha: CharacterBody3D, wm: Node, blade: WeaponPart, enemy: MockEnemy) -> void:
	var anim = mecha.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator")
	enemy.hits.clear()
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	var id_before: int = animator.attack_id
	for i in range(4):
		wm._melee_attack("right", blade)
	_check(animator.attack_id == id_before + 4, "four inputs mint four attack starts (combo preserved)")
	var final_strikes: int = animator.strike_times.size()
	for i in range(220):
		await get_tree().physics_frame
	_check(enemy.hits.size() == final_strikes, "spam yields only the final swing's strikes (%d, no phantoms)" % enemy.hits.size())
	for i in range(60):
		await get_tree().physics_frame
	_check(enemy.hits.size() == final_strikes, "no late duplicate hits after completion")


## Full lifecycle telemetry on one swing, in order, exactly once each.
func _test_telemetry_sequence() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)
	var log: Array = []
	animator.play_af_melee("right", 1)
	log.append("start:%d" % animator.attack_id)
	for i in range(240):
		animator.update(1.0 / 60.0)
		while animator.poll_strike():
			log.append("strike:%d" % animator.attack_id)
		if animator.poll_attack_complete():
			log.append("complete:%d" % animator.attack_id)
	_check(log == ["start:1", "strike:1", "complete:1"], "telemetry sequence is exactly start->strike->complete (got %s)" % str(log))


func _make_joints() -> Dictionary:
	var j := {}
	for key in ["head", "body", "arm_left", "arm_right", "forearm_left",
			"forearm_right", "leg_left", "leg_right", "shin_left",
			"shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		add_child(n)
		j[key] = n
	return j


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.0)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _settle(mecha: CharacterBody3D) -> void:
	for i in range(90):
		await get_tree().physics_frame
		if mecha.is_on_floor():
			break


func _range_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var lo: float = a[0]
	var hi: float = a[0]
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo
