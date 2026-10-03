extends Node
## VALKREN INNER FRAME REFERENCE VERIFY (spec 2026-10-03)
##
## Pins the unarmored mechanical-skeleton reference built by
## tools/valkren_innerframe_reference.gd:
##  1. Overall height 4.95 m (~5 m class; production frame is 5.33 m).
##  2. Joint-center spans: shoulders 1.70 m, hips 1.10 m.
##  3. Segment lengths: upper arm 0.95, forearm 1.15, hand 0.40,
##     thigh 1.15, shin 1.45, foot 0.90 x 0.55, head 0.40 x 0.35.
##  4. Seated 180 cm pilot fits the tub (narrower than interior, head
##     below the neck joint); standing pilot is exactly 1.80 m.
##  5. Production mecha_base.tscn pivots are UNCHANGED by the reference
##     (negative constraint: armor/reference never moves joints).

var _fails := 0
var _checks := 0

const InnerFrameRef = preload("res://tools/valkren_innerframe_reference.gd")


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("INNERREF OK: " + name)
	else:
		_fails += 1
		printerr("INNERREF FAIL: " + name)


func _jpos(ref_root: Node3D, jname: String) -> Vector3:
	var j: Node3D = ref_root.get_node_or_null("InnerFrame/" + jname)
	if j == null:
		j = ref_root.find_child(jname, true, false) as Node3D
	if j == null:
		return Vector3(999, 999, 999)
	return j.position


func _ready() -> void:
	await get_tree().process_frame

	var ref_root: Node3D = InnerFrameRef.build()
	add_child(ref_root)
	await get_tree().process_frame

	_test_overall_height(ref_root)
	_test_spans(ref_root)
	_test_segments(ref_root)
	_test_pilot_fit(ref_root)
	_test_production_untouched()

	print("VALKREN_INNERFRAME_REFERENCE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("VALKREN_INNERFRAME_REFERENCE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_VALKREN_INNERFRAME_REFERENCE_TESTS_PASSED")
		get_tree().quit(0)


func _mesh_aabb_world(mi: MeshInstance3D) -> AABB:
	# Full 8-corner transform so rotated members (axles, reclined seat)
	# measure their true world extents instead of their local AABB.
	var a := mi.get_aabb()
	var t := mi.global_transform
	var first := true
	var box := AABB()
	for ix in [a.position.x, a.position.x + a.size.x]:
		for iy in [a.position.y, a.position.y + a.size.y]:
			for iz in [a.position.z, a.position.z + a.size.z]:
				var p: Vector3 = t * Vector3(ix, iy, iz)
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	return box


func _test_overall_height(ref_root: Node3D) -> void:
	var all: Array = []
	_collect(ref_root.get_node_or_null("InnerFrame"), all)
	var lo := 999.0
	var hi := -999.0
	for mi in all:
		var b := _mesh_aabb_world(mi)
		lo = minf(lo, b.position.y)
		hi = maxf(hi, b.position.y + b.size.y)
		if b.position.y + b.size.y > 5.0:
			print("INNERREF TALL: %s top=%.3f" % [String((mi as Node).name), b.position.y + b.size.y])
	var h := hi - lo
	print("INNERREF overall minY=%.3f maxY=%.3f h=%.3f" % [lo, hi, h])
	_check(absf(lo - 0.0) < 0.02, "feet planted at ground (minY %.3f)" % lo)
	_check(absf(h - 4.95) < 0.06, "overall height 4.95 m (got %.3f)" % h)


func _test_spans(ref_root: Node3D) -> void:
	var sl := _jpos(ref_root, "JNT_ShoulderL")
	var sr := _jpos(ref_root, "JNT_ShoulderR")
	_check(sl.x < 900.0 and sr.x < 900.0, "shoulder joints exist")
	var span := absf(sr.x - sl.x)
	_check(absf(span - 1.70) < 0.01, "shoulder span 1.70 m (got %.3f)" % span)
	_check(absf(sl.y - 4.40) < 0.01 and absf(sr.y - 4.40) < 0.01, "shoulders at 4.40 m level")
	var hl := _jpos(ref_root, "JNT_HipL")
	var hr := _jpos(ref_root, "JNT_HipR")
	var hspan := absf(hr.x - hl.x)
	_check(absf(hspan - 1.10) < 0.01, "hip span 1.10 m (got %.3f)" % hspan)
	_check(absf(hl.y - 2.85) < 0.01, "hips at 2.85 m")


func _test_segments(ref_root: Node3D) -> void:
	_check(absf(_jpos(ref_root, "JNT_ShoulderL").y - _jpos(ref_root, "JNT_ElbowL").y - 0.95) < 0.01, "upper arm 0.95 m")
	_check(absf(_jpos(ref_root, "JNT_ElbowL").y - _jpos(ref_root, "JNT_WristL").y - 1.15) < 0.01, "forearm 1.15 m")
	_check(absf(_jpos(ref_root, "JNT_HipL").y - _jpos(ref_root, "JNT_KneeL").y - 1.15) < 0.01, "thigh 1.15 m")
	_check(absf(_jpos(ref_root, "JNT_KneeL").y - _jpos(ref_root, "JNT_AnkleL").y - 1.45) < 0.01, "shin 1.45 m")
	_check(absf(_jpos(ref_root, "JNT_Neck").y - _jpos(ref_root, "JNT_HipL").y - 1.70) < 0.06, "torso hip-neck ~1.70 m")
	var head: MeshInstance3D = ref_root.get_node_or_null("InnerFrame/SensorHead")
	_check(head != null and absf((head.mesh as BoxMesh).size.y - 0.40) < 0.001 and absf((head.mesh as BoxMesh).size.x - 0.35) < 0.001, "head 0.40 x 0.35 m")
	var foot: MeshInstance3D = ref_root.get_node_or_null("InnerFrame/FootBlockL")
	_check(foot != null and absf((foot.mesh as BoxMesh).size.z - 0.90) < 0.001 and absf((foot.mesh as BoxMesh).size.x - 0.55) < 0.001, "foot 0.90 x 0.55 m")
	# mirrored L/R
	_check(_jpos(ref_root, "JNT_ShoulderL").x == -_jpos(ref_root, "JNT_ShoulderR").x, "shoulders mirrored")
	_check(_jpos(ref_root, "JNT_HipL").x == -_jpos(ref_root, "JNT_HipR").x, "hips mirrored")


func _test_pilot_fit(ref_root: Node3D) -> void:
	var top: Node3D = ref_root.get_node_or_null("StandingPilot180/JNT_PilotTop")
	_check(top != null and absf(top.global_position.y - 1.80) < 0.01, "standing pilot exactly 1.80 m")
	var all: Array = []
	_collect(ref_root.get_node_or_null("InnerFrame/Cockpit/SeatedPilot180"), all)
	var lo := 999.0
	var hi := -999.0
	var wid := 0.0
	for mi in all:
		var b := _mesh_aabb_world(mi)
		lo = minf(lo, b.position.y)
		hi = maxf(hi, b.position.y + b.size.y)
		wid = maxf(wid, b.size.x)
	var sitting := hi - lo
	print("INNERREF seated pilot h=%.3f w=%.3f" % [sitting, wid])
	_check(sitting < 1.45, "seated pilot under 1.45 m (got %.3f)" % sitting)
	_check(wid < 0.89, "seated pilot fits tub interior 0.89 m (got %.3f)" % wid)
	_check(hi < _jpos(ref_root, "JNT_Neck").y, "seated head below neck joint")


func _test_production_untouched() -> void:
	# Negative constraint: the reference must never redefine production joints.
	var tscn: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var probe: Node3D = tscn.instantiate()
	_check(absf((probe.get_node_or_null("ArmLeft") as Node3D).position.x + 1.1424) < 0.0001, "production ArmLeft pivot untouched")
	_check(absf((probe.get_node_or_null("LegLeft") as Node3D).position.x + 0.6384) < 0.0001, "production LegLeft pivot untouched")
	_check(absf((probe.get_node_or_null("Body") as Node3D).position.y - 3.841) < 0.0001, "production Body pivot untouched")
	probe.queue_free()


func _collect(n: Node, out: Array) -> void:
	if n == null:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		# Skip faint armor-clearance envelopes in height math.
		if not String(n.name).begins_with("Clear"):
			out.append(n)
	for c in n.get_children():
		_collect(c, out)
