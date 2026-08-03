extends CharacterBody3D

## Allied mech AI (our side). Fights alongside the player by chasing and
## engaging enemies (group "enemy"). Uses the shared enemy health system and
## archetype stat templates so it behaves like a friendly counterpart to the
## enemy grunts (GM vs Zaku).

@export var move_speed: float = 4.0
@export var attack_range: float = 60.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 0.9

## Archetype: 0=Rusher melee, 1=Ranged, 2=Heavy, 3=Support
@export var archetype: int = 1

## Fleet roster template id used to resolve name/hp/color.
@export var template_id: String = ""

var target: Node3D = null
var attack_timer: float = 0.0
var strafe_timer: float = 0.0
var strafe_direction: float = 1.0
var scan_timer: float = 0.0
var health_system: Node = null
var template_color: Color = Color(0.3, 0.6, 0.9, 1)

# Ammo for ranged archetypes
var ammo: int = 0
var max_ammo: int = 0
var reload_time: float = 3.0
var reload_timer: float = 0.0
var is_reloading: bool = false


func _ready() -> void:
	add_to_group("ally")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	health_system = $HealthSystem
	if template_id != "":
		_apply_template(GlobalData.get_ally_template(template_id))
	_setup_enemy_status()
	health_system.mecha_destroyed.connect(_on_destroyed)
	health_system.armor_broken.connect(_on_armor_broken)


func _apply_template(template: Dictionary) -> void:
	if template.is_empty():
		return
	move_speed = float(template.get("move_speed", move_speed))
	attack_range = float(template.get("attack_range", attack_range))
	attack_damage = float(template.get("attack_damage", attack_damage))
	attack_cooldown = float(template.get("attack_cooldown", attack_cooldown))
	archetype = int(template.get("archetype", archetype))
	template_color = template.get("color", template_color)
	_scale_to_template_hp(float(template.get("frame_hp", 55.0)))
	_set_name_label(template.get("name", "ALLY"))
	_apply_ally_color()


# Scale all frame_hp values so the total matches the template's frame HP budget.
func _scale_to_template_hp(target_total: float) -> void:
	if health_system == null or not health_system.parts is Dictionary:
		return
	var current_total = 0.0
	for slot in health_system.parts:
		current_total += float(health_system.parts[slot]["max_frame"])
	if current_total <= 0.0:
		return
	var factor = target_total / current_total
	for slot in health_system.parts:
		var part = health_system.parts[slot]
		part["max_frame"] = part["max_frame"] * factor
		part["frame_hp"] = part["max_frame"]
	if health_system.has_method("_calculate_totals"):
		health_system._calculate_totals()


func _set_name_label(text: String) -> void:
	var label = get_node_or_null("NameLabel3D")
	if label:
		label.text = text


func _apply_ally_color() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.material_override:
			child.material_override.albedo_color = template_color
		for sub in child.get_children():
			if sub is MeshInstance3D and sub.material_override:
				sub.material_override.albedo_color = template_color


func _setup_enemy_status() -> void:
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("setup_target"):
		status.setup_target(self)


func _physics_process(delta: float) -> void:
	if health_system == null or health_system.get("is_destroyed"):
		velocity = Vector3.ZERO
		return

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			is_reloading = false
			ammo = max_ammo

	_acquire_target()
	if target == null:
		velocity.y -= 10.0 * delta
		move_and_slide()
		return

	var distance = global_position.distance_to(target.global_position)

	if distance > attack_range:
		_move_toward_target(delta)
	else:
		_strafe_and_attack(delta)


func _acquire_target() -> void:
	if target and is_instance_valid(target) and not target.health_system.get("is_destroyed", false):
		return
	target = null
	scan_timer -= get_physics_process_delta_time()
	if scan_timer > 0.0:
		return
	scan_timer = 0.5
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0
	for e in enemies:
		if not is_instance_valid(e) or e.get("health_system") == null:
			continue
		if e.health_system.get("is_destroyed", false):
			continue
		var dist = global_position.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest = e
			nearest_dist = dist
	target = nearest


func _move_toward_target(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * move_speed
	velocity.y = -10.0
	move_and_slide()
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _strafe_and_attack(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 8.0 * delta)

	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	var strafe = global_transform.basis.x * strafe_direction * move_speed * 0.3
	velocity = strafe
	velocity.y = -10.0
	move_and_slide()

	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown
		_perform_attack()


func _perform_attack() -> void:
	match archetype:
		0:  # RUSHER - melee
			if target and target.has_method("take_damage"):
				target.take_damage(attack_damage, "melee")
		1, 2:  # RANGED / HEAVY - projectile
			if has_ammo():
				_fire_ranged()
				use_ammo()


func has_ammo() -> bool:
	return ammo > 0


func use_ammo() -> void:
	if max_ammo == 0:
		return
	ammo -= 1
	if ammo <= 0:
		is_reloading = true
		reload_timer = reload_time


func _fire_ranged() -> void:
	var from_pos = global_position + Vector3(0, 2, 0)
	var to_pos = target.global_position + Vector3(0, 1.5, 0)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)
	if result:
		var obstacle_dist = from_pos.distance_to(result["position"])
		var target_dist = from_pos.distance_to(to_pos)
		if obstacle_dist < target_dist * 0.8:
			return

	var projectile_scene = preload("res://scenes/mecha/effects/projectile.tscn")
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = from_pos

	var dir = (to_pos - from_pos).normalized()
	projectile.speed = 35.0
	projectile.damage = attack_damage
	projectile.damage_type = "kinetic"
	projectile.fired_by_enemy = false
	projectile.direction = dir
	projectile.look_at(from_pos + dir, Vector3.UP)


func _on_destroyed() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	visible = false
	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)


func _on_armor_broken(slot_name: String) -> void:
	if slot_name == "body":
		if health_system:
			health_system.set("is_destroyed", true)
			if health_system.has_signal("mecha_destroyed"):
				health_system.mecha_destroyed.emit()
		EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if health_system:
		health_system.take_damage(amount, damage_type)
