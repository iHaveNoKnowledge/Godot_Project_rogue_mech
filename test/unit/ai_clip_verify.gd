extends Node
## AI CLIP VERIFY — the HY-Motion generated run must drive modular pivots.
##
## Covers:
##  1. ai_mech_run.glb exists with all 16 MechaRig bones + the ai_run clip.
##  2. The clip carries real locomotion (legs swing, knees flex, body bobs).
##  3. Its motion differs from the hand-authored run (it is a new take,
##     not a duplicate file).

const AI_GLB := "res://scenes/mecha/animations/ai_mech_run.glb"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("AI_CLIP OK: " + name)
	else:
		_fails += 1
		printerr("AI_CLIP FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ResourceLoader.exists(AI_GLB), "ai glb exists")
	var packed: PackedScene = load(AI_GLB)
	_check(packed != null and packed.can_instantiate(), "ai glb loads as PackedScene")
	if packed == null or not packed.can_instantiate():
		get_tree().quit(1)
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var skel := _find_skeleton(inst)
	_check(skel != null, "Skeleton3D present in ai glb")
	var missing := 0
	if skel != null:
		for b in [MechaRig.BONE_HEAD, MechaRig.BONE_NECK, MechaRig.BONE_TORSO, MechaRig.BONE_HIP,
				MechaRig.BONE_UPPER_ARM_L, MechaRig.BONE_UPPER_ARM_R,
				MechaRig.BONE_LOWER_ARM_L, MechaRig.BONE_LOWER_ARM_R,
				MechaRig.BONE_HAND_L, MechaRig.BONE_HAND_R,
				MechaRig.BONE_THIGH_L, MechaRig.BONE_THIGH_R,
				MechaRig.BONE_SHIN_L, MechaRig.BONE_SHIN_R,
				MechaRig.BONE_FOOT_L, MechaRig.BONE_FOOT_R]:
			if skel.find_bone(b) < 0:
				missing += 1
	_check(missing == 0, "all 16 MechaRig bones present (missing=%d)" % missing)
	var player := _find_player(inst)
	_check(player != null and player.has_animation(MechaRig.CLIP_AI_RUN), "ai_run clip present")
	inst.queue_free()
	await get_tree().process_frame

	# Drive check through the real retarget path.
	var retarget := MechaClipRetarget.new()
	add_child(retarget)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(retarget.has_clip(MechaRig.CLIP_AI_RUN), "retarget picks up ai_run")
	if retarget.has_clip(MechaRig.CLIP_AI_RUN):
		var ai_series := _drive(retarget, MechaRig.CLIP_AI_RUN)
		var run_series := _drive(retarget, MechaRig.CLIP_RUN)
		_check(rad_to_deg(_range_of(ai_series["leg"])) > 5.0, "ai legs swing (range=%.1f deg)" % rad_to_deg(_range_of(ai_series["leg"])))
		_check(rad_to_deg(_range_of(ai_series["shin"])) > 5.0, "ai knees flex (range=%.1f deg)" % rad_to_deg(_range_of(ai_series["shin"])))
		_check(_range_of(ai_series["bob"]) > 0.002, "ai hip bobs (bob=%.3fm)" % _range_of(ai_series["bob"]))
		_check(absf(_correlation(ai_series["leg"], run_series["leg"])) < 0.98, "ai motion differs from run (corr=%.2f)" % _correlation(ai_series["leg"], run_series["leg"]))

	print("AI_CLIP_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("AI_CLIP_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_AI_CLIP_TESTS_PASSED")
		get_tree().quit(0)


func _drive(retarget: MechaClipRetarget, clip: String) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var joints: Dictionary = {}
	for key in ["head", "body", "arm_left", "arm_right", "forearm_left", "forearm_right",
			"leg_left", "leg_right", "shin_left", "shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		root.add_child(n)
		joints[key] = n
	(joints["body"] as Node3D).position.y = 3.0
	retarget.play_clip(clip)
	var leg: Array = []
	var shin: Array = []
	var bob: Array = []
	for i in range(240):
		retarget.advance_and_apply(1.0 / 60.0, joints, 3.0)
		leg.append((joints["leg_left"] as Node3D).rotation.x)
		shin.append((joints["shin_left"] as Node3D).rotation.x)
		bob.append((joints["body"] as Node3D).position.y)
	root.queue_free()
	return {"leg": leg, "shin": shin, "bob": bob}


func _range_of(a: Array) -> float:
	var lo: float = a[0]
	var hi: float = a[0]
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


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
