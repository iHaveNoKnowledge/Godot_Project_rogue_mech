extends Node3D

@export var attack_range: float = 3.0
@export var attack_damage: float = 40.0
@export var attack_cooldown: float = 1.0
@export var swing_speed: float = 10.0

var attack_timer: float = 0.0
var is_swinging: bool = false
var swing_angle: float = 0.0
var swing_direction: Vector3 = Vector3.FORWARD
var trail_scene: PackedScene = null


func _ready() -> void:
	trail_scene = load("res://scripts/effects/melee_trail.gd") as PackedScene


func _process(delta: float) -> void:
	attack_timer -= delta

	if is_swinging:
		_update_swing(delta)


func can_attack() -> bool:
	return attack_timer <= 0.0


func attack(mecha: Node3D) -> void:
	if not can_attack():
		return

	attack_timer = attack_cooldown
	is_swinging = true
	swing_angle = 0.0

	_face_crosshair(mecha)
	_spawn_trail()
	_check_hit(mecha)


func _face_crosshair(mecha: Node3D) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var fwd = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd.length() > 0.1:
		var target_angle = atan2(-fwd.x, -fwd.z)
		mecha.rotation.y = target_angle
		swing_direction = fwd


func _spawn_trail() -> void:
	var trail = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.3, 2.0, 0.05)
	trail.mesh = box

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.8, 0.9, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.no_depth_test = true
	trail.material_override = mat

	get_tree().current_scene.add_child(trail)
	trail.global_position = global_position + swing_direction * 1.5 + Vector3(0, 1, 0)
	trail.look_at(trail.global_position + swing_direction, Vector3.UP)
	trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))

	var tween = get_tree().create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(trail.queue_free)


func _update_swing(delta: float) -> void:
	swing_angle += swing_speed * delta
	if swing_angle >= 180.0:
		is_swinging = false


func _check_hit(mecha: Node3D) -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var mecha_pos = mecha.global_position + Vector3(0, 1.5, 0)
	var end_pos = mecha_pos + swing_direction * attack_range

	var query = PhysicsRayQueryParameters3D.create(mecha_pos, end_pos)
	query.collision_mask = 8
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result["collider"]
		if collider.has_method("take_damage"):
			collider.take_damage(attack_damage, "melee")
			EffectManager.spawn_damage_number(result["position"] + Vector3(0, 1, 0), attack_damage, Color(1, 0.5, 0))
