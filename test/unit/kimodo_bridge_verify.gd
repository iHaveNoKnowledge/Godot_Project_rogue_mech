extends Node
## KIMODO BRIDGE VERIFY — the Kimodo->pilot bridge must stay import-safe.
##
## 1. Bridge files present (converter, mock, wrapper, Blender stager, sample).
## 2. Sample clip JSON parses to exactly 1 clip with the 19 pilot bones and
##    passes KimodoClipPolicy (unit quats, pelvis-bounded, finite).
## 3. Policy rejects a corrupted clip (non-unit quaternion).
## 4. Blender stager keeps the Godot export convention (export_yup=True).

const Policy = preload("res://scripts/systems/kimodo_clip_policy.gd")

const SAMPLE_JSON := "res://tools/kimodo/samples/kimodo_pilot_walk.json"
const RUN_JSON := "res://tools/kimodo/samples/kimodo_pilot_run.json"
const STAGER_PY := "res://tools/kimodo/blender_stage_kimodo.py"
const CONVERTER_PY := "res://tools/kimodo/kimodo_npz_to_pilot.py"
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

	for p in [SAMPLE_JSON, RUN_JSON, STAGER_PY, CONVERTER_PY, MOCK_PY, WRAPPER_PY, FORMAT_PY]:
		_check(FileAccess.file_exists(p), "bridge file present: " + p)

	_check(Policy.required_bones().size() == 19, "policy tracks 19 pilot bones")

	var data: Dictionary = {}
	if FileAccess.file_exists(SAMPLE_JSON):
		var raw := FileAccess.get_file_as_string(SAMPLE_JSON)
		_check(raw.length() > 100, "sample JSON non-empty (%d bytes)" % raw.length())
		var parsed = JSON.parse_string(raw)
		_check(parsed is Dictionary, "sample JSON parses to Dictionary")
		if parsed is Dictionary:
			data = parsed
			_check(data.size() == 1, "sample has exactly 1 clip")
			_check(data.has("kimodo_pilot_walk"), "sample clip named kimodo_pilot_walk")
			var errs: Array = Policy.validate_clip_dict(data)
			_check(errs.is_empty(), "sample passes clip policy" + (" (%s)" % str(errs) if not errs.is_empty() else ""))
			_check(Policy.clip_frame_count(data) == 60, "sample has 60 frames (2s @30fps)")
	else:
		_check(false, "sample JSON loadable")

	var run_data: Dictionary = _load_clip_json(RUN_JSON, "kimodo_pilot_run", 48)
	if not run_data.is_empty() and not data.is_empty():
		var walk_range := _pelvis_y_range(data)
		var run_range := _pelvis_y_range(run_data)
		_check(run_range > walk_range, "run bounces more than walk (run %.3fm vs walk %.3fm)" % [run_range, walk_range])

	if not data.is_empty():
		var bad: Dictionary = (data.duplicate(true) as Dictionary)
		var bb: Dictionary = (bad["kimodo_pilot_walk"] as Dictionary)["bones"]
		((bb["pelvis"] as Dictionary)["q"] as Array)[0] = [9.0, 0.0, 0.0, 0.0]
		var bad_errs: Array = Policy.validate_clip_dict(bad)
		_check(not bad_errs.is_empty(), "policy rejects non-unit quaternion")

	if FileAccess.file_exists(STAGER_PY):
		var stager := FileAccess.get_file_as_string(STAGER_PY)
		_check(stager.contains("export_yup=True"), "stager keeps export_yup=True (Blender +Y -> Godot -Z)")
		_check(stager.contains("Pilot_Character"), "stager targets Pilot_Character armature")
		_check(stager.contains("rotation_quaternion"), "stager keys quaternions (no euler drift)")
		_check(not stager.contains("xyzw"), "stager keeps (w,x,y,z) order (no XYZW shuffle)")

	print("KIMODO_BRIDGE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("KIMODO_BRIDGE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_KIMODO_BRIDGE_TESTS_PASSED")
		get_tree().quit(0)


func _load_clip_json(path: String, clip: String, want_frames: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		_check(false, "run sample present: " + path)
		return {}
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	_check(parsed is Dictionary and (parsed as Dictionary).has(clip), "run clip named " + clip)
	if not (parsed is Dictionary):
		return {}
	var dd: Dictionary = parsed
	_check(Policy.validate_clip_dict(dd).is_empty(), "run sample passes clip policy")
	_check(Policy.clip_frame_count(dd) == want_frames, "run sample has %d frames" % want_frames)
	return dd


func _pelvis_y_range(data: Dictionary) -> float:
	var rec: Dictionary = data[data.keys()[0]]
	var ts: Array = ((rec["bones"] as Dictionary)["pelvis"] as Dictionary)["t"]
	var lo := 1e9
	var hi := -1e9
	for t in ts:
		var y := float((t as Array)[1])
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return hi - lo
