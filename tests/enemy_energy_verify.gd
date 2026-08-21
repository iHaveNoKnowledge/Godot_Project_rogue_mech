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
	await _verify_archetype_tuning()
	await _verify_heavy_charge_drain()
	await _verify_retreat_feedback()
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
	# Draining then letting the pool recharge (while not boosting). The regen
	# rate is the rusher's tuned value (fast — 12/s).
	enemy.energy = 50.0
	enemy._process(1.0)
	_check(is_equal_approx(enemy.energy, 50.0 + enemy.energy_regen_rate), "pool recharges at the archetype's regen rate while not boosting")
	_check(not enemy.is_low_energy(), "50+ regen energy is above the low threshold")

	enemy.queue_free()
	await get_tree().process_frame


func _verify_rusher_dash() -> void:
	var enemy = _spawn_enemy(0)  # RUSHER
	await get_tree().process_frame
	var start_energy: float = enemy.energy

	var started: bool = enemy.start_dash(Vector3.FORWARD)
	_check(started, "rusher starts a dash burst with a full pool")
	_check(enemy.is_dashing, "rusher is mid-dash after start_dash")
	_check(is_equal_approx(enemy.energy, start_energy - enemy.dash_energy_cost), "dash burst costs the rusher's tuned dash energy")
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
	# climbs back above the archetype's recharged_energy the flee reassessment
	# returns to chase.
	enemy.energy = enemy.recharged_energy + 10.0
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


func _verify_retreat_feedback() -> void:
	# An energy-drained withdrawal must be telegraphed: a positional retreat
	# klaxon exists in the SFX cache, and set_retreating() shows/hides the
	# pulsing "RETREATING" plate + amber signal flash cleanly.
	_check(AudioManager != null, "AudioManager autoload is available")
	_check(AudioManager.sfx._sound_cache.has("enemy_retreat"), "AudioManager generates the enemy retreat klaxon")
	var retreat_stream = AudioManager.sfx._sound_cache["enemy_retreat"]
	_check(retreat_stream is AudioStreamWAV and retreat_stream.data.size() > 0, "retreat klaxon is a non-empty generated stream")
	_check(AudioManager.has_method("play_enemy_retreat"), "AudioManager exposes play_enemy_retreat()")

	var enemy = _spawn_enemy(0)  # RUSHER
	await get_tree().process_frame
	var body_mesh: MeshInstance3D = enemy.get_node_or_null("BodyMesh")
	var original_override = body_mesh.material_override if body_mesh else null

	_check(not enemy.is_retreating, "enemy starts with no retreat feedback")
	enemy.set_retreating(true)
	_check(enemy.is_retreating, "set_retreating(true) flags the enemy as retreating")
	var label: Label3D = enemy.get_node_or_null("RetreatLabel")
	_check(label != null, "retreating enemy gains a RETREATING label")
	if label:
		_check(label.text == "RETREATING", "retreat label reads RETREATING")
		_check(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED, "retreat label is billboarded")
		_check(label.no_depth_test, "retreat label ignores depth so it stays visible")
	if body_mesh:
		_check(body_mesh.material_override == enemy._flash_material, "amber signal flash applied to the body")
		var amber: Color = enemy._retreat_flash_color()
		_check(enemy._flash_material.emission.is_equal_approx(amber), "signal flash is amber (emission=%s)" % str(enemy._flash_material.emission))

	# Toggling off restores the original materials and removes the plate
	# (queue_free defers the actual deletion to end of frame).
	enemy.set_retreating(false)
	_check(not enemy.is_retreating, "set_retreating(false) clears the flag")
	await get_tree().process_frame
	_check(enemy.get_node_or_null("RetreatLabel") == null, "RETREATING label is removed when the enemy returns")
	if body_mesh:
		_check(body_mesh.material_override == original_override, "original body material restored after retreat ends")

	# End-to-end: a drained enemy that enters StateFlee (energy reason) shows the
	# feedback, and returning to chase clears it.
	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	target.add_to_group("mecha")
	target.position = Vector3(8.0, 0.0, 0.0)
	add_child(target)
	await get_tree().physics_frame
	enemy.target = target
	enemy.energy = 5.0
	var fled := false
	for i in range(30):
		await get_tree().physics_frame
		if enemy.state_machine and enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateFlee":
			fled = true
			break
	_check(fled, "drained enemy enters StateFlee")
	_check(enemy.is_retreating, "fleeing on energy shows the retreat feedback")

	enemy.energy = enemy.recharged_energy + 10.0
	var flee_state = enemy.state_machine.get_node_or_null("StateFlee") if enemy.state_machine else null
	var returned := false
	if flee_state:
		flee_state.flee_timer = 4.0
		for i in range(20):
			await get_tree().physics_frame
			if enemy.state_machine and enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateChase":
				returned = true
				break
	_check(returned, "recharged enemy returns to combat")
	_check(not enemy.is_retreating, "retreat feedback cleared once back in combat")

	target.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func _verify_archetype_tuning() -> void:
	# Each archetype gets its own energy profile (see _apply_energy_tuning), so
	# costs, regen, break-off points and flee speed all differ per enemy.
	var rusher = _spawn_enemy(0)
	var ranged = _spawn_enemy(1)
	var heavy = _spawn_enemy(2)
	var support = _spawn_enemy(3)
	await get_tree().process_frame

	_check(rusher.dash_energy_cost == 20.0, "rusher dashes cost 20 energy")
	_check(ranged.dash_energy_cost == 18.0, "ranged keeps the base dash cost (never dashes)")
	_check(rusher.attack_energy_cost == 6.0, "rusher swings cost 6 energy")
	_check(ranged.attack_energy_cost == 6.0, "ranged shots cost 6 energy")
	_check(heavy.attack_energy_cost == 5.0, "heavy keeps a low attack cost")
	_check(heavy.charge_energy_cost == 5.0, "heavy charges cost 5 energy")

	# Regen: rusher recharges fastest, heavy slowest.
	_check(rusher.energy_regen_rate == 12.0, "rusher recharges fast (12/s)")
	_check(ranged.energy_regen_rate == 8.0, "ranged recharges slow (8/s)")
	_check(heavy.energy_regen_rate == 7.0, "heavy recharges slowest (7/s)")

	# Break-off points: ranged pulls out early, heavy fights almost forever.
	_check(rusher.low_energy_threshold == 15.0, "rusher fights until very drained (15)")
	_check(ranged.low_energy_threshold == 25.0, "ranged pulls out early to keep distance (25)")
	_check(rusher.recharged_energy == 50.0, "rusher returns to combat quickly (50)")
	_check(ranged.recharged_energy == 70.0, "ranged returns only fully recharged (70)")

	# Flee speed: rusher sprints away, heavy lumbers.
	_check(rusher.flee_speed_mult == 1.5, "rusher flees fast (1.5x)")
	_check(ranged.flee_speed_mult == 1.1, "ranged flees at a deliberate 1.1x")
	_check(heavy.flee_speed_mult == 0.9, "heavy flees slowly (0.9x)")
	_check(support.flee_speed_mult == 1.2, "support flees at the base 1.2x")

	rusher.queue_free()
	ranged.queue_free()
	heavy.queue_free()
	support.queue_free()
	await get_tree().process_frame


func _verify_heavy_charge_drain() -> void:
	# A heavy's charge attack costs charge_energy_cost: after the 0.8s wind-up
	# the charge starts and the pool drops. This also confirms the charge state
	# now runs for heavies (routed from chase when in range).
	var enemy = _spawn_enemy(2)  # HEAVY
	await get_tree().process_frame

	var target := CharacterBody3D.new()
	target.name = "FakePlayer"
	target.add_to_group("mecha")
	target.position = Vector3(5.0, 0.0, 0.0)
	add_child(target)
	await get_tree().physics_frame
	enemy.target = target
	# Freeze regen for the wind-up window so the charge cost is the only
	# movement the pool sees (regen is an instance var per archetype now).
	enemy.energy_regen_rate = 0.0

	var energy_before: float = enemy.energy
	var charge_state = enemy.state_machine.get_node_or_null("StateCharge") if enemy.state_machine else null
	var charged := false
	for i in range(80):  # 0.8s wind-up + margin at 60fps
		await get_tree().physics_frame
		if charge_state and charge_state.is_charging:
			charged = true
			break
	_check(charged, "heavy starts its charge attack in range")
	_check(is_equal_approx(enemy.energy, energy_before - enemy.charge_energy_cost), "charge start drains charge_energy_cost")

	# A heavy that drains below its threshold breaks off to recharge.
	enemy.energy = 5.0
	var fled := false
	for i in range(30):
		await get_tree().physics_frame
		if enemy.state_machine and enemy.state_machine.current_state and enemy.state_machine.current_state.name == "StateFlee":
			fled = true
			break
	_check(fled, "drained heavy breaks off to recharge")
	_check(enemy.flee_reason == "energy", "heavy flee is an energy withdrawal")

	target.queue_free()
	enemy.queue_free()
	await get_tree().process_frame
