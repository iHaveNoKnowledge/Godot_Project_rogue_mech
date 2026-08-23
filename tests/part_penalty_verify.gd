extends Node

## ---------------------------------------------------------------------------
## VERIFICATION: Part Penalty System (GDD §6.1)
##
## Run: godot --headless --path . res://tests/part_penalty_verify.tscn
## ---------------------------------------------------------------------------

var _checks := 0
var _fails := 0

const PPS = preload("res://scripts/systems/part_penalty_system.gd")


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("  ✔ %s" % msg)
	else:
		_fails += 1
		print("  ✘ FAIL: %s" % msg)


func _ready() -> void:
	print("")
	print("=== PART PENALTY SYSTEM VERIFICATION (GDD §6.1) ===")
	print("")

	test_no_damage_no_penalty()
	test_head_mild_penalty()
	test_head_severe_penalty()
	test_head_hud_glitch()
	test_arm_mild_penalty()
	test_arm_severe_penalty()
	test_arm_heavy_equip_lockout()
	test_leg_mild_penalty()
	test_leg_severe_penalty()
	test_torso_energy_penalty()
	test_torso_heat_penalty()
	test_active_penalties_text()
	test_combined_multipliers()

	print("")
	print("=== RESULT: %d checks, %d failures ===" % [_checks, _fails])
	print("")
	if _fails == 0:
		print("ALL TESTS PASSED ✅")
	else:
		print("SOME TESTS FAILED ❌")
	get_tree().quit(1 if _fails > 0 else 0)


# ===========================================================================
# 1. Pristine parts → no penalties
# ===========================================================================

func test_no_damage_no_penalty() -> void:
	print("[1] No Damage = No Penalties")
	GlobalData.weapons.part_damage.clear()
	_check(PPS.head_spread_penalty() == 0.0, "head spread = 0")
	_check(PPS.head_lock_on_multiplier() == 1.0, "head lock-on = 1.0")
	_check(not PPS.head_hud_glitching(), "HUD not glitching")
	_check(PPS.arm_recoil_multiplier() == 1.0, "arm recoil = 1.0")
	_check(PPS.arm_melee_speed_multiplier() == 1.0, "arm melee = 1.0")
	_check(not PPS.arm_cannot_equip_heavy(), "arms can equip heavy")
	_check(PPS.leg_speed_multiplier() == 1.0, "leg speed = 1.0")
	_check(PPS.leg_dash_multiplier() == 1.0, "leg dash = 1.0")
	_check(PPS.torso_energy_multiplier() == 1.0, "torso energy = 1.0")
	_check(PPS.torso_heat_multiplier() == 1.0, "torso heat = 1.0")


# ===========================================================================
# 2. Head mild penalty (40% damage)
# ===========================================================================

func test_head_mild_penalty() -> void:
	print("[2] Head Mild Penalty (40%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["head"] = 0.4
	_check(absf(PPS.head_spread_penalty() - 0.03) < 0.001, "head spread = +0.03")
	_check(absf(PPS.head_lock_on_multiplier() - 0.85) < 0.001, "head lock-on = 0.85")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 3. Head severe penalty (80%+ damage)
# ===========================================================================

func test_head_severe_penalty() -> void:
	print("[3] Head Severe Penalty (85%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["head"] = 0.85
	_check(absf(PPS.head_spread_penalty() - 0.15) < 0.001, "head spread = +0.15")
	_check(absf(PPS.head_lock_on_multiplier() - 0.40) < 0.001, "head lock-on = 0.40")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 4. HUD glitch threshold
# ===========================================================================

func test_head_hud_glitch() -> void:
	print("[4] HUD Glitch Threshold")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["head"] = 0.49
	_check(not PPS.head_hud_glitching(), "49% damage: no glitch")
	GlobalData.weapons.part_damage["head"] = 0.50
	_check(PPS.head_hud_glitching(), "50% damage: glitch")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 5. Arm mild penalty (40%)
# ===========================================================================

func test_arm_mild_penalty() -> void:
	print("[5] Arm Mild Penalty (45%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["arm_left"] = 0.45
	_check(absf(PPS.arm_recoil_multiplier() - 1.20) < 0.001, "arm recoil = 1.20")
	_check(absf(PPS.arm_melee_speed_multiplier() - 0.90) < 0.001, "arm melee = 0.90")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 6. Arm severe penalty (80%+)
# ===========================================================================

func test_arm_severe_penalty() -> void:
	print("[6] Arm Severe Penalty (85%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["arm_right"] = 0.85
	_check(absf(PPS.arm_recoil_multiplier() - 2.00) < 0.001, "arm recoil = 2.00")
	_check(absf(PPS.arm_melee_speed_multiplier() - 0.55) < 0.001, "arm melee = 0.55")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 7. Heavy weapon lockout
# ===========================================================================

func test_arm_heavy_equip_lockout() -> void:
	print("[7] Heavy Weapon Lockout (70%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["arm_left"] = 0.69
	_check(not PPS.arm_cannot_equip_heavy(), "69%: can equip heavy")
	GlobalData.weapons.part_damage["arm_left"] = 0.70
	_check(PPS.arm_cannot_equip_heavy(), "70%: cannot equip heavy")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 8. Leg mild penalty (40%)
# ===========================================================================

func test_leg_mild_penalty() -> void:
	print("[8] Leg Mild Penalty (50%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["leg_left"] = 0.50
	_check(absf(PPS.leg_speed_multiplier() - 0.90) < 0.001, "leg speed = 0.90")
	_check(absf(PPS.leg_dash_multiplier() - 0.85) < 0.001, "leg dash = 0.85")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 9. Leg severe penalty (80%+)
# ===========================================================================

func test_leg_severe_penalty() -> void:
	print("[9] Leg Severe Penalty (85%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["leg_right"] = 0.85
	_check(absf(PPS.leg_speed_multiplier() - 0.55) < 0.001, "leg speed = 0.55")
	_check(absf(PPS.leg_dash_multiplier() - 0.40) < 0.001, "leg dash = 0.40")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 10. Torso energy penalty
# ===========================================================================

func test_torso_energy_penalty() -> void:
	print("[10] Torso Energy Penalty (65%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["body"] = 0.65
	_check(absf(PPS.torso_energy_multiplier() - 0.75) < 0.001, "torso energy = 0.75")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 11. Torso heat penalty
# ===========================================================================

func test_torso_heat_penalty() -> void:
	print("[11] Torso Heat Penalty (80%)")
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["body"] = 0.80
	_check(absf(PPS.torso_heat_multiplier() - 1.60) < 0.001, "torso heat = 1.60")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 12. Active penalties text
# ===========================================================================

func test_active_penalties_text() -> void:
	print("[12] Active Penalties Text")
	GlobalData.weapons.part_damage.clear()
	var p0 := PPS.active_penalties()
	_check(p0.is_empty(), "no penalties when pristine")

	GlobalData.weapons.part_damage["head"] = 0.55
	var p1 := PPS.active_penalties()
	_check(p1.size() == 1, "1 penalty when head damaged")
	_check(p1[0].contains("HEAD"), "penalty mentions HEAD")
	GlobalData.weapons.part_damage.clear()


# ===========================================================================
# 13. Combined / worst-arm / worst-leg
# ===========================================================================

func test_combined_multipliers() -> void:
	print("[13] Combined Multipliers")
	GlobalData.weapons.part_damage.clear()
	# Both arms at different damage levels — worst arm dictates
	GlobalData.weapons.part_damage["arm_left"] = 0.85
	GlobalData.weapons.part_damage["arm_right"] = 0.50
	_check(absf(PPS.worst_arm_damage() - 0.85) < 0.001, "worst_arm_damage = 0.85")
	_check(absf(PPS.arm_recoil_multiplier() - 2.00) < 0.001, "recoil follows worst arm")

	# Torso energy + leg speed combined
	GlobalData.weapons.part_damage["body"] = 0.65
	GlobalData.weapons.part_damage["leg_left"] = 0.50
	_check(absf(PPS.total_energy_multiplier() - 0.75) < 0.001, "energy from torso = 0.75")
	_check(absf(PPS.total_board_speed_multiplier() - 0.90) < 0.001, "speed from legs = 0.90")
	GlobalData.weapons.part_damage.clear()
