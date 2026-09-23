extends Node
## AF JOG RETARGET VERIFY - the ActionForge-baked jog clip must drive modular pivots.
##
## Covers:
##  1. The af_jog_fwd source loads (MechaRig bone names + clip present).
##  2. Over ~4s the legs swing (>10 deg) in L/R antiphase, knees flex,
##     arms pump, and hip bob moves the body - real locomotion, not frozen.
##  3. The clip loops cleanly (28 baked frames, loop point rejoins).
##  4. Missing pivots never crash.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("AF_JOG OK: " + name)
	else:
		_fails += 1
		printerr("AF_JOG FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var retarget := MechaClipRetarget.new()
	add_child(retarget)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(retarget.has_clip(MechaRig.CLIP_AF_JOG), "af_jog_fwd clip present on retarget source")
	if not retarget.has_clip(MechaRig.CLIP_AF_JOG):
		get_tree().quit(1)
		return

	var joints := _make_joints()
	retarget.play_clip(MechaRig.CLIP_AF_JOG)

	var leg_l: Array = []
	var leg_r: Array = []
	var shin_l: Array = []
	var arm_l: Array = []
	var body_y: Array = []
	for i in range(240):
		retarget.advance_and_apply(1.0 / 60.0, joints, 3.0)
		leg_l.append((joints["leg_left"] as Node3D).rotation.x)
		leg_r.append((joints["leg_right"] as Node3D).rotation.x)
		shin_l.append((joints["shin_left"] as Node3D).rotation.x)
		arm_l.append((joints["arm_left"] as Node3D).rotation.x)
		body_y.append((joints["body"] as Node3D).position.y)

	_check(_all_finite(leg_l) and _all_finite(body_y), "all driven pivots stay finite")
	_check(rad_to_deg(_range_of(leg_l)) > 10.0, "legs swing (L range=%.1f deg)" % rad_to_deg(_range_of(leg_l)))
	_check(rad_to_deg(_range_of(leg_r)) > 10.0, "legs swing (R range=%.1f deg)" % rad_to_deg(_range_of(leg_r)))
	_check(_correlation(leg_l, leg_r) < -0.3, "L/R legs alternate antiphase (corr=%.2f)" % _correlation(leg_l, leg_r))
	_check(rad_to_deg(_range_of(shin_l)) > 10.0, "knees flex (shin range=%.1f deg)" % rad_to_deg(_range_of(shin_l)))
	_check(rad_to_deg(_range_of(arm_l)) > 5.0, "arms pump (range=%.1f deg)" % rad_to_deg(_range_of(arm_l)))
	_check(_range_of(body_y) > 0.005, "hip bob moves body (bob=%.3fm)" % _range_of(body_y))

	# Loop closure: two full loops must rejoin the starting pose.
	var length: float = retarget.player.current_animation_length
	_check(length > 0.5 and length < 2.0, "clip length sane (%.3fs)" % length)
	retarget.advance_and_apply(0.001, joints, 3.0)
	var leg_start: float = (joints["leg_left"] as Node3D).rotation.x
	retarget.advance_and_apply(length, joints, 3.0)
	retarget.advance_and_apply(length, joints, 3.0)
	var leg_end: float = (joints["leg_left"] as Node3D).rotation.x
	_check(absf(wrapf(leg_end - leg_start, -PI, PI)) < deg_to_rad(5.0),
		"loop rejoins (drift=%.2f deg)" % rad_to_deg(absf(wrapf(leg_end - leg_start, -PI, PI))))

	var pruned := _make_joints()
	pruned.erase("leg_left")
	pruned.erase("shin_left")
	pruned.erase("foot_left")
	retarget.advance_and_apply(1.0 / 60.0, pruned, 3.0)
	_check(true, "missing pivots do not crash")

	print("AF_JOG_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("AF_JOG_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_AF_JOG_TESTS_PASSED")
		get_tree().quit(0)


func _make_joints() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var j: Dictionary = {}
	for key in ["head", "body", "arm_left", "arm_right", "forearm_left", "forearm_right",
			"leg_left", "leg_right", "shin_left", "shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		n.name = key
		root.add_child(n)
		j[key] = n
	(j["body"] as Node3D).position.y = 3.0
	return j


func _range_of(a: Array) -> float:
	var lo: float = a[0]
	var hi: float = a[0]
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


func _all_finite(a: Array) -> bool:
	for v in a:
		if not is_finite(v):
			return false
	return true


func _correlation(a: Array, b: Array) -> float:
	var ma := 0.0
	var mb := 0.0
	for v in a:
		ma += v
	for v in b:
		mb += v
	ma /= a.size()
	mb /= b.size()
	var num := 0.0
	var da := 0.0
	var db := 0.0
	for i in range(a.size()):
		num += (a[i] - ma) * (b[i] - mb)
		da += (a[i] - ma) * (a[i] - ma)
		db += (b[i] - mb) * (b[i] - mb)
	if da <= 0.0 or db <= 0.0:
		return 0.0
	return num / sqrt(da * db)