extends Node
class_name WarConstructionAI

## AI สำหรับรถก่อสร้าง — ขน ore จาก depot ไปจุดก่อสร้าง แล้วสร้างฐาน
## States: idle -> to_depot (load) -> to_site (build) -> building

var truck: CharacterBody3D = null
var agent: NavigationAgent3D = null
var depot_pos: Vector3 = Vector3.ZERO
var build_site: Vector3 = Vector3.ZERO
var build_type: String = "outpost" # outpost / bunker / pipeline
var state: String = "idle"
var speed: float = 6.0
var build_time: float = 12.0
var _build_timer: float = 0.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _ore_needed: int = 120
var _ore_loaded: int = 0

func setup(p_truck: CharacterBody3D) -> void:
	truck = p_truck
	depot_pos = truck.get_meta("depot_pos", truck.position)
	agent = truck.get_node_or_null("NavAgent") as NavigationAgent3D
	_last_pos = truck.global_position if truck.is_inside_tree() else truck.position
	_pick_next_site()

func _ready() -> void:
	if truck == null:
		var p = get_parent() as CharacterBody3D
		if p:
			setup(p)
	set_physics_process(true)

func _pick_next_site() -> void:
	# หา build site จาก WarConstructionSystem queue หรือ random mid-map
	var sites := get_tree().get_nodes_in_group("construction_site") if get_tree() else []
	var best: Node3D = null
	var best_d := INF
	for s in sites:
		if not is_instance_valid(s) or not s is Node3D:
			continue
		if s.get_meta("built", false):
			continue
		var d := truck.global_position.distance_to((s as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = s as Node3D
	if best:
		build_site = best.global_position
		build_type = str(best.get_meta("build_type", "outpost"))
		state = "to_depot" if _ore_loaded < _ore_needed else "to_site"
		if agent and _has_navmesh():
			agent.target_position = depot_pos if state == "to_depot" else build_site
	else:
		# ไม่มี site → idle ที่ depot
		state = "idle"
		if agent and _has_navmesh():
			agent.target_position = depot_pos

func _has_navmesh() -> bool:
	if agent == null:
		return false
	return agent.get_navigation_map() != RID()

func _physics_process(delta: float) -> void:
	if truck == null or not is_instance_valid(truck):
		queue_free()
		return
	if not truck.get_meta("is_ai_driven", true):
		return
	# Unstuck
	if truck.global_position.distance_to(_last_pos) < 0.2:
		_stuck_timer += delta
		if _stuck_timer > 3.0:
			_pick_next_site()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	_last_pos = truck.global_position

	match state:
		"idle":
			if truck.global_position.distance_to(depot_pos) > 4.0:
				_move_toward(depot_pos, delta)
			else:
				_pick_next_site()
		"to_depot":
			if truck.global_position.distance_to(depot_pos) < 4.0:
				# Load ore from depot (consume GlobalData if available)
				_ore_loaded = _ore_needed
				truck.set_meta("hauled_ore", _ore_loaded)
				_flash("+LOAD %d ORE" % _ore_loaded, Color(0.85, 0.65, 0.2))
				state = "to_site"
				if agent and _has_navmesh():
					agent.target_position = build_site
			else:
				_move_toward(depot_pos, delta)
		"to_site":
			if truck.global_position.distance_to(build_site) < 5.0:
				state = "building"
				_build_timer = build_time
				_flash("CONSTRUCTING...", Color(0.4, 0.8, 1.0))
			else:
				_move_toward(build_site, delta)
		"building":
			_build_timer -= delta
			# เล่น VFX หมุน crane
			var crane = truck.get_node_or_null("CraneArm")
			if crane:
				crane.rotation.y += delta * 1.2
			if _build_timer <= 0:
				_complete_build()
				_ore_loaded = 0
				truck.set_meta("hauled_ore", 0)
				state = "idle"
				_pick_next_site()

func _move_toward(dest: Vector3, delta: float) -> void:
	var dir: Vector3
	if agent and _has_navmesh() and not agent.is_navigation_finished():
		dir = (agent.get_next_path_position() - truck.global_position)
	else:
		dir = (dest - truck.global_position)
	dir.y = 0
	if dir.length() < 0.1:
		return
	dir = dir.normalized()
	truck.velocity.x = dir.x * speed
	truck.velocity.z = dir.z * speed
	truck.velocity.y = -2.0
	truck.move_and_slide()
	if dir.length() > 0.01:
		truck.rotation.y = lerp_angle(truck.rotation.y, atan2(dir.x, dir.z), 5.0 * delta)

func _complete_build() -> void:
	# หา site node ที่ build_site
	var sites := get_tree().get_nodes_in_group("construction_site") if get_tree() else []
	var target: Node3D = null
	for s in sites:
		if s is Node3D and (s as Node3D).global_position.distance_to(build_site) < 1.0:
			target = s as Node3D
			break
	if target == null:
		# ไม่มี site marker → สร้าง outpost ตรง build_site เลย
		var outpost = WarBiomeGenerator.spawn_military_outpost(truck.get_parent(), build_site, true)
		if outpost:
			outpost.add_to_group("solid_obstacle")
		_flash("OUTPOST BUILT!", Color(0.5, 1.0, 0.5))
		return
	# มี marker → สร้างตาม type
	match build_type:
		"outpost":
			WarBiomeGenerator.spawn_military_outpost(truck.get_parent(), target.global_position, true)
		"bunker":
			WarBiomeGenerator.spawn_military_outpost(truck.get_parent(), target.global_position, true)
		"ruins":
			WarBiomeGenerator.spawn_frontline_ruins(truck.get_parent(), target.global_position)
		_:
			WarBiomeGenerator.spawn_military_outpost(truck.get_parent(), target.global_position, true)
	target.set_meta("built", true)
	target.visible = false
	_flash("BUILT: %s" % build_type.to_upper(), Color(0.5, 1.0, 0.5))
	# Smoke VFX
	var puff := GPUParticles3D.new()
	puff.position = target.global_position + Vector3(0, 1.5, 0)
	puff.emitting = true
	puff.lifetime = 1.2
	puff.amount = 12
	puff.process_material = ParticleProcessMaterial.new()
	truck.get_parent().add_child(puff)
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(puff): puff.queue_free())

func _flash(txt: String, col: Color) -> void:
	if not truck.get_tree():
		return
	var lbl := Label3D.new()
	lbl.text = txt
	lbl.font_size = 18
	lbl.modulate = col
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = Vector3(0, 3.5, 0)
	truck.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", 5.5, 1.2)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.2)
	tw.tween_callback(lbl.queue_free)
