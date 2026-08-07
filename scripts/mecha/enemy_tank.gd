extends CharacterBody3D

var _loot_script = preload("res://scripts/systems/loot_system.gd")

@export var move_speed: float = 4.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 2.5

var archetype: int = 1  # RANGED
var target: Node3D = null
var attack_timer: float = 0.0

# Tank specific part statuses
var turret_destroyed: bool = false
var treads_destroyed: bool = false
var hull_destroyed: bool = false

var health_system: Node = null
@onready var turret_node: Node3D = get_node_or_null("TurretMesh")
@onready var treads_node: Node3D = get_node_or_null("TreadsMesh")
@onready var hull_node: Node3D = get_node_or_null("HullMesh")


func _ready() -> void:
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	_setup_health_system()
	_scale_by_wanted_level()


func _setup_health_system() -> void:
	var tank_health_script = preload("res://scripts/mecha/enemy_tank_health.gd")
	health_system = tank_health_script.new()
	health_system.name = "HealthSystem"
	add_child(health_system)
	health_system.mecha_destroyed.connect(_explode_and_destroy)


func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if health_system and health_system.has_method("take_damage_to_part"):
		var local_pos = to_local(world_pos)
		var target_part = "hull"
		if local_pos.y > 1.2:
			target_part = "turret"
		elif local_pos.y < 0.5:
			target_part = "treads"

		if health_system.has_method("take_damage_to_part_at"):
			health_system.take_damage_to_part_at(target_part, amount, world_pos, damage_type)
		elif health_system.has_method("take_damage_to_part"):
			health_system.take_damage_to_part(target_part, amount, damage_type)
		else:
			take_damage(amount, damage_type)


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if health_system and health_system.has_method("take_damage"):
		health_system.take_damage(amount, damage_type)


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic") -> void:
	if health_system and health_system.has_method("take_damage_to_part"):
		health_system.take_damage_to_part(slot_name, amount, damage_type)



func _on_part_destroyed(slot_name: String) -> void:
	match slot_name:
		"turret":
			turret_destroyed = true
			print("Tank Turret Destroyed! Weapons Offline.")
			if turret_node:
				turret_node.visible = false
		"treads":
			treads_destroyed = true
			move_speed = 0.0
			print("Tank Treads Destroyed! Mobility Kill.")
		"hull":
			hull_destroyed = true
			_explode_and_destroy()


func _physics_process(delta: float) -> void:
	if hull_destroyed or health_system.get("is_destroyed"):
		return

	# Acquire target
	if target == null or not is_instance_valid(target):
		var mechas = get_tree().get_nodes_in_group("mecha")
		if not mechas.is_empty():
			target = mechas[0]

	if target and is_instance_valid(target):
		var dist = global_position.distance_to(target.global_position)

		# Move if treads intact
		if not treads_destroyed and dist > 8.0:
			var dir = (target.global_position - global_position).normalized()
			dir.y = 0.0
			velocity = dir * move_speed
			velocity.y = -10.0
			move_and_slide()
			if dir.length() > 0.1:
				rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 5.0 * delta)

		# Rotate turret and shoot if turret intact
		if not turret_destroyed and dist <= attack_range:
			if turret_node:
				var t_dir = (target.global_position - turret_node.global_position).normalized()
				turret_node.rotation.y = lerp_angle(turret_node.rotation.y, atan2(t_dir.x, t_dir.z), 8.0 * delta)

			attack_timer -= delta
			if attack_timer <= 0.0:
				attack_timer = attack_cooldown
				_fire_tank_cannon()


func _fire_tank_cannon() -> void:
	if turret_destroyed or target == null:
		return

	var from_pos = global_position + Vector3(0, 1.5, 0)
	var to_pos = target.global_position + Vector3(0, 1.0, 0)

	var projectile_scene = preload("res://scenes/mecha/effects/projectile.tscn")
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = from_pos

	var dir = (to_pos - from_pos).normalized()
	projectile.speed = 35.0
	projectile.damage = attack_damage
	projectile.damage_type = "explosive"
	projectile.fired_by_enemy = true
	projectile.direction = dir
	projectile.look_at(from_pos + dir, Vector3.UP)


func _explode_and_destroy() -> void:
	if health_system:
		health_system.set("is_destroyed", true)
	EffectManager.spawn_explosion(global_position + Vector3(0, 1.0, 0))

	# Spawn loot
	var loot = get_node_or_null("/root/GameWorld/LootSystem")
	if loot == null:
		loot = Node3D.new()
		loot.set_script(_loot_script)
		loot.name = "LootSystem"
		get_tree().current_scene.add_child(loot)
	loot.spawn_enemy_loot(global_position)

	set_physics_process(false)
	visible = false

	var spawn_mgr = get_node_or_null("/root/GameWorld/SpawnManager")
	if spawn_mgr and spawn_mgr.has_method("notify_enemy_killed"):
		spawn_mgr.notify_enemy_killed()
	else:
		_check_fallback_victory()

	queue_free()


func _check_fallback_victory() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var alive = 0
	for e in enemies:
		if is_instance_valid(e) and e != self and e.get("health_system") != null:
			var hs = e.health_system
			if not hs.get("is_destroyed"):
				alive += 1
	if alive == 0:
		EventBus.combat_ended.emit(true)



func disable_movement() -> void:
	treads_destroyed = true
	move_speed = 0.0
	print("Tank Treads Destroyed! Mobility Kill.")


func disable_weapons() -> void:
	turret_destroyed = true
	print("Tank Turret Destroyed! Weapons Offline.")
	if turret_node:
		turret_node.visible = false


func _scale_by_wanted_level() -> void:
	var wanted = GlobalData.wanted_level
	if wanted <= 0:
		return
	var scale_factor = 1.0 + (wanted * 0.15)
	attack_damage *= scale_factor

