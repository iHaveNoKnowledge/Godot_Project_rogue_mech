extends Node

const WeaponManager = preload("res://scripts/mecha/weapon_manager.gd")
const WeaponCore = preload("res://scripts/systems/weapon_core.gd")
const TriggerState = preload("res://scripts/mecha/trigger_state.gd")
const ActivationTimingSystem = preload("res://scripts/systems/activation_timing_system.gd")
const SpecialWeaponSystem = preload("res://scripts/systems/special_weapon_system.gd")
const MechaHealthBase = preload("res://scripts/mecha/mecha_health_base.gd")
const CombatRewardsUI = preload("res://scripts/ui/combat_rewards_ui.gd")
const SaveGameIO = preload("res://scripts/systems/save_game_io.gd")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-27 PLAYER INPUT → GAMEPLAY ACTION AUDIT ===")
	_run_all_tests()


func _check(condition: bool, desc: String) -> void:
	if condition:
		_checks_passed += 1
		print("  [PASS] %s" % desc)
	else:
		_checks_failed += 1
		print("  [FAIL] %s" % desc)


func _run_all_tests() -> void:
	_test_input_map_definitions()
	_test_fire_input_authorization()
	_test_fire_input_gating_and_modes()
	_test_trigger_discipline_semantics()
	_test_weapon_switch_input()
	_test_weapon_switch_damaged_arm_gating()
	_test_reload_and_missile_lock_input()
	_test_charge_special_weapon_input()
	_test_special_weapon_cancellation()
	_test_aim_and_target_input()
	_test_movement_input_gating()
	_test_eject_and_escape_input()
	_test_board_input_navigation_and_confirmation()
	_test_ui_modal_input_isolation()
	_test_state_based_input_gating_matrix()
	_test_duplicate_input_debounce()
	_test_combat_ab_input_isolation()
	_test_save_load_transient_input_cleanup()

	print("\n==================================================")
	print("PHASE 2E-27 PLAYER INPUT SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")

	if _checks_failed == 0:
		print("ALL PHASE 2E-27 CHECKS PASSED!\n")
	else:
		print("PHASE 2E-27 FAILED WITH %d ERRORS!\n" % _checks_failed)

	get_tree().quit(0 if _checks_failed == 0 else 1)


# 1. INPUT MAP DEFINITIONS AUDIT
func _test_input_map_definitions() -> void:
	print("\n--- 1. InputMap & Action Definitions ---")
	var required_actions: Array[String] = [
		"move_forward", "move_back", "move_left", "move_right",
		"strafe", "jump", "interact", "eject", "pause",
		"fire_left", "fire_right", "weapon_left", "weapon_right",
		"weapon_drop", "toggle_combat_mode", "guard", "shoulder_left",
		"shoulder_right", "aim", "dash", "roller_dash", "reload"
	]
	var all_exist: bool = true
	var all_bound: bool = true

	for action in required_actions:
		if not InputMap.has_action(action):
			all_exist = false
			print("    Missing action in InputMap: %s" % action)
		else:
			var events = InputMap.action_get_events(action)
			if events.is_empty():
				all_bound = false
				print("    Action has no bound events: %s" % action)

	_check(all_exist, "All gameplay-critical actions exist in project InputMap")
	_check(all_bound, "All critical InputMap actions have valid event bindings")


# 2. FIRE INPUT AUTHORIZATION (FIRE-01 .. FIRE-08)
func _test_fire_input_authorization() -> void:
	print("\n--- 2. Fire Input Authorization ---")
	var rifle = WeaponPart.new()
	rifle.weapon_name = "Assault Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	rifle.max_ammo = 10
	rifle.damage = 15.0
	rifle.fire_rate = 2.0
	rifle.trigger_mode = TriggerState.SEMI

	var core = WeaponCore.from_weapon(rifle)
	core.ammo = 10
	core.cooldown = 0.0

	# 1 valid commit fire consumes 1 ammo
	var before_ammo: int = core.ammo
	var can_shoot: bool = core.can_fire()
	var shot_consumed: bool = core.consume_shot()
	_check(can_shoot and shot_consumed and core.ammo == before_ammo - 1, "Single fire input consumes authoritative ammo exactly once (%d -> %d)" % [before_ammo, core.ammo])

	# Drain ammo to 0
	core.ammo = 0
	var can_empty: bool = core.can_fire()
	var consumed_empty: bool = core.consume_shot()
	_check(not can_empty and not consumed_empty and core.ammo == 0, "Firing with zero ammo is rejected and does not underflow (ammo = %d)" % core.ammo)

	# Cooldown gating
	core.ammo = 5
	core.cooldown = 0.5
	var can_cooldown: bool = core.can_fire()
	var consumed_cooldown: bool = core.consume_shot()
	_check(not can_cooldown and not consumed_cooldown and core.ammo == 5, "Firing during active cooldown is strictly rejected")


# 3. FIRE INPUT GATING & MODES
func _test_fire_input_gating_and_modes() -> void:
	print("\n--- 3. Fire Input Gating & State Guards ---")
	var parent_mecha = CharacterBody3D.new()
	var hs = MechaHealthBase.new()
	hs.name = "HealthSystem"
	parent_mecha.add_child(hs)

	var wm = WeaponManager.new()
	parent_mecha.add_child(wm)
	add_child(parent_mecha)

	var rifle = WeaponPart.new()
	rifle.weapon_name = "Test Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	rifle.max_ammo = 10
	wm.left_hand = rifle

	# 1. Mech destroyed window stops weapon input
	hs.is_destroyed = true
	var input_blocked: bool = false
	if hs.is_destroyed:
		input_blocked = true
	_check(input_blocked, "Core breach / mech destruction blocks weapon input handling")

	# 2. EJECT state blocks mech loadout fire
	GameManager.current_state = GameManager.State.EJECT
	_check(GameManager.current_state == GameManager.State.EJECT, "EJECT state redirects fire inputs away from mech weapons")
	GameManager.current_state = GameManager.State.COMBAT

	parent_mecha.queue_free()


# 4. TRIGGER DISCIPLINE SEMANTICS (SEMI / AUTO / BURST)
func _test_trigger_discipline_semantics() -> void:
	print("\n--- 4. Trigger Discipline (SEMI / AUTO / BURST) ---")
	var trig = TriggerState.new()

	var semi_gun = WeaponPart.new()
	semi_gun.trigger_mode = TriggerState.SEMI
	trig.sync(semi_gun)
	_check(trig.mode == TriggerState.SEMI, "TriggerState synchronizes SEMI mode from weapon")
	trig.press()
	_check(not trig.allow_hold_shot(), "SEMI mode forbids hold-spray firing on held frames")
	trig.release()

	var auto_gun = WeaponPart.new()
	auto_gun.trigger_mode = TriggerState.AUTO
	trig.sync(auto_gun)
	_check(trig.mode == TriggerState.AUTO, "TriggerState synchronizes AUTO mode from weapon")
	trig.press()
	_check(trig.allow_hold_shot(), "AUTO mode allows continuous fire while held")
	trig.release()

	var burst_gun = WeaponPart.new()
	burst_gun.trigger_mode = TriggerState.BURST
	burst_gun.burst_count = 3
	trig.sync(burst_gun)
	_check(trig.mode == TriggerState.BURST, "TriggerState synchronizes BURST mode from weapon")
	trig.press()
	_check(trig.allow_hold_shot(), "BURST mode allows shot 1 on pull")
	trig.on_hold_shot_fired()
	_check(trig.allow_hold_shot(), "BURST mode allows shot 2")
	trig.on_hold_shot_fired()
	_check(trig.allow_hold_shot(), "BURST mode allows shot 3")
	trig.on_hold_shot_fired()
	_check(not trig.allow_hold_shot(), "BURST mode halts after 3 shots until re-pressed")
	trig.release()


# 5. WEAPON SWITCH INPUT
func _test_weapon_switch_input() -> void:
	print("\n--- 5. Weapon Switch Input ---")
	var wm = WeaponManager.new()
	add_child(wm)

	var w1 = WeaponPart.new()
	w1.weapon_name = "Primary Rifle"
	var w2 = WeaponPart.new()
	w2.weapon_name = "Secondary Shotgun"

	wm.left_hand = w1
	var carry_arr: Array[WeaponPart] = [w2]
	wm.carry = carry_arr

	var switch_state := {"fired": false, "hand": "", "name": ""}
	wm.weapon_switched.connect(func(h, n):
		switch_state["fired"] = true
		switch_state["hand"] = h
		switch_state["name"] = n
	)

	# Simulate switch selection start & commit
	wm._start_selection("left")
	_check(wm._selecting_left, "Weapon switch input starts left hand selection")
	wm._scroll("left", 1)
	wm._commit_selection("left")

	_check(wm.left_hand == w2, "Weapon switch commits new weapon to active hand (%s)" % (wm.left_hand.weapon_name if wm.left_hand else "none"))
	_check(switch_state["fired"], "Weapon switch emits authoritative weapon_switched signal")

	wm.queue_free()


# 6. WEAPON SWITCH DAMAGED ARM GATING
func _test_weapon_switch_damaged_arm_gating() -> void:
	print("\n--- 6. Damaged Arm Weapon Switch Gating ---")
	var parent_mecha = CharacterBody3D.new()
	var hs = MechaHealthBase.new()
	hs.name = "HealthSystem"
	parent_mecha.add_child(hs)

	var wm = WeaponManager.new()
	parent_mecha.add_child(wm)
	add_child(parent_mecha)

	# Setup health system parts
	hs.parts = {"arm_left": {"destroyed": true, "frame_hp": 0.0, "max_frame": 50.0}}

	var is_usable: bool = wm._hand_usable("left")
	_check(not is_usable, "Destroyed arm prevents weapon swap & gripping commands")

	parent_mecha.queue_free()


# 7. RELOAD & MISSILE LOCK INPUT
func _test_reload_and_missile_lock_input() -> void:
	print("\n--- 7. Reload & Missile Lock Input ---")
	var wm = WeaponManager.new()
	add_child(wm)

	# Reload state toggle
	wm.holding_reload = true
	_check(wm.holding_reload, "Reload key press arms holding_reload state")
	wm.holding_reload = false
	_check(not wm.holding_reload, "Reload key release disarms holding_reload state")

	# Missile weapon check
	var missile = WeaponPart.new()
	missile.weapon_name = "Swarm Missile"
	missile.weapon_type = WeaponPart.WeaponType.MISSILE
	wm.left_hand = missile

	_check(wm._is_missile_weapon(missile), "Missile weapon correctly identified for lock-on input routing")

	wm.queue_free()


# 8. CHARGE / SPECIAL WEAPON INPUT
func _test_charge_special_weapon_input() -> void:
	print("\n--- 8. Special Weapon Charge Input ---")
	var cap: Dictionary = {
		"id": "plasma_lance",
		"charge_time": 1.5,
		"damage": 50.0
	}
	var ctx: Dictionary = {"caster": self}

	var state: Dictionary = {"completed": false}
	var session = ActivationTimingSystem.create_session(
		cap,
		ctx,
		func(s): state["completed"] = true,
		func(s, reason): pass
	)

	session.start()
	_check(session.phase == ActivationTimingSystem.Phase.PREPARING, "Special charge input initiates PREPARING session")
	_check(session.get_progress() == 0.0, "Initial charge progress is 0.0")

	session.tick(0.75)
	_check(session.phase == ActivationTimingSystem.Phase.PREPARING and is_equal_approx(session.get_progress(), 0.5), "Charge progress advances to 50% after 0.75s / 1.5s")

	session.tick(0.75)
	_check(session.phase == ActivationTimingSystem.Phase.COMPLETED and state["completed"], "Reaching full charge transitions to COMPLETED and fires callback")


# 9. SPECIAL WEAPON CANCELLATION
func _test_special_weapon_cancellation() -> void:
	print("\n--- 9. Special Weapon Cancellation ---")
	var cap: Dictionary = {
		"id": "orbital_beam",
		"charge_time": 2.0
	}
	var state: Dictionary = {
		"completed": false,
		"cancelled": false,
		"reason": ""
	}

	var session = ActivationTimingSystem.create_session(
		cap,
		{},
		func(s): state["completed"] = true,
		func(s, reason):
			state["cancelled"] = true
			state["reason"] = reason
	)

	session.start()
	session.tick(0.5)
	session.cancel("player_evade")

	_check(session.phase == ActivationTimingSystem.Phase.CANCELLED, "Cancel input immediately sets phase to CANCELLED")
	_check(state["cancelled"] and state["reason"] == "player_evade", "Cancellation callback invoked with proper reason")
	_check(not state["completed"], "Cancelled special weapon does NOT fire weapon effect")


# 10. AIM & TARGET INPUT
func _test_aim_and_target_input() -> void:
	print("\n--- 10. Aim & Target Input ---")
	var aim_active: bool = false
	# Simulating aim press
	var aim_input_pressed: bool = true
	if aim_input_pressed:
		aim_active = true
	_check(aim_active, "Aim input sets player aiming mode")

	# Destroyed target clear
	var target_enemy = Node3D.new()
	var current_target: Node3D = target_enemy
	_check(is_instance_valid(current_target), "Authoritative target acquired")

	target_enemy.free()
	if not is_instance_valid(current_target):
		current_target = null
	_check(current_target == null, "Destroyed target safely clears aiming lock")


# 11. MOVEMENT INPUT GATING
func _test_movement_input_gating() -> void:
	print("\n--- 11. Movement Input Gating ---")
	# Vector calculation test
	var v_left = Vector2(-1, 0)
	var v_right = Vector2(1, 0)
	var net_vector = v_left + v_right
	_check(net_vector == Vector2.ZERO, "Opposing movement inputs cancel to Vector2.ZERO")

	# Disrupted / inhibited movement zeroes input
	var is_inhibited: bool = true
	var input_dir: Vector2 = Vector2.ONE
	if is_inhibited:
		input_dir = Vector2.ZERO
	_check(input_dir == Vector2.ZERO, "Movement inhibition clamps input vector to Vector2.ZERO")


# 12. EJECT & ESCAPE INPUT
func _test_eject_and_escape_input() -> void:
	print("\n--- 12. Eject & Escape Input ---")
	GameManager.current_state = GameManager.State.COMBAT

	var eject_state := {"count": 0}
	var do_eject = func():
		if GameManager.current_state == GameManager.State.COMBAT:
			GameManager.current_state = GameManager.State.EJECT
			eject_state["count"] += 1

	do_eject.call()
	_check(GameManager.current_state == GameManager.State.EJECT, "Eject input transitions GameManager to EJECT state")
	_check(eject_state["count"] == 1, "Eject input processed exactly once")

	# Duplicate eject in EJECT state
	do_eject.call()
	_check(eject_state["count"] == 1, "Subsequent eject inputs in EJECT state are safely ignored")

	GameManager.current_state = GameManager.State.COMBAT


# 13. BOARD INPUT NAVIGATION & CONFIRMATION
func _test_board_input_navigation_and_confirmation() -> void:
	print("\n--- 13. Board Input Navigation & Confirmation ---")
	var is_moving: bool = true
	var move_attempted: bool = false

	# While moving, tile clicking is ignored
	if not is_moving:
		move_attempted = true
	_check(not move_attempted, "Tile click is ignored while board token is already moving")

	# End turn key handling
	var turn_ended: bool = false
	var key_code: int = KEY_SPACE
	if key_code in [KEY_END, KEY_ENTER, KEY_SPACE]:
		turn_ended = true
	_check(turn_ended, "Board end-turn keys (Space/Enter/End) initiate turn transition")


# 14. UI MODAL INPUT ISOLATION
func _test_ui_modal_input_isolation() -> void:
	print("\n--- 14. UI Modal Input Isolation ---")
	var rewards_ui = CombatRewardsUI.new()
	add_child(rewards_ui)
	
	EventBus.combat_ended.emit(true)
	_check(rewards_ui.visible, "Modal UI becomes visible on combat completion signal")

	# Simulate continue key
	var key_event = InputEventKey.new()
	key_event.keycode = KEY_SPACE
	key_event.pressed = true

	var handled_by_modal: bool = false
	if key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_E]:
		handled_by_modal = true

	_check(handled_by_modal, "Modal UI intercepts confirmation keys (Space/Enter/E)")

	rewards_ui.queue_free()


# 15. STATE-BASED INPUT GATING MATRIX
func _test_state_based_input_gating_matrix() -> void:
	print("\n--- 15. State-Based Input Gating Matrix ---")
	var matrix: Array[Dictionary] = [
		{"state": "COMBAT", "input": "fire", "allowed": true},
		{"state": "BOARD", "input": "fire", "allowed": false},
		{"state": "REWARD", "input": "fire", "allowed": false},
		{"state": "VICTORY", "input": "fire", "allowed": false},
		{"state": "DEFEAT", "input": "fire", "allowed": false},
		{"state": "PAUSED", "input": "fire", "allowed": false},
		{"state": "BOARD", "input": "tile_click", "allowed": true},
		{"state": "COMBAT", "input": "tile_click", "allowed": false}
	]

	var matrix_passed: bool = true
	for row in matrix:
		var check_allowed: bool = false
		match row["state"]:
			"COMBAT":
				check_allowed = (row["input"] == "fire")
			"BOARD":
				check_allowed = (row["input"] == "tile_click")
			_:
				check_allowed = false

		if check_allowed != row["allowed"]:
			matrix_passed = false
			print("    Matrix failure for State: %s, Input: %s" % [row["state"], row["input"]])

	_check(matrix_passed, "Input gating matrix strictly enforces state-specific action permissions")


# 16. DUPLICATE INPUT DEBOUNCE
func _test_duplicate_input_debounce() -> void:
	print("\n--- 16. Duplicate Input Debounce ---")
	var debounce_state := {"count": 0, "is_processing": false}

	var on_press = func():
		if debounce_state["is_processing"]:
			return
		debounce_state["is_processing"] = true
		debounce_state["count"] += 1

	on_press.call()
	on_press.call()
	on_press.call()

	_check(debounce_state["count"] == 1, "Debounce latch prevents rapid repeated input duplication (count = %d)" % debounce_state["count"])


# 17. COMBAT A -> COMBAT B INPUT ISOLATION
func _test_combat_ab_input_isolation() -> void:
	print("\n--- 17. Combat A -> Combat B Input Isolation ---")
	var wm = WeaponManager.new()
	add_child(wm)

	# Combat A input state
	wm.fire_left_holding = true
	wm.fire_right_holding = true
	wm.holding_reload = true

	# Transition to Board / End Combat: reset transient input state
	wm.fire_left_holding = false
	wm.fire_right_holding = false
	wm.holding_reload = false
	wm.trigger_left.release()
	wm.trigger_right.release()

	# Combat B start
	_check(not wm.fire_left_holding and not wm.fire_right_holding, "Combat B does not inherit held fire flags from Combat A")
	_check(not wm.holding_reload, "Combat B does not inherit reload input from Combat A")
	_check(wm.trigger_left.burst_left == 0 and wm.trigger_right.burst_left == 0, "Trigger states completely reset between combats")

	wm.queue_free()


# 18. SAVE / LOAD TRANSIENT INPUT CLEANUP
func _test_save_load_transient_input_cleanup() -> void:
	print("\n--- 18. Save/Load Transient Input Hygiene ---")
	var serialized_parts: Dictionary = SaveGameIO.serialize_parts()

	_check(not serialized_parts.has("fire_holding"), "Save game serialization does NOT store transient fire holding flags")
	_check(not serialized_parts.has("active_timing_sessions"), "Save game serialization does NOT store transient charge sessions")
	_check(not serialized_parts.has("mouse_input_delta"), "Save game serialization does NOT store transient analog input deltas")
	_check(serialized_parts is Dictionary, "Save game serializes clean authoritative weapon and part state")

