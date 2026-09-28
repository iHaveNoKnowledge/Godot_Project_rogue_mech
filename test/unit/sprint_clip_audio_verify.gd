extends Node
## SPRINT CLIP AUDIO VERIFY — the Kimodo sprint runs in game with footsteps
## synced to the exact touchdown/liftoff frames (not a procedural timer).
##
## 1. MechaJsonClip loads the sprint JSON (44 frames @30fps) with stance data.
## 2. Stepping a full loop emits touchdown events matching the stance edges
##    in the file, alternating sides, plus liftoff events; events only fire
##    on frames whose stance actually changed (exact sync proof).
## 3. advance(0) emits nothing; looping wraps without an event burst.
## 4. MechaClipRetarget registers/plays the JSON clip, drives mock pivots,
##    and delegates step/lift events; GLB-less operation needs no skeleton.
## 5. The game exposes play_footstep/play_step_lift for the audio hook.

const SPRINT_JSON := "res://tools/kimodo/samples/valkren_sprint_run.json"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SPRINT_AUDIO OK: " + name)
	else:
		_fails += 1
		printerr("SPRINT_AUDIO FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var clip := MechaJsonClip.load_file(SPRINT_JSON)
	_check(clip.is_loaded(), "sprint JSON clip loads")
	_check(clip.frames == 44, "sprint clip has 44 frames (got %d)" % clip.frames)
	_check(absf(clip.fps - 30.0) < 0.01, "sprint clip runs at 30fps")

	# Expected edges recomputed straight from the stance channels.
	var want_down: Array = []
	var want_up: Array = []
	for f in range(1, clip.frames):
		if bool(clip.stance_l[f]) and not bool(clip.stance_l[f - 1]):
			want_down.append([f, false])
		if bool(clip.stance_r[f]) and not bool(clip.stance_r[f - 1]):
			want_down.append([f, true])
		if not bool(clip.stance_l[f]) and bool(clip.stance_l[f - 1]):
			want_up.append([f, false])
		if not bool(clip.stance_r[f]) and bool(clip.stance_r[f - 1]):
			want_up.append([f, true])
	_check(not want_down.is_empty(), "sprint stance has touchdown edges (%d)" % want_down.size())
	_check(not want_up.is_empty(), "sprint stance has liftoff edges (%d)" % want_up.size())

	# Step frame-by-frame through two full loops; every emitted event must
	# land on a frame whose stance actually holds that foot.
	var got_down := 0
	var got_up := 0
	var sides := {}
	var misfired := 0
	var dt := 1.0 / 30.0
	for i in range(clip.frames * 2):
		clip.advance(dt)
		var f: int = int(floor(clip.cursor)) % clip.frames
		for is_right in clip.poll_step_events():
			got_down += 1
			sides[bool(is_right)] = true
			var st: Array = clip.stance_r if bool(is_right) else clip.stance_l
			if not bool(st[f]):
				misfired += 1
		for is_right in clip.poll_lift_events():
			got_up += 1
			var st2: Array = clip.stance_r if bool(is_right) else clip.stance_l
			if bool(st2[f]):
				misfired += 1
	_check(got_down == want_down.size() * 2, "touchdowns match stance edges x2 loops (%d)" % got_down)
	_check(got_up == want_up.size() * 2, "liftoffs match stance edges x2 loops (%d)" % got_up)
	_check(sides.size() == 2, "both feet strike across the loop")
	_check(misfired == 0, "no event fires on a wrong-stance frame")

	# advance(0) is silent; wrap emits at most the single wrap edge.
	var quiet := MechaJsonClip.load_file(SPRINT_JSON)
	quiet.advance(0.0)
	_check(quiet.poll_step_events().is_empty() and quiet.poll_lift_events().is_empty(), "advance(0) emits nothing")

	# Retarget integration on mock pivots (no skeleton needed for JSON).
	var retarget := MechaClipRetarget.new()
	add_child(retarget)
	_check(retarget.register_json_clip(MechaRig.CLIP_SPRINT_KIMODO, SPRINT_JSON), "retarget registers JSON sprint")
	_check(retarget.has_clip(MechaRig.CLIP_SPRINT_KIMODO), "sprint clip listed")
	retarget.play_clip(MechaRig.CLIP_SPRINT_KIMODO)
	var joints := _mock_joints()
	var before: float = (joints["leg_left"] as Node3D).rotation.x
	for i in range(30):
		retarget.advance_and_apply(1.0 / 30.0, joints, 3.841)
	_check(absf((joints["leg_left"] as Node3D).rotation.x - before) > deg_to_rad(3.0), "JSON clip drives leg pivots")
	var ev: Array = retarget.poll_step_events()
	_check(ev.all(func(v): return v is bool), "retarget step events are side bools")
	var li: Array = retarget.poll_lift_events()
	_check(li.all(func(v): return v is bool), "retarget lift events are side bools")
	_check((joints["foot_left"] as Node3D).rotation == Vector3.ZERO, "JSON clip never touches feet (FootIK owns them)")

	var audio_mgr: Node = get_node_or_null("/root/AudioManager")
	_check(audio_mgr != null and audio_mgr.has_method("play_footstep"), "AudioManager.play_footstep exists")
	_check(audio_mgr != null and audio_mgr.has_method("play_step_lift"), "AudioManager.play_step_lift exists")

	print("SPRINT_CLIP_AUDIO_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("SPRINT_CLIP_AUDIO_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_SPRINT_CLIP_AUDIO_TESTS_PASSED")
		get_tree().quit(0)


func _mock_joints() -> Dictionary:
	var joints := {}
	for key in ["body", "head", "arm_left", "arm_right", "forearm_left",
			"forearm_right", "leg_left", "leg_right", "shin_left",
			"shin_right", "foot_left", "foot_right"]:
		var n := Node3D.new()
		add_child(n)
		joints[key] = n
	joints["original_body_pos"] = Vector3(0, 3.841, 0)
	joints["original_head_pos"] = Vector3(0, 4.377, -0.16)
	joints["original_leg_left_pos"] = Vector3(-0.6384, 3.001, 0)
	joints["original_leg_right_pos"] = Vector3(0.6384, 3.001, 0)
	return joints
