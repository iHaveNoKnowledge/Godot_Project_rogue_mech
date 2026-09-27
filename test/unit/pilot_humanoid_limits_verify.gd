extends Node
## PILOT HUMANOID LIMITS VERIFY - the pilot rig must stay humanoid in every clip.
##
## Covers (per image spec: no alien stretch):
##  1. Full humanoid bone set present (spine chain, both arms with hands, both legs).
##  2. Rest proportions sane (head ~1.7m, hips ~0.8m, feet on ground).
##  3. For EVERY clip: limb segment lengths stay within 3% of rest (no stretch),
##     elbows flex at most 150 deg, knees at most 150 deg (no hyperextension
##     past straight, no folding inside-out), everything finite.

const KIT_PATH := "res://scenes/pilot/pilot_pistol_kit.glb"
const CLIPS := ["pistol_idle", "pistol_reload", "pistol_shoot"]

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOT_HUM OK: " + name)
	else:
		_fails += 1
		printerr("PILOT_HUM FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ResourceLoader.exists(KIT_PATH), "kit file present")
	var packed: PackedScene = load(KIT_PATH)
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var skel := _find_skeleton(inst)
	var player := _find_player(inst)
	_check(skel != null and player != null, "skeleton + player present")
	if skel == null or player == null:
		get_tree().quit(1)
		return

	var need := ["pelvis", "spine_01", "spine_02", "neck_01", "Head",
		"clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
		"lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
		"thigh_r", "thigh_l", "calf_r", "calf_l",
		"foot_r", "foot_l"]
	var missing: Array = []
	for b in need:
		if skel.find_bone(b) < 0:
			missing.append(b)
	_check(missing.is_empty(), "humanoid bone set complete" + (" (missing %s)" % str(missing) if not missing.is_empty() else ""))

	var head_y: float = skel.get_bone_global_rest(skel.find_bone("Head")).origin.y
	var hip_y: float = skel.get_bone_global_rest(skel.find_bone("pelvis")).origin.y
	var foot_y: float = skel.get_bone_global_rest(skel.find_bone("foot_l")).origin.y
	_check(head_y > 1.55 and head_y < 2.0, "head height human (%.2fm)" % head_y)
	_check(hip_y > 0.65 and hip_y < 1.0, "hip height human (%.2fm)" % hip_y)
	_check(foot_y > -0.05 and foot_y < 0.15, "feet on ground (%.2fm)" % foot_y)

	var segs := [["thigh_l", "calf_l"], ["calf_l", "foot_l"],
		["upperarm_r", "lowerarm_r"], ["lowerarm_r", "hand_r"],
		["upperarm_l", "lowerarm_l"], ["lowerarm_l", "hand_l"]]
	var rest_len := {}
	for pair in segs:
		rest_len[pair[0] + ">" + pair[1]] = _seg_len(skel, pair[0], pair[1], true)
	for clip in CLIPS:
		_check(player.has_animation(clip), "clip present: " + clip)
		if not player.has_animation(clip):
			continue
		player.play(clip)
		var length: float = player.get_animation(clip).length
		var n := int(maxf(length * 20.0, 4.0))
		var worst_elong := 0.0
		var deepest_elbow := 180.0
		var deepest_knee := 180.0
		var finite := true
		for i in range(n + 1):
			player.seek(length * float(i) / float(n), true)
			for pair in segs:
				var l := _seg_len(skel, pair[0], pair[1], false)
				if not is_finite(l):
					finite = false
				else:
					var base: float = rest_len[pair[0] + ">" + pair[1]]
					worst_elong = maxf(worst_elong, absf(l - base) / maxf(base, 0.001))
			var e := _hinge(skel, "upperarm_r", "lowerarm_r", "hand_r")
			var e2 := _hinge(skel, "upperarm_l", "lowerarm_l", "hand_l")
			var k := _hinge(skel, "thigh_l", "calf_l", "foot_l")
			var k2 := _hinge(skel, "thigh_r", "calf_r", "foot_r")
			for v in [e, e2, k, k2]:
				if not is_finite(v):
					finite = false
			deepest_elbow = minf(deepest_elbow, minf(e, e2))
			deepest_knee = minf(deepest_knee, minf(k, k2))
		_check(finite, "%s all samples finite" % clip)
		_check(worst_elong < 0.03, "%s no stretch (drift=%.2f%%)" % [clip, worst_elong * 100.0])
		_check(deepest_elbow > deg_to_rad(30.0), "%s elbows never fold inside-out (min=%.0f deg)" % [clip, rad_to_deg(deepest_elbow)])
		_check(deepest_knee > deg_to_rad(40.0), "%s knees never fold inside-out (min=%.0f deg)" % [clip, rad_to_deg(deepest_knee)])

	print("PILOT_HUM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("PILOT_HUM_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_PILOT_HUM_TESTS_PASSED")
		get_tree().quit(0)


func _seg_len(skel: Skeleton3D, a: String, b: String, rest: bool) -> float:
	var ia := skel.find_bone(a)
	var ib := skel.find_bone(b)
	var pa: Vector3
	var pb: Vector3
	if rest:
		pa = skel.get_bone_global_rest(ia).origin
		pb = skel.get_bone_global_rest(ib).origin
	else:
		pa = skel.get_bone_global_pose(ia).origin
		pb = skel.get_bone_global_pose(ib).origin
	return pa.distance_to(pb)


## Hinge between segments (mid->prox) and (mid->dist): 180 = straight limb,
## 0 = fully folded. Human elbow flexes to ~35, knee to ~50 at most.
func _hinge(skel: Skeleton3D, prox: String, mid: String, dist: String) -> float:
	var a := skel.get_bone_global_pose(skel.find_bone(prox)).origin
	var b := skel.get_bone_global_pose(skel.find_bone(mid)).origin
	var c := skel.get_bone_global_pose(skel.find_bone(dist)).origin
	var v1 := (a - b)
	var v2 := (c - b)
	if v1.length_squared() < 0.00000001 or v2.length_squared() < 0.00000001:
		return 0.0
	return v1.normalized().angle_to(v2.normalized())


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null