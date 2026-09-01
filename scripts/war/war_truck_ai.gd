extends Node
class_name WarTruckAI

## Simple logistic patrol AI for trucks created by WarLogisticSystem
## Loops between depot and nearest ore nodes, using NavigationAgent3D if a NavMesh exists,
## otherwise direct move. Attach to each truck CharacterBody3D.

var truck: CharacterBody3D = null
var agent: NavigationAgent3D = null
var depot_pos: Vector3 = Vector3.ZERO
var target_ore: Node3D = null
var state: String = "to_ore" # to_ore, to_depot
var speed: float = 7.0
var _stuck_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO

func setup(p_truck: CharacterBody3D) -> void:
	truck = p_truck
	depot_pos = truck.get_meta("depot_pos", truck.position)
	agent = truck.get_node_or_null("NavAgent") as NavigationAgent3D
	if agent:
		agent.path_desired_distance = 1.2
		agent.target_desired_distance = 1.8
	_last_pos = truck.global_position if truck.is_inside_tree() else truck.position
	_pick_next_ore()

func _ready() -> void:
	if truck == null:
		# Auto-setup when added as child of truck
		var p = get_parent() as CharacterBody3D
		if p:
			setup(p)
	set_physics_process(true)

func _pick_next_ore() -> void:
	var ores := get_tree().get_nodes_in_group("ore_node") if get_tree() else []
	var best: Node3D = null
	var best_d := INF
	var tpos := truck.global_position
	for o in ores:
		if not is_instance_valid(o) or not o is Node3D:
			continue
		if o.get_meta("collected", false):
			continue
		if not (o as Node3D).visible:
			continue
		var d := tpos.distance_to((o as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = o as Node3D
	target_ore = best
	if target_ore:
		state = "to_ore"
		if agent and _has_navmesh():
			agent.target_position = target_ore.global_position
	else:
		# No ore left -> go to depot and idle
		state = "to_depot"
		if agent and _has_navmesh():
			agent.target_position = depot_pos

func _has_navmesh() -> bool:
	if agent == null:
		return false
	var map := agent.get_navigation_map()
	return map != RID()

func _physics_process(delta: float) -> void:
	if truck == null or not is_instance_valid(truck):
		queue_free()
		return
	if not truck.get_meta("is_ai_driven", true):
		return # player driving
	# Unstuck check
	if truck.global_position.distance_to(_last_pos) < 0.2:
		_stuck_timer += delta
		if _stuck_timer > 2.5:
			_pick_next_ore()
			_stuck_timer = 0.0
	else:
		_stuck_timer = 0.0
	_last_pos = truck.global_position

	# State machine
	match state:
		"to_ore":
			if target_ore == null or not is_instance_valid(target_ore) or not target_ore.visible:
				_pick_next_ore()
				return
			var dest: Vector3 = target_ore.global_position
			if not _move_toward(dest, delta):
				return
			if truck.global_position.distance_to(dest) < 3.0:
				# Try to collect if ore still there
				if target_ore.has_method("collect"):
					target_ore.collect(truck)
				state = "to_depot"
				if agent and _has_navmesh():
					agent.target_position = depot_pos
		"to_depot":
			if truck.global_position.distance_to(depot_pos) < 4.0:
				# Deliver hauled ore
				var hauled: int = int(truck.get_meta("hauled_ore", 0))
				if hauled > 0:
					# Deposit to GlobalData or depot base
					truck.set_meta("hauled_ore", 0)
					truck.set_meta("hauled_scrap", 0)
					# Visual feedback
					if truck.get_tree():
						var lbl := Label3D.new()
						lbl.text = "+%d ORE DELIVERED" % hauled
						lbl.font_size = 18
						lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
						lbl.no_depth_test = true
						lbl.position = Vector3(0, 3.0, 0)
						truck.add_child(lbl)
						var tw := lbl.create_tween()
						tw.tween_property(lbl, "position:y", 5.0, 1.2)
						tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.2)
						tw.tween_callback(lbl.queue_free)
				_pick_next_ore()
			else:
				_move_toward(depot_pos, delta)

func _move_toward(dest: Vector3, delta: float) -> bool:
	var dir: Vector3
	if agent and _has_navmesh() and not agent.is_navigation_finished():
		var next: Vector3 = agent.get_next_path_position()
		dir = (next - truck.global_position)
	else:
		dir = (dest - truck.global_position)
	dir.y = 0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	var vel := dir * speed
	truck.velocity.x = vel.x
	truck.velocity.z = vel.z
	truck.velocity.y = -2.0 # keep grounded
	truck.move_and_slide()
	if dir.length() > 0.01:
		truck.rotation.y = lerp_angle(truck.rotation.y, atan2(dir.x, dir.z), 6.0 * delta)
	return true
