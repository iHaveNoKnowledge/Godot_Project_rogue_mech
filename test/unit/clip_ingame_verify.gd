extends Node
## CLIP INGAME VERIFY — ai_run drives the real mecha_base with meshes on.
##
## Covers end-to-end (beyond pivot-only unit tests):
##  1. mecha_base builds with ClipRetarget holding the ai_run clip.
##  2. A mech moving on the floor actually swings its LegLeft pivot.
##  3. Destroying a limb mid-run never crashes and the rest keeps moving.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CLIP_INGAME OK: " + name)
	else:
		_fails += 1
		printerr("CLIP_INGAME FAIL: " + name)


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
	_check(retarget != null and retarget.has_clip(MechaRig.CLIP_AI_RUN), "ai_run clip live on mech")

	# Bare inner frames (procedural) so pivots exist with real child meshes.
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

	# Let it land, then drive it forward while sampling the leg.
	await _settle(mecha)
	var swings: Array = []
	for i in range(120):
		mecha.velocity = Vector3(0, mecha.velocity.y, -6.0)
		await get_tree().physics_frame
		swings.append(leg.rotation.x)
	_check(_range_of(swings) > deg_to_rad(5.0), "mech leg swings on the move (range=%.1f deg)" % rad_to_deg(_range_of(swings)))

	# Blow the arm off mid-run: must not crash, leg keeps swinging.
	if pmm != null and pmm.has_method("hide_slot_completely"):
		pmm.hide_slot_completely("arm_left")
	var after: Array = []
	for i in range(60):
		mecha.velocity = Vector3(0, mecha.velocity.y, -6.0)
		await get_tree().physics_frame
		after.append(leg.rotation.x)
	_check(_range_of(after) > deg_to_rad(5.0), "leg keeps moving after arm destroyed (range=%.1f deg)" % rad_to_deg(_range_of(after)))

	# Dune bump: brief airtime (< grace) must NOT snap to the static fall
	# pose — the run clip carries over the bump.
	mecha.position.y += 1.5
	mecha.velocity = Vector3(0, 1.0, -6.0)
	var bump: Array = []
	for i in range(10):
		await get_tree().physics_frame
		bump.append(leg.rotation.x)
	_check(_range_of(bump) > deg_to_rad(3.0), "run survives brief airtime (range=%.1f deg)" % rad_to_deg(_range_of(bump)))

	print("CLIP_INGAME_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CLIP_INGAME_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CLIP_INGAME_TESTS_PASSED")
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
