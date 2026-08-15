extends Node

## Headless verification of the enemy energy system:
##   1. Enemies run on a shared energy pool that recharges when not boosting.
##   2. Only the Rusher archetype dashes; a burst costs a chunk of energy and
##      respects a cooldown, so rushers can't spam dashes all fight.
##   3. A drained pool blocks further dashes.
##   4. When the pool runs low the enemy breaks off and flees to recharge
##      (StateFlee with flee_reason "energy") instead of fighting on empty.
## Run: godot --headless --path . res://tests/enemy_energy_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await _verify_energy_pool()
	await _verify_rusher_dash()
	await _verify_dash_blocked_when_empty()
	await _verify_low_energy_flees()
	print("ENEMY_ENERGY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _spawn_enemy(archetype: int) -> Node:
	var scene = load("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = scene.instantiate()
	enemy.archetype = archetype
	add_child(enemy)
	return enemy


func _verify_energy_pool() -> void:
	var enemy = _spawn_enemy(0)
	await get_tree().process_frame

	_check(is_equal_approx(enemy.energy, enemy.max_energy), "enemy starts with a full energy pool")
	# Regen caps at max.
	enemy._process(5.0)
	_check(is_equal_approx(enemy.energy, enemy.max_energy), "regen caps the pool at max_energy")
	# Draining then letting the pool recharge (while not boosting).
	enemy.energy = 50.0
	enemy._process(1.0)
	_check(is_equal_approx(enemy.energy, 59.0), "pool recharges at ENERGY_REGEN_RATE while not boosting")
	_check(not enemy.is_low_energy(), "59 energy is above the low threshold")

	enemy.queue_free()
	await get_tree().process_frame


func _verify_rusher_dash() -> void:
	var enemy = _spawn_enemy(0)  # RUSHER
	await get_tree().process_frame
	var start_energy: float = enemy.energy

	var started: bool = enemy.start_dash(Vector3.FORWARD)
	_check(started, "rusher starts a dash burst with a full pool")
	_check(enemy.is_dashing, "rusher is mid-dash after start_dash")
	_check(is_equal_approx(enemy.energy, start_energy - enemy.DASH_ENERGY_COST), "dash burst costs DASH_ENERGY_COST energy")
	_check(enemy.dash_cooldown_timer > 0.0, "dash starts the cooldown timer")

	# Cooldown blocks a second dash immediately after.
	_check(not enemy.start_dash(Vector3.BACK), "cooldown blocks an immediate second dash")
	_check(enemy.is_dashing, "still mid-dash after the rejected second attempt")

	# The dash applies movement for its duration, then ends. Let the ENGINE's
	# physics step drive the burst (manual _physics_process calls don't move
	# CharacterBody3D reliably headless — move_and_slide uses the real delta).
	var pos_before: Vector3 = enemy.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("DBG dash: before=", pos_before, " after=", enemy.global_position, " is_dashing=", enemy.is_dashing, " dash_timer=", enemy.dash_timer)
	_check(enemy.global_position.distance_to(pos_before) > 0.3, "dash moves the rusher along the burst direction")
	_check(enemy.is_dashing, "dash persists mid-burst (0.05s < 0.3s duration)")
	# Let the rest of the burst play out (0.3s total) and confirm it ends.
	for i in range(20):
		await get_tree().physics_frame
	_check(not enemy.is_dashing, "dash ends once dash_duration elapses")

	# Energy regen resumes after the burst (call _process with the flag cleared).
	enemy.is_dashing = false
	var drained: float = enemy.energy
	enemy._process(1.0)
	_check(enemy.energy > drained, "pool recharges after the dash burst ends")

	enemy.queue_free()
	await get_tree().process_frame


func _verify_dash_blocked_when_empty() -> void:
	# Rusher with a nearly-empty pool cannot dash.
	var enemy = _spawn_enemy(0)
	await get_tree().process_frame
	enemy.energy = 5.0
	_check(not enemy.start_dash(Vector3.FORWARD), "rusher cannot dash with an empty pool")
	_check(not enemy.is_dashing, "no dash starts when the pool is empty")

	# Non-rusher archetypes never dash at all.
	enemy.queue_free()
	await get_tree().process_frame
	var ranged = _spawn_enemy(1)  # RANGED
	await get_tree().process_frame
	_check(not ranged.start_dash(Vector3.FORWARD), "non-rusher archetypes never dash")
	_check(not ranged.is_dashing, "non-rusher stays grounded")
	ranged.queue_free()
	await get_tree().process_frame


func _verify_low_energy_flees() -> void:
	var enemy = _spawn_enemy(0)  # RUSHER
	await get_tree().process_frame

	# Give the rusher a player-like target to hunt. Real engine physics drives
	# the AI: idle spots the target, chase sees the drained pool, flee breaks
	# off to recharge.
	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	target.add_to_group("mecha")
	target.position = Vector3(8.0, 0.0, 0.0)
	add_child(target)
	await get_tree().physics_frame
	# Drain the pool while the enemy is hunting so the next chase step
	# withdraws it.
	enemy.energy = 5.0

	var fled := false
	for i in range(30):
		await get_tree().physics_frame
		if enemy.state_machine and enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateFlee":
			fled = true
			break
	_check(enemy.state_machine != null, "enemy has a state machine")
	_check(fled, "drained enemy flees to recharge")
	_check(enemy.flee_reason == "energy", "flee is marked as an energy withdrawal (reason=%s)" % enemy.flee_reason)

	# While fleeing the pool recharges (the enemy is not boosting), and once it
	# climbs back above RECHARGED_ENERGY the flee reassessment returns to chase.
	enemy.energy = 70.0
	var flee_state = enemy.state_machine.get_node_or_null("StateFlee") if enemy.state_machine else null
	var returned := false
	if flee_state:
		# Force the 3s reassessment window open on the next physics step.
		flee_state.flee_timer = 4.0
		for i in range(20):
			await get_tree().physics_frame
			if enemy.state_machine and enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateChase":
				returned = true
				break
		_check(returned, "recharged enemy returns to combat")
	else:
		_check(false, "flee state node exists for reassessment")

	target.queue_free()
	enemy.queue_free()
	await get_tree().process_frame
