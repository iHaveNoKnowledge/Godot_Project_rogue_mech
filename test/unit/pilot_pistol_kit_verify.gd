extends Node
## PILOT PISTOL KIT VERIFY - Quaternius pilot mesh + 3 baked ActionForge pistol clips.
##
## Covers:
##  1. Kit loads: Skeleton3D with Palm.R / LowerArm.L, MeshInstance3D present.
##  2. AnimationPlayer has pistol_idle / pistol_reload / pistol_shoot.
##  3. pistol_shoot visibly recoils the right arm.
##  4. pistol_reload flexes the left elbow (>10 deg).
##  5. pistol_idle sways (subtle) and all playback stays finite.

const KIT_PATH := "res://scenes/pilot/pilot_pistol_kit.glb"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOT_KIT OK: " + name)
	else:
		_fails += 1
		printerr("PILOT_KIT FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_check(ResourceLoader.exists(KIT_PATH), "kit file present")
	if not ResourceLoader.exists(KIT_PATH):
		get_tree().quit(1)
		return
	var packed: PackedScene = load(KIT_PATH)
	_check(packed != null and packed.can_instantiate(), "kit instantiates")
	if packed == null or not packed.can_instantiate():
		get_tree().quit(1)
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame

	var skel := _find_skeleton(inst)
	_check(skel != null, "Skeleton3D present")
	var player := _find_player(inst)
	_check(player != null, "AnimationPlayer present")
	if skel == null or player == null:
		get_tree().quit(1)
		return
	_check(skel.find_bone("Palm.R") >= 0, "Palm.R bone present")
	_check(skel.find_bone("LowerArm.L") >= 0, "LowerArm.L bone present")
	_check(_has_mesh(inst), "pilot mesh present")
	for clip in ["pistol_idle", "pistol_reload", "pistol_shoot"]:
		_check(player.has_animation(clip), "clip present: " + clip)

	# Shoot: right-arm recoil.
	var arm_arc := _play_arc(skel, player, "pistol_shoot", "UpperArm.R", 0.7)
	_check(arm_arc > deg_to_rad(1.0), "shoot recoils right arm (arc=%.1f deg)" % rad_to_deg(arm_arc))
	# Reload: left elbow works the mag.
	var elbow := _play_arc(skel, player, "pistol_reload", "LowerArm.L", 1.8)
	_check(elbow > deg_to_rad(10.0), "reload flexes left elbow (arc=%.1f deg)" % rad_to_deg(elbow))
	# Idle: subtle sway, finite, sane length.
	var sway := _play_arc(skel, player, "pistol_idle", "UpperArm.R", 1.8)
	_check(sway > deg_to_rad(0.5), "idle sways (arc=%.2f deg)" % rad_to_deg(sway))
	var idle_len: float = player.get_animation("pistol_idle").length
	_check(absf(idle_len - 1.667) < 0.15, "idle length sane (%.3fs)" % idle_len)
	var shoot_len: float = player.get_animation("pistol_shoot").length
	_check(shoot_len < idle_len, "shoot shorter than idle (%.3fs)" % shoot_len)

	print("PILOT_KIT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("PILOT_KIT_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_PILOT_KIT_TESTS_PASSED")
		get_tree().quit(0)


func _play_arc(skel: Skeleton3D, player: AnimationPlayer, clip: String, bone: String, window: float) -> float:
	var idx := skel.find_bone(bone)
	if idx < 0 or not player.has_animation(clip):
		return 0.0
	var length: float = player.get_animation(clip).length
	var n := int(minf(length, window) * 60.0)
	player.play(clip)
	player.seek(0.0, true)
	var rest: Quaternion = skel.get_bone_global_pose(idx).basis.get_rotation_quaternion().normalized()
	var peak := 0.0
	for i in range(1, n + 1):
		player.seek(float(i) / 60.0, true)
		var q: Quaternion = skel.get_bone_global_pose(idx).basis.get_rotation_quaternion().normalized()
		peak = maxf(peak, (rest.inverse() * q).normalized().get_angle())
		if not is_finite(peak):
			return 0.0
	return peak
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


func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false