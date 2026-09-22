extends Node
## INNERFRAME RIG VERIFY — cleaned run-cycle GLB must match the game rig.
##
## Regression for: innerframe_run_cycle.glb imported with Inner_* bone names
## at ~2.55m, so clips could never drive the MechaRig Bone_* Rig.
## The cleaned file (scenes/mecha/animations/innerframe_run_cycle_clean.glb)
## must have: a Skeleton3D with all 16 MechaRig bones, scaled to true height
## (~4.3m head), and a "run" clip for the AnimationPlayer.

const CLEAN_GLB := "res://scenes/mecha/animations/innerframe_run_cycle_clean.glb"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("INNERFRAME_RIG OK: " + name)
	else:
		_fails += 1
		printerr("INNERFRAME_RIG FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ResourceLoader.exists(CLEAN_GLB), "cleaned glb exists")
	var packed: PackedScene = load(CLEAN_GLB)
	_check(packed != null and packed.can_instantiate(), "cleaned glb loads as PackedScene")
	if packed == null or not packed.can_instantiate():
		get_tree().quit(1)
		return

	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame

	var skel := _find_skeleton(inst)
	_check(skel != null, "Skeleton3D present in cleaned glb")
	if skel == null:
		inst.queue_free()
		get_tree().quit(1)
		return

	var required := [
		MechaRig.BONE_HEAD, MechaRig.BONE_NECK, MechaRig.BONE_TORSO, MechaRig.BONE_HIP,
		MechaRig.BONE_UPPER_ARM_L, MechaRig.BONE_UPPER_ARM_R,
		MechaRig.BONE_LOWER_ARM_L, MechaRig.BONE_LOWER_ARM_R,
		MechaRig.BONE_HAND_L, MechaRig.BONE_HAND_R,
		MechaRig.BONE_THIGH_L, MechaRig.BONE_THIGH_R,
		MechaRig.BONE_SHIN_L, MechaRig.BONE_SHIN_R,
		MechaRig.BONE_FOOT_L, MechaRig.BONE_FOOT_R,
	]
	var missing := 0
	for b in required:
		if skel.find_bone(b) < 0:
			missing += 1
			printerr("INNERFRAME_RIG MISSING BONE: " + b)
	_check(missing == 0, "all 16 MechaRig bones present (missing=%d)" % missing)
	_check(skel.get_bone_count() >= 16, "skeleton has >= 16 bones (got %d)" % skel.get_bone_count())

	# True-height check: head must sit at game scale (~4.3m), not raw 2.55m.
	# NOTE: get_bone_rest is parent-relative; use the global rest instead.
	var head_idx := skel.find_bone(MechaRig.BONE_HEAD)
	if head_idx >= 0:
		var head_y: float = skel.get_bone_global_rest(head_idx).origin.y
		_check(head_y > 3.5, "head at game scale (head_y=%.2f)" % head_y)
	else:
		_check(false, "head at game scale (no head bone)")

	var player := _find_anim_player(inst)
	_check(player != null, "AnimationPlayer present in cleaned glb")
	if player != null:
		_check(player.has_animation(MechaRig.CLIP_RUN), "run clip present (has %s)" % str(player.get_animation_list()))

	print("INNERFRAME_RIG_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	inst.queue_free()
	await get_tree().process_frame
	if _fails > 0:
		printerr("INNERFRAME_RIG_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_INNERFRAME_RIG_TESTS_PASSED")
		get_tree().quit(0)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null
