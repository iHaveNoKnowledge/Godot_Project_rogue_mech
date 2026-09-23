extends Node3D
## Preview: assemble mecha_base with the tankmech armor set, then save PNG
## snapshots of the viewport for visual proportion checks (run windowed).
## Usage:
##   Godot --path . --resolution 1280x720 res://tools/preview_tankmech.tscn
##   TANKMECH_ANGLES=front,side,back,3q to pick angles (default all four)
## Also prints measured world-space AABBs per armor slot so proportion
## decisions come from numbers, not eyeballing alone.

const OUT_PATH := "user://tankmech_preview"
## Relative fallback when running from the project root.
const OUT_ABS := "tools/tankmech_preview"
## Camera presets: azimuth degrees around the mecha (0 = looking at the front
## -Z face) and elevation degrees above the horizon.
const ANGLE_PRESETS := {
	"front": {"az": 0.0, "el": 8.0},
	"side": {"az": 90.0, "el": 8.0},
	"back": {"az": 180.0, "el": 8.0},
	"3q": {"az": 38.0, "el": 16.0},
}

var _cam: Camera3D


func _ready() -> void:
	var base_res: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha := base_res.instantiate()
	# Freeze the whole subtree BEFORE it enters the tree: the controller would
	# otherwise pose the rig every frame and skew the measured AABBs. _ready
	# still runs (setup code works), but per-frame posing/animation/IK stops.
	mecha.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mecha)
	await get_tree().process_frame
	await get_tree().process_frame

	var pm := mecha.get_node_or_null("PartMeshManager")
	if pm == null:
		printerr("[PREVIEW] no PartMeshManager")
		get_tree().quit(1)
		return
	var slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var loadout := {}
	for slot in slots:
		var res_path := "res://resources/mech/parts/%s/tankmech_%s.tres" % [slot, slot]
		loadout[slot] = {
			"frame": {"id": "frame_%s_01" % slot, "equipped": true},
			"armor": {"id": "tankmech_%s" % slot, "equipped": true,
				"path": res_path, "slot": slot},
		}
	pm.refresh_from_loadout(loadout)
	await get_tree().process_frame
	await get_tree().process_frame

	_dump_slot_aabbs(mecha)

	var angles: PackedStringArray = "front,side,back,3q".split(",")
	var env_opt := OS.get_environment("TANKMECH_ANGLES")
	if env_opt != "":
		angles = env_opt.split(",")
	for ang in angles:
		var label := String(ang).strip_edges().to_lower()
		if not ANGLE_PRESETS.has(label):
			printerr("[PREVIEW] unknown angle '%s' (skip; try front/side/back/3q)" % label)
			continue
		_frame_camera(mecha, label)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%s.png" % [OUT_ABS, label]
		var err := img.save_png(path)
		if err != OK:
			err = img.save_png("%s_%s.png" % [OUT_PATH, label])
		print("[PREVIEW] saved %s (err=%d) size=%s" % [path, err, img.get_size()])
	get_tree().quit(0)


## Merged world-space AABB per armor bucket. Armor containers are all named
## "ArmorMesh" (one per slot parent), so bucket by the rig ancestor:
## Head/Body/ArmLeft/ForearmLeft/LegLeft/ShinLeft/FootLeft (and _R twins).
const _BUCKETS := {
	"Head": "head", "Body": "body",
	"ArmLeft": "shoulder_l", "ArmRight": "shoulder_r",
	"ForearmLeft": "forearm_l", "ForearmRight": "forearm_r",
	"LegLeft": "thigh_l", "LegRight": "thigh_r",
	"ShinLeft": "shin_l", "ShinRight": "shin_r",
	"FootLeft": "foot_l", "FootRight": "foot_r",
}


func _dump_slot_aabbs(mecha: Node) -> void:
	var per_slot := {}
	var stack: Array[Node] = [mecha]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			var bucket := ""
			var anc := mi.get_parent()
			while anc != null:
				if _BUCKETS.has(String(anc.name)):
					bucket = _BUCKETS[String(anc.name)]
					break
				anc = anc.get_parent()
			if bucket != "":
				per_slot[bucket] = aabb if not per_slot.has(bucket) \
						else (per_slot[bucket] as AABB).merge(aabb)
		for c in n.get_children():
			stack.append(c)
	var all := AABB()
	var first := true
	for slot in per_slot.keys():
		var b: AABB = per_slot[slot]
		if first:
			all = b
			first = false
		else:
			all = all.merge(b)
		print("[AUDIT] %-11s pos=%s size=%s" % [slot, _v3(b.position), _v3(b.size)])
	print("[AUDIT] %-11s pos=%s size=%s" % ["SILHOUETTE", _v3(all.position), _v3(all.size)])


func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func _frame_camera(mecha: Node, label: String) -> void:
	if _cam == null:
		_cam = Camera3D.new()
		_cam.name = "PreviewCam"
		add_child(_cam)
		_ensure_stage()
	_cam.make_current()

	# Orbit preset around the mecha: azimuth 0 looks at the front (-Z face).
	var preset: Dictionary = ANGLE_PRESETS[label]
	var az: float = deg_to_rad(preset["az"])
	var el: float = deg_to_rad(preset["el"])
	var focus: Vector3 = (mecha as Node3D).global_position + Vector3(0, 3.0, 0)
	var dist := 8.6
	var offset := Vector3(
		sin(az) * cos(el),
		sin(el),
		-cos(az) * cos(el)
	) * dist
	_cam.global_position = focus + offset
	_cam.look_at(focus, Vector3.UP)
	_cam.fov = 45.0


func _ensure_stage() -> void:
	# Soft studio lighting: key + fill + rim, faint ambient.
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

	# Ground plane so the feet read against a floor.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.72, 0.72, 0.74)
	ground.material_override = gmat
	add_child(ground)
