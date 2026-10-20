extends Node3D
## ISOLATED A/B/C POSTURE PREVIEW (E2-F2 Phase 2, separately approved).
##
## READ-ONLY vs the repository: assembles the real production model
## (mecha_base.tscn + wanzer_local_001 six-slot set via the established
## PartMeshManager path, hangar base pose via the real
## HangarGaragePanel.apply_tactical_idle_pose) on an isolated,
## driver-frozen instance. FootIK / MechaAnimation / AnimationPlayer clips /
## combat / locomotion NEVER run (whole subtree PROCESS_MODE_DISABLED, same
## precedent as tools/preview_tankmech.gd).
##
## OUTPUT ISOLATION: PNGs are written ONLY to user://posture_abc/ (Godot
## user-data dir, outside the repository). There is deliberately NO fallback
## that writes into the repository: a failed save prints an error and quits
## nonzero. Nothing in this script edits, imports, or regenerates project
## files, resources, or metadata.
##
## Usage (after approval):
##   Godot --path . --resolution 1280x720 res://tools/preview_posture_abc.tscn
##   POSTURE_VIEWS=front,side,3q to pick views (default all three).
## Poses A/B/C below are initial experimental candidates (degrees, absolute
## mecha-local euler XYZ per pivot + body drop). Head rotation preserves the
## production head-pivot contract (head == torso + relative counter-tilt);
## head POSITION reproduces the production collar anchor
## (Body.pos + HEAD_COLLAR_LOCAL rotated by torso pitch) without touching
## production scripts. No silent compensation is applied: feet may float or
## touch, and the measured foot height is reported as data.

const OUT_DIR := "user://posture_abc"

const LOADOUT := {
	"head": {"frame": {"id": "frame_head_01", "equipped": true}, "armor": {"id": "wanzer_local_head_001", "equipped": true, "path": "res://resources/mech/parts/head/wanzer_local_001.tres", "slot": "head"}},
	"body": {"frame": {"id": "frame_body_01", "equipped": true}, "armor": {"id": "wanzer_local_body_001", "equipped": true, "path": "res://resources/mech/parts/body/wanzer_local_001.tres", "slot": "body"}},
	"arm_left": {"frame": {"id": "frame_arm_left_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_left_001", "equipped": true, "path": "res://resources/mech/parts/arm_left/wanzer_local_001.tres", "slot": "arm_left"}},
	"arm_right": {"frame": {"id": "frame_arm_right_01", "equipped": true}, "armor": {"id": "wanzer_local_arm_right_001", "equipped": true, "path": "res://resources/mech/parts/arm_right/wanzer_local_001.tres", "slot": "arm_right"}},
	"leg_left": {"frame": {"id": "frame_leg_left_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_left_001", "equipped": true, "path": "res://resources/mech/parts/leg_left/wanzer_local_001.tres", "slot": "leg_left"}},
	"leg_right": {"frame": {"id": "frame_leg_right_01", "equipped": true}, "armor": {"id": "wanzer_local_leg_right_001", "equipped": true, "path": "res://resources/mech/parts/leg_right/wanzer_local_001.tres", "slot": "leg_right"}},
}

# Variant pose tables: pivot path -> Vector3(deg_x, deg_y, deg_z), absolute
# mecha-local euler. "Body/drop" is a rest-relative Y offset in mecha-local
# meters applied to the Body pivot only (same convention as combat idle drop).
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

const VIEW_PRESETS := {
	"front": {"az": 0.0, "el": 6.0},
	"side": {"az": 90.0, "el": 6.0},
	"3q": {"az": 38.0, "el": 14.0},
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
var _failed := false


func _ready() -> void:
	var out := DirAccess.open("user://")
	if out == null:
		printerr("[POSTURE-ABC] cannot open user:// (fail-closed, no repo fallback)")
		get_tree().quit(1)
		return
	if not out.dir_exists("posture_abc") and out.make_dir("posture_abc") != OK:
		printerr("[POSTURE-ABC] cannot create user://posture_abc (fail-closed)")
		get_tree().quit(1)
		return
	print("[POSTURE-ABC] output dir: " + OS.get_user_data_dir() + "/posture_abc")

	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	if base_res == null or not base_res.can_instantiate():
		printerr("[POSTURE-ABC] mecha_base.tscn missing")
		get_tree().quit(1)
		return
	var mecha := base_res.instantiate() as Node3D
	# Freeze BEFORE entering the tree: _ready still runs (setup works) but no
	# per-frame driver (gait, clips, FootIK, aim, action animator) can ever
	# overwrite the preview pose.
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame

	var pm := mecha.get_node_or_null("PartMeshManager")
	if pm == null or not pm.has_method("refresh_from_loadout"):
		printerr("[POSTURE-ABC] no PartMeshManager assembly path")
		get_tree().quit(1)
		return
	pm.refresh_from_loadout(LOADOUT)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[POSTURE-ABC] model: mecha_base.tscn + wanzer_local_001 six-slot set, root scale " + str(mecha.scale))

	# Pass 1: apply each variant, measure silhouette bounds, accumulate union.
	var union := AABB()
	var first := true
	for label in ["A", "B", "C"]:
		_apply_variant(mecha, label)
		await get_tree().process_frame
		_log_variant(mecha, label)
		_dump_slot_aabbs(mecha, label)
		_log_foot_height(mecha, label)
		var sil := _silhouette_aabb(mecha)
		print("[POSTURE-ABC] %s silhouette pos=%s size=%s" % [label, _v3(sil.position), _v3(sil.size)])
		if first:
			union = sil
			first = false
		else:
			union = union.merge(sil)
	print("[POSTURE-ABC] shared union pos=%s size=%s" % [_v3(union.position), _v3(union.size)])

	# Pass 2: identical ortho framing from the shared union; capture.
	_setup_stage()
	_frame_shared(mecha, union)
	var views: PackedStringArray = "front,side,3q".split(",")
	var env_opt := OS.get_environment("POSTURE_VIEWS")
	if env_opt != "":
		views = env_opt.split(",")
	for label in ["A", "B", "C"]:
		_apply_variant(mecha, label)
		_set_layer_visibility(mecha, true, true)
		await get_tree().process_frame
		for v in views:
			var view := String(v).strip_edges().to_lower()
			if not VIEW_PRESETS.has(view):
				printerr("[POSTURE-ABC] unknown view '%s' (skip)" % view)
				continue
			_aim_camera(mecha, union, view)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_save_capture("%s_%s.png" % [label, view])
	# Diagnostic extras on C/3q only: armor-only and frame-only via the
	# EXISTING container visibility (isolated instance; production untouched).
	_apply_variant(mecha, "C")
	_set_layer_visibility(mecha, true, false)
	await get_tree().process_frame
	_aim_camera(mecha, union, "3q")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("C_3q_armor_only.png")
	_set_layer_visibility(mecha, false, true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save_capture("C_3q_frame_only.png")

	if _failed:
		printerr("[POSTURE-ABC] one or more captures failed (see above)")
		get_tree().quit(1)
	else:
		print("[POSTURE-ABC] ALL_CAPTURES_DONE")
		get_tree().quit(0)


# Hangar base (real production function) + preview-only variant offsets.
# Rotations are set absolute per the pose tables; nothing else is touched.
func _apply_variant(mecha: Node3D, label: String) -> void:
	HangarGaragePanel.new().apply_tactical_idle_pose(mecha)
	var table: Dictionary = {"A": POSE_A, "B": POSE_B, "C": POSE_C}[label]
	var body := mecha.get_node_or_null("Body") as Node3D
	for path in table:
		if String(path) == "Body/drop":
			continue
		var n := mecha.get_node_or_null(String(path)) as Node3D
		if n == null:
			printerr("[POSTURE-ABC] %s: missing pivot %s" % [label, String(path)])
			_failed = true
			continue
		var deg: Vector3 = table[path]
		n.rotation = Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
	# Rest-relative body drop (combat-idle convention), then the production
	# collar anchor so the head follows torso pitch without touching prod code.
	if body != null:
		var hangar_body_y := (MechaScaleSystem.HANGAR_POSE["body_pos"] as Vector3).y
		body.position.y = hangar_body_y + (table["Body/drop"] as Vector3).y
		var head := mecha.get_node_or_null("Head") as Node3D
		if head != null:
			head.position = body.position + MechaRig.HEAD_COLLAR_LOCAL.rotated(Vector3.RIGHT, body.rotation.x)


func _log_variant(mecha: Node3D, label: String) -> void:
	for path in ["Body", "Head", "LegLeft", "LegLeft/ShinLeft", "ArmLeft", "ArmLeft/ForearmLeft"]:
		var n := mecha.get_node_or_null(path) as Node3D
		if n != null:
			var r: Vector3 = n.rotation
			print("[POSTURE-ABC] %s %s rot_deg=(%.2f, %.2f, %.2f) pos=%s" % [label, path, rad_to_deg(r.x), rad_to_deg(r.y), rad_to_deg(r.z), _v3(n.position)])


func _log_foot_height(mecha: Node, label: String) -> void:
	# Lowest rendered foot point vs the shared ground plane (y=0). Measured
	# fact, not a contact claim: a value above 0 means visible float.
	var lowest := 999.0
	for m in _collect_meshes(mecha):
		var mi := m as MeshInstance3D
		var anc := mi.get_parent()
		var in_foot := false
		while anc != null:
			if String(anc.name) in ["FootLeft", "FootRight"]:
				in_foot = true
				break
			anc = anc.get_parent()
		if in_foot:
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			lowest = minf(lowest, b.position.y)
	print("[POSTURE-ABC] %s foot_minY=%.3f (ground=0.000)" % [label, lowest])


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


func _collect_meshes(mecha: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _silhouette_aabb(mecha: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in _collect_meshes(mecha):
		var mi := m as MeshInstance3D
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


func _dump_slot_aabbs(mecha: Node, label: String) -> void:
	var per_slot := {}
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
			var mi := n as MeshInstance3D
			var b: AABB = mi.global_transform * mi.mesh.get_aabb()
			var bucket := ""
			var anc := mi.get_parent()
			while anc != null:
				if _BUCKETS.has(String(anc.name)):
					bucket = _BUCKETS[String(anc.name)]
					break
				anc = anc.get_parent()
			if bucket != "":
				per_slot[bucket] = b if not per_slot.has(bucket) else (per_slot[bucket] as AABB).merge(b)
		for c in n.get_children():
			stack.append(c)
	for slot in per_slot.keys():
		var b: AABB = per_slot[slot]
		print("[POSTURE-ABC] %s %-10s pos=%s size=%s minY=%.3f" % [label, slot, _v3(b.position), _v3(b.size), b.position.y])


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


func _frame_shared(mecha: Node, union: AABB) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "PostureOrthoCam"
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		add_child(_cam)
	var vp := get_viewport().get_visible_rect().size
	var aspect: float = vp.x / maxf(vp.y, 1.0)
	# Ortho size is vertical: fit union height AND width (via aspect) + margin.
	_cam.size = maxf(union.size.y, union.size.x / aspect) * 1.15
	_cam.near = 0.05
	_cam.far = 200.0
	_cam.make_current()
	print("[POSTURE-ABC] ortho size=%.3f focus=%s dist=%.2f" % [_cam.size, _v3(union.get_center()), maxf(union.size.y, union.size.x) * 2.0 + 4.0])


func _aim_camera(mecha: Node, union: AABB, view: String) -> void:
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
		printerr("[POSTURE-ABC] SAVE FAILED %s err=%d (no repo fallback by design)" % [fname, err])
		_failed = true
	else:
		print("[POSTURE-ABC] saved %s size=%s" % [fname, img.get_size()])


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
