extends Node3D
## ISOLATED GROUNDED-STANCE PREVIEW (E2-F2 Phase 6, separately approved).
##
## Compares three modes on the identically assembled production mecha
## (mecha_base.tscn + wanzer_local_001 six-slot set, root scale 1.15):
##   H — Hangar showroom reference (frozen; real apply_tactical_idle_pose).
##   R — Combat Rest via the REAL production path: a LIVE isolated instance
##       settles under gravity + its own shipped drivers (procedural idle +
##       FootIK) on a preview-owned mask-2 static floor, then freezes.
##   G — Experimental grounded stance (preview-owned pose only; root NEVER
##       moves; hip-Y settle iterations are joint-chain variables, logged).
## FootIK is NEVER enabled by changing production settings or code: in H/G
## the frozen subtree never calls it; in R the isolated instance calls its
## own shipped update_ik itself (documented, zero production changes).
## OUTPUT ISOLATION: PNGs ONLY to user://posture_abc/, fail-closed, no repo
## fallback. No production/test/preview file is modified by this script.
##
## Usage (after approval):
##   Godot --path . --resolution 1280x720 res://tools/preview_grounded_stance.tscn

const OUT_DIR := "user://posture_abc"
const TOL := 0.02 # touching band, metres (model ~5.3 m; AABB noise ~1 mm)

const LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_local_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_local_001.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_local_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_local_001.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_local_001.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_right_001", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_local_001.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_local_001.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_right_001", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_local_001.tres", "slot": "leg_right"}},
}

# G experimental pose, version G1 (ALL values experimental-marked in logs):
# legs at Combat-Rest heights, mild flexion, torso/arms from C-hybrid.
# Ankle pitch/roll are COMPUTED from MechaFootIK.ankle_compensation (existing
# production math, preview-owned call), never hand-tuned.
const G_POSE := {
	"Body": Vector3(-5, 0, 0), "Head": Vector3(-2.5, 0, 0),
	"ArmLeft": Vector3(15, 5, -28), "ArmLeft/ForearmLeft": Vector3(32, 0, 12),
	"ArmRight": Vector3(15, -5, 28), "ArmRight/ForearmRight": Vector3(32, 0, -12),
	"LegLeft": Vector3(6, 10, -10), "LegLeft/ShinLeft": Vector3(-12, 0, 6),
	"LegRight": Vector3(6, -10, 10), "LegRight/ShinRight": Vector3(-12, 0, -6),
	"Body/drop": Vector3(0, -0.03, 0),
}

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


func _ready() -> void:
	var out := DirAccess.open("user://")
	if out == null or not out.dir_exists("posture_abc"):
		printerr("[GROUND] user://posture_abc missing (fail-closed, no repo fallback)")
		get_tree().quit(1)
		return
	_setup_stage()
	_overlay = Node3D.new()
	_overlay.name = "GroundedOverlay"
	add_child(_overlay)

	var mecha_h := await _assemble_frozen("H")
	_pose_hangar(mecha_h)
	var mecha_r := await _settle_rest_live()
	var mecha_g := await _assemble_frozen("G")
	await _pose_grounded_experimental(mecha_g)

	# Shared union framing over H/R/G silhouettes (identical for all captures).
	var union := AABB()
	var first := true
	for m in [mecha_h, mecha_r, mecha_g]:
		var sil := _silhouette_aabb(m)
		if first:
			union = sil
			first = false
		else:
			union = union.merge(sil)
	print("[GROUND] shared union pos=%s size=%s" % [_v3(union.position), _v3(union.size)])
	_frame_shared(union)

	for entry in [["H", mecha_h, "production reference"], ["R", mecha_r, "production live settle"], ["G", mecha_g, "EXPERIMENTAL preview-only"]]:
		var tag: String = entry[0]
		var mech: Node3D = entry[1]
		var kind: String = entry[2]
		_log_mode(tag, mech, kind)
		_set_layer_visibility(mech, true, true)
		_clear_overlay()
		await get_tree().process_frame
		for v in ["front", "side", "3q"]:
			_aim_camera(union, v)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_save_capture("GND_%s_%s.png" % [tag, v])
		await _capture_foot(mech, tag, "left")
		await _capture_foot(mech, tag, "right")
		await _capture_chain(mech, tag, "")
		_set_layer_visibility(mech, true, false)
		await get_tree().process_frame
		await _capture_chain(mech, tag, "_armor")
		_set_layer_visibility(mech, false, true)
		await get_tree().process_frame
		await _capture_chain(mech, tag, "_frame")
		_set_layer_visibility(mech, true, true)
	_compose_contact_sheet()
	if _failed:
		printerr("[GROUND] failures occurred (see above)")
		get_tree().quit(1)
	else:
		print("[GROUND] ALL_GROUNDED_DONE files=%d" % _saved.size())
		get_tree().quit(0)


func _assemble_frozen(tag: String) -> Node3D:
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
	print("[GROUND] %s assembled frozen, root=%s scale=%s" % [tag, _v3(mecha.global_position), _v3(mecha.scale)])
	return mecha


func _pose_hangar(mecha: Node3D) -> void:
	# Production showroom reference, unchanged. FootIK never runs (frozen).
	HangarGaragePanel.new().apply_tactical_idle_pose(mecha)
	print("[GROUND] H = production hangar pose, FootIK absent-by-freeze, floor physical-but-untouched")


func _settle_rest_live() -> Node3D:
	# Combat Rest through the REAL production path: live isolated instance on
	# the preview-owned mask-2 static floor; shipped drivers (procedural idle
	# + FootIK tail) settle it; then freeze to lock the pose for capture.
	# Zero production changes: the instance runs its own code as shipped.
	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha := base_res.instantiate() as Node3D
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame
	var pm := mecha.get_node_or_null("PartMeshManager")
	pm.refresh_from_loadout(LOADOUT)
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim != null:
		anim.set("stance_mode", "combat_crouch")
	for i in range(150):
		await get_tree().physics_frame
	var ik = mecha.get_node_or_null("FootIKSystem")
	var on_floor: bool = (mecha as CharacterBody3D).is_on_floor()
	print("[GROUND] R live settle done, stance=%s footik_present=%s ik_weight=%.3f on_floor=%s" % [str(anim.get("stance_mode")) if anim != null else "?", str(ik != null), float(ik.get("ik_weight")) if ik != null else -1.0, str(on_floor)])
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().process_frame
	return mecha


func _pose_grounded_experimental(mecha: Node3D) -> void:
	# G1: legs at Combat-Rest heights (production rest values, NOT hangar),
	# mild flexion, ankle leveled by existing ankle_compensation math.
	# Root NEVER moves (asserted in logs). Hip-Y settle loop below adjusts
	# only leg pivots symmetrically toward sole contact (FootIK does the same
	# class of adjustment in production).
	var rest: Dictionary = FrameVariantData.STANDARD_REST
	for path in ["LegLeft", "LegRight", "LegLeft/ShinLeft", "LegRight/ShinRight"]:
		var n := mecha.get_node_or_null(path) as Node3D
		n.position = rest[path]
	var body := mecha.get_node_or_null("Body") as Node3D
	for path in G_POSE:
		if String(path) == "Body/drop":
			continue
		var n := mecha.get_node_or_null(String(path)) as Node3D
		var deg: Vector3 = G_POSE[path]
		n.rotation = Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	body.position.y = (rest["Body"] as Vector3).y + (G_POSE["Body/drop"] as Vector3).y
	var head := mecha.get_node_or_null("Head") as Node3D
	head.position = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	_level_ankles(mecha)
	# Hip-Y settle: symmetric leg-pivot adjustments toward contact (max 3).
	for i in range(3):
		await get_tree().process_frame
		var sole: float = _bucket_aabb(mecha, "foot_l").position.y
		print("[GROUND] G settle iter %d sole=%.3f" % [i, sole])
		if absf(sole) <= TOL:
			break
		for path in ["LegLeft", "LegRight"]:
			var n := mecha.get_node_or_null(path) as Node3D
			n.position.y -= sole
		_level_ankles(mecha)
	print("[GROUND] G experimental pose applied, root_y=%.4f (must stay 0)" % mecha.global_position.y)


func _level_ankles(mecha: Node3D) -> void:
	for side in [["LegLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/FootLeft"], ["LegRight", "LegRight/ShinRight", "LegRight/ShinRight/FootRight"]]:
		var leg := mecha.get_node_or_null(side[0]) as Node3D
		var shin := mecha.get_node_or_null(side[1]) as Node3D
		var foot := mecha.get_node_or_null(side[2]) as Node3D
		if leg == null or shin == null or foot == null:
			continue
		var comp: Vector2 = MechaFootIK.ankle_compensation(leg.rotation.x, shin.rotation.x, leg.rotation.z, shin.rotation.z)
		foot.rotation = Vector3(comp.x, 0.0, comp.y)
		print("[GROUND] G ankle-level %s pitch=%.2f roll=%.2f (existing production math)" % [side[2], rad_to_deg(comp.x), rad_to_deg(comp.y)])


func _log_mode(tag: String, mecha: Node3D, kind: String) -> void:
	print("[GROUND] mode %s (%s) root=%s scale=%s" % [tag, kind, _v3(mecha.global_position), _v3(mecha.scale)])
	for path in ["Body", "Head", "LegLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/FootLeft"]:
		var n := mecha.get_node_or_null(path) as Node3D
		if n != null:
			var r: Vector3 = n.rotation
			print("[GROUND] %s %s rot_deg=(%.2f, %.2f, %.2f) pos=%s" % [tag, path, rad_to_deg(r.x), rad_to_deg(r.y), rad_to_deg(r.z), _v3(n.position)])
	for b in ["foot_l", "foot_r"]:
		var fb := _bucket_aabb(mecha, b)
		if fb.size.length_squared() > 0.0:
			print("[GROUND] %s %s minY=%.3f clearance=%+.3f(%s)" % [tag, b, fb.position.y, fb.position.y, _clearance_word(fb.position.y)])
		else:
			print("[GROUND] %s %s UNKNOWN (empty bucket)" % [tag, b])
	var hip := (mecha.get_node_or_null("LegLeft") as Node3D).global_position
	var head := mecha.get_node_or_null("Head") as Node3D
	var body := mecha.get_node_or_null("Body") as Node3D
	var collar: Vector3 = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)
	print("[GROUND] %s head-collar drift=%.4f (must stay ~0)" % [tag, (head.position - collar).length()])
	print("[GROUND] %s silhouette pos=%s size=%s" % [tag, _v3(_silhouette_aabb(mecha).position), _v3(_silhouette_aabb(mecha).size)])


func _clearance_word(v: float) -> String:
	if v < -TOL:
		return "PENETRATING"
	if v <= TOL:
		return "TOUCHING"
	return "FLOATING"


# --- overlay + capture helpers (same isolated-overlay pattern as diagnostics)


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


func _add_label(text: String, pos: Vector3, pixel: float = 0.006) -> void:
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
		_add_label("%s FOOT_%s sole=%+.3f %s" % [tag, side.to_upper(), sole, _clearance_word(sole)], Vector3(fc.x, sole + 0.45, fc.z), 0.005)
	else:
		_add_label("%s FOOT_%s sole=UNKNOWN" % [tag, side.to_upper()], Vector3(fc.x, 1.35, fc.z), 0.005)
	_add_label("ankle=%s shin_min=%.2f" % [_v3(ankle), sb.position.y], Vector3(fc.x, (sole + 0.28) if known else 1.12, fc.z), 0.004)
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 1.7
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(fc.x, 0.95, fc.z), 90.0 if side == "left" else 270.0, 6.0, 9.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("GND_%s_foot_%s.png" % [tag, side])


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
	_add_label("%s CHAIN%s hip=%s knee=%s" % [tag, suffix, _v3(hip), _v3(knee)], Vector3(hip.x, hip.y + 0.55, 0.0), 0.006)
	_add_label("ankle=%s sole=%s %s" % [_v3(ankle), ("%.3f" % sole) if known else "UNKNOWN", word], Vector3(hip.x, hip.y + 0.28, 0.0), 0.005)
	print("[GROUND] %s chain%s sole=%s(%s)" % [tag, suffix, ("%.3f" % sole) if known else "UNKNOWN", word])
	_ensure_cam()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 4.6
	_cam.near = 0.05
	_cam.far = 200.0
	_place_cam(Vector3(hip.x, 2.35, 0.0), 90.0, 6.0, 12.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("GND_%s_chain%s.png" % [tag, suffix])


func _ensure_cam() -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "GroundedOrthoCam"
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
	# Preview-owned PHYSICS floor (mask layer 2 = FootIK ray target). Visual
	# plane above has no collision; this body is what rays can actually hit.
	# Isolated to this preview scene; production floors untouched.
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
		_cam.name = "GroundedOrthoCam"
		add_child(_cam)
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(union.size.y, union.size.x / aspect) * 1.15
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.make_current()
	print("[GROUND] ortho size=%.3f focus=%s" % [_cam.size, _v3(union.get_center())])


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
		printerr("[GROUND] SAVE FAILED %s err=%d (no repo fallback by design)" % [fname, err])
		_failed = true
	else:
		_saved.append(fname)
		print("[GROUND] saved %s size=%s" % [fname, img.get_size()])


func _compose_contact_sheet() -> void:
	var cols: Array[String] = []
	for tag in ["H", "R", "G"]:
		for v in ["front", "side", "3q"]:
			cols.append("GND_%s_%s.png" % [tag, v])
	var cell_w := 480
	var cell_h := 270
	var sheet := Image.create(3 * cell_w, 3 * cell_h, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.16, 0.16, 0.18))
	var ok := true
	for i in range(cols.size()):
		var cell: Image = Image.load_from_file("%s/%s" % [OUT_DIR, cols[i]])
		if cell == null or cell.is_empty():
			printerr("[GROUND] sheet: cannot load %s (cell outstanding)" % cols[i])
			ok = false
			continue
		cell.resize(cell_w, cell_h)
		sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i((i % 3) * cell_w, (i / 3) * cell_h))
	if not ok:
		print("[GROUND] CONTACT_SHEET_OUTSTANDING (individual captures stand)")
		return
	var err := sheet.save_png("%s/GND_contact_sheet.png" % OUT_DIR)
	if err != OK:
		print("[GROUND] CONTACT_SHEET_OUTSTANDING save err=%d" % err)
	else:
		_saved.append("GND_contact_sheet.png")
		print("[GROUND] saved GND_contact_sheet.png size=%s" % sheet.get_size())


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
