extends EnemyState

## Charge state: heavy enemies build speed for devastating charge attack.

var charge_speed: float = 12.0
var charge_timer: float = 0.0
var charge_duration: float = 1.5
var charge_cooldown: float = 0.0
var is_charging: bool = false
var charge_direction: Vector3 = Vector3.ZERO


func enter() -> void:
	charge_timer = 0.0
	is_charging = false
	# Pick charge direction toward target
	if enemy.target and is_instance_valid(enemy.target):
		charge_direction = (enemy.target.global_position - enemy.global_position).normalized()
		charge_direction.y = 0.0


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

	# Drained pool: even a heavy breaks off to recharge instead of charging on
	# empty (the pool recharges while it withdraws).
	if enemy.is_low_energy():
		enemy.flee_reason = "energy"
		state_machine.transition_to("StateFlee")
		return

	charge_cooldown -= delta

	if not is_charging:
		# Wind up: face target, wait briefly
		var face_dir = (enemy.target.global_position - enemy.global_position).normalized()
		face_dir.y = 0.0
		if face_dir.length() > 0.1:
			enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(face_dir.x, face_dir.z), 5.0 * delta)

		charge_timer += delta
		if charge_timer > 0.8:  # Wind-up time
			is_charging = true
			charge_timer = 0.0
			charge_direction = face_dir
			# A charge costs energy (tuned per archetype), so a heavy that keeps
			# charging eventually runs dry and withdraws.
			enemy.energy = maxf(enemy.energy - enemy.charge_energy_cost, 0.0)
	else:
		# Charging!
		enemy.velocity = charge_direction * charge_speed
		enemy.velocity.y = -10.0
		enemy.move_and_slide()

		charge_timer += delta

		# Check for hit with player
		var mechas = enemy.get_tree().get_nodes_in_group("mecha")
		for mecha in mechas:
			if is_instance_valid(mecha) and mecha != enemy:
				var dist = enemy.global_position.distance_to(mecha.global_position)
				if dist < 3.0:
					# Deal AoE damage
					if mecha is Damageable:
						mecha.take_damage(enemy.attack_damage * 2.0, "charge")
					# Stun self
					_end_charge()
					return

		# End charge after duration
		if charge_timer > charge_duration:
			_end_charge()


func _end_charge() -> void:
	is_charging = false
	enemy.velocity = Vector3.ZERO
	charge_cooldown = 3.0  # Stun cooldown
	charge_timer = -charge_cooldown  # Wait before next charge
	state_machine.transition_to("StateChase")
