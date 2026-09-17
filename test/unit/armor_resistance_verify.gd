extends Node
## ARMOR RESISTANCE VERIFICATION (PHASE 2A)
## Validates the multi-channel armor resistance calculation, damage normalization,
## legacy defense_type fallback, armor HP reduction, armor break, and frame exposure.

var _fails: int = 0
var _checks: int = 0

const MechaHealthScript = preload("res://scripts/mecha/mecha_health.gd")

func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("RES_OK: " + test_name)
	else:
		_fails += 1
		printerr("RES_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING ARMOR RESISTANCE VERIFICATION (PHASE 2A) ===")
	_test_damage_type_normalization()
	_test_resistance_semantics()
	_test_multi_channel_armor_profiles()
	_test_legacy_defense_type_fallback()
	_test_armor_hp_reduction_and_mitigation()
	_test_armor_break_and_frame_exposure()
	_test_no_double_damage()
	_test_old_and_new_armor_data()

	print("\n=== ARMOR RESISTANCE TEST SUMMARY ===")
	print("Checks: %d, Failures: %d" % [_checks, _fails])
	if _fails == 0:
		print("ALL_ARMOR_RESISTANCE_TESTS_PASSED")
		get_tree().quit(0)
	else:
		printerr("ARMOR_RESISTANCE_TESTS_FAILED")
		get_tree().quit(1)


func _test_damage_type_normalization() -> void:
	print("\n-- [1] Damage Type Normalization --")
	# Heat channel
	_check(DamageCalculator.normalize_damage_type("heat") == "heat", "heat normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("beam") == "heat", "beam normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("energy") == "heat", "energy normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("thermal") == "heat", "thermal normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("plasma") == "heat", "plasma normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("fire") == "heat", "fire normalizes to heat")
	_check(DamageCalculator.normalize_damage_type("explosive") == "heat", "explosive normalizes to heat (critical)")

	# Pierce channel
	_check(DamageCalculator.normalize_damage_type("pierce") == "pierce", "pierce normalizes to pierce")
	_check(DamageCalculator.normalize_damage_type("piercing") == "pierce", "piercing normalizes to pierce")
	_check(DamageCalculator.normalize_damage_type("kinetic") == "pierce", "kinetic normalizes to pierce")
	_check(DamageCalculator.normalize_damage_type("rail") == "pierce", "rail normalizes to pierce")
	_check(DamageCalculator.normalize_damage_type("bullet") == "pierce", "bullet normalizes to pierce")
	_check(DamageCalculator.normalize_damage_type("shell") == "pierce", "shell normalizes to pierce")

	# Impact channel
	_check(DamageCalculator.normalize_damage_type("impact") == "impact", "impact normalizes to impact")
	_check(DamageCalculator.normalize_damage_type("blunt") == "impact", "blunt normalizes to impact")
	_check(DamageCalculator.normalize_damage_type("crush") == "impact", "crush normalizes to impact")
	_check(DamageCalculator.normalize_damage_type("melee") == "impact", "melee normalizes to impact")
	_check(DamageCalculator.normalize_damage_type("force") == "impact", "force normalizes to impact")
	_check(DamageCalculator.normalize_damage_type("ram") == "impact", "ram normalizes to impact")


func _test_resistance_semantics() -> void:
	print("\n-- [2] Resistance Semantics (Multipliers) --")
	# 1.0 = normal damage
	var armor_neutral := {"resistance": {"heat": 1.0, "pierce": 1.0, "impact": 1.0}}
	var dmg_neutral = DamageCalculator.calculate_armor_damage(100.0, "heat", armor_neutral)
	_check(is_equal_approx(dmg_neutral, 100.0), "Neutral resistance 1.0 results in 100% damage")

	# 0.5 = 50% damage reduction
	var armor_half := {"resistance": {"heat": 0.5, "pierce": 0.5, "impact": 0.5}}
	var dmg_half_heat = DamageCalculator.calculate_armor_damage(100.0, "heat", armor_half)
	var dmg_half_pierce = DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_half)
	var dmg_half_impact = DamageCalculator.calculate_armor_damage(100.0, "impact", armor_half)
	_check(is_equal_approx(dmg_half_heat, 50.0), "Heat resistance 0.5 results in 50 damage")
	_check(is_equal_approx(dmg_half_pierce, 50.0), "Pierce resistance 0.5 results in 50 damage")
	_check(is_equal_approx(dmg_half_impact, 50.0), "Impact resistance 0.5 results in 50 damage")

	# 0.0 = immunity
	var armor_immune := {"resistance": {"heat": 0.0, "pierce": 0.0, "impact": 0.0}}
	var dmg_immune = DamageCalculator.calculate_armor_damage(100.0, "heat", armor_immune)
	_check(is_equal_approx(dmg_immune, 0.0), "Immunity resistance 0.0 results in 0 damage")

	# 1.2 = vulnerability
	var armor_vuln := {"resistance": {"heat": 1.2, "pierce": 1.5, "impact": 2.0}}
	var dmg_vuln_heat = DamageCalculator.calculate_armor_damage(100.0, "heat", armor_vuln)
	var dmg_vuln_pierce = DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_vuln)
	var dmg_vuln_impact = DamageCalculator.calculate_armor_damage(100.0, "impact", armor_vuln)
	_check(is_equal_approx(dmg_vuln_heat, 120.0), "Vulnerability 1.2 results in 120 damage")
	_check(is_equal_approx(dmg_vuln_pierce, 150.0), "Vulnerability 1.5 results in 150 damage")
	_check(is_equal_approx(dmg_vuln_impact, 200.0), "Vulnerability 2.0 results in 200 damage")


func _test_multi_channel_armor_profiles() -> void:
	print("\n-- [3] Multi-Channel Armor Profiles (Section 7) --")
	# Armor A: heat = 0.5, pierce = 1.0, impact = 1.0
	var armor_a := {"resistance": {"heat": 0.5, "pierce": 1.0, "impact": 1.0}}
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "heat", armor_a), 50.0), "Armor A takes 50 heat dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "beam", armor_a), 50.0), "Armor A takes 50 beam (heat) dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "explosive", armor_a), 50.0), "Armor A takes 50 explosive (heat) dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_a), 100.0), "Armor A takes 100 pierce dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "impact", armor_a), 100.0), "Armor A takes 100 impact dmg")

	# Armor B: heat = 1.0, pierce = 0.5, impact = 1.0
	var armor_b := {"resistance": {"heat": 1.0, "pierce": 0.5, "impact": 1.0}}
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "heat", armor_b), 100.0), "Armor B takes 100 heat dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_b), 50.0), "Armor B takes 50 pierce dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "kinetic", armor_b), 50.0), "Armor B takes 50 kinetic (pierce) dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "impact", armor_b), 100.0), "Armor B takes 100 impact dmg")

	# Armor C: heat = 1.0, pierce = 1.0, impact = 0.5
	var armor_c := {"resistance": {"heat": 1.0, "pierce": 1.0, "impact": 0.5}}
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "heat", armor_c), 100.0), "Armor C takes 100 heat dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_c), 100.0), "Armor C takes 100 pierce dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "impact", armor_c), 50.0), "Armor C takes 50 impact dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "blunt", armor_c), 50.0), "Armor C takes 50 blunt (impact) dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "melee", armor_c), 50.0), "Armor C takes 50 melee (impact) dmg")

	# Armor D: heat = 0.7, pierce = 0.8, impact = 0.6
	var armor_d := {"resistance": {"heat": 0.7, "pierce": 0.8, "impact": 0.6}}
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "heat", armor_d), 70.0), "Armor D takes 70 heat dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "pierce", armor_d), 80.0), "Armor D takes 80 pierce dmg")
	_check(is_equal_approx(DamageCalculator.calculate_armor_damage(100.0, "impact", armor_d), 60.0), "Armor D takes 60 impact dmg")


func _test_legacy_defense_type_fallback() -> void:
	print("\n-- [4] Legacy defense_type Fallback --")
	# Legacy plate with defense_type="heat", armor_class=2.0
	var legacy_heat := {"defense_type": "heat", "armor_class": 2.0}
	var res_matched = DamageCalculator.get_armor_resistance(legacy_heat, "heat")
	var res_mismatched = DamageCalculator.get_armor_resistance(legacy_heat, "pierce")
	_check(is_equal_approx(res_matched, 0.5), "Legacy heat defense matching yields 0.5 (1/2.0)")
	_check(is_equal_approx(res_mismatched, 1.0), "Legacy heat defense mismatching pierce yields 1.0")

	# Legacy balanced plate (empty defense_type or "balanced")
	var legacy_balanced := {"defense_type": "balanced", "armor_class": 1.25}
	_check(is_equal_approx(DamageCalculator.get_armor_resistance(legacy_balanced, "heat"), 0.8), "Legacy balanced yields 1/1.25 = 0.8 vs heat")
	_check(is_equal_approx(DamageCalculator.get_armor_resistance(legacy_balanced, "pierce"), 0.8), "Legacy balanced yields 1/1.25 = 0.8 vs pierce")
	_check(is_equal_approx(DamageCalculator.get_armor_resistance(legacy_balanced, "impact"), 0.8), "Legacy balanced yields 1/1.25 = 0.8 vs impact")

	# Legacy blunt/impact compatibility
	var legacy_blunt := {"defense_type": "blunt", "armor_class": 2.0}
	_check(is_equal_approx(DamageCalculator.get_armor_resistance(legacy_blunt, "impact"), 0.5), "Legacy blunt matches impact attack")
	_check(is_equal_approx(DamageCalculator.get_armor_resistance(legacy_blunt, "melee"), 0.5), "Legacy blunt matches melee attack")


func _test_armor_hp_reduction_and_mitigation() -> void:
	print("\n-- [5] Live Armor HP Reduction and Mitigation --")
	var health = MechaHealthScript.new()
	add_child(health)
	health._init_parts()
	health.is_player = false

	# Equip a test armor with resistance into "body" slot
	health.parts["body"]["armor_hp"] = 100.0
	health.parts["body"]["max_armor"] = 100.0
	health.parts["body"]["frame_hp"] = 100.0
	health.parts["body"]["max_frame"] = 100.0
	health.parts["body"]["armor_broken"] = false
	health.parts["body"]["destroyed"] = false
	health.parts["body"]["resistance"] = {"heat": 0.5, "pierce": 1.0, "impact": 0.8}

	# Deal 40 raw heat damage -> resistance 0.5 -> 20 armor damage
	health.take_damage_to_part("body", 40.0, "heat")
	_check(is_equal_approx(health.parts["body"]["armor_hp"], 80.0), "Armor HP reduced from 100 to 80 by 40 raw heat (0.5 res)")
	_check(is_equal_approx(health.parts["body"]["frame_hp"], 100.0), "Frame HP unaffected while armor intact")
	_check(health.parts["body"]["armor_broken"] == false, "Armor remains intact")

	# Deal 20 raw pierce damage -> resistance 1.0 -> 20 armor damage
	health.take_damage_to_part("body", 20.0, "pierce")
	_check(is_equal_approx(health.parts["body"]["armor_hp"], 60.0), "Armor HP reduced from 80 to 60 by 20 raw pierce (1.0 res)")
	_check(is_equal_approx(health.parts["body"]["frame_hp"], 100.0), "Frame HP still unaffected")

	# Deal 50 raw impact damage -> resistance 0.8 -> 40 armor damage
	health.take_damage_to_part("body", 50.0, "impact")
	_check(is_equal_approx(health.parts["body"]["armor_hp"], 20.0), "Armor HP reduced from 60 to 20 by 50 raw impact (0.8 res)")

	health.queue_free()


func _test_armor_break_and_frame_exposure() -> void:
	print("\n-- [6] Armor Break and Frame Exposure --")
	var health = MechaHealthScript.new()
	add_child(health)
	health._init_parts()
	health.is_player = false

	var broken_signals: Array[String] = []
	health.armor_broken.connect(func(slot): broken_signals.append(slot))

	health.parts["arm_left"]["armor_hp"] = 30.0
	health.parts["arm_left"]["max_armor"] = 30.0
	health.parts["arm_left"]["frame_hp"] = 50.0
	health.parts["arm_left"]["max_frame"] = 50.0
	health.parts["arm_left"]["armor_broken"] = false
	health.parts["arm_left"]["destroyed"] = false
	health.parts["arm_left"]["resistance"] = {"heat": 0.5, "pierce": 1.0, "impact": 1.0}

	# Deal 60 raw heat -> 30 armor damage -> exactly exhausts armor HP!
	health.take_damage_to_part("arm_left", 60.0, "heat")
	_check(is_equal_approx(health.parts["arm_left"]["armor_hp"], 0.0), "Armor HP exhausted to 0")
	_check(health.parts["arm_left"]["armor_broken"] == true, "Armor marked as broken")
	_check(broken_signals.has("arm_left"), "armor_broken signal emitted for arm_left")
	_check(is_equal_approx(health.parts["arm_left"]["frame_hp"], 50.0), "Frame HP not damaged on the exact breaking hit")

	# Frame is now exposed: subsequent damage directly reaches frame
	health.take_damage_to_part("arm_left", 15.0, "heat")
	_check(is_equal_approx(health.parts["arm_left"]["frame_hp"], 35.0), "Exposed frame takes subsequent 15 damage")
	_check(is_equal_approx(health.parts["arm_left"]["armor_hp"], 0.0), "Broken armor HP remains 0")

	health.queue_free()


func _test_no_double_damage() -> void:
	print("\n-- [7] No Double Damage Audit --")
	var health = MechaHealthScript.new()
	add_child(health)
	health._init_parts()
	health.is_player = false

	health.parts["head"]["armor_hp"] = 100.0
	health.parts["head"]["max_armor"] = 100.0
	health.parts["head"]["frame_hp"] = 100.0
	health.parts["head"]["max_frame"] = 100.0
	health.parts["head"]["armor_broken"] = false
	health.parts["head"]["resistance"] = {"heat": 1.0, "pierce": 1.0, "impact": 1.0}

	# Take a single hit
	health.take_damage_to_part("head", 25.0, "pierce")
	_check(is_equal_approx(health.parts["head"]["armor_hp"], 75.0), "Armor absorbed exactly 25 damage")
	_check(is_equal_approx(health.parts["head"]["frame_hp"], 100.0), "Frame took 0 damage (no leakage/double damage)")

	health.queue_free()


func _test_old_and_new_armor_data() -> void:
	print("\n-- [8] Old and New Armor Data Coexistence --")
	# Old armor data with only defense_type
	var old_armor := {
		"id": "old_plate",
		"defense_type": "heat",
		"armor_class": 2.0,
		"hp": 50.0,
	}
	_check(not old_armor.has("resistance"), "Old armor has no resistance dict")
	var old_dmg_heat = DamageCalculator.calculate_armor_damage(50.0, "heat", old_armor)
	var old_dmg_pierce = DamageCalculator.calculate_armor_damage(50.0, "pierce", old_armor)
	_check(is_equal_approx(old_dmg_heat, 25.0), "Old armor resists heat matching defense_type")
	_check(is_equal_approx(old_dmg_pierce, 50.0), "Old armor takes unmitigated pierce on mismatch")

	# New armor data with resistance dictionary (takes priority)
	var new_armor := {
		"id": "new_composite_plate",
		"defense_type": "heat", # legacy field preserved
		"armor_class": 1.0,
		"resistance": {
			"heat": 0.6,
			"pierce": 0.8,
			"impact": 0.9,
		}
	}
	_check(new_armor.has("resistance"), "New armor has resistance dict")
	var new_dmg_heat = DamageCalculator.calculate_armor_damage(100.0, "heat", new_armor)
	var new_dmg_pierce = DamageCalculator.calculate_armor_damage(100.0, "pierce", new_armor)
	var new_dmg_impact = DamageCalculator.calculate_armor_damage(100.0, "impact", new_armor)
	_check(is_equal_approx(new_dmg_heat, 60.0), "New armor uses resistance dict for heat (60 dmg)")
	_check(is_equal_approx(new_dmg_pierce, 80.0), "New armor uses resistance dict for pierce (80 dmg)")
	_check(is_equal_approx(new_dmg_impact, 90.0), "New armor uses resistance dict for impact (90 dmg)")
