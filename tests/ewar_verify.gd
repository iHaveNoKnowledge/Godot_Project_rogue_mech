extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: EWar System (GDD §7 Electronic Warfare)
##
## Tests:
##   1. Ability activation and energy cost
##   2. Cooldown management
##   3. Effect duration and expiry
##   4. Tier scaling
##   5. JAM detection and accuracy penalties
##   6. SPOOF false signatures
##   7. EMP stun and weapon disable
##   8. SCRAMBLE block radius
##   9. Serialization round-trip
##
## Run: godot --headless --path . res://tests/ewar_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

const EWAR_SCRIPT = preload("res://scripts/systems/ewar_system.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== EWAR SYSTEM VERIFICATION (GDD §7) ===")
	print("")

	test_activation_energy()
	test_cooldowns()
	test_effect_duration()
	test_tier_scaling()
	test_jam_effects()
	test_spoof_effects()
	test_emp_effects()
	test_scramble_effects()
	test_ability_names()
	test_serialization()

	print("")
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _fails])
	print("")
	if _fails == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fails > 0 else 0)


# ===========================================================================
# 1. Activation and Energy Cost
# ===========================================================================

func test_activation_energy() -> void:
	print("[1] Activation & Energy Cost")
	var e = EWAR_SCRIPT.new()

	# Not enough energy — should fail
	var new_energy := e.activate(e.Ability.JAM, 10.0)  # JAM costs 15
	_check(absf(new_energy - 10.0) < 0.01, "JAM fails with 10 energy (costs 15)")

	# Enough energy — should succeed
	new_energy = e.activate(e.Ability.JAM, 20.0)
	_check(absf(new_energy - 5.0) < 0.01, "JAM succeeds: 20 - 15 = 5 remaining")

	# Check cooldown started
	_check(e.get_cooldown(e.Ability.JAM) > 0.0, "JAM cooldown started after activation")

	# All abilities have correct costs
	var e2 = EWAR_SCRIPT.new()
	_check(absf(e2.activate(e2.Ability.SPOOF, 25.0) - 5.0) < 0.01, "SPOOF costs 20")
	var e3 = EWAR_SCRIPT.new()
	_check(absf(e3.activate(e3.Ability.EMP, 40.0) - 5.0) < 0.01, "EMP costs 35")
	var e4 = EWAR_SCRIPT.new()
	_check(absf(e4.activate(e4.Ability.SCRAMBLE, 30.0) - 5.0) < 0.01, "SCRAMBLE costs 25")


# ===========================================================================
# 2. Cooldown Management
# ===========================================================================

func test_cooldowns() -> void:
	print("[2] Cooldown Management")
	var e = EWAR_SCRIPT.new()
	e.activate(e.Ability.JAM, 50.0)

	var cd := e.get_cooldown(e.Ability.JAM)
	_check(cd > 0.0, "JAM cooldown > 0 after activation")
	_check(absf(cd - 12.0) < 0.01, "JAM cooldown = 12s")

	# Tick reduces cooldown
	e.tick(5.0)
	_check(absf(e.get_cooldown(e.Ability.JAM) - 7.0) < 0.01, "JAM cooldown reduced to 7s after 5s tick")

	e.tick(7.0)
	_check(absf(e.get_cooldown(e.Ability.JAM)) < 0.01, "JAM cooldown reached 0")

	# Can activate again after cooldown
	_check(e.can_activate(e.Ability.JAM, 20.0), "JAM can_activate after cooldown")

	# Can't activate during cooldown
	var e2 = EWAR_SCRIPT.new()
	e2.activate(e2.Ability.EMP, 100.0)
	_check(not e2.can_activate(e2.Ability.EMP, 100.0), "EMP can't_activate during cooldown")

	# Reset clears all cooldowns
	e2.reset_cooldowns()
	_check(e2.can_activate(e2.Ability.EMP, 100.0), "EMP can_activate after reset_cooldowns")


# ===========================================================================
# 3. Effect Duration and Expiry
# ===========================================================================

func test_effect_duration() -> void:
	print("[3] Effect Duration & Expiry")
	var e = EWAR_SCRIPT.new()
	e.activate(e.Ability.JAM, 50.0)

	_check(e.is_active(e.Ability.JAM), "JAM is_active after activation")
	_check(not e.is_active(e.Ability.SPOOF), "SPOOF not active when not activated")

	var dur := e.get_active_duration(e.Ability.JAM)
	_check(absf(dur - 8.0) < 0.01, "JAM duration = 8s")

	# Tick reduces duration
	e.tick(5.0)
	_check(absf(e.get_active_duration(e.Ability.JAM) - 3.0) < 0.01, "JAM duration reduced to 3s")

	e.tick(3.0)
	_check(not e.is_active(e.Ability.JAM), "JAM expired after full duration")


# ===========================================================================
# 4. Tier Scaling
# ===========================================================================

func test_tier_scaling() -> void:
	print("[4] Tier Scaling")
	var e = EWAR_SCRIPT.new()
	e.head_tier = 1
	e.activate(e.Ability.JAM, 50.0)
	_check(e.jam_detection_reduction() == 4, "Tier 1 JAM detection reduction = 4")
	_check(absf(e.jam_accuracy_penalty() - 0.3) < 0.01, "Tier 1 JAM accuracy penalty = 0.3")

	# Tier 2: 1.25x
	var e2 = EWAR_SCRIPT.new()
	e2.head_tier = 2
	e2.activate(e2.Ability.JAM, 50.0)
	_check(e2.jam_detection_reduction() == 5, "Tier 2 JAM detection reduction = 5")
	_check(absf(e2.jam_accuracy_penalty() - 0.375) < 0.01, "Tier 2 JAM accuracy penalty = 0.375")

	# Tier 3: 1.5x
	var e3 = EWAR_SCRIPT.new()
	e3.head_tier = 3
	e3.activate(e3.Ability.JAM, 50.0)
	_check(e3.jam_detection_reduction() == 6, "Tier 3 JAM detection reduction = 6")
	_check(absf(e3.jam_accuracy_penalty() - 0.45) < 0.01, "Tier 3 JAM accuracy penalty = 0.45")


# ===========================================================================
# 5. JAM Effects
# ===========================================================================

func test_jam_effects() -> void:
	print("[5] JAM Detection & Accuracy")
	var e = EWAR_SCRIPT.new()
	_check(e.jam_detection_reduction() == 0, "JAM detection reduction = 0 when inactive")
	_check(absf(e.jam_accuracy_penalty()) < 0.01, "JAM accuracy penalty = 0 when inactive")

	e.activate(e.Ability.JAM, 50.0)
	_check(e.jam_detection_reduction() > 0, "JAM detection reduction > 0 when active")
	_check(e.jam_accuracy_penalty() > 0.0, "JAM accuracy penalty > 0 when active")


# ===========================================================================
# 6. SPOOF Effects
# ===========================================================================

func test_spoof_effects() -> void:
	print("[6] SPOOF False Signatures")
	var e = EWAR_SCRIPT.new()
	_check(e.spoof_false_signature_count() == 0, "SPOOF false signatures = 0 when inactive")
	_check(e.spoof_redirect_range() == 5, "SPOOF redirect range = 5")

	e.activate(e.Ability.SPOOF, 50.0)
	_check(e.spoof_false_signature_count() == 2, "SPOOF creates 2 false signatures when active")


# ===========================================================================
# 7. EMP Effects
# ===========================================================================

func test_emp_effects() -> void:
	print("[7] EMP Stun & Weapon Disable")
	var e = EWAR_SCRIPT.new()
	_check(absf(e.emp_stun_duration()) < 0.01, "EMP stun = 0 when inactive")
	_check(absf(e.emp_weapon_disable_duration()) < 0.01, "EMP weapon disable = 0 when inactive")

	e.activate(e.Ability.EMP, 50.0)
	_check(absf(e.emp_stun_duration() - 3.0) < 0.01, "EMP stun = 3s when active")
	_check(absf(e.emp_weapon_disable_duration() - 5.0) < 0.01, "EMP weapon disable = 5s when active")


# ===========================================================================
# 8. SCRAMBLE Effects
# ===========================================================================

func test_scramble_effects() -> void:
	print("[8] SCRAMBLE Block Radius")
	var e = EWAR_SCRIPT.new()
	_check(e.scramble_block_radius() == 0, "SCRAMBLE block radius = 0 when inactive")

	e.activate(e.Ability.SCRAMBLE, 50.0)
	_check(e.scramble_block_radius() == 8, "SCRAMBLE block radius = 8 when active")


# ===========================================================================
# 9. Ability Names & Icons
# ===========================================================================

func test_ability_names() -> void:
	print("[9] Ability Names & Icons")
	var e = EWAR_SCRIPT.new()
	_check(e.ability_name(e.Ability.JAM) == "SENSOR JAM", "JAM name = SENSOR JAM")
	_check(e.ability_name(e.Ability.SPOOF) == "RADAR SPOOF", "SPOOF name = RADAR SPOOF")
	_check(e.ability_name(e.Ability.EMP) == "EMP BURST", "EMP name = EMP BURST")
	_check(e.ability_name(e.Ability.SCRAMBLE) == "COMM SCRAMBLE", "SCRAMBLE name = COMM SCRAMBLE")
	_check(e.ability_icon(e.Ability.JAM) == "📡", "JAM icon = 📡")
	_check(e.ability_icon(e.Ability.EMP) == "⚡", "EMP icon = ⚡")


# ===========================================================================
# 10. Serialization Round-trip
# ===========================================================================

func test_serialization() -> void:
	print("[10] Serialization Round-trip")
	var e = EWAR_SCRIPT.new()
	e.head_tier = 3
	e.activate(e.Ability.JAM, 50.0)
	e.tick(2.0)  # Reduce cooldown/duration slightly

	var data := e.serialize()
	_check(data.get("head_tier", 0) == 3, "serialized head_tier = 3")

	var fresh = EWAR_SCRIPT.new()
	fresh.deserialize(data)
	_check(fresh.head_tier == 3, "deserialized head_tier = 3")
	_check(absf(fresh.get_cooldown(e.Ability.JAM) - 10.0) < 0.1, "deserialized JAM cooldown ≈ 10s")
	_check(fresh.is_active(e.Ability.JAM), "deserialized JAM still active")
	_check(absf(fresh.get_active_duration(e.Ability.JAM) - 6.0) < 0.1, "deserialized JAM duration ≈ 6s")
