extends EnemyState
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")

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

# Shield archetypes (4/5) hold their barrier UP while waiting, then DROP it
# around their own attack so the player gets a punish window: a shield melee
# commits (telegraph -> swing) with the shield down, a shield gunner is exposed
# right after each shot. This timer counts down the exposed window.
const SHIELD_MELEE_EXPOSED := 0.5   # extra recovery after the swing lands
const SHIELD_RANGED_EXPOSED := 0.5  # post-shot recoil window
var _shield_down_timer: float = 0.0


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
	_shield_down_timer = 0.0
	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)
	# Shield archetypes enter combat with the barrier raised; it only drops
	# while they commit to an attack (see physics_process below).
	if enemy and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)


func exit() -> void:
	# Never leave the enemy stuck glowing red when it switches states.
	_telegraph_active = false
	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)
	# Restore the barrier so the enemy doesn't leave the fight exposed after a
	# swing/shot interrupted by a state change.
	if enemy and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)


func physics_process(delta: float) -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return
	# A parked mech (pilot ejected) is no longer a combat threat.
	if enemy.target.has_meta("is_parked"):
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

	# Both arms destroyed: nothing left to attack with — withdraw instead.
	if enemy.has_method("can_attack") and not enemy.can_attack():
		enemy.flee_reason = "disabled"
		state_machine.transition_to("StateFlee")
		return

	# Face target
	var direction = (enemy.target.global_position - enemy.global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(-direction.x, -direction.z), 8.0 * delta)

	# Slight strafe while attacking
	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	# No legs: the torso stays planted (still fires ranged weapons from the
	# ground, but it can't strafe).
	if enemy.get("ragdolled") != true:
		var strafe = enemy.global_transform.basis.x * strafe_direction * enemy.move_speed * 0.3
		enemy.velocity.x = strafe.x
		enemy.velocity.z = strafe.z
		if not enemy.is_on_floor():
			enemy.velocity.y -= 19.6 * delta
		elif enemy.velocity.y < 0.0:
			enemy.velocity.y = -1.0
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

	# Attack
	attack_timer -= delta
	# Telegraph (red blink + warning tone) is MELEE-ONLY per user request:
	# machine-gun (1,5) fires without the rising warning and without the red flash,
	# so only a melee swing (0,4) telegraphs. This removes the noisy “red + beep”
	# on every ranged burst while keeping the dodge cue for melee.
	var arch_val = enemy.get("archetype")
	var is_melee_arch := int(arch_val) in [0, 4] if arch_val != null else false
	# Start the warning telegraph as soon as we enter the pre-fire window, so the
	# player sees the red blink and hears the rising tone BEFORE the swing lands.
	# The swing direction is committed exactly once per cycle: once _melee_swing_dir
	# is set, never re-snapshot it (the telegraph flag is cleared right before the
	# swing fires, which would otherwise overwrite the aimed arc with the target's
	# current position and make dodging impossible).
	if is_melee_arch and not _telegraph_active and _melee_swing_dir == Vector3.ZERO and attack_timer <= _telegraph_duration():
		_telegraph_active = true
		_telegraph_remaining = attack_timer
		_blink_timer = 0.0
		_flash_visible = false
		_snapshot_melee_swing_dir()
		_trigger_enemy_melee_animation()
		# A shield melee COMMITS to the swing when the telegraph starts: the
		# barrier drops for the telegraph + swing + recovery, leaving it exposed
		# — dodge the swing and shoot it while it's open.
		if enemy.get("archetype") == 4 and enemy.has_method("set_shield_up"):
			enemy.set_shield_up(false)
			_shield_down_timer = _telegraph_duration() + SHIELD_MELEE_EXPOSED
		if enemy.get_tree() and enemy.get_tree().root.has_node("AudioManager"):
			AudioManager.play_enemy_warning(enemy.global_position + Vector3(0, 2, 0))
	if is_melee_arch:
		_update_telegraph(delta)
	else:
		# Ensure ranged never leaves a lingering red flash from a previous melee cycle
		if enemy and enemy.has_method("set_attack_flash"):
			enemy.set_attack_flash(false)
		_telegraph_active = false
	# Count down the shield's exposed window; when it closes the barrier comes
	# back up (shield archetypes only).
	if _shield_down_timer > 0.0:
		_shield_down_timer = maxf(_shield_down_timer - delta, 0.0)
		if _shield_down_timer <= 0.0 and enemy.has_method("set_shield_up"):
			enemy.set_shield_up(true)
	if attack_timer <= 0.0:
		attack_timer = enemy.attack_cooldown
		_telegraph_active = false
		_perform_attack()
		# A shield gunner is exposed right after each shot (recoil window) so
		# the player can shoot it back between volleys.
		if enemy.get("archetype") == 5 and enemy.has_method("set_shield_up"):
			enemy.set_shield_up(false)
			_shield_down_timer = SHIELD_RANGED_EXPOSED
		# Every attack action draws from the shared energy pool, so sustained
		# fire (and rusher dashes) gradually drain the enemy until it breaks
		# off to recharge instead of fighting forever. The cost is tuned per
		# archetype (see enemy_dummy._apply_energy_tuning).
		enemy.energy = maxf(enemy.energy - enemy.attack_energy_cost, 0.0)


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
		1:  # RANGED - projectile (or melee fallback when dry)
			if enemy.has_ammo():
				_fire_ranged()
			elif enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
			else:
				state_machine.transition_to("StateChase")
		2:  # HEAVY - charge (handled by state_charge) or melee smash when dry
			if enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
		3:  # SUPPORT - heal nearest ally
			_heal_nearest_ally()
		4:  # SHIELD MELEE - melee swing, shield dropped around the swing
			_perform_melee()
		5:  # SHIELD RANGED - projectile (or melee fallback when dry)
			if enemy.has_ammo():
				_fire_ranged()
			elif enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
			else:
				state_machine.transition_to("StateChase")


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


func _trigger_enemy_melee_animation() -> void:
	if not enemy or not is_instance_valid(enemy):
		return
	var action_anim: MechaActionAnimator = null
	var anim_node = enemy.get_node_or_null("MechaAnimation")
	if anim_node == null:
		anim_node = enemy.get_node_or_null("EnemyAnimation")
	if anim_node == null:
		anim_node = enemy.get_node_or_null("AnimationSystem")
	
	if anim_node != null and anim_node.get("action_animator") != null:
		action_anim = anim_node.action_animator
	elif enemy.get_node_or_null("MechaAnimation/ActionAnimator") != null:
		action_anim = enemy.get_node_or_null("MechaAnimation/ActionAnimator") as MechaActionAnimator

	if action_anim != null:
		var hand := "right"
		var t_dur := _telegraph_duration()
		# One-handed sword enemies (rusher / shield-melee / dry fallback) wind up
		# with the ActionForge single slash so the telegraph reads as ง้างแล้วตี;
		# fall back to the Mech_00 take when the AF clips are missing.
		var played_af := false
		if action_anim.has_method("play_enemy_af_melee"):
			played_af = action_anim.play_enemy_af_melee(hand, t_dur)
		if not played_af:
			action_anim.play_enemy_melee(hand, t_dur)


# Freeze the melee swing direction the moment the telegraph starts, so the
# player can sidestep or boost out of the arc before the swing connects.
func _snapshot_melee_swing_dir() -> void:
	var arch2 = enemy.get("archetype")
	var is_melee_action: bool = (arch2 != null and int(arch2) in [0, 4]) or (enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo())
	if not is_melee_action or not enemy.target or not is_instance_valid(enemy.target):
		return
	var dir: Vector3 = enemy.target.global_position - enemy.global_position
	dir.y = 0.0
	_melee_swing_dir = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO


func _perform_melee() -> void:
	if enemy and enemy.has_method("report_technology_observation"):
		enemy.report_technology_observation("melee_attack")
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

	enemy.rotation.y = atan2(-dir.x, -dir.z)
	# Positional swing voice (low brute whoosh) so enemy melee reads at range.
	if AudioManager:
		AudioManager.play_enemy_melee_swing(enemy.global_position)
	# Shared melee FX + collision hit check (same rules as allies and the player).
	EffectManager.spawn_melee_trail(enemy.global_position, dir, Color(1.0, 0.35, 0.2), Color(1.0, 0.3, 0.1))
	var hit := EffectManager.melee_hit_ray(enemy, dir, enemy.attack_range, 1 | 2, enemy.attack_damage, "blunt")
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

	# GDD §7: EWar JAM accuracy penalty — additional wobble on enemy shots
	if GlobalData.ewar != null and GlobalData.ewar.is_active(GlobalData.ewar.Ability.JAM):
		var jam_wobble: float = GlobalData.ewar.jam_accuracy_penalty()
		var jw := Vector3(
			randf_range(-jam_wobble, jam_wobble),
			randf_range(-jam_wobble * 0.5, jam_wobble * 0.5),
			randf_range(-jam_wobble, jam_wobble))
		dir = (dir + jw).normalized()

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
