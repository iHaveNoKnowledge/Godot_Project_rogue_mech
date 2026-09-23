extends Node

const PilotSys = preload("res://scripts/systems/pilot_system.gd")
const CombatModRes = preload("res://scripts/systems/combat_modifier_resolver.gd")
const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const MechaDashSys = preload("res://scripts/mecha/mecha_dash_system.gd")

var _checks_passed: int = 0
var _checks_failed: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-16A PILOT FOUNDATION & MODIFIER RESOLVER VERIFICATION ===")
	_run_all_tests()


func _check(condition: bool, desc: String) -> void:
	if condition:
		_checks_passed += 1
		print("  [PASS] %s" % desc)
	else:
		_checks_failed += 1
		print("  [FAIL] %s" % desc)


func _run_all_tests() -> void:
	_test_pilot_progression_defaults_and_reset()
	_test_save_load_progression_fidelity()
	_test_combat_modifier_resolver_neutrality()
	_test_precognitive_flow_perk_migration()
	_test_mecha_dash_system_resolver_integration()
	_test_technology_and_loadout_boundary_integrity()

	print("\n==================================================")
	print("PHASE 2E-16A VERIFICATION SUMMARY:")
	print("  Passed: %d" % _checks_passed)
	print("  Failed: %d" % _checks_failed)
	print("==================================================")

	if _checks_failed == 0:
		print("PHASE_2E_16A_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_16A_FAILED: %d assertions failed." % _checks_failed)
		get_tree().quit(1)


func _test_pilot_progression_defaults_and_reset() -> void:
	print("\n-- [1] Pilot Progression Defaults & Reset Semantics --")

	GlobalData.reset_run_data()

	var prog: Dictionary = PilotSys.get_progression()
	_check(int(prog.get("level", 0)) == 1, "Default pilot level is 1")
	_check(int(prog.get("xp", -1)) == 0, "Default pilot XP is 0")
	_check(int(prog.get("skill_points", -1)) == 0, "Default skill points is 0")
	_check((prog.get("unlocked_skills", []) as Array).is_empty(), "Default unlocked skills list is empty")
	_check(str(prog.get("specialization", "none")) == "", "Default specialization is empty string")

	_check(PilotSys.get_pilot_level() == 1, "PilotSystem.get_pilot_level() returns 1")
	_check(PilotSys.get_pilot_xp() == 0, "PilotSystem.get_pilot_xp() returns 0")
	_check(PilotSys.get_skill_points() == 0, "PilotSystem.get_skill_points() returns 0")

	# Simulate mid-run progression mutation
	GlobalData.pilot.progression["level"] = 3
	GlobalData.pilot.progression["xp"] = 450
	GlobalData.pilot.progression["skill_points"] = 2
	GlobalData.pilot.progression["unlocked_skills"] = ["iron_discipline"]
	GlobalData.pilot.progression["specialization"] = "vanguard"

	_check(PilotSys.get_pilot_level() == 3, "Mutated level reflects 3")

	# Trigger new run reset
	GlobalData.reset_run_data()
	_check(PilotSys.get_pilot_level() == 1, "Run reset restores pilot level to 1")
	_check(PilotSys.get_pilot_xp() == 0, "Run reset restores pilot XP to 0")
	_check(PilotSys.get_skill_points() == 0, "Run reset restores skill points to 0")
	_check(PilotSys.get_unlocked_skills().is_empty(), "Run reset clears unlocked skills")


func _test_save_load_progression_fidelity() -> void:
	print("\n-- [2] Save / Load Progression Serialization & Backward Compatibility --")

	# 1. Test serialization of active progression
	GlobalData.pilot.progression["level"] = 4
	GlobalData.pilot.progression["xp"] = 1200
	GlobalData.pilot.progression["skill_points"] = 1
	GlobalData.pilot.progression["unlocked_skills"] = ["quick_draw", "evasion_mastery"]
	GlobalData.pilot.progression["specialization"] = "skirmisher"

	var serialized: Dictionary = PilotSys.serialize_progression()
	_check(int(serialized.get("level", 0)) == 4, "Serialized level is 4")
	_check(int(serialized.get("xp", 0)) == 1200, "Serialized XP is 1200")
	_check(int(serialized.get("skill_points", 0)) == 1, "Serialized skill points is 1")
	_check((serialized.get("unlocked_skills", []) as Array).size() == 2, "Serialized unlocked skills has 2 entries")

	# 2. Test deserialization into clean state
	GlobalData.pilot.progression.clear()
	PilotSys.deserialize_progression(serialized)

	_check(PilotSys.get_pilot_level() == 4, "Deserialized level is 4")
	_check(PilotSys.get_pilot_xp() == 1200, "Deserialized XP is 1200")
	_check(PilotSys.get_skill_points() == 1, "Deserialized skill points is 1")
	_check(PilotSys.get_unlocked_skills().has("quick_draw"), "Deserialized contains 'quick_draw'")
	_check(PilotSys.get_specialization() == "skirmisher", "Deserialized specialization is 'skirmisher'")

	# 3. Test backward compatibility: empty / legacy save dict
	PilotSys.deserialize_progression({})
	_check(PilotSys.get_pilot_level() == 1, "Empty save data safely initializes default level 1")
	_check(PilotSys.get_pilot_xp() == 0, "Empty save data safely initializes default XP 0")


func _test_combat_modifier_resolver_neutrality() -> void:
	print("\n-- [3] CombatModifierResolver Neutrality Checks --")

	GlobalData.reset_run_data()

	# With no perks or specializations, all channels must return neutral 1.0 multipliers
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 1.0), "Neutral dash energy multiplier is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.0), "Neutral dash precision multiplier is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_damage_multiplier(), 1.0), "Neutral pilot damage multiplier is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_spread_multiplier(), 1.0), "Neutral pilot spread multiplier is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_heat_generation_multiplier(), 1.0), "Neutral pilot heat multiplier is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_movement_speed_multiplier(), 1.0), "Neutral pilot movement multiplier is 1.0")


func _test_precognitive_flow_perk_migration() -> void:
	print("\n-- [4] Legacy Precognitive Flow Perk Migration & Exact Semantics --")

	GlobalData.reset_run_data()

	# 1. Verify absent without perk
	_check(not CombatModRes.has_pilot_perk("precognitive_flow"), "Precognitive flow is false by default")
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 1.0), "Energy cost is 1.0x without precog")
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.0), "Precision window is 1.0x without precog")

	# 2. Add hired pilot with precognitive_flow
	var mock_pilot := {
		"id": "pilot_legendary_01",
		"name": "Ace Pilot",
		"perk_id": "precognitive_flow"
	}
	GlobalData.pilot.hired_pilots.append(mock_pilot)

	_check(PilotSys.has_pilot_perk("precognitive_flow"), "PilotSystem reports precognitive_flow true")
	_check(CombatModRes.has_pilot_perk("precognitive_flow"), "CombatModifierResolver reports precognitive_flow true")
	_check(GlobalData.narrative.has_pilot_perk("precognitive_flow"), "NarrativeState backward compatibility layer delegates accurately")

	# 3. Verify exact math channels
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.5), "Precog grants exact 0.5x dash energy multiplier")
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.5), "Precog grants exact 1.5x precision window multiplier")


func _test_mecha_dash_system_resolver_integration() -> void:
	print("\n-- [5] MechaDashSystem Decoupling & Execution Tests --")

	GlobalData.reset_run_data()

	var dash_sys = MechaDashSys.new()
	add_child(dash_sys)

	# 1. Base dash cost without perk (DASH_ENERGY_COST = 6.0)
	var mult_base := CombatModRes.resolve_dash_energy_multiplier()
	var cost_base := MechaDashSys.DASH_ENERGY_COST * mult_base
	_check(is_equal_approx(cost_base, 6.0), "Base dash cost is 6.0")

	# 2. Base dash cost with precog perk (DASH_ENERGY_COST * 0.5 = 3.0)
	GlobalData.pilot.hired_pilots.append({"id": "p1", "perk_id": "precognitive_flow"})
	var mult_precog := CombatModRes.resolve_dash_energy_multiplier()
	var cost_precog := MechaDashSys.DASH_ENERGY_COST * mult_precog
	_check(is_equal_approx(cost_precog, 3.0), "Precog dash cost is 3.0")

	dash_sys.queue_free()


func _test_technology_and_loadout_boundary_integrity() -> void:
	print("\n-- [6] Technology & Equipment Gate Boundary Integrity --")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	# Simulate maximum pilot level & skills
	GlobalData.pilot.progression["level"] = 10
	GlobalData.pilot.progression["skill_points"] = 5
	GlobalData.pilot.progression["unlocked_skills"] = ["master_gunner", "titan_operator"]

	# 1. Technology Locked Item must STILL be rejected by LoadoutSystem
	var locked_tech_item := {
		"name": "Beam Carbine",
		"tech_id": "tech_beam_weaponry",
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres"
	}
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN, "Tech starts UNKNOWN")

	var val_locked := LoadoutSys.validate_equip_request("weapon_right", locked_tech_item)
	_check(not bool(val_locked.get("can_equip", true)), "LoadoutSystem rejects locked tech regardless of pilot level")
	_check(str(val_locked.get("reason", "")) == "technology_locked", "Rejection reason is strictly 'technology_locked'")

	# 2. Authorize technology, but check physical frame incompatibility
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.USABLE)
	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_tank_valkren",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": ["ballistic", "power"]
	}
	GlobalData.weapons.frame_modules = {}

	var val_incomp := LoadoutSys.validate_equip_request("weapon_right", locked_tech_item)
	_check(not bool(val_incomp.get("can_equip", true)), "LoadoutSystem rejects incompatible frame regardless of pilot level")
	_check(str(val_incomp.get("reason", "")) == "physically_incompatible", "Rejection reason is strictly 'physically_incompatible'")
