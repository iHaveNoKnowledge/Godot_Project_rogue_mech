extends EnemyState
const _NavAvoidance = preload("res://scripts/arena/nav_avoidance.gd")
const GroundTelegraphScript = preload("res://scripts/effects/ground_telegraph_indicator.gd")

## =============================================================================
## STATE ATTACK — Melee Combat Pacing, Telegraph & Action Flow
## =============================================================================
## Drives tactical combat engagement for enemies:
## - Melee Archetypes (Rusher, Shield Melee, CQB Fallback):
##     1. PACING: Circle-strafes and manages personal space at 6.0–8.5m.
##        Back-pedals if the player gets closer than 5.5m.
##     2. WINDUP: Wind-up telegraph at distance (0.6s Rusher, 0.8s Shield Melee).
##        GroundTelegraphIndicator warning on the ground + rising audio cue.
##        Tracks target, then Direction Lock engages in the final 0.2s.
##     3. LUNGE: Dashes forward 4.5–6.0m along the locked vector to strike.
##     4. RECOVERY: Punish opening (0.55s Rusher, 0.70s Shield Melee).
##        Enemy is stationary with shield down, allowing player counterattacks.
##     5. DISENGAGE: Dashes / steps backward to 7.0–9.0m, resetting the cycle.
## - Ranged Archetypes (Ranged, Support, Shield Ranged):
##     Maintains line-of-sight and fires projectile volleys.
## =============================================================================

enum MeleePhase {
	PACING,
	WINDUP,
	LUNGE,
	RECOVERY,
	DISENGAGE
}

var attack_timer: float = 0.0
var strafe_timer: float = 0.0
var strafe_direction: float = 1.0

# Melee Sub-Phase Lifecycle
var melee_phase: MeleePhase = MeleePhase.PACING
var melee_phase_timer: float = 0.0
var melee_windup_duration: float = 0.6
var melee_recovery_duration: float = 0.55
var melee_lunge_speed: float = 16.5
var melee_lunge_duration: float = 0.26
var _has_struck_in_lunge: bool = false
var is_direction_locked: bool = false
var ground_telegraph: Node3D = null

# Attack telegraph state & backward compatibility
const TELEGRAPH_FRACTION := 0.35
const TELEGRAPH_MIN := 0.35
const TELEGRAPH_MAX := 0.9
const BLINK_INTERVAL := 0.14
var _telegraph_active: bool = false
var _telegraph_remaining: float = 0.0
var _blink_timer: float = 0.0
var _flash_visible: bool = false

# Melee swing direction, committed when direction lock engages before strike
var _melee_swing_dir: Vector3 = Vector3.ZERO

# Shield archetypes (4/5) exposure recovery timers
const SHIELD_MELEE_EXPOSED := 0.5
const SHIELD_RANGED_EXPOSED := 0.5
var _shield_down_timer: float = 0.0


func enter() -> void:
	# Small initial pacing breathing room
	attack_timer = randf_range(0.8, 1.4)
	strafe_timer = 0.0
	strafe_direction = [-1.0, 1.0][randi() % 2]
	melee_phase = MeleePhase.PACING
	melee_phase_timer = 0.0
	is_direction_locked = false
	_has_struck_in_lunge = false
	_telegraph_active = false
	_telegraph_remaining = 0.0
	_blink_timer = 0.0
	_flash_visible = false
	_melee_swing_dir = Vector3.ZERO
	_shield_down_timer = 0.0
	_cleanup_ground_telegraph()

	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)

	# Shield archetypes enter combat with the barrier raised
	if enemy and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)


func exit() -> void:
	_cleanup_ground_telegraph()
	_release_attacker_token()
	melee_phase = MeleePhase.PACING
	is_direction_locked = false
	_telegraph_active = false

	if enemy and enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)

	if enemy and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)


func physics_process(delta: float) -> void:
	if not enemy or not is_instance_valid(enemy):
		return

	if not enemy.target or not is_instance_valid(enemy.target):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	if enemy.target.has_meta("is_parked"):
		enemy.target = null
		state_machine.transition_to("StateIdle")
		return

	var distance: float = enemy.global_position.distance_to(enemy.target.global_position)

	# Low HP / Energy retreat checks (allowed during pacing and recovery)
	if melee_phase in [MeleePhase.PACING, MeleePhase.RECOVERY]:
		if enemy.is_low_energy():
			_cleanup_ground_telegraph()
			_release_attacker_token()
			enemy.flee_reason = "energy"
			state_machine.transition_to("StateFlee")
			return

		if enemy.health_system and _is_low_hp():
			_cleanup_ground_telegraph()
			_release_attacker_token()
			enemy.flee_reason = "hp"
			state_machine.transition_to("StateFlee")
			return

		if enemy.has_method("can_attack") and not enemy.can_attack():
			_cleanup_ground_telegraph()
			_release_attacker_token()
			enemy.flee_reason = "disabled"
			state_machine.transition_to("StateFlee")
			return

	var is_melee_arch: bool = (int(enemy.get("archetype")) in [0, 4]) or (enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo())

	if is_melee_arch:
		_process_melee_lifecycle(delta, distance)
	else:
		_process_ranged_combat(delta, distance)


# =============================================================================
# MELEE COMBAT LIFECYCLE (Pacing -> Windup -> Lunge -> Recovery -> Disengage)
# =============================================================================

func _process_melee_lifecycle(delta: float, distance: float) -> void:
	# If target fled far outside engagement range while pacing, resume chase
	var max_disengage_dist: float = enemy.attack_range * 1.5 if enemy.attack_range > 0.0 else 14.0
	if distance > max_disengage_dist and melee_phase == MeleePhase.PACING:
		state_machine.transition_to("StateChase")
		return

	match melee_phase:
		MeleePhase.PACING:
			_process_melee_pacing(delta, distance)
		MeleePhase.WINDUP:
			_process_melee_windup(delta)
		MeleePhase.LUNGE:
			_process_melee_lunge(delta)
		MeleePhase.RECOVERY:
			_process_melee_recovery(delta)
		MeleePhase.DISENGAGE:
			_process_melee_disengage(delta)


## Phase 1: PACING — Circle-strafe at 6.0–8.5m and maintain personal space (back-pedal)
func _process_melee_pacing(delta: float, distance: float) -> void:
	var pacing_min: float = 6.0
	var pacing_max: float = 8.5
	if enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo() and enemy.attack_range < 5.0:
		pacing_min = 4.0
		pacing_max = 6.0

	var to_target: Vector3 = enemy.target.global_position - enemy.global_position
	to_target.y = 0.0
	var to_target_norm: Vector3 = to_target.normalized() if to_target.length_squared() > 0.01 else -enemy.global_transform.basis.z

	# Turn smoothly to face target
	var target_yaw := atan2(-to_target_norm.x, -to_target_norm.z)
	enemy.rotation.y = lerp_angle(enemy.rotation.y, target_yaw, 8.0 * delta)

	# Circle-strafe & distance control
	strafe_timer += delta
	if strafe_timer > 2.8:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	var lateral := Vector3(-to_target_norm.z, 0, to_target_norm.x) * strafe_direction
	var move_dir := Vector3.ZERO

	if distance < pacing_min:
		# Player too close: Back-pedal firmly to maintain personal space
		move_dir = -to_target_norm * 1.2 + lateral * 0.35
	elif distance > pacing_max:
		# Approach gently into pacing zone
		move_dir = to_target_norm * 0.9 + lateral * 0.4
	else:
		# Sweet spot: Circle-strafe around the player with slight radial dampening
		var radial_corr: float = clampf(((pacing_min + pacing_max) * 0.5 - distance), -1.0, 1.0)
		move_dir = lateral + to_target_norm * (radial_corr * 0.35)

	move_dir = move_dir.normalized()
	if enemy.get("ragdolled") != true:
		enemy.velocity.x = move_dir.x * enemy.move_speed * 0.85
		enemy.velocity.z = move_dir.z * enemy.move_speed * 0.85
		if not enemy.is_on_floor():
			enemy.velocity.y -= 19.6 * delta
		elif enemy.velocity.y < 0.0:
			enemy.velocity.y = -1.0
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

	# Shield Melee holds shield raised during pacing
	if enemy.archetype == 4 and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)

	# Check attack trigger & token availability
	attack_timer -= delta
	var t_dur := _telegraph_duration()
	if attack_timer <= t_dur:
		if _can_acquire_attacker_token():
			_acquire_attacker_token()
			_start_melee_windup()


## Phase 2: WINDUP — Clear telegraph, ground danger zone, and direction lock
func _start_melee_windup() -> void:
	melee_phase = MeleePhase.WINDUP
	is_direction_locked = false
	_has_struck_in_lunge = false

	# Stop horizontal movement immediately on windup (root in place)
	if enemy:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0

	# Archetype-specific timings (Balanced Tuning: reduced lunge speed & extended recovery punish window)
	if enemy.archetype == 4: # Shield Melee
		melee_windup_duration = 0.80
		melee_recovery_duration = 1.00
		melee_lunge_speed = 10.0
		# Drop shield when committing to wind-up (punish / exposed window)
		if enemy.has_method("set_shield_up"):
			enemy.set_shield_up(false)
	else: # Rusher / Fallback
		melee_windup_duration = 0.60
		melee_recovery_duration = 0.85
		melee_lunge_speed = 11.5

	melee_phase_timer = melee_windup_duration
	_telegraph_active = true
	_snapshot_melee_swing_dir()

	# Melee windup animation through action animator
	_trigger_enemy_melee_animation()

	# Audio warning tone
	if AudioManager:
		AudioManager.play_enemy_warning(enemy.global_position + Vector3(0, 2, 0))

	# Flash body
	if enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(true, Color(1.0, 0.15, 0.1))

	# Spawn ground telegraph danger zone
	_spawn_ground_telegraph()


func _process_melee_windup(delta: float) -> void:
	# Stop movement during wind-up (root in place)
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if not enemy.is_on_floor():
		enemy.velocity.y -= 19.6 * delta
	enemy.move_and_slide()

	melee_phase_timer -= delta
	var progress: float = 1.0 - clampf(melee_phase_timer / melee_windup_duration, 0.0, 1.0)
	if ground_telegraph:
		ground_telegraph.set_progress(progress)

	# Direction Tracking vs Direction Lock:
	# Locks early (0.35s for Rusher, 0.45s for Shield Melee) allowing player fair sidestep/dash escape
	var lock_threshold: float = 0.45 if enemy.archetype == 4 else 0.35
	if melee_phase_timer > lock_threshold:
		if enemy.target and is_instance_valid(enemy.target):
			var dir: Vector3 = enemy.target.global_position - enemy.global_position
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				_melee_swing_dir = dir.normalized()
				var target_yaw := atan2(-_melee_swing_dir.x, -_melee_swing_dir.z)
				enemy.rotation.y = lerp_angle(enemy.rotation.y, target_yaw, 12.0 * delta)
		if ground_telegraph:
			ground_telegraph.update_orientation(enemy.global_position, _melee_swing_dir)
	else:
		if not is_direction_locked:
			is_direction_locked = true
			if ground_telegraph:
				ground_telegraph.set_locked(true)

	if melee_phase_timer <= 0.0:
		_start_melee_lunge()


## Phase 3: LUNGE — Rapid forward dash & strike execution
func _start_melee_lunge() -> void:
	melee_phase = MeleePhase.LUNGE
	melee_lunge_duration = 0.26
	melee_phase_timer = melee_lunge_duration
	_has_struck_in_lunge = false
	_telegraph_active = false
	_cleanup_ground_telegraph()

	# Ensure forward facing along committed swing vector
	if _melee_swing_dir.length_squared() > 0.01:
		enemy.rotation.y = atan2(-_melee_swing_dir.x, -_melee_swing_dir.z)


func _process_melee_lunge(delta: float) -> void:
	enemy.velocity.x = _melee_swing_dir.x * melee_lunge_speed
	enemy.velocity.z = _melee_swing_dir.z * melee_lunge_speed
	if not enemy.is_on_floor():
		enemy.velocity.y -= 19.6 * delta
	enemy.move_and_slide()

	melee_phase_timer -= delta

	# Execute strike check halfway into lunge
	if not _has_struck_in_lunge and melee_phase_timer <= melee_lunge_duration * 0.5:
		_has_struck_in_lunge = true
		_perform_melee()

	if melee_phase_timer <= 0.0:
		_start_melee_recovery()


## Phase 4: RECOVERY — Punish window where enemy is frozen/exposed
func _start_melee_recovery() -> void:
	melee_phase = MeleePhase.RECOVERY
	melee_phase_timer = melee_recovery_duration
	enemy.velocity = Vector3.ZERO

	if enemy.has_method("set_attack_flash"):
		enemy.set_attack_flash(false)


func _process_melee_recovery(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if not enemy.is_on_floor():
		enemy.velocity.y -= 19.6 * delta
	enemy.move_and_slide()

	melee_phase_timer -= delta
	if melee_phase_timer <= 0.0:
		_start_melee_disengage()


## Phase 5: DISENGAGE — Back-dash / step back to reset to pacing distance
func _start_melee_disengage() -> void:
	melee_phase = MeleePhase.DISENGAGE
	melee_phase_timer = 0.32

	# Rusher performs a quick backward burst/dash
	if enemy.archetype == 0 and enemy.has_method("start_dash"):
		enemy.start_dash(-_melee_swing_dir)

	# Shield Melee restores shield defense upon disengaging
	if enemy.archetype == 4 and enemy.has_method("set_shield_up"):
		enemy.set_shield_up(true)

	_release_attacker_token()


func _process_melee_disengage(delta: float) -> void:
	if not enemy.get("is_dashing"):
		var back_dir := -_melee_swing_dir
		enemy.velocity.x = back_dir.x * enemy.move_speed * 1.3
		enemy.velocity.z = back_dir.z * enemy.move_speed * 1.3
		if not enemy.is_on_floor():
			enemy.velocity.y -= 19.6 * delta
		enemy.move_and_slide()

	melee_phase_timer -= delta
	if melee_phase_timer <= 0.0:
		melee_phase = MeleePhase.PACING
		attack_timer = enemy.attack_cooldown
		_melee_swing_dir = Vector3.ZERO


## Called when an attacking enemy is parried by player's Perfect Guard / Just Deflect
func interrupt_by_parry() -> void:
	_cleanup_ground_telegraph()
	_release_attacker_token()
	_has_struck_in_lunge = true
	is_direction_locked = false
	_telegraph_active = false
	melee_phase = MeleePhase.RECOVERY
	melee_phase_timer = 1.5 # Staggered & exposed for 1.5s
	if enemy:
		enemy.velocity.x = 0.0
		enemy.velocity.z = 0.0
		if enemy.has_method("set_attack_flash"):
			enemy.set_attack_flash(false)
		if enemy.has_method("set_shield_up"):
			enemy.set_shield_up(false)


# =============================================================================
# GROUND TELEGRAPH INDICATOR HELPERS
# =============================================================================

func _spawn_ground_telegraph() -> void:
	_cleanup_ground_telegraph()
	if not enemy.is_inside_tree() or enemy.get_parent() == null:
		return
	ground_telegraph = GroundTelegraphScript.new()
	var length: float = 6.0
	var width: float = 2.4
	ground_telegraph.setup(width, length)
	enemy.get_parent().add_child(ground_telegraph)
	ground_telegraph.update_orientation(enemy.global_position, _melee_swing_dir)


func _cleanup_ground_telegraph() -> void:
	if ground_telegraph != null and is_instance_valid(ground_telegraph):
		ground_telegraph.dismiss()
		ground_telegraph = null


# =============================================================================
# ATTACKER TOKEN MANAGEMENT
# =============================================================================

func _can_acquire_attacker_token() -> bool:
	if enemy and enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		return enemy.squad_coordinator.request_attacker_token(enemy)
	return true


func _acquire_attacker_token() -> void:
	if enemy and enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		enemy.squad_coordinator.request_attacker_token(enemy)


func _release_attacker_token() -> void:
	if enemy and enemy.get("squad_coordinator") != null and is_instance_valid(enemy.squad_coordinator):
		enemy.squad_coordinator.release_attacker_token(enemy)


# =============================================================================
# RANGED COMBAT PROCESS (Existing baseline for rifle/cannon/support)
# =============================================================================

func _process_ranged_combat(delta: float, distance: float) -> void:
	if distance > enemy.attack_range * 1.2:
		state_machine.transition_to("StateChase")
		return

	# Face target
	var direction: Vector3 = (enemy.target.global_position - enemy.global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(-direction.x, -direction.z), 8.0 * delta)

	# Slight strafe while attacking
	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	if enemy.get("ragdolled") != true:
		var strafe: Vector3 = enemy.global_transform.basis.x * strafe_direction * enemy.move_speed * 0.3
		enemy.velocity.x = strafe.x
		enemy.velocity.z = strafe.z
		if not enemy.is_on_floor():
			enemy.velocity.y -= 19.6 * delta
		elif enemy.velocity.y < 0.0:
			enemy.velocity.y = -1.0
		enemy.move_and_slide()
		if enemy.get_slide_collision_count() > 0:
			enemy.velocity = _NavAvoidance.slide_along_wall(enemy.velocity, enemy)

	# Countdown to fire
	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = enemy.attack_cooldown
		_perform_attack()
		if enemy.get("archetype") == 5 and enemy.has_method("set_shield_up"):
			enemy.set_shield_up(false)
			_shield_down_timer = SHIELD_RANGED_EXPOSED
		enemy.energy = maxf(enemy.energy - enemy.attack_energy_cost, 0.0)

	if _shield_down_timer > 0.0:
		_shield_down_timer = maxf(_shield_down_timer - delta, 0.0)
		if _shield_down_timer <= 0.0 and enemy.has_method("set_shield_up"):
			enemy.set_shield_up(true)


# =============================================================================
# SHARED ATTACK DISPATCH & TELEGRAPH DURATION (Backwards Compatible)
# =============================================================================

func _telegraph_duration() -> float:
	if enemy.get("archetype") == 4:
		return 0.80
	elif enemy.get("archetype") == 0:
		return 0.60
	var base: float = enemy.attack_cooldown * TELEGRAPH_FRACTION
	return clampf(base, TELEGRAPH_MIN, TELEGRAPH_MAX)


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
		var played_af := false
		if action_anim.has_method("play_enemy_af_melee"):
			played_af = action_anim.play_enemy_af_melee(hand, t_dur)
		if not played_af:
			action_anim.play_enemy_melee(hand, t_dur)


func _snapshot_melee_swing_dir() -> void:
	if not enemy.target or not is_instance_valid(enemy.target):
		return
	var dir: Vector3 = enemy.target.global_position - enemy.global_position
	dir.y = 0.0
	_melee_swing_dir = dir.normalized() if dir.length() > 0.01 else -enemy.global_transform.basis.z


func _perform_attack() -> void:
	var archetype = enemy.archetype if enemy.get("archetype") != null else 0
	match archetype:
		0:
			_perform_melee()
		1:
			if enemy.has_ammo():
				_fire_ranged()
			elif enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
			else:
				state_machine.transition_to("StateChase")
		2:
			if enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
		3:
			_heal_nearest_ally()
		4:
			_perform_melee()
		5:
			if enemy.has_ammo():
				_fire_ranged()
			elif enemy.has_method("is_out_of_ammo") and enemy.is_out_of_ammo():
				_perform_melee()
			else:
				state_machine.transition_to("StateChase")


func _perform_melee() -> void:
	if enemy and enemy.has_method("report_technology_observation"):
		enemy.report_technology_observation("melee_attack")

	var dir := _melee_swing_dir
	if dir.length() < 0.01:
		if not enemy.target or not is_instance_valid(enemy.target):
			return
		dir = enemy.target.global_position - enemy.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else -enemy.global_transform.basis.z

	enemy.rotation.y = atan2(-dir.x, -dir.z)
	if AudioManager:
		AudioManager.play_enemy_melee_swing(enemy.global_position)
	EffectManager.spawn_melee_trail(enemy.global_position, dir, Color(1.0, 0.35, 0.2), Color(1.0, 0.3, 0.1))
	var hit := EffectManager.melee_hit_ray(enemy, dir, 5.0, 1 | 2, enemy.attack_damage, "blunt")
	if hit and AudioManager:
		AudioManager.play_npc_melee_hit(enemy.global_position)


func _fire_ranged() -> void:
	var from_pos: Vector3 = enemy.global_position + Vector3(0, 2, 0)
	var to_pos: Vector3 = enemy.target.global_position + Vector3(0, 1.5, 0)
	var space_state = enemy.get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)

	if result:
		var obstacle_dist: float = from_pos.distance_to(result["position"])
		var target_dist: float = from_pos.distance_to(to_pos)
		if obstacle_dist < target_dist * 0.8:
			state_machine.transition_to("StateChase")
			return

	if AudioManager:
		AudioManager.play_sfx("machine_gun", from_pos, -8.0)

	var dir: Vector3 = (to_pos - from_pos).normalized()

	var is_head_broken := false
	if enemy.health_system and enemy.health_system.parts.has("head"):
		if enemy.health_system.parts["head"].get("destroyed", false):
			is_head_broken = true

	if is_head_broken:
		var wobble := Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.3), randf_range(-0.6, 0.6))
		dir = (dir + wobble).normalized()

	if GlobalData.ewar != null and GlobalData.ewar.is_active(GlobalData.ewar.Ability.JAM):
		var jam_wobble: float = GlobalData.ewar.jam_accuracy_penalty()
		var jw := Vector3(
			randf_range(-jam_wobble, jam_wobble),
			randf_range(-jam_wobble * 0.5, jam_wobble * 0.5),
			randf_range(-jam_wobble, jam_wobble))
		dir = (dir + jw).normalized()

	if enemy.fire_core:
		enemy.fire_core.try_fire(from_pos, dir, true, enemy)


func _heal_nearest_ally() -> void:
	var enemies = enemy.get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0

	for e in enemies:
		if not is_instance_valid(e) or e == enemy:
			continue
		if not e.health_system or e.health_system.is_destroyed:
			continue
		var dist: float = enemy.global_position.distance_to(e.global_position)
		if dist < 40.0 and dist < nearest_dist:
			nearest = e
			nearest_dist = dist

	if nearest and nearest.health_system and nearest.health_system.has_method("take_heal"):
		nearest.health_system.take_heal(5.0)
		EffectManager.spawn_damage_number(nearest.global_position + Vector3(0, 3, 0), 5.0, Color(0.2, 1.0, 0.2))


func _is_low_hp() -> bool:
	if not enemy.health_system:
		return false
	var total_frame := 0.0
	var max_frame := 0.0
	for slot in enemy.health_system.parts:
		total_frame += enemy.health_system.parts[slot]["frame_hp"]
		max_frame += enemy.health_system.parts[slot]["max_frame"]
	return total_frame / max(max_frame, 1.0) < 0.3
