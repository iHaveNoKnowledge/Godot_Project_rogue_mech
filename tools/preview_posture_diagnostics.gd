extends Node3D
## ISOLATED POSTURE DIAGNOSTICS (E2-F2 Phase 4, separately approved).
##
## Close-up visual evidence for the frozen A/B/C postures assembled EXACTLY
## like tools/preview_posture_abc.gd (same mecha_base.tscn, same
## wanzer_local_001 loadout, same hangar base + identical pose tables, same
## root scale, drivers frozen). Nothing here runs gameplay, combat, FootIK,
## animation, or locomotion; production files are only READ.
##
## DIAGNOSTIC OVERLAYS (markers, floor strip, labels) live on a dedicated
## overlay node that is a SIBLING of the mecha, never parented under its
## pivots or meshes, with unshaded emissive materials visually distinct
## from model geometry. Marker positions are READ from live pivot
## global_positions and measured AABB minima (never invented); every overlay
## value is also printed to stdout, and the script asserts agreement.
##
## OUTPUT ISOLATION: all PNGs go ONLY to user://posture_abc/ (outside the
## repository). No repo fallback: a failed save marks failure and quits
## nonzero. Contact sheet is composed at runtime from the saved captures;
## if composition fails, individual captures still stand and the sheet is
## reported OUTSTANDING (never blocking the evidence).
##
## Usage (after approval):
##   Godot --path . --resolution 1280x720 res://tools/preview_posture_diagnostics.tscn

const OUT_DIR := "user://posture_abc"
const TOLERANCE := 0.02 # touching band, metres; fixed before any measurement

const LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_local_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_local_001.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_local_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_local_001.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_local_001.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_right_001", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_local_001.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_local_001.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_right_001", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_local_001.tres", "slot": "leg_right"}},
}

# IDENTICAL to preview_posture_abc.gd POSE_A/B/C (verbatim values; any drift
# between the two scripts is a bug — cross-checked by stdout rotation logs).
const POSE_A := {
	"Body": Vector3(-8, 0, 0), "Head": Vector3(-4, 0, 0),
	"ArmLeft": Vector3(18, 4, -28), "ArmLeft/ForearmLeft": Vector3(35, 0, 10),
	"ArmRight": Vector3(18, -4, 28), "ArmRight/ForearmRight": Vector3(35, 0, -10),
	"LegLeft": Vector3(14, 8, -8), "LegLeft/ShinLeft": Vector3(-24, 0, 4),
	"LegRight": Vector3(14, -8, 8), "LegRight/ShinRight": Vector3(-24, 0, -4),
	"Body/drop": Vector3(0, -0.10, 0),
}
const POSE_B := {
	"Body": Vector3(-2, 0, 0), "Head": Vector3(0, 0, 0),
	"ArmLeft": Vector3(14, 6, -28), "ArmLeft/ForearmLeft": Vector3(30, 0, 14),
	"ArmRight": Vector3(14, -6, 28), "ArmRight/ForearmRight": Vector3(30, 0, -14),
	"LegLeft": Vector3(5, 14, -14), "LegLeft/ShinLeft": Vector3(-10, 0, 8),
	"LegRight": Vector3(5, -14, 14), "LegRight/ShinRight": Vector3(-10, 0, -8),
	"Body/drop": Vector3(0, -0.06, 0),
}
const POSE_C := {
	"Body": Vector3(-5, 0, 0), "Head": Vector3(-2.5, 0, 0),
	"ArmLeft": Vector3(15, 5, -28), "ArmLeft/ForearmLeft": Vector3(32, 0, 12),
	"ArmRight": Vector3(15, -5, 28), "ArmRight/ForearmRight": Vector3(32, 0, -12),
	"LegLeft": Vector3(9, 11, -11), "LegLeft/ShinLeft": Vector3(-17, 0, 6),
	"LegRight": Vector3(9, -11, 11), "LegRight/ShinRight": Vector3(-17, 0, -6),
	"Body/drop": Vector3(0, -0.07, 0),
}

const _BUCKETS := {
	"Head": "head", "Body": "body",
	"ArmLeft": "shoulder_l", "ArmRight": "shoulder_r",
	"ForearmLeft": "forearm_l", "ForearmRight": "forearm_r",
	"LegLeft": "thigh_l", "LegRight": "thigh_r",
	"ShinLeft": "shin_l", "ShinRight": "shin_r",
	"FootLeft": "foot_l", "FootRight": "foot_r",
}

var _cam: Camera3D
var _overlay: Node3D
var _failed := false
var _saved: Array[String] = []


func _ready() -> void:
	var out := DirAccess.open("user://")
	if out == null or not out.dir_exists("posture_abc"):
		printerr("[POSTURE-DIAG] user://posture_abc missing (fail-closed, no repo fallback)")
		get_tree().quit(1)
		return
	print("[POSTURE-DIAG] output dir: " + OS.get_user_data_dir() + "/posture_abc")

	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	if base_res == null or not base_res.can_instantiate():
		printerr("[POSTURE-DIAG] mecha_base.tscn missing")
		get_tree().quit(1)
		return
	var mecha := base_res.instantiate() as Node3D
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame

	var pm := mecha.get_node_or_null("PartMeshManager")
	if pm == null or not pm.has_method("refresh_from_loadout"):
		printerr("[POSTURE-DIAG] no PartMeshManager assembly path")
		get_tree().quit(1)
		return
	pm.refresh_from_loadout(LOADOUT)
	await get_tree().process_frame
	await get_tree().process_frame
	_setup_stage()
	_overlay = Node3D.new()
	_overlay.name = "DiagOverlay"
	add_child(_overlay)

	for label in ["A", "B", "C"]:
		_apply_variant(mecha, label)
		_set_layer_visibility(mecha, true, true)
		await get_tree().process_frame
		await _capture_foot(mecha, label, "left")
		await _capture_foot(mecha, label, "right")
		await _capture_chain(mecha, label)
		_apply_variant(mecha, label)
		_set_layer_visibility(mecha, true, false)
		await get_tree().process_frame
		await _capture_chain(mecha, label, "_armor")
		_set_layer_visibility(mecha, false, true)
		await get_tree().process_frame
		await _capture_chain(mecha, label, "_frame")
		_set_layer_visibility(mecha, true, true)

	_compose_contact_sheet()
	if _failed:
		printerr("[POSTURE-DIAG] failures occurred (see above)")
		get_tree().quit(1)
	else:
		print("[POSTURE-DIAG] ALL_DIAGNOSTICS_DONE files=%d" % _saved.size())
		get_tree().quit(0)


func _apply_variant(mecha: Node3D, label: String) -> void:
	HangarGaragePanel.new().apply_tactical_idle_pose(mecha)
	var table: Dictionary = {"A": POSE_A, "B": POSE_B, "C": POSE_C}[label]
	var body := mecha.get_node_or_null("Body") as Node3D
	for path in table:
		if String(path) == "Body/drop":
			continue
		var n := mecha.get_node_or_null(String(path)) as Node3D
		if n == null:
			printerr("[POSTURE-DIAG] %s: missing pivot %s" % [label, String(path)])
			_failed = true
			continue
		var deg: Vector3 = table[path]
		n.rotation = Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	if body != null:
		var hangar_body_y := (MechaScaleSystem.HANGAR_POSE["body_pos"] as Vector3).y
		body.position.y = hangar_body_y + (table["Body/drop"] as Vector3).y
		var head := mecha.get_node_or_null("Head") as Node3D
		if head != null:
			head.position = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)


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


func _add_label(text: String, pos: Vector3, pixel: float = 0.008) -> void:
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


func _clearance_word(v: float) -> String:
	if v < -TOLERANCE:
		return "PENETRATING"
	if v <= TOLERANCE:
		return "TOUCHING"
	return "FLOATING"


func _measure_foot(mecha: Node3D, label: String, side: String) -> Dictionary:
	var foot_b := "foot_l" if side == "left" else "foot_r"
	var shin_b := "shin_l" if side == "left" else "shin_r"
	var foot_node := mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft" if side == "left" else "LegRight/ShinRight/FootRight") as Node3D
	var fb := _bucket_aabb(mecha, foot_b)
	var sb := _bucket_aabb(mecha, shin_b)
	var ankle: Vector3 = foot_node.global_position if foot_node != null else Vector3.ZERO
	# Empty foot bucket (e.g. armor-only view where foot armor hangs under
	# shin ancestors): NEVER report default 0.0 as a measurement.
	var sole_known := fb.size.length_squared() > 0.0
	var sole_y: float = fb.position.y if sole_known else NAN
	var clearance: float = sole_y - 0.0 if sole_known else NAN
	var word := _clearance_word(clearance) if sole_known else "UNKNOWN"
	var fc: Vector3 = fb.get_center() if sole_known else ankle
	var d := {
		"ankle": ankle, "sole_y": sole_y, "clearance": clearance,
		"word": word, "known": sole_known,
		"foot_center": fc, "shin_min_y": sb.position.y,
		"foot_ok": foot_node != null,
	}
	print("[POSTURE-DIAG] %s foot_%s sole=%s clearance=%s(%s) ankle=%s shin_min=%.3f src=mesh-AABB+ankle-pivot" % [label, side, ("%.3f" % sole_y) if sole_known else "UNKNOWN", ("%+.3f" % clearance) if sole_known else "UNKNOWN", word, _v3(ankle), sb.position.y])
	return d


func _capture_foot(mecha: Node3D, label: String, side: String) -> void:
	_clear_overlay()
	var d := _measure_foot(mecha, label, side)
	var ankle: Vector3 = d["ankle"]
	var fc: Vector3 = d["foot_center"]
	# Floor reference strip under this foot (overlay sibling, not model geometry).
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.012, 0.5)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(fc.x, 0.006, fc.z)
	_overlay.add_child(strip)
	_add_marker(ankle, Color(0.1, 1.0, 0.2)) # green = ankle pivot (measured)
	var sole_known: bool = d["known"]
	if sole_known:
		_add_marker(Vector3(fc.x, d["sole_y"], fc.z), Color(0.2, 0.8, 1.0)) # cyan = sole minimum (measured)
		_add_label("%s FOOT_%s sole=%+.3f %s (tol %.2f)" % [label, side.to_upper(), d["clearance"], d["word"], TOLERANCE], Vector3(fc.x, d["sole_y"] + 0.55, fc.z))
	else:
		_add_label("%s FOOT_%s sole=UNKNOWN (no foot-bucket meshes)" % [label, side.to_upper()], Vector3(fc.x, 1.45, fc.z))
	_add_marker(Vector3(fc.x, d["shin_min_y"], fc.z), Color(1.0, 1.0, 1.0), 0.025) # white = shin-bucket min (proxy)
	_add_label("ankle=%s shin_min=%.2f" % [_v3(ankle), d["shin_min_y"]], Vector3(fc.x, (d["sole_y"] + 0.33) if sole_known else 1.20, fc.z), 0.006)
	_ensure_cam()
	# Near side per foot avoids far-leg occlusion: left az90, right az270.
	var az := 90.0 if side == "left" else 270.0
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.7
	_cam.near = 0.05
	_cam.far = 200.0
	var focus := Vector3(fc.x, 0.95, fc.z)
	_place_cam(focus, az, 6.0, 9.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("DIAG_%s_foot_%s.png" % [label, side])


func _capture_chain(mecha: Node3D, label: String, suffix: String = "") -> void:
	_clear_overlay()
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var knee := (mecha.get_node_or_null("LegLeft/ShinLeft") as Node3D).global_position
	var ankle := (mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft") as Node3D).global_position
	var foot_box := _bucket_aabb(mecha, "foot_l")
	var sole_known := foot_box.size.length_squared() > 0.0
	var sole: float = foot_box.position.y if sole_known else NAN
	var sole_word := _clearance_word(sole) if sole_known else "UNKNOWN"
	_add_marker(hip, Color(1.0, 0.15, 0.15)) # red = hip pivot
	_add_marker(knee, Color(1.0, 0.9, 0.1)) # yellow = knee pivot
	_add_marker(ankle, Color(0.1, 1.0, 0.2)) # green = ankle pivot
	if sole_known:
		_add_marker(Vector3(ankle.x, sole, ankle.z), Color(0.2, 0.8, 1.0)) # cyan = sole min
	var strip := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.5, 0.012, 0.4)
	strip.mesh = bm
	strip.material_override = _marker_mat(Color(1.0, 0.45, 0.0))
	strip.position = Vector3(hip.x, 0.006, ankle.z)
	_overlay.add_child(strip)
	_add_label("%s CHAIN%s hip=%s knee=%s" % [label, suffix, _v3(hip), _v3(knee)], Vector3(hip.x, hip.y + 0.55, 0.0))
	_add_label("ankle=%s sole=%s %s" % [_v3(ankle), ("%.3f" % sole) if sole_known else "UNKNOWN", sole_word], Vector3(hip.x, hip.y + 0.28, 0.0), 0.007)
	print("[POSTURE-DIAG] %s chain%s hip=%s knee=%s ankle=%s sole=%s src=pivot-globals+mesh-AABB" % [label, suffix, _v3(hip), _v3(knee), _v3(ankle), ("%.3f" % sole) if sole_known else "UNKNOWN"])
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 4.6
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(hip.x, 2.35, 0.0), 90.0, 6.0, 12.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("DIAG_%s_chain%s.png" % [label, suffix])


func _ensure_cam() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "DiagOrthoCam"
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


func _save_capture(fname: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s" % [OUT_DIR, fname])
	if err != OK:
		printerr("[POSTURE-DIAG] SAVE FAILED %s err=%d (no repo fallback by design)" % [fname, err])
		_failed = true
	else:
		_saved.append(fname)
		print("[POSTURE-DIAG] saved %s size=%s" % [fname, img.get_size()])


func _compose_contact_sheet() -> void:
	# Rows A/B/C x cols [foot_L, foot_R, chain, chain_armor, chain_frame].
	var cols: Array[String] = ["DIAG_%s_foot_left.png", "DIAG_%s_foot_right.png", "DIAG_%s_chain.png", "DIAG_%s_chain_armor.png", "DIAG_%s_chain_frame.png"]
	var cell_w := 480
	var cell_h := 270
	var sheet := Image.create(cols.size() * cell_w, 3 * cell_h, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.16, 0.16, 0.18))
	var ok := true
	for r in range(3):
		var label: String = ["A", "B", "C"][r]
		for c in range(cols.size()):
			var path := "%s/%s" % [OUT_DIR, cols[c] % label]
			var cell: Image = Image.load_from_file(path)
			if cell == null or cell.is_empty():
				printerr("[POSTURE-DIAG] sheet: cannot load %s (remains outstanding for this cell)" % path)
				ok = false
				continue
			cell.resize(cell_w, cell_h)
			sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(c * cell_w, r * cell_h))
	if not ok:
		print("[POSTURE-DIAG] CONTACT_SHEET_OUTSTANDING (individual captures stand)")
		return
	var err := sheet.save_png("%s/DIAG_contact_sheet.png" % OUT_DIR)
	if err != OK:
		print("[POSTURE-DIAG] CONTACT_SHEET_OUTSTANDING save err=%d" % err)
	else:
		_saved.append("DIAG_contact_sheet.png")
		print("[POSTURE-DIAG] saved DIAG_contact_sheet.png size=%s" % sheet.get_size())


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
