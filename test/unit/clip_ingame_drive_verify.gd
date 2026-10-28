extends Node
## CLIP INGAME DRIVE VERIFY — Controller-driven verification of mecha locomotion and clip retargeting.
##
## Validates:
##  1. mecha_base loads and settles on the floor in procedural idle.
##  2. Driving through the authoritative set_drive_commands(Vector3(0, 0, -1), Vector3.ZERO)
##     activates horizontal velocity > 0.8 m/s and engages the clip-retargeting branch.
##  3. The leg swings cyclically (stride range > 5.0 deg, zero-crossings > 0).
##  4. Armor destruction mid-stride (removing arm_left) preserves leg stride motion without crash.
##  5. Cadence scales with speed (fast run crosses more zero-cadence points than slow run).
##  6. Brief airtime (< 0.3s grace) preserves clip playback without reverting to idle/fall posture.
##  7. Stopping drive commands smoothly returns the mecha to procedural idle.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CLIP_DRIVE OK: " + name)
	else:
		_fails += 1
		printerr("CLIP_DRIVE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads")
	_make_ground()
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var anim = mecha.get_node_or_null("MechaAnimation")
	_check(anim != null, "MechaAnimation exists")
	_check(anim != null and anim.get("clip_retarget") != null, "ClipRetarget attached")
	var retarget = anim.get("clip_retarget") if anim != null else null
	_check(retarget != null and (retarget.has_clip(MechaRig.CLIP_RUN) or retarget.has_clip(MechaRig.CLIP_AI_RUN)), "locomotion clip live on mech")

	# Initialize modular part mesh slots so pivots exist
	var pmm = mecha.get_node_or_null("PartMeshManager")
	if pmm != null:
		for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
			var part := ArmorPart.new()
			part.slot_id = slot
			pmm.initialize_slot(slot, part, false, null)
		await get_tree().process_frame

	var leg: Node3D = mecha.get_node_or_null("LegLeft")
	var arm: Node3D = mecha.get_node_or_null("ArmLeft")
	_check(leg != null and arm != null, "leg/arm pivots present")

	# Settle to ground and verify initial procedural idle posture
	await _settle(mecha)
	for i in range(30):
		await get_tree().physics_frame
	_check(anim.debug_branch == "procedural_idle", "mecha starts in procedural_idle while stationary (got %s)" % anim.debug_branch)

	# 1. Drive forward via authoritative controller interface
	print("--- TEST 1: Forward locomotion drive via set_drive_commands ---")
	var drive_dir := Vector3(0.0, 0.0, -1.0)
	mecha.set_drive_commands(drive_dir, Vector3.ZERO)

	# Allow acceleration (10 frames)
	for i in range(10):
		await get_tree().physics_frame

	var swings: Array = []
	var velocities: Array = []
	var branches: Array = []
	for i in range(120):
		mecha.set_drive_commands(drive_dir, Vector3.ZERO)
		await get_tree().physics_frame
		swings.append(leg.rotation.x)
		velocities.append(Vector2(mecha.velocity.x, mecha.velocity.z).length())
		branches.append(anim.debug_branch)

	var mean_speed: float = _mean_of(velocities)
	var swing_range_deg: float = rad_to_deg(_range_of(swings))
	var crossings: int = _zero_crossings(swings)
	var active_branch: String = branches[branches.size() - 1] if not branches.is_empty() else ""

	_check(mean_speed >= 0.8, "controller drives horizontal velocity above threshold (mean=%.2f m/s)" % mean_speed)
	_check(active_branch.begins_with("clip_"), "animation enters clip branch (branch=%s)" % active_branch)
	_check(swing_range_deg > 5.0, "leg swings during drive (range=%.1f deg)" % swing_range_deg)
	_check(crossings > 0, "stride exhibits cadence crossings (crossings=%d)" % crossings)

	# 2. Limb destruction mid-stride
	print("--- TEST 2: Mid-stride limb destruction ---")
	if pmm != null and pmm.has_method("hide_slot_completely"):
		pmm.hide_slot_completely("arm_left")
	var after_damage_swings: Array = []
	for i in range(60):
		mecha.set_drive_commands(drive_dir, Vector3.ZERO)
		await get_tree().physics_frame
		after_damage_swings.append(leg.rotation.x)
	var after_dmg_range: float = rad_to_deg(_range_of(after_damage_swings))
	_check(after_dmg_range > 5.0, "leg keeps swinging after arm destroyed (range=%.1f deg)" % after_dmg_range)

	# 3. Cadence speed scaling
	print("--- TEST 3: Cadence tracks speed ---")
	mecha.current_speed = 6.0
	var fast_swings: Array = []
	for i in range(90):
		mecha.set_drive_commands(drive_dir, Vector3.ZERO)
		await get_tree().physics_frame
		fast_swings.append(leg.rotation.x)
	var fast_crossings: int = _zero_crossings(fast_swings)

	mecha.current_speed = 2.0
	var slow_swings: Array = []
	for i in range(90):
		mecha.set_drive_commands(drive_dir, Vector3.ZERO)
		await get_tree().physics_frame
		slow_swings.append(leg.rotation.x)
	var slow_crossings: int = _zero_crossings(slow_swings)
	var slow_range: float = rad_to_deg(_range_of(slow_swings))

	_check(fast_crossings > slow_crossings, "cadence tracks speed (fast=%d slow=%d crossings)" % [fast_crossings, slow_crossings])
	_check(slow_range > 3.0, "slow speed still strides (range=%.1f deg)" % slow_range)

	# 4. Dune bump / brief airtime (< 0.3s grace)
	print("--- TEST 4: Dune bump airtime grace ---")
	mecha.current_speed = 6.0
	mecha.position.y += 1.5
	mecha.velocity.y = 1.0
	var bump_swings: Array = []
	var bump_branches: Array = []
	for i in range(16):
		mecha.set_drive_commands(drive_dir, Vector3.ZERO)
		await get_tree().physics_frame
		bump_swings.append(leg.rotation.x)
		bump_branches.append(anim.debug_branch)
	var bump_range: float = rad_to_deg(_range_of(bump_swings))
	var last_bump_branch: String = bump_branches[bump_branches.size() - 1] if not bump_branches.is_empty() else ""
	_check(last_bump_branch.begins_with("clip_"), "airtime grace keeps clip playing (branch=%s)" % last_bump_branch)
	_check(bump_range > 3.0, "leg moves during brief airtime (range=%.1f deg)" % bump_range)

	# 5. Stop command and return to procedural idle
	print("--- TEST 5: Return to idle upon stopping ---")
	mecha.set_drive_commands(Vector3.ZERO, Vector3.ZERO)
	for i in range(30):
		await get_tree().physics_frame
	_check(anim.debug_branch == "procedural_idle", "stops and returns to procedural_idle (branch=%s)" % anim.debug_branch)

	print("CLIP_INGAME_DRIVE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CLIP_INGAME_DRIVE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CLIP_INGAME_DRIVE_TESTS_PASSED")
		get_tree().quit(0)


func _settle(mecha: CharacterBody3D) -> void:
	for i in range(90):
		await get_tree().physics_frame
		if mecha.is_on_floor():
			break


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.0)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _range_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var lo: float = a[0]
	var hi: float = a[0]
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


func _mean_of(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var total := 0.0
	for v in a:
		total += v
	return total / float(a.size())


func _zero_crossings(a: Array) -> int:
	if a.size() < 3:
		return 0
	var mean := _mean_of(a)
	var n := 0
	for i in range(1, a.size()):
		if (a[i - 1] < mean) != (a[i] < mean):
			n += 1
	return n
