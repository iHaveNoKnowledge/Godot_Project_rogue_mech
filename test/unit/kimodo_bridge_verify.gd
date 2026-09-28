extends Node
## KIMODO BRIDGE VERIFY — Kimodo motion transfer must stay Valkren-safe.
##
## The Valkren mech (MechaBase Node3D rig, ~5.5m) is driven by euler clips
## from tools/kimodo/kimodo_npz_to_valkren.py, never by the pilot pipeline.
## 1. Bridge files present (transfer, mock, wrapper, format, both samples).
## 2. Walk + run Valkren JSON parse to exactly 1 clip with the 12 mech
##    joints and pass KimodoValkrenPolicy (limits, finite, FK floor).
## 3. Run reads as a run: shorter cycle than walk, wider thigh swing,
##    deeper hull bob, feet never below floor on either clip.
## 4. Policy rejects a corrupted clip (thigh pitched past the mech limit).

const Policy = preload("res://scripts/systems/kimodo_valkren_policy.gd")

const WALK_JSON := "res://tools/kimodo/samples/valkren_walk.json"
const RUN_JSON := "res://tools/kimodo/samples/valkren_run.json"
const KIMODO_RUN_JSON := "res://tools/kimodo/samples/valkren_kimodo_run.json"
const SPRINT_RUN_JSON := "res://tools/kimodo/samples/valkren_sprint_run.json"
const KIMODO_CROP_NPZ := "res://tools/kimodo/samples/kimodo_g1_run_crop.npz"
const TRANSFER_PY := "res://tools/kimodo/kimodo_npz_to_valkren.py"
const MOCK_PY := "res://tools/kimodo/kimodo_mock.py"
const WRAPPER_PY := "res://tools/kimodo/kimodo_generate.py"
const FORMAT_PY := "res://tools/kimodo/kimodo_npz_format.py"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("KIMODO_BRIDGE OK: " + name)
	else:
		_fails += 1
		printerr("KIMODO_BRIDGE FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	for p in [WALK_JSON, RUN_JSON, KIMODO_RUN_JSON, SPRINT_RUN_JSON, TRANSFER_PY, MOCK_PY, WRAPPER_PY, FORMAT_PY]:
		_check(FileAccess.file_exists(p), "bridge file present: " + p)

	_check(Policy.required_joints().size() == 12, "policy tracks 12 Valkren joints")

	var walk: Dictionary = _load_clip_json(WALK_JSON, "valkren_walk", 60)
	var run: Dictionary = _load_clip_json(RUN_JSON, "valkren_run", 48)
	var kimodo: Dictionary = _load_clip_json(KIMODO_RUN_JSON, "valkren_kimodo_run", 42)

	if not kimodo.is_empty():
		# Real Kimodo Gen output: heavy readable steps (thigh span >= 30 deg),
		# symmetric arm pump (|L+R| ~ 0 after mirror symmetrization),
		# seamless loop (last frame == first after loop-blend).
		_check(_x_span(kimodo, "LegLeft") >= 30.0, "kimodo run takes heavy steps (span %.1f deg)" % _x_span(kimodo, "LegLeft"))
		var rec: Dictionary = kimodo[kimodo.keys()[0]]
		var joints: Dictionary = rec["joints"]
		var n: int = Policy.clip_frame_count(kimodo)
		var asym := 0.0
		var seam := 0.0
		for f in range(n):
			var al := float((((joints["ArmLeft"] as Dictionary)["rot"] as Array)[f] as Array)[0])
			var ar := float((((joints["ArmRight"] as Dictionary)["rot"] as Array)[f] as Array)[0])
			asym = maxf(asym, absf(al + ar))
		for j in Policy.required_joints():
			var arr: Array = ((joints[j] as Dictionary)["rot"] as Array)
			for k in range(3):
				seam = maxf(seam, absf(float((arr[0] as Array)[k]) - float((arr[n - 1] as Array)[k])))
		_check(asym < 1.0, "kimodo arms pump symmetric (|L+R| max %.2f deg)" % asym)
		_check(seam < 0.01, "kimodo loop is seamless (head/tail diff %.3f deg)" % seam)
		_check(Policy.min_foot_y(kimodo) >= 0.27, "kimodo feet never sink (min %.3fm)" % Policy.min_foot_y(kimodo))

	var sprint: Dictionary = _load_clip_json(SPRINT_RUN_JSON, "valkren_sprint_run", 31)
	if not sprint.is_empty():
		# Aggressive sprint: long drive (front reach >= 25 deg AND rear
		# extension behind zero), strong net lean, seamless loop, floor.
		var srec: Dictionary = sprint[sprint.keys()[0]]
		var sj: Dictionary = srec["joints"]
		var lleg: Array = Policy.joint_x_range(sprint, "LegLeft")
		var rleg: Array = Policy.joint_x_range(sprint, "LegRight")
		var body: Array = Policy.joint_x_range(sprint, "Body")
		_check(maxf(lleg[1], rleg[1]) >= 25.0, "sprint reaches forward decisively (max %.1f deg)" % maxf(lleg[1], rleg[1]))
		_check(minf(lleg[0], rleg[0]) <= -5.0, "sprint extends behind on push (min %.1f deg)" % minf(lleg[0], rleg[0]))
		_check(body[1] <= -5.0, "sprint keeps forward lean (max %.1f deg)" % body[1])
		var n2: int = Policy.clip_frame_count(sprint)
		var seam2 := 0.0
		for j in Policy.required_joints():
			var arr: Array = ((sj[j] as Dictionary)["rot"] as Array)
			for k in range(3):
				seam2 = maxf(seam2, absf(float((arr[0] as Array)[k]) - float((arr[n2 - 1] as Array)[k])))
		_check(seam2 < 0.01, "sprint loop is seamless (diff %.3f deg)" % seam2)
		_check(Policy.min_foot_y(sprint) >= 0.27, "sprint feet never sink (min %.3fm)" % Policy.min_foot_y(sprint))

	if not walk.is_empty() and not run.is_empty():
		_check(Policy.clip_frame_count(run) < Policy.clip_frame_count(walk),
			"run cycle shorter than walk (%d vs %d frames)"
			% [Policy.clip_frame_count(run), Policy.clip_frame_count(walk)])
		var walk_swing := _x_span(walk, "LegLeft")
		var run_swing := _x_span(run, "LegLeft")
		_check(run_swing > walk_swing,
			"run swings wider than walk (%.1f vs %.1f deg)" % [run_swing, walk_swing])
		var walk_bob := _off_span(walk, "Body")
		var run_bob := _off_span(run, "Body")
		_check(run_bob > walk_bob,
			"run hull bobs more than walk (%.3fm vs %.3fm)" % [run_bob, walk_bob])
		_check(Policy.min_foot_y(walk) >= 0.27, "walk feet never sink (min %.3fm)" % Policy.min_foot_y(walk))
		_check(Policy.min_foot_y(run) >= 0.27, "run feet never sink (min %.3fm)" % Policy.min_foot_y(run))

	if not walk.is_empty():
		var bad: Dictionary = (walk.duplicate(true) as Dictionary)
		var bj: Dictionary = (bad["valkren_walk"] as Dictionary)["joints"]
		(((bj["LegLeft"] as Dictionary)["rot"] as Array)[0] as Array)[0] = 80.0
		_check(not Policy.validate_clip_dict(bad).is_empty(), "policy rejects over-pitched thigh")

	print("KIMODO_BRIDGE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("KIMODO_BRIDGE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_KIMODO_BRIDGE_TESTS_PASSED")
		get_tree().quit(0)


func _load_clip_json(path: String, clip: String, want_frames: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		_check(false, "sample present: " + path)
		return {}
	var raw := FileAccess.get_file_as_string(path)
	_check(raw.length() > 100, "%s non-empty (%d bytes)" % [clip, raw.length()])
	var parsed = JSON.parse_string(raw)
	_check(parsed is Dictionary and (parsed as Dictionary).has(clip), "clip named " + clip)
	if not (parsed is Dictionary):
		return {}
	var dd: Dictionary = parsed
	var errs: Array = Policy.validate_clip_dict(dd)
	_check(errs.is_empty(), "%s passes Valkren policy" % clip + (" (%s)" % str(errs) if not errs.is_empty() else ""))
	_check(Policy.clip_frame_count(dd) == want_frames, "%s has %d frames" % [clip, want_frames])
	return dd


func _x_span(data: Dictionary, joint: String) -> float:
	var r: Array = Policy.joint_x_range(data, joint)
	return r[1] - r[0]


func _off_span(data: Dictionary, joint: String) -> float:
	var rec: Dictionary = data[data.keys()[0]]
	var arr: Array = (((rec["joints"] as Dictionary)[joint] as Dictionary)["off_y"] as Array)
	var lo := 1e9
	var hi := -1e9
	for v in arr:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	return hi - lo
