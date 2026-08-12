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
	_init_ammo()
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


# Ranged/heavy allies need ammo, exactly like their enemy counterparts, or the
# "has_ammo" gate in _perform_attack blocks every shot and they stand there idle.
func _init_ammo() -> void:
	if archetype == 1:  # RANGED
		max_ammo = 25
		ammo = max_ammo
		reload_time = 3.0
	elif archetype == 2:  # HEAVY
		max_ammo = 5
		ammo = max_ammo
		reload_time = 4.0


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

	# Staggered: freeze AI actions while the stumble plays out.
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
		move_and_slide()
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
	if target and is_instance_valid(target) and target.health_system and not target.health_system.is_destroyed:
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
		if e.health_system.is_destroyed:
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
		0:  # RUSHER - melee swing (collision-based, see _perform_melee)
			_perform_melee()
		1, 2:  # RANGED / HEAVY - projectile
			if has_ammo():
				_fire_ranged()
				use_ammo()
		3:  # SUPPORT - heal nearest ally
			_heal_nearest_ally()


func _perform_melee() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir = target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	rotation.y = atan2(dir.x, dir.z)
	_spawn_melee_trail(dir)
	_check_melee_hit(dir)


func _spawn_melee_trail(direction: Vector3) -> void:
	var trail_count := 5
	var sweep_width := 5.0
	for i in range(trail_count):
		var t := float(i) / float(trail_count - 1)
		var trail := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(sweep_width, 0.08, 0.2)
		trail.mesh = box

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var alpha := 1.0 - t * 0.6
		mat.albedo_color = Color(0.5, 0.9, 1.0, alpha)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.7, 1.0)
		mat.emission_energy_multiplier = 5.0 - t * 3.0
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		get_tree().current_scene.add_child(trail)

		var height_offset := lerpf(1.8, 0.8, t)
		trail.global_position = global_position + Vector3(0, height_offset, 0) + direction * (1.2 + t * 1.2)
		trail.look_at(trail.global_position + direction, Vector3.UP)
		trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))
		trail.rotate_object_local(Vector3.UP, deg_to_rad(-30.0 + t * 60.0))

		var delay := t * 0.04
		var tween := get_tree().create_tween()
		tween.tween_interval(delay)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tween.tween_callback(trail.queue_free)


func _check_melee_hit(direction: Vector3) -> void:
	# Collision-based melee: only hits if an enemy body is actually in front
	# within reach along the swing arc — no lock-on.
	var space_state = get_viewport().get_world_3d().direct_space_state
	var from_pos = global_position + Vector3(0, 1.5, 0)
	var end_pos = from_pos + direction * attack_range
	var query = PhysicsRayQueryParameters3D.create(from_pos, end_pos)
	# Layer 8 = Enemy bodies; layer 2 = Environment (walls block swings).
	query.collision_mask = 8 | 2
	var result = space_state.intersect_ray(query)
	if not result:
		return

	var collider: CollisionObject3D = result["collider"]
	# If the ray stopped on a wall/cover first, the swing whiffs.
	if collider.collision_layer & 2 != 0:
		return

	var victim: Node = collider
	while victim and not victim.has_method("take_damage"):
		victim = victim.get_parent()
	if victim == null or not victim.has_method("take_damage"):
		return

	victim.take_damage(attack_damage, "melee")
	EffectManager.spawn_damage_number(result["position"] + Vector3(0, 1, 0), attack_damage, Color(1, 0.5, 0))


func _heal_nearest_ally() -> void:
	var allies = get_tree().get_nodes_in_group("ally")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0
	for a in allies:
		if not is_instance_valid(a) or a == self:
			continue
		if a.get("health_system") == null or a.health_system.is_destroyed:
			continue
		var dist = global_position.distance_to(a.global_position)
		if dist < 40.0 and dist < nearest_dist:
			nearest = a
			nearest_dist = dist
	if nearest and nearest.health_system and nearest.health_system.has_method("take_heal"):
		nearest.health_system.take_heal(5.0)
		EffectManager.spawn_damage_number(nearest.global_position + Vector3(0, 3, 0), 5.0, Color(0.2, 1.0, 0.2))


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

	# Fire sound at the muzzle so the player can hear their ally fighting back.
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("machine_gun", from_pos, -3.0)

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


# Called when the ally eats an impact-heavy enemy shot. Brief stagger so hits
# feel real, mirroring the enemy behavior (enemy_dummy.apply_impact).
var stagger_timer: float = 0.0


func apply_impact(amount: float, from_dir: Vector3) -> void:
	stagger_timer = maxf(stagger_timer, clampf(0.25 + amount * 0.02, 0.3, 1.2))
	from_dir.y = 0.0
	if from_dir.length() > 0.001:
		var shove = from_dir.normalized() * minf(amount * 2.5, 9.0)
		velocity.x += shove.x
		velocity.z += shove.z
	attack_timer = maxf(attack_timer, 0.0)
