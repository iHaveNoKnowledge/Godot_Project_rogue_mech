extends EnemyState

## Attack state: execute attack when in range.

var attack_timer: float = 0.0
var strafe_timer: float = 0.0
var strafe_direction: float = 0.0

# --- Attack telegraph: the enemy blinks red + plays a rising warning sound for
# the last ~0.35x of its cooldown so the player sees/hears the shot coming. ---
const TELEGRAPH_FRACTION := 0.35
const TELEGRAPH_MIN := 0.35
const TELEGRAPH_MAX := 0.9
const BLINK_INTERVAL := 0.14
var _telegraph_active: bool = false
var _telegraph_remaining: float = 0.0
var _blink_timer: float = 0.0
var _flash_visible: bool = false

# Melee swing direction, committed when the telegraph starts so the player has
# time to dodge out of the arc. Prevents lock-on guaranteed hits.
var _melee_swing_dir: Vector3 = Vector3.ZERO


func enter() -> void:
	# Small delay before the first attack so the telegraph has time to play.
	attack_timer = minf(enemy.attack_cooldown, 0.9)
	strafe_timer = 0.0
	strafe_direction = [-1.0, 1.0][randi() % 2]
	_telegraph_active = false
	_telegraph_remaining = 0.0
	_blink_timer = 0.0
	_flash_visible = false
	_melee_swing_dir = Vector3.ZERO
	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)


func exit() -> void:
	# Never leave the enemy stuck glowing red when it switches states.
	_telegraph_active = false
	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance = enemy.global_position.distance_to(enemy.target.global_position)

	# If target moved out of range, chase again
	if distance > enemy.attack_range * 1.2:
		state_machine.transition_to("StateChase")
		return

	# Drained pool: break off and recharge rather than fight on empty.
	if enemy.is_low_energy():
		enemy.flee_reason = "energy"
		state_machine.transition_to("StateFlee")
		return

	# Low HP check
	if enemy.health_system and _is_low_hp():
		enemy.flee_reason = "hp"
		state_machine.transition_to("StateFlee")
		return

	# Face target
	var direction = (enemy.target.global_position - enemy.global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(direction.x, direction.z), 8.0 * delta)

	# Slight strafe while attacking
	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	var strafe = enemy.global_transform.basis.x * strafe_direction * enemy.move_speed * 0.3
	enemy.velocity = strafe
	enemy.velocity.y = -10.0
	enemy.move_and_slide()

	# Attack
	attack_timer -= delta
	# Start the warning telegraph as soon as we enter the pre-fire window, so the
	# player sees the red blink and hears the rising tone BEFORE the shot lands.
	# The swing direction is committed exactly once per cycle: once _melee_swing_dir
	# is set, never re-snapshot it (the telegraph flag is cleared right before the
	# swing fires, which would otherwise overwrite the aimed arc with the target's
	# current position and make dodging impossible).
	if not _telegraph_active and _melee_swing_dir == Vector3.ZERO and attack_timer <= _telegraph_duration():
		_telegraph_active = true
		_telegraph_remaining = attack_timer
		_blink_timer = 0.0
		_flash_visible = false
		_snapshot_melee_swing_dir()
		if enemy.get_tree() and enemy.get_tree().root.has_node("AudioManager"):
			AudioManager.play_enemy_warning(enemy.global_position + Vector3(0, 2, 0))
	_update_telegraph(delta)
	if attack_timer <= 0.0:
		attack_timer = enemy.attack_cooldown
		_telegraph_active = false
		_perform_attack()
		# Every attack action draws from the shared energy pool, so sustained
		# fire (and rusher dashes) gradually drain the enemy until it breaks
		# off to recharge instead of fighting forever.
		enemy.energy = maxf(enemy.energy - enemy.ATTACK_ENERGY_COST, 0.0)


# The warning lasts a fraction of the cooldown (clamped) so fast ranged units
# blink briefly and heavy hitters telegraph longer, but never longer than ~0.9s.
func _telegraph_duration() -> float:
	var base = enemy.attack_cooldown * TELEGRAPH_FRACTION
	return clampf(base, TELEGRAPH_MIN, TELEGRAPH_MAX)


func _update_telegraph(delta: float) -> void:
	if not _telegraph_active or _telegraph_remaining <= 0.0:
		return
	_telegraph_remaining -= delta
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = BLINK_INTERVAL
		_flash_visible = not _flash_visible
		if enemy and enemy.has_method("set_attack_flash"):
			enemy.set_attack_flash(_flash_visible)
	if _telegraph_remaining <= 0.0:
		_telegraph_active = false
		if enemy and enemy.has_method("set_attack_flash"):
			enemy.set_attack_flash(false)


func _perform_attack() -> void:
	var archetype = enemy.archetype if enemy.get("archetype") != null else 0

	match archetype:
		0:  # RUSHER - melee swing (collision-based, see _perform_melee)
			_perform_melee()
		1:  # RANGED - projectile
			if enemy.has_ammo():
				_fire_ranged()
			else:
				state_machine.transition_to("StateChase")
		2:  # HEAVY - charge (handled by state_charge)
			pass
		3:  # SUPPORT - heal nearest ally
			_heal_nearest_ally()


func _heal_nearest_ally() -> void:
	var enemies = enemy.get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0

	for e in enemies:
		if not is_instance_valid(e) or e == enemy:
			continue
		if not e.health_system or e.health_system.is_destroyed:
			continue
		var dist = enemy.global_position.distance_to(e.global_position)
		if dist < 40.0 and dist < nearest_dist:
			nearest = e
			nearest_dist = dist

	if nearest and nearest.health_system and nearest.health_system.has_method("take_heal"):
		nearest.health_system.take_heal(5.0)
		# Visual feedback
		EffectManager.spawn_damage_number(nearest.global_position + Vector3(0, 3, 0), 5.0, Color(0.2, 1.0, 0.2))


# Freeze the melee swing direction the moment the telegraph starts, so the
# player can sidestep or boost out of the arc before the swing connects.
func _snapshot_melee_swing_dir() -> void:
	if enemy.archetype != 0 or not enemy.target or not is_instance_valid(enemy.target):
		return
	var dir: Vector3 = enemy.target.global_position - enemy.global_position
	dir.y = 0.0
	_melee_swing_dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO


func _perform_melee() -> void:
	var dir := _melee_swing_dir
	if dir.length() < 0.01:
		if not enemy.target or not is_instance_valid(enemy.target):
			return
		dir = enemy.target.global_position - enemy.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	_melee_swing_dir = Vector3.ZERO
	if dir.length() < 0.01:
		return

	enemy.rotation.y = atan2(dir.x, dir.z)
	# Positional swing voice (low brute whoosh) so enemy melee reads at range.
	if AudioManager:
		AudioManager.play_enemy_melee_swing(enemy.global_position)
	# Shared melee FX + collision hit check (same rules as allies and the player).
	EffectManager.spawn_melee_trail(enemy.global_position, dir, Color(1.0, 0.35, 0.2), Color(1.0, 0.3, 0.1))
	var hit := EffectManager.melee_hit_ray(enemy, dir, enemy.attack_range, 1 | 2, enemy.attack_damage)
	if hit and AudioManager:
		AudioManager.play_npc_melee_hit(enemy.global_position)


func _fire_ranged() -> void:
	# Line-of-sight check: don't fire through obstacles
	var from_pos = enemy.global_position + Vector3(0, 2, 0)
	var to_pos = enemy.target.global_position + Vector3(0, 1.5, 0)
	var space_state = enemy.get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	# Layer 2 = Environment (cover, walls)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)

	if result:
		# Obstacle in the way — don't fire, try to reposition
		var obstacle_dist = from_pos.distance_to(result["position"])
		var target_dist = from_pos.distance_to(to_pos)
		if obstacle_dist < target_dist * 0.8:
			# Blocked — transition to chase to find better angle
			state_machine.transition_to("StateChase")
			return

	# Fire sound at the muzzle so the player can hear the shot being fired.
	if AudioManager:
		AudioManager.play_sfx("machine_gun", from_pos, -8.0)

	var dir = (to_pos - from_pos).normalized()

	# Head Loss Penalty Check: 60% accuracy loss & trajectory wobble
	var is_head_broken = false
	if enemy.health_system and enemy.health_system.parts.has("head"):
		if enemy.health_system.parts["head"].get("destroyed", false):
			is_head_broken = true

	if is_head_broken:
		var wobble = Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.6, 0.6))
		dir = (dir + wobble).normalized()

	# Spawn through the shared WeaponCore (cooldown/ammo/heat all owned there).
	if enemy.fire_core:
		enemy.fire_core.try_fire(from_pos, dir, true, enemy)


func _is_low_hp() -> bool:
	if not enemy.health_system:
		return false
	var total_frame = 0.0
	var max_frame = 0.0
	for slot in enemy.health_system.parts:
		total_frame += enemy.health_system.parts[slot]["frame_hp"]
		max_frame += enemy.health_system.parts[slot]["max_frame"]
	return total_frame / max(max_frame, 1.0) < 0.3
