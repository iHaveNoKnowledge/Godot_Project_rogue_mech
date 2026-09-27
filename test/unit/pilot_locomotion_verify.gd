## PILOT LOCOMOTION VERIFY — procedural walk/run clips on the pilot kit.
##
## 1. pilot_walk / pilot_run clips exist; run cycle is shorter than walk.
## 2. Legs actually swing: thigh rotation deviates > 10 deg from its frame-0
##    pose on both sides; knee height oscillates (hip-anchored stride).
## 3. Feet never sink below the floor (Godot up = +Y, floor = 0).
## 4. Arms keep the gun-ready pose: hand_r stays at chest height all clip.
## Sampling is synchronous (seek + update, no awaits) like pilot_pistol_kit_verify.

extends Node

const KIT_PATH := "res://scenes/pilot/pilot_pistol_kit.glb"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOT_LOCO OK: " + name)
	else:
		_fails += 1
		printerr("PILOT_LOCO FAIL: " + name)


func _ready() -> void:
	_check(ResourceLoader.exists(KIT_PATH), "kit file present")
	if not ResourceLoader.exists(KIT_PATH):
		_finish()
		return
	var packed: PackedScene = load(KIT_PATH)
	_check(packed != null and packed.can_instantiate(), "kit instantiates")
	if packed == null or not packed.can_instantiate():
		_finish()
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	var skel := _find_skeleton(inst)
	var player := _find_player(inst)
	_check(skel != null, "Skeleton3D present")
	_check(player != null, "AnimationPlayer present")
	if skel == null or player == null:
		_finish()
		return
	for clip in ["pilot_walk", "pilot_run"]:
		_check(player.has_animation(clip), "clip present: " + clip)
	if not player.has_animation("pilot_walk") or not player.has_animation("pilot_run"):
		_finish()
		return
	_check(player.get_animation("pilot_run").length < player.get_animation("pilot_walk").length,
		"run cycle shorter than walk (%.2fs vs %.2fs)" % [player.get_animation("pilot_run").length, player.get_animation("pilot_walk").length])

	var ti: int = skel.find_bone("thigh_l")
	var tri: int = skel.find_bone("thigh_r")
	var ci: int = skel.find_bone("calf_l")
	var hi: int = skel.find_bone("hand_r")
	_check(ti >= 0 and tri >= 0 and ci >= 0 and hi >= 0, "leg + hand bones present")

	for clip in ["pilot_walk", "pilot_run"]:
		var a: Animation = player.get_animation(clip)
		var n := int(a.length * 30.0)
		player.play(clip)
		player.seek(0.0, true)
		var q0l: Quaternion = skel.get_bone_global_pose(ti).basis.get_rotation_quaternion().normalized()
		var q0r: Quaternion = skel.get_bone_global_pose(tri).basis.get_rotation_quaternion().normalized()
		var dev_l := 0.0
		var dev_r := 0.0
		var knee_min := 1e9
		var knee_max := -1e9
		var ymin := 1e9
		var hand_lo := 1e9
		var hand_hi := -1e9
		for i in range(n + 1):
			player.seek(a.length * float(i) / float(n), true)
			var ql: Quaternion = skel.get_bone_global_pose(ti).basis.get_rotation_quaternion().normalized()
			var qr: Quaternion = skel.get_bone_global_pose(tri).basis.get_rotation_quaternion().normalized()
			dev_l = maxf(dev_l, rad_to_deg(q0l.angle_to(ql)))
			dev_r = maxf(dev_r, rad_to_deg(q0r.angle_to(qr)))
			var knee_y: float = skel.get_bone_global_pose(ci).origin.y
			knee_min = minf(knee_min, knee_y)
			knee_max = maxf(knee_max, knee_y)
			for fb in ["foot_l", "foot_r"]:
				var fi2: int = skel.find_bone(fb)
				if fi2 >= 0:
					ymin = minf(ymin, skel.get_bone_global_pose(fi2).origin.y)
			var hand_y: float = skel.get_bone_global_pose(hi).origin.y
			hand_lo = minf(hand_lo, hand_y)
			hand_hi = maxf(hand_hi, hand_y)
		_check(dev_l > 10.0, "%s left thigh swings (%.1f deg)" % [clip, dev_l])
		_check(dev_r > 10.0, "%s right thigh swings (%.1f deg)" % [clip, dev_r])
		_check(knee_max - knee_min > 0.02, "%s knee height oscillates (range=%.0f mm)" % [clip, (knee_max - knee_min) * 1000.0])
		_check(ymin > -0.06, "%s feet never sink below floor (ymin=%.3f)" % [clip, ymin])
		_check(hand_lo > 0.9 and hand_hi < 1.6, "%s keeps gun-ready hands (hand y %.2f..%.2f)" % [clip, hand_lo, hand_hi])
	_finish()


func _finish() -> void:
	print("PILOT_LOCO_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	print("ALL_PILOT_LOCO_TESTS_PASSED" if _fails == 0 else "PILOT_LOCO_TESTS_FAILED")
	get_tree().quit(0 if _fails == 0 else 1)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null
