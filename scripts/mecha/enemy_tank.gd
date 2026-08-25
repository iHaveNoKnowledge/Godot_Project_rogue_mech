extends CharacterBody3D

var _loot_script = preload("res://scripts/systems/loot_system.gd")

@export var move_speed: float = 4.0
@export var attack_range: float = 20.0
@export var attack_damage: float = 25.0
@export var attack_cooldown: float = 2.5

var archetype: int = 1  # RANGED
var target: Node3D = null
var attack_timer: float = 0.0
var stagger_timer: float = 0.0

# Tank specific part statuses
var turret_destroyed: bool = false
var treads_destroyed: bool = false
var hull_destroyed: bool = false

var health_system: Node = null

# Concealment state: set by the arena concealment system when this tank stands
# inside a cover footprint (tree/building) — hides the hull so it can't be seen.
var concealed: bool = false

# Shared firing core: owns cooldown + projectile spawning with the same rules
# as every other weapon (fire rate is still paced by attack_timer below).
var fire_core: WeaponCore = null
@onready var turret_node: Node3D = get_node_or_null("TurretMesh")
@onready var treads_node: Node3D = get_node_or_null("TreadsMesh")
@onready var hull_node: Node3D = get_node_or_null("HullMesh")


func _ready() -> void:
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	_setup_health_system()
	_scale_by_wanted_level()
	_build_fire_core()


func _setup_health_system() -> void:
	var enemy_health_script = preload("res://scripts/mecha/enemy_health.gd")
	health_system = enemy_health_script.new()
	health_system.name = "HealthSystem"
	health_system.layout = enemy_health_script.Layout.TANK
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


func set_concealed(on: bool) -> void:
	if concealed == on:
		return
	concealed = on


func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic") -> void:
	if health_system and health_system.has_method("take_damage_to_part"):
		health_system.take_damage_to_part(slot_name, amount, damage_type)


# Stagger interrupt: heavy impacts stun the tank (stops fire + gives a small
# knockback shove) so brief windows open up to flank it.
func apply_impact(amount: float, from_dir: Vector3) -> void:
	stagger_timer = maxf(stagger_timer, clampf(0.2 + amount * 0.015, 0.25, 1.0))
	from_dir.y = 0.0
	if from_dir.length() > 0.001:
		var shove = from_dir.normalized() * minf(amount * 2.0, 7.0)
		velocity.x += shove.x
		velocity.z += shove.z
	attack_timer = maxf(attack_timer, mini(attack_timer + 0.4, attack_cooldown))



func _hide_turret_visual() -> void:
	if turret_node and is_instance_valid(turret_node):
		# Clear any procedural damage overlay before hiding so its ShaderMaterial
		# does not stay alive on an invisible mesh and keep its variant resident.
		if turret_node is MeshInstance3D:
			(turret_node as MeshInstance3D).material_overlay = null
		turret_node.visible = false
	# Also tell the health system's damage visuals to drop the turret material
	# so the ShaderMaterial RID can be freed cleanly.
	if health_system and health_system.damage_visuals:
		health_system.damage_visuals.clear_slot_damage("turret")
	# Small disable puff so the turret kill reads visually
	if is_inside_tree():
		EffectManager.spawn_hit_spark(global_position + Vector3(0, 1.2, 0), Vector3.UP, "kinetic")


func _on_part_destroyed(slot_name: String) -> void:
	match slot_name:
		"turret":
			turret_destroyed = true
			print("Tank Turret Destroyed! Weapons Offline.")
			_hide_turret_visual()
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

	# Staggered: halt firing & movement while the impact shock plays out.
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		velocity.y = -10.0
		move_and_slide()
		return

	# Acquire target
	if target == null or not is_instance_valid(target):
		var mechas = get_tree().get_nodes_in_group("mecha")
		if not mechas.is_empty():
			target = mechas[0]

	if target == null or not is_instance_valid(target):
		# No target yet: apply gravity so the tank settles onto the ground at
		# spawn instead of hovering in mid-air until it finds one.
		velocity.y = -10.0
		move_and_slide()
		return

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


func _build_fire_core() -> void:
	fire_core = WeaponCore.from_stats({
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"max_ammo": 0,  # unlimited — the tank fires on its attack_timer
		"projectile_speed": 35.0,
		"damage_type": "explosive",
		"projectile_color": Color(0.55, 0.85, 0.45),
	})
	fire_core.fire_interval = 0.0


func _fire_tank_cannon() -> void:
	if turret_destroyed or target == null or fire_core == null:
		return

	var from_pos = global_position + Vector3(0, 1.5, 0)
	var to_pos = target.global_position + Vector3(0, 1.0, 0)
	var dir = (to_pos - from_pos).normalized()
	fire_core.try_fire(from_pos, dir, true, self)


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
	loot.spawn_enemy_loot(global_position, archetype)

	set_physics_process(false)
	visible = false

	var spawn_mgr = get_node_or_null("/root/GameWorld/SpawnManager")
	if spawn_mgr and spawn_mgr.has_method("notify_enemy_killed"):
		spawn_mgr.notify_enemy_killed()
	else:
		const SpawnManagerScript := preload("res://scripts/systems/spawn_manager.gd")
		SpawnManagerScript.check_all_enemies_defeated()

	queue_free()



func disable_movement() -> void:
	if treads_destroyed:
		return
	treads_destroyed = true
	move_speed = 0.0
	print("Tank Treads Destroyed! Mobility Kill.")


func disable_weapons() -> void:
	if turret_destroyed:
		return
	turret_destroyed = true
	print("Tank Turret Destroyed! Weapons Offline.")
	_hide_turret_visual()


func _scale_by_wanted_level() -> void:
	var wanted = GlobalData.board.wanted_level
	if wanted <= 0:
		return
	var scale_factor = 1.0 + (wanted * 0.15)
	attack_damage *= scale_factor

