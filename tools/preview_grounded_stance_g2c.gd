extends Node3D
## ISOLATED G2c CONTROLLED POSE SWEEP (E2-F2 Phase 8, separately approved).
##
## Narrow shin/thigh sweep around G2a (the better Phase-7 candidate) using the
## verified transform contract (degrees tables -> radians, mecha-local YXZ
## euler; legs rest positions -> absolute rotations -> body rest+drop ->
## collar-anchored head -> ankle_compensation math -> toe-aware settle;
## root NEVER moves). Frozen assembly, preview-owned mask-2 static floor,
## FootIK never invoked. No production/existing file touched.
##
## vs Phase 7: (1) armor proxy fixed — min over ALL visible shin-subtree
## meshes (Phase 7 excluded big assemblies whose center sat above the ankle,
## blinding the settle loop); (2) per-mesh attribution for every candidate;
## (3) baselines G1/G2a/G2b re-measured (no re-capture; Phase-7 images stand).
## OUTPUT ISOLATION: ONLY user://posture_abc/g2c/ (new subdir). Fail-closed,
## no repo fallback.
##
## Usage (after approval):
##   Godot --path . --resolution 1280x720 res://tools/preview_grounded_stance_g2c.tscn

const OUT_DIR := "user://posture_abc/g2c"
const TOL := 0.02 # contact band, metres (model ~5.3 m; AABB noise ~1 mm)
const PEN_FAIL := -0.02 # any mesh below this = penetration failure

const LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_local_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_local_001.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_local_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_local_001.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_local_001.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_right_001", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_local_001.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_local_001.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_right_001", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_local_001.tres", "slot": "leg_right"}},
}

const TORSO_ARMS := {
	"Body": Vector3(-5, 0, 0), "Head": Vector3(-2.5, 0, 0),
	"ArmLeft": Vector3(15, 5, -28), "ArmLeft/ForearmLeft": Vector3(32, 0, 12),
	"ArmRight": Vector3(15, -5, 28), "ArmRight/ForearmRight": Vector3(32, 0, -12),
	"Body/drop": Vector3(0, -0.03, 0),
}

# Baselines reproduced verbatim (thigh_x, shin_x); yaw/roll follow G-series.
const BASELINES := {
	"G1": {"thigh": 6.0, "shin": -12.0},
	"G2a": {"thigh": 9.0, "shin": -9.0},
	"G2b": {"thigh": 12.0, "shin": -6.0},
}
# Sweep around G2a (thigh 9 / shin -9), 1-2 deg steps, one axis at a time.
const SWEEP := {
	"S1": {"thigh": 8.0, "shin": -10.0},
	"S2": {"thigh": 10.0, "shin": -8.0},
	"S3": {"thigh": 9.0, "shin": -7.0},
	"S4": {"thigh": 7.0, "shin": -9.0},
}
const LEG_YAW := 10.0
const LEG_ROLL := 10.0
const SHIN_ROLL := 6.0

const _BUCKETS := {
	"Head": "head", "Body": "body",
	"ArmLeft": "shoulder_l", "ArmRight": "shoulder_r",
	"ForearmLeft": "forearm_l", "ForearmRight": "forearm_r",
	"LegLeft": "thigh_l", "LegRight": "thigh_r",
	"ShinLeft": "shin_l", "ShinRight": "shin_r",
	"FootLeft": "foot_l", "FootRight": "foot_r",
}

const VIEW_PRESETS := {
	"front": {"az": 0.0, "el": 6.0},
	"side": {"az": 90.0, "el": 6.0},
	"3q": {"az": 38.0, "el": 14.0},
}

var _cam: Camera3D
var _overlay: Node3D
var _failed := false
var _saved: Array[String] = []
var _results := {}
var _captured: Array[String] = []


func _ready() -> void:
	var out := DirAccess.open("user://")
	if out == null or not out.dir_exists("posture_abc"):
		printerr("[G2c] user://posture_abc missing (fail-closed, no repo fallback)")
		get_tree().quit(1)
		return
	if not out.dir_exists("posture_abc/g2c") and out.make_dir("posture_abc/g2c") != OK:
		printerr("[G2c] cannot create user://posture_abc/g2c (fail-closed)")
		get_tree().quit(1)
		return
	print("[G2c] output dir: " + OS.get_user_data_dir() + "/posture_abc/g2c")
	_setup_stage()
	_overlay = Node3D.new()
	_overlay.name = "G2cOverlay"
	add_child(_overlay)

	var mecha := await _assemble_frozen()
	# Baselines: measure only (Phase-7 images stand as their visuals).
	for tag in ["G1", "G2a", "G2b"]:
		_apply_candidate(mecha, tag)
		await _settle(mecha, tag)
		_measure_all(mecha, tag)
	# Sweep candidates: measure, then pick best for captures.
	for tag in ["S1", "S2", "S3", "S4"]:
		_apply_candidate(mecha, tag)
		await _settle(mecha, tag)
		_measure_all(mecha, tag)
	var best := _pick_best()
	print("[G2c] best sweep candidate: %s" % best)
	# Captures for baselines + best under IDENTICAL conditions (same union).
	# Phase-7 g2/ images stand as their own evidence; these re-captures allow
	# pixel-fair comparison inside one framing.
	var capture_modes: Array[String] = ["G1", "G2a", "G2b"]
	if not capture_modes.has(best):
		capture_modes.append(best)
	var union := _silhouette_aabb(mecha)
	for tag in capture_modes:
		_apply_candidate(mecha, tag)
		await _settle(mecha, tag + "-recap")
		union = union.merge(_silhouette_aabb(mecha))
	_frame_shared(union)
	for tag in capture_modes:
		_apply_candidate(mecha, tag)
		await _settle(mecha, tag + "-recap2")
		_set_layer_visibility(mecha, true, true)
		_clear_overlay()
		await get_tree().process_frame
		for v in ["front", "side", "3q"]:
			_aim_camera(union, v)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_save_capture("G2c_%s_%s.png" % [tag, v])
		await _capture_foot(mecha, tag, "left")
		await _capture_foot(mecha, tag, "right")
		await _capture_chain(mecha, tag, "")
		_set_layer_visibility(mecha, true, false)
		await get_tree().process_frame
		await _capture_chain(mecha, tag, "_armor")
		_set_layer_visibility(mecha, false, true)
		await get_tree().process_frame
		await _capture_chain(mecha, tag, "_frame")
		_set_layer_visibility(mecha, true, true)
		_captured.append(tag)
	_compose_contact_sheet(capture_modes)
	if _failed:
		printerr("[G2c] failures occurred (see above)")
		get_tree().quit(1)
	else:
		print("[G2c] ALL_G2C_DONE files=%d best=%s" % [_saved.size(), best])
		get_tree().quit(0)


func _candidate_table(tag: String) -> Dictionary:
	var src: Dictionary = BASELINES.get(tag, SWEEP.get(tag, {}))
	var tx: float = src["thigh"]
	var sx: float = src["shin"]
	var t := {
		"LegLeft": Vector3(tx, LEG_YAW, -LEG_ROLL), "LegLeft/ShinLeft": Vector3(sx, 0, SHIN_ROLL),
		"LegRight": Vector3(tx, -LEG_YAW, LEG_ROLL), "LegRight/ShinRight": Vector3(sx, 0, -SHIN_ROLL),
	}
	for k in TORSO_ARMS:
		t[k] = TORSO_ARMS[k]
	return t


func _assemble_frozen() -> Node3D:
	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha := base_res.instantiate() as Node3D
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame
	var pm := mecha.get_node_or_null("PartMeshManager")
	pm.refresh_from_loadout(LOADOUT)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[G2c] assembled frozen, root=%s scale=%s" % [_v3(mecha.global_position), _v3(mecha.scale)])
	return mecha


func _apply_candidate(mecha: Node3D, tag: String) -> void:
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	for path in ["LegLeft", "LegRight", "LegLeft/ShinLeft", "LegRight/ShinRight"]:
		(mecha.get_node_or_null(path) as Node3D).position = rest[path]
	var table := _candidate_table(tag)
	var body := mecha.get_node_or_null("Body") as Node3D
	for path in table:
		if String(path) == "Body/drop":
			continue
		var n := mecha.get_node_or_null(String(path)) as Node3D
		if n == null:
			printerr("[G2c] %s: missing pivot %s" % [tag, String(path)])
			_failed = true
			continue
		var deg: Vector3 = table[path]
		n.rotation = Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	body.position.y = (rest["Body"] as Vector3).y + (table["Body/drop"] as Vector3).y
	var head := mecha.get_node_or_null("Head") as Node3D
	head.position = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	_level_ankles(mecha)


func _level_ankles(mecha: Node3D) -> void:
	for side in [["LegLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/FootLeft"], ["LegRight", "LegRight/ShinRight", "LegRight/ShinRight/FootRight"]]:
		var leg := mecha.get_node_or_null(side[0]) as Node3D
		var shin := mecha.get_node_or_null(side[1]) as Node3D
		var foot := mecha.get_node_or_null(side[2]) as Node3D
		if leg == null or shin == null or foot == null:
			continue
		var comp: Vector2 = MechaFootIK.ankle_compensation(leg.rotation.x, shin.rotation.x, leg.rotation.z, shin.rotation.z)
		foot.rotation = Vector3(comp.x, 0.0, comp.y)


func _frame_sole(mecha: Node3D) -> float:
	var fb := _bucket_aabb(mecha, "foot_l")
	return fb.position.y if fb.size.length_squared() > 0.0 else NAN


func _armor_min_all(mecha: Node3D) -> float:
	# FIXED vs Phase 7: min over ALL visible shin-subtree meshes (the big
	# armor assembly's center sits above the ankle, which blinded the old
	# below-ankle-center filter). Still an AABB proxy, labeled as such.
	var worst := 999.0
	for side in ["LegLeft", "LegRight"]:
		var stack: Array[Node] = [mecha.get_node_or_null(side + "/Shin" + ("Left" if side == "LegLeft" else "Right"))]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				var mi := n as MeshInstance3D
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				worst = minf(worst, b.position.y)
			for c in n.get_children():
				stack.append(c)
	return worst


func _settle(mecha: Node3D, tag: String) -> void:
	for i in range(4):
		await get_tree().process_frame
		var fs: float = _frame_sole(mecha)
		var am: float = _armor_min_all(mecha)
		var sig: float = minf(fs, am)
		print("[G2c] %s settle iter %d frame_sole=%.3f armor_min=%.3f signal=%.3f" % [tag, i, fs, am, sig])
		if absf(sig) <= TOL:
			break
		for path in ["LegLeft", "LegRight"]:
			var n := mecha.get_node_or_null(path) as Node3D
			n.position.y -= sig
		_level_ankles(mecha)


func _dump_lowest_meshes(mecha: Node3D, tag: String) -> void:
	var rows: Array = []
	for side in ["LegLeft", "LegRight"]:
		var stack: Array[Node] = [mecha.get_node_or_null(side)]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
				var mi := n as MeshInstance3D
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				rows.append([b.position.y, str(mi.get_path())])
			for c in n.get_children():
				stack.append(c)
	rows.sort()
	for i in range(mini(5, rows.size())):
		print("[G2c] %s lowestmesh[%d] y=%.3f %s" % [tag, i, rows[i][0], rows[i][1]])


func _measure_all(mecha: Node3D, tag: String) -> void:
	var r := {}
	r["root_y"] = mecha.global_position.y
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var knee := (mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D).global_position
	var ankle := (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position
	r["hip"] = hip
	r["knee"] = knee
	r["ankle"] = ankle
	var fl := _bucket_aabb(mecha, "foot_l")
	var fr := _bucket_aabb(mecha, "foot_r")
	r["frame_sole_l"] = fl.position.y if fl.size.length_squared() > 0.0 else NAN
	r["frame_sole_r"] = fr.position.y if fr.size.length_squared() > 0.0 else NAN
	r["armor_min"] = _armor_min_all(mecha)
	var head := mecha.get_node_or_null("Head") as Node3D
	var body := mecha.get_node_or_null("Body") as Node3D
	var collar: Vector3 = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	r["collar_drift"] = (head.position - collar).length()
	r["sil_min_y"] = _silhouette_aabb(mecha).position.y
	_results[tag] = r
	print("[G2c] %s frame_sole L=%.3f R=%.3f armor_min=%.3f ankle=%s knee=%s collar=%.4f root=%.4f sil_min=%.3f" % [tag, r["frame_sole_l"], r["frame_sole_r"], r["armor_min"], _v3(ankle), _v3(knee), r["collar_drift"], r["root_y"], r["sil_min_y"]])
	_dump_lowest_meshes(mecha, tag)


func _worst_violation(tag: String) -> float:
	# Predeclared picker: worst penetration below fail line, else worst float
	# above contact band; tie-break = angular distance from G2a (handled by
	# ordered evaluation in _pick_best).
	var r: Dictionary = _results[tag]
	var pen: float = minf(minf(r["frame_sole_l"], r["frame_sole_r"]), r["armor_min"])
	if pen < PEN_FAIL:
		return -pen # positive magnitude of worst penetration
	var fl: float = maxf(r["frame_sole_l"], r["frame_sole_r"])
	return fl # float above floor (0.004-class values win ties below)


func _pick_best() -> String:
	# Ordered candidates S1..S4; best = smallest worst-violation; strict
	# improvement over G2a required to displace it (tie keeps G2a).
	var best := "G2a"
	var best_v: float = _worst_violation("G2a")
	print("[G2c] G2a worst-violation=%.3f (must beat to displace)" % best_v)
	for tag in ["S1", "S2", "S3", "S4"]:
		var v: float = _worst_violation(tag)
		print("[G2c] %s worst-violation=%.3f" % [tag, v])
		if v < best_v:
			best = tag
			best_v = v
	print("[G2c] best sweep candidate: %s (%.3f)" % [best, best_v])
	return best


# --- overlay + capture + stage helpers (proven pattern, small labels)
func _marker_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 2.0
	m.no_depth_test = true
	return m


func _add_marker(pos: Vector3, color: Color, r: float = 0.035) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.material_override = _marker_mat(color)
	mi.position = pos
	_overlay.add_child(mi)


func _add_label(text: String, pos: Vector3, pixel: float = 0.004) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = 48
	l.pixel_size = pixel
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 1)
	l.outline_size = 8
	l.outline_modulate = Color(0, 0, 0)
	_overlay.add_child(l)


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		_overlay.remove_child(c)
		c.queue_free()


func _bucket_aabb(mecha: Node, bucket: String) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var tag := ""
			var anc := mi.get_parent()
			while anc != null:
				if _BUCKETS.has(String(anc.name)):
					tag = _BUCKETS[String(anc.name)]
					break
				anc = anc.get_parent()
			if tag == bucket:
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				if first:
					box = b
					first = false
				else:
					box = box.merge(b)
		for c in n.get_children():
			stack.append(c)
	return box


func _silhouette_aabb(mecha: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			if first:
				box = b
				first = false
			else:
				box = box.merge(b)
		for c in n.get_children():
			stack.append(c)
	return box


func _silhouette_aabb_for(mecha: Node3D, _tag: String) -> AABB:
	return _silhouette_aabb(mecha)


func _set_layer_visibility(mecha: Node3D, armor: bool, frame: bool) -> void:
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var p := n.get_parent()
			var pname := String(p.name) if p != null else ""
			if pname == "ArmorMesh":
				(n as MeshInstance3D).visible = armor
			elif pname == "FrameMesh":
				(n as MeshInstance3D).visible = frame
		for c in n.get_children():
			stack.append(c)


func _capture_foot(mecha: Node3D, tag: String, side: String) -> void:
	_clear_overlay()
	var foot_b := "foot_l" if side == "left" else "foot_r"
	var shin_b := "shin_l" if side == "left" else "shin_r"
	var fb := _bucket_aabb(mecha, foot_b)
	var sb := _bucket_aabb(mecha, shin_b)
	var ankle: Vector3 = (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position if side == "left" else (mecha.get_node_or_null("LegRight/ShinRight/FootRight") as Node3D).global_position
	var known := fb.size.length_squared() > 0.0
	var sole: float = fb.position.y if known else NAN
	var fc: Vector3 = fb.get_center() if known else ankle
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.012, 0.5)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(fc.x, 0.006, fc.z)
	_overlay.add_child(strip)
	_add_marker(ankle, Color(0.1, 1.0, 0.2))
	_add_marker(Vector3(fc.x, sb.position.y, fc.z), Color(1.0, 1.0, 1.0), 0.025)
	if known:
		_add_marker(Vector3(fc.x, sole, fc.z), Color(0.2, 0.8, 1.0))
		_add_label("%s FOOT_%s sole=%+.3f %s" % [tag, side.to_upper(), sole, _clearance_word(sole)], Vector3(fc.x, sole + 0.45, fc.z), 0.004)
	else:
		_add_label("%s FOOT_%s sole=UNKNOWN" % [tag, side.to_upper()], Vector3(fc.x, 1.35, fc.z), 0.004)
	_add_label("ankle=%s shin_min=%.2f" % [_v3(ankle), sb.position.y], Vector3(fc.x, (sole + 0.28) if known else 1.12, fc.z), 0.0035)
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.7
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(fc.x, 0.95, fc.z), 90.0 if side == "left" else 270.0, 6.0, 9.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("G2c_%s_foot_%s.png" % [tag, side])


func _capture_chain(mecha: Node3D, tag: String, suffix: String = "") -> void:
	_clear_overlay()
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var knee := (mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D).global_position
	var ankle := (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position
	var foot_box := _bucket_aabb(mecha, "foot_l")
	var known := foot_box.size.length_squared() > 0.0
	var sole: float = foot_box.position.y if known else NAN
	var word := _clearance_word(sole) if known else "UNKNOWN"
	_add_marker(hip, Color(1.0, 0.15, 0.15))
	_add_marker(knee, Color(1.0, 0.9, 0.1))
	_add_marker(ankle, Color(0.1, 1.0, 0.2))
	if known:
		_add_marker(Vector3(ankle.x, sole, ankle.z), Color(0.2, 0.8, 1.0))
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.5, 0.012, 0.4)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(hip.x, 0.006, ankle.z)
	_overlay.add_child(strip)
	_add_label("%s CHAIN%s hip=%s knee=%s" % [tag, suffix, _v3(hip), _v3(knee)], Vector3(hip.x, hip.y + 0.55, 0.0), 0.005)
	_add_label("ankle=%s sole=%s %s" % [_v3(ankle), ("%.3f" % sole) if known else "UNKNOWN", word], Vector3(hip.x, hip.y + 0.28, 0.0), 0.0045)
	print("[G2c] %s chain%s sole=%s(%s)" % [tag, suffix, ("%.3f" % sole) if known else "UNKNOWN", word])
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 4.6
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(hip.x, 2.35, 0.0), 90.0, 6.0, 12.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("G2c_%s_chain%s.png" % [tag, suffix])


func _clearance_word(v: float) -> String:
	if v < -TOL:
		return "PENETRATING"
	if v <= TOL:
		return "TOUCHING"
	return "FLOATING"


func _ensure_cam() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "G2cOrthoCam"
		add_child(_cam)
	_cam.make_current()


func _place_cam(focus: Vector3, az_deg: float, el_deg: float, dist: float) -> void:
	var az: float = deg_to_rad(az_deg)
	var el: float = deg_to_rad(el_deg)
	_cam.global_position = focus + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist
	_cam.look_at(focus, Vector3.UP)


func _setup_stage() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 1.2
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 130, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 55, 0)
	rim.light_energy = 0.8
	add_child(rim)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.85, 0.85, 0.87)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.72, 0.72, 0.74)
	ground.material_override = gmat
	add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.name = "PreviewPhysFloor"
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.2, 40)
	col.shape = box
	col.position = Vector3(0, -0.1, 0)
	floor_body.add_child(col)
	add_child(floor_body)


func _frame_shared(union: AABB) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "G2cOrthoCam"
		add_child(_cam)
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(union.size.y, union.size.x / aspect) * 1.15
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.make_current()
	print("[G2c] ortho shared framing ready")


func _aim_camera(union: AABB, view: String) -> void:
	var preset: Dictionary = VIEW_PRESETS[view]
	var az: float = deg_to_rad(preset["az"])
	var el: float = deg_to_rad(preset["el"])
	var focus: Vector3 = union.get_center()
	var dist: float = maxf(union.size.y, union.size.x) * 2.0 + 4.0
	_cam.global_position = focus + Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist
	_cam.look_at(focus, Vector3.UP)


func _save_capture(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s" % [OUT_DIR, fname])
	if err != OK:
		printerr("[G2c] SAVE FAILED %s err=%d (no repo fallback by design)" % [fname, err])
		_failed = true
	else:
		_saved.append(fname)
		print("[G2c] saved %s size=%s" % [fname, img.get_size()])


func _compose_contact_sheet(modes: Array[String]) -> void:
	# Rows = captured modes, cols = [side, foot_left, chain]; all from THIS
	# run under one shared framing, so cells are directly comparable.
	var order: Array[String] = []
	for tag in modes:
		for v in ["side", "foot_left", "chain"]:
			order.append("G2c_%s_%s.png" % [tag, v])
	var cell_w := 480
	var cell_h := 270
	var sheet := Image.create(3 * cell_w, modes.size() * cell_h, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.16, 0.16, 0.18))
	var ok := true
	for i in range(order.size()):
		var cell: Image = Image.load_from_file("%s/%s" % [OUT_DIR, order[i]])
		if cell == null or cell.is_empty():
			printerr("[G2c] sheet: cannot load %s (cell outstanding)" % order[i])
			ok = false
			continue
		cell.resize(cell_w, cell_h)
		sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i((i % 3) * cell_w, (i / 3) * cell_h))
	if not ok:
		print("[G2c] CONTACT_SHEET_OUTSTANDING (individual captures stand)")
		return
	var err := sheet.save_png("%s/G2c_contact_sheet.png" % OUT_DIR)
	if err != OK:
		print("[G2c] CONTACT_SHEET_OUTSTANDING save err=%d" % err)
	else:
		_saved.append("G2c_contact_sheet.png")
		print("[G2c] saved G2c_contact_sheet.png size=%s" % sheet.get_size())


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
