extends Node
## CLIP RETARGET VERIFY — the cleaned run clip must drive modular pivots.
##
## Covers:
##  1. The run clip exists on the retarget source.
##  2. Over a full loop the legs swing (>10 deg) in L/R antiphase, knees
##     flex, arms pump, and the hip bob moves the body — i.e. the transfer
##     carries real locomotion, not a frozen/T-pose.
##  3. Missing pivots never crash (limb destroyed mid-run stays safe).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CLIP_RETARGET OK: " + name)
	else:
		_fails += 1
		printerr("CLIP_RETARGET FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var retarget := MechaClipRetarget.new()
	add_child(retarget)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(retarget.has_clip(MechaRig.CLIP_RUN), "run clip present on retarget source")
	if not retarget.has_clip(MechaRig.CLIP_RUN):
		get_tree().quit(1)
		return

	var joints := _make_joints()
	retarget.play_clip(MechaRig.CLIP_RUN)

	var leg_l: Array = []
	var leg_r: Array = []
	var shin_l: Array = []
	var arm_l: Array = []
	var body_y: Array = []
	# 4s at 60fps covers several loops of any run cycle.
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

	# Destroyed limb (pivot gone) must not crash the transfer.
	var pruned := _make_joints()
	pruned.erase("leg_left")
	pruned.erase("shin_left")
	pruned.erase("foot_left")
	retarget.advance_and_apply(1.0 / 60.0, pruned, 3.0)
	_check(true, "missing pivots do not crash")

	print("CLIP_RETARGET_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CLIP_RETARGET_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_CLIP_RETARGET_TESTS_PASSED")
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
