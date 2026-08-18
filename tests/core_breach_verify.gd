extends Node

## Headless verification of the mech core-breach death sequence (fires when the
## mech's total frame HP depletes):
##   1. The mech instantly RAGDOLLS over (rotation.x -> -82°, drop to y 0.55)
##      and reads as downed.
##   2. A heat-glow OmniLight3D spawns dark and ramps up over the warning
##      window, like the reactor heating to blow.
##   3. During the breach window every system is off EXCEPT the eject seat:
##      movement and weapon-fire inputs are ignored.
##   4. After CORE_BREACH_DELAY the machine detonates and the glow is freed.
## Run: godot --headless --path . res://tests/core_breach_verify.tscn

const CORE_BREACH_DELAY := 1.8

var _fails := 0
var _checks := 0
var _shots := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("BREACH_OK: " + name)
	else:
		_fails += 1
		printerr("BREACH_FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	EventBus.weapon_fired.connect(func(_target: Vector3): _shots += 1)

	var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	mech.position = Vector3(0, 8, 0)
	add_child(mech)
	await get_tree().process_frame
	await get_tree().process_frame

	var hs: Node = mech.get_node_or_null("HealthSystem")
	_check(hs != null, "mecha exposes a HealthSystem")
	if hs == null:
		_finish()
		return

	# Stand-in for a hostile: skip the player-death flow (pilot eject / GameManager
	# transitions) so the test only exercises the core-breach sequence itself.
	hs.set("is_player", false)

	# --- 1. Depleting all frame HP ragdolls the mech immediately ---
	var start_ms := Time.get_ticks_msec()
	# layer "frame" routes straight into the frame HP (the player mech has no
	# armor-break shortcut like the single-body enemies: its frame must actually
	# hit 0 for _on_mecha_destroyed to fire).
	for slot in hs.get("parts"):
		hs.take_damage_to_part(slot, 99999.0, "kinetic", "frame")
	_check(bool(hs.get("is_destroyed")), "depleting all frame HP sets is_destroyed")
	_check(_mech_downed(mech), "controller reports the mech as downed")
	var waited := 0
	while is_instance_valid(mech) and absf(mech.rotation.x - deg_to_rad(-82.0)) > 0.02 and waited < 120:
		await get_tree().process_frame
		waited += 1
	_check(is_instance_valid(mech) and absf(mech.rotation.x - deg_to_rad(-82.0)) < 0.05,
		"mech ragdolls over (rotation.x %.1f deg)" % rad_to_deg(mech.rotation.x))
	_check(is_instance_valid(mech) and absf(mech.position.y - 0.55) < 0.25,
		"mech drops to the ground (y %.2f)" % mech.position.y)

	# --- 2. Heat-glow light spawns dark, then ramps up ---
	var glow: OmniLight3D = mech.get_node_or_null("BreachGlow")
	_check(glow != null, "heat-glow light attaches during the breach")
	if glow != null:
		var lit := false
		for i in range(20):
			if glow.light_energy > 0.0:
				lit = true
				break
			await get_tree().create_timer(0.1).timeout
		_check(lit, "breach glow lights up from dark (energy %.2f)" % glow.light_energy)
		# Average the energy over two 0.5s windows (the flash pulses alternate),
		# so the ramp-up trend is what gets compared.
		var early_avg := 0.0
		for i in range(5):
			early_avg += glow.light_energy
			await get_tree().create_timer(0.1).timeout
		early_avg /= 5.0
		var late_avg := 0.0
		for i in range(5):
			late_avg += glow.light_energy
			await get_tree().create_timer(0.1).timeout
		late_avg /= 5.0
		_check(late_avg > early_avg,
			"breach glow intensifies as heat builds (avg %.2f -> %.2f)" % [early_avg, late_avg])

	# --- 3. Everything off except the eject seat ---
	var vel_before: Vector3 = mech.velocity
	Input.action_press("move_forward")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("move_forward")
	_check((mech.velocity - vel_before).length() < 0.01,
		"downed mech ignores movement input (dv %.3f)" % (mech.velocity - vel_before).length())

	var shots_before := _shots
	Input.action_press("fire_left")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire_left")
	_check(_shots == shots_before, "downed mech ignores weapon-fire input")

	var eject := mech.get_node_or_null("MechaEject")
	_check(eject != null and eject.has_method("initiate_eject"), "eject seat stays present and armed")

	# --- 4. Detonation after the delay: the glow is freed with the blast ---
	while is_instance_valid(mech) and is_instance_valid(mech.get_node_or_null("BreachGlow")) and Time.get_ticks_msec() - start_ms < 6000:
		await get_tree().process_frame
	var det_ms := Time.get_ticks_msec() - start_ms
	_check(det_ms >= int(CORE_BREACH_DELAY * 1000) - 250,
		"detonation waits out the CORE_BREACH_DELAY window (%.2fs from destruction)" % (det_ms / 1000.0))
	_check(det_ms < 6000, "detonation fires promptly after the window")
	_check(is_instance_valid(mech) and not is_instance_valid(mech.get_node_or_null("BreachGlow")),
		"breach glow is gone after the blast")

	_finish()


func _mech_downed(mech: CharacterBody3D) -> bool:
	# mecha_controller.gd lives on the mech root itself.
	return mech.has_method("_is_downed") and bool(mech.call("_is_downed"))


func _finish() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("core_breach_verify: checks=%d fails=%d" % [_checks, _fails])
	if _fails == 0:
		get_tree().quit(0)
	else:
		get_tree().quit(1)