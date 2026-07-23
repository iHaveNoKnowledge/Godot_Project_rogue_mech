extends CharacterBody3D

@export var move_speed: float = 3.0
@export var attack_range: float = 15.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 2.0

var target: Node3D = null
var attack_timer: float = 0.0
var health_system: Node = null


func _ready() -> void:
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	health_system = $HealthSystem
	_setup_hitbox()
	_setup_enemy_status()
	health_system.mecha_destroyed.connect(_on_destroyed)
	health_system.armor_broken.connect(_on_armor_broken)
	_scale_by_wanted_level()


func _on_destroyed() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	visible = false

	# Spawn loot
	var loot = get_node_or_null("/root/GameWorld/LootSystem")
	if loot == null:
		loot = LootSystem.new()
		loot.name = "LootSystem"
		get_tree().current_scene.add_child(loot)
	loot.spawn_enemy_loot(global_position)

	# Check if all enemies destroyed
	var enemies = get_tree().get_nodes_in_group("enemy")
	var alive = 0
	for e in enemies:
		if is_instance_valid(e) and e != self and e.health_system and not e.health_system.is_destroyed:
			alive += 1

	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)

	if alive == 0:
		tween.tween_callback(func():
			EventBus.combat_ended.emit(true)
			GameManager.return_to_board()
		)


func _on_armor_broken(slot_name: String) -> void:
	if slot_name == "body":
		health_system.is_destroyed = true
		health_system.mecha_destroyed.emit()
		EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))


func _setup_hitbox() -> void:
	var hitbox = $Hitbox
	if hitbox and hitbox.has_method("set_health_system"):
		hitbox.set_health_system(health_system)


func _setup_enemy_status() -> void:
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("setup_target"):
		status.setup_target(self)


func _physics_process(delta: float) -> void:
	if health_system == null or health_system.is_destroyed:
		velocity = Vector3.ZERO
		return

	_find_target()
	if target:
		_move_toward_target(delta)
		_try_attack(delta)


func _find_target() -> void:
	if target and is_instance_valid(target):
		return
	var mechas = get_tree().get_nodes_in_group("mecha")
	if mechas.size() > 0:
		target = mechas[0]


func _move_toward_target(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * move_speed
	velocity.y = -10.0
	move_and_slide()

	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _try_attack(delta: float) -> void:
	attack_timer -= delta
	if attack_timer > 0.0:
		return

	var distance = global_position.distance_to(target.global_position)
	if distance <= attack_range:
		attack_timer = attack_cooldown
		if target.has_method("take_damage"):
			target.take_damage(attack_damage, "melee")


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if health_system:
		health_system.take_damage(amount, damage_type)


func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if health_system == null:
		return

	var local_pos = to_local(world_pos)
	var target_part = _determine_hit_part(local_pos)

	if health_system.parts[target_part]["destroyed"]:
		target_part = _find_alive_part()
		if target_part == "":
			return

	health_system.take_damage_to_part(target_part, amount, damage_type)


func _find_alive_part() -> String:
	for slot in health_system.parts:
		if not health_system.parts[slot]["destroyed"]:
			return slot
	return ""


func _determine_hit_part(local_pos: Vector3) -> String:
	if local_pos.y > 2.0:
		return "head"
	elif local_pos.y > 0.5:
		if local_pos.x < -0.3:
			return "arm_left"
		elif local_pos.x > 0.3:
			return "arm_right"
		else:
			return "body"
	else:
		if local_pos.x < 0.0:
			return "leg_left"
		else:
			return "leg_right"


func _scale_by_wanted_level() -> void:
	var wanted = GlobalData.wanted_level
	if wanted <= 0:
		return

	# Scale stats based on wanted level
	var scale_factor = 1.0 + (wanted * 0.2)  # +20% per wanted level
	move_speed *= scale_factor
	attack_damage *= scale_factor
	attack_cooldown /= scale_factor

	# Scale health
	if health_system:
		for slot in health_system.parts:
			health_system.parts[slot]["armor_hp"] *= scale_factor
			health_system.parts[slot]["max_armor"] *= scale_factor
			health_system.parts[slot]["frame_hp"] *= scale_factor
			health_system.parts[slot]["max_frame"] *= scale_factor
		health_system._calculate_totals()

	# Visual feedback - higher wanted = redder color
	if wanted >= 3:
		var mesh = get_node_or_null("Body/BodyMesh")
		if mesh and mesh.material_override:
			mesh.material_override.albedo_color = Color(0.9, 0.1, 0.1, 1)
