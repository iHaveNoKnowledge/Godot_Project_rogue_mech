extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Thermal / Camouflage Cloak (GDD §6.2)
##
## Tests:
##   1. Cloak activation and deactivation
##   2. Charge drain on steps
##   3. Recharge at end of day
##   4. Detection reduction when active
##   5. Serialization round-trip
##
## Run: godot --headless --path . res://tests/thermal_cloak_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

const CLOAK_SCRIPT = preload("res://scripts/systems/thermal_cloak_system.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== THERMAL CLOAK VERIFICATION (GDD §6.2) ===")
	print("")

	test_activation_deactivation()
	test_charge_drain()
	test_recharge()
	test_detection_reduction()
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
# 1. Activation and Deactivation
# ===========================================================================

func test_activation_deactivation() -> void:
	print("[1] Activation & Deactivation")
	var cloak = CLOAK_SCRIPT.new()
	_check(not cloak.is_active, "starts inactive")
	_check(cloak.can_activate(), "can activate with full charge")

	var result := cloak.activate()
	_check(result, "activate returns true")
	_check(cloak.is_active, "is_active after activate")
	_check(cloak.is_cloak_active(), "is_cloak_active() returns true")

	cloak.deactivate()
	_check(not cloak.is_active, "is_active after deactivate")
	_check(not cloak.is_cloak_active(), "is_cloak_active() returns false")

	# Toggle
	cloak.toggle()
	_check(cloak.is_active, "toggle on")
	cloak.toggle()
	_check(not cloak.is_active, "toggle off")


# ===========================================================================
# 2. Charge Drain
# ===========================================================================

func test_charge_drain() -> void:
	print("[2] Charge Drain on Steps")
	var cloak = CLOAK_SCRIPT.new()
	cloak.activate()
	var charge_before: float = cloak.charge
	cloak.drain_step()
	_check(cloak.charge < charge_before, "charge decreased after drain_step")
	_check(absf(cloak.charge - (charge_before - 8.0)) < 0.01, "charge decreased by 8.0")

	# Drain to minimum
	cloak.charge = 12.0
	cloak.drain_step()
	_check(not cloak.is_active, "cloak auto-deactivates below minimum charge")


# ===========================================================================
# 3. Recharge
# ===========================================================================

func test_recharge() -> void:
	print("[3] Recharge at End of Day")
	var cloak = CLOAK_SCRIPT.new()
	cloak.charge = 50.0
	cloak.recharge_day()
	_check(absf(cloak.charge - 75.0) < 0.01, "recharge adds 25.0 per day")

	cloak.recharge_day()
	_check(absf(cloak.charge - 100.0) < 0.01, "recharge caps at max")

	cloak.full_recharge()
	_check(absf(cloak.charge - 100.0) < 0.01, "full_recharge restores to max")


# ===========================================================================
# 4. Detection Reduction
# ===========================================================================

func test_detection_reduction() -> void:
	print("[4] Detection Reduction")
	var cloak = CLOAK_SCRIPT.new()
	_check(CLOAK_SCRIPT.detection_reduction() == 0, "no reduction when inactive")
	_check(CLOAK_SCRIPT.artillery_multiplier() == 1.0, "artillery mult 1.0 when inactive")
	_check(CLOAK_SCRIPT.alert_reduction() == 0, "no alert reduction when inactive")
	_check(absf(CLOAK_SCRIPT.thermal_signature() - 1.0) < 0.001, "full signature when inactive")


# ===========================================================================
# 5. Serialization
# ===========================================================================

func test_serialization() -> void:
	print("[5] Serialization Round-trip")
	var cloak = CLOAK_SCRIPT.new()
	cloak.activate()
	cloak.charge = 73.5

	var data := cloak.serialize()
	_check(bool(data.get("active", false)) == true, "serialized active = true")
	_check(absf(float(data.get("charge", 0.0)) - 73.5) < 0.01, "serialized charge = 73.5")

	var fresh = CLOAK_SCRIPT.new()
	fresh.deserialize(data)
	_check(fresh.is_active, "deserialized active")
	_check(absf(fresh.charge - 73.5) < 0.01, "deserialized charge")
