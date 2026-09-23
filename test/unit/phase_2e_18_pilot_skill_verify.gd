extends Node

## ===========================================================================
## PHASE 2E-18 PILOT SKILL TREE & SPECIALIZATION VERIFICATION SUITE
## ===========================================================================

const PilotSkillSys = preload("res://scripts/systems/pilot_skill_system.gd")
const PilotSkillCat = preload("res://scripts/systems/pilot_skill_catalog.gd")
const PilotSys = preload("res://scripts/systems/pilot_system.gd")
const CombatModRes = preload("res://scripts/systems/combat_modifier_resolver.gd")
const TechSys = preload("res://scripts/systems/technology_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("\n=== STARTING PHASE 2E-18 PILOT SKILL TREE & SPECIALIZATION VERIFICATION ===")
	_run_all_tests()
	_print_summary()
	if _fail_count == 0:
		print("PHASE_2E_18_SUCCESS")
		get_tree().quit(0)
	else:
		push_error("PHASE_2E_18_FAILED with %d errors" % _fail_count)
		get_tree().quit(1)


func _run_all_tests() -> void:
	_test_progression_defaults_and_xp_math()
	_test_combat_xp_reward_table_and_decisive_bonus()
	_test_catalog_and_skill_unlock_validation()
	_test_specialization_lifecycle()
	_test_combat_modifier_resolver_channels_and_stacking()
	_test_precognitive_flow_preservation()
	_test_technology_and_equipment_boundaries()
	_test_save_load_persistence_and_schema_preservation()


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % test_name)
	else:
		_fail_count += 1
		push_error("  [FAIL] %s" % test_name)


# --- [1] Progression Defaults & XP Math ---
func _test_progression_defaults_and_xp_math() -> void:
	print("\n-- [1] Pilot Progression Defaults, XP Thresholds & Level-Up Math --")
	GlobalData.reset_run_data()

	_check(PilotSkillSys.get_level() == 1, "Default pilot level is 1")
	_check(PilotSkillSys.get_xp() == 0, "Default pilot XP is 0")
	_check(PilotSkillSys.get_skill_points() == 0, "Default skill points is 0")
	_check(PilotSkillSys.get_unlocked_skills().is_empty(), "Default unlocked skills is empty array")
	_check(PilotSkillSys.get_specialization() == "", "Default specialization is empty string")

	# Threshold calculations: 100 + (level - 1) * 50
	_check(PilotSkillSys.get_xp_required_for_next_level(1) == 100, "Level 1 required XP is 100")
	_check(PilotSkillSys.get_xp_required_for_next_level(2) == 150, "Level 2 required XP is 150")
	_check(PilotSkillSys.get_xp_required_for_next_level(3) == 200, "Level 3 required XP is 200")
	_check(PilotSkillSys.get_xp_required_for_next_level(9) == 500, "Level 9 required XP is 500")
	_check(PilotSkillSys.get_xp_required_for_next_level(10) == 0, "Level 10 required XP is 0 (Max Cap)")

	# Single level-up grant
	var res1: Dictionary = PilotSkillSys.award_xp(100)
	_check(int(res1.get("levels_gained", 0)) == 1, "Awarding 100 XP grants 1 level-up from Level 1")
	_check(PilotSkillSys.get_level() == 2, "Pilot is now Level 2")
	_check(PilotSkillSys.get_xp() == 0, "XP carried over cleanly (0)")
	_check(PilotSkillSys.get_skill_points() == 1, "Skill points is now 1")

	# Multi-level XP grant: At Level 2 (req 150), award 370 XP -> gains L2->L3 (150), L3->L4 (200), leaves 20 XP
	var res2: Dictionary = PilotSkillSys.award_xp(370)
	_check(int(res2.get("levels_gained", 0)) == 2, "Awarding 370 XP grants 2 level-ups")
	_check(PilotSkillSys.get_level() == 4, "Pilot is now Level 4")
	_check(PilotSkillSys.get_xp() == 20, "Remaining XP is 20")
	_check(PilotSkillSys.get_skill_points() == 3, "Skill points is now 3 (1 + 2)")

	# Level 10 Cap & Clamping
	PilotSkillSys.award_xp(10000)
	_check(PilotSkillSys.get_level() == 10, "Pilot level capped at exactly 10")
	_check(PilotSkillSys.get_xp() == 0, "XP clamped to 0 at Max Level")
	_check(PilotSkillSys.get_skill_points() == 9, "Total earned skill points at Level 10 is 9")

	# Run reset restores pristine defaults
	GlobalData.reset_run_data()
	_check(PilotSkillSys.get_level() == 1, "Run reset restores Level 1")
	_check(PilotSkillSys.get_xp() == 0, "Run reset restores 0 XP")
	_check(PilotSkillSys.get_skill_points() == 0, "Run reset restores 0 Skill Points")


# --- [2] Combat XP Reward Table & Decisive Victory ---
func _test_combat_xp_reward_table_and_decisive_bonus() -> void:
	print("\n-- [2] Combat XP Reward Table & Decisive Victory Bonus --")
	GlobalData.reset_run_data()

	# Base combat rewards: grunt 50, ace 100, boss 250, duel 100, enemy_base 200
	var r_grunt: Dictionary = PilotSkillSys.award_combat_xp("grunt", false)
	_check(int(r_grunt.get("awarded_xp", 0)) == 50, "Grunt normal victory awards exactly 50 XP")

	GlobalData.reset_run_data()
	var r_grunt_decisive: Dictionary = PilotSkillSys.award_combat_xp("grunt", true)
	_check(int(r_grunt_decisive.get("awarded_xp", 0)) == 63, "Grunt decisive victory awards 63 XP (50 * 1.25 rounded)")

	GlobalData.reset_run_data()
	var r_ace: Dictionary = PilotSkillSys.award_combat_xp("ace", true)
	_check(int(r_ace.get("awarded_xp", 0)) == 125, "Ace decisive victory awards 125 XP (100 * 1.25)")

	GlobalData.reset_run_data()
	var r_boss: Dictionary = PilotSkillSys.award_combat_xp("boss", false)
	_check(int(r_boss.get("awarded_xp", 0)) == 250, "Boss normal victory awards 250 XP")

	GlobalData.reset_run_data()
	var r_duel: Dictionary = PilotSkillSys.award_combat_xp("duel", false)
	_check(int(r_duel.get("awarded_xp", 0)) == 100, "Duel victory awards 100 XP")

	GlobalData.reset_run_data()
	var r_base: Dictionary = PilotSkillSys.award_combat_xp("enemy_base", false)
	_check(int(r_base.get("awarded_xp", 0)) == 200, "Enemy base raid awards 200 XP")

	var r_unknown: Dictionary = PilotSkillSys.award_combat_xp("unknown_node", false)
	_check(int(r_unknown.get("awarded_xp", 0)) == 0, "Unknown combat node type awards 0 XP safely")


# --- [3] Catalog & Skill Unlock Validation ---
func _test_catalog_and_skill_unlock_validation() -> void:
	print("\n-- [3] Skill Catalog & Unlock Validation Pipeline --")
	GlobalData.reset_run_data()

	var all_skills: Array = PilotSkillCat.get_all_skills()
	_check(all_skills.size() == 8, "Skill catalog contains exactly 8 locked V1 skills")

	# Check validation on pristine Level 1 with 0 points
	var val_nopoints: Dictionary = PilotSkillSys.validate_unlock("tactical_dash")
	_check(not bool(val_nopoints.get("allowed", false)) and str(val_nopoints.get("reason", "")) == "insufficient_skill_points",
		"Unlock rejected with insufficient_skill_points when points == 0")

	# Grant level and points for testing
	PilotSkillSys.award_xp(250) # Level 3, 2 points
	_check(PilotSkillSys.get_level() == 3, "Leveled up to Level 3")
	_check(PilotSkillSys.get_skill_points() == 2, "Has 2 skill points")

	# Level requirement check (e.g. evasive_reflexes requires Level 2 and prereq tactical_dash)
	var val_prereq: Dictionary = PilotSkillSys.validate_unlock("evasive_reflexes")
	_check(not bool(val_prereq.get("allowed", false)) and str(val_prereq.get("reason", "")) == "missing_prerequisite",
		"evasive_reflexes rejected with missing_prerequisite when tactical_dash is locked")

	# Specialization requirement check before selecting specialization
	var val_spec: Dictionary = PilotSkillSys.validate_unlock("point_blank_mastery")
	_check(not bool(val_spec.get("allowed", false)) and str(val_spec.get("reason", "")) == "specialization_locked",
		"point_blank_mastery rejected with specialization_locked when unspecialized")

	# Valid unlock of universal skill
	var res_unlock: Dictionary = PilotSkillSys.unlock_skill("tactical_dash")
	_check(bool(res_unlock.get("allowed", false)), "tactical_dash unlocked successfully")
	_check(PilotSkillSys.is_skill_unlocked("tactical_dash"), "tactical_dash is marked unlocked")
	_check(PilotSkillSys.get_skill_points() == 1, "Skill points deducted from 2 to 1")

	# Duplicate unlock prevention
	var val_dup: Dictionary = PilotSkillSys.validate_unlock("tactical_dash")
	_check(not bool(val_dup.get("allowed", false)) and str(val_dup.get("reason", "")) == "already_unlocked",
		"tactical_dash rejected with already_unlocked on second attempt")

	# Now that tactical_dash is unlocked, evasive_reflexes prerequisites are satisfied
	var val_prereq_met: Dictionary = PilotSkillSys.validate_unlock("evasive_reflexes")
	_check(bool(val_prereq_met.get("allowed", false)), "evasive_reflexes unlock is now allowed with prereq met")

	# Invalid skill ID
	var val_invalid: Dictionary = PilotSkillSys.validate_unlock("non_existent_skill")
	_check(not bool(val_invalid.get("allowed", false)) and str(val_invalid.get("reason", "")) == "invalid_skill",
		"non_existent_skill rejected with invalid_skill")


# --- [4] Specialization Lifecycle ---
func _test_specialization_lifecycle() -> void:
	print("\n-- [4] Specialization Selection & Lifecycle --")
	GlobalData.reset_run_data()

	# Level < 3 rejected
	var val_early: Dictionary = PilotSkillSys.validate_specialization("vanguard")
	_check(not bool(val_early.get("allowed", false)) and str(val_early.get("reason", "")) == "insufficient_level",
		"Specialization rejected at Level 1 with insufficient_level")

	# Advance to Level 3
	PilotSkillSys.award_xp(250)
	_check(PilotSkillSys.get_level() == 3, "Advanced to Level 3")

	# Invalid specialization name
	var val_bad: Dictionary = PilotSkillSys.validate_specialization("cyber_mage")
	_check(not bool(val_bad.get("allowed", false)) and str(val_bad.get("reason", "")) == "invalid_specialization",
		"Invalid specialization name rejected with invalid_specialization")

	# Valid selection
	var res_spec: Dictionary = PilotSkillSys.select_specialization("skirmisher")
	_check(bool(res_spec.get("allowed", false)), "Selected specialization 'skirmisher' successfully")
	_check(PilotSkillSys.get_specialization() == "skirmisher", "Active specialization is 'skirmisher'")

	# Second selection rejected (Permanence)
	var val_second: Dictionary = PilotSkillSys.validate_specialization("vanguard")
	_check(not bool(val_second.get("allowed", false)) and str(val_second.get("reason", "")) == "already_selected",
		"Changing specialization rejected with already_selected")

	# Specialization unlocked skill access
	# skirmisher skill 'slipstream_dash' requires tactical_dash and skirmisher specialization
	PilotSkillSys.unlock_skill("tactical_dash")
	var val_skirm: Dictionary = PilotSkillSys.validate_unlock("slipstream_dash")
	_check(bool(val_skirm.get("allowed", false)), "slipstream_dash allowed for skirmisher pilot")

	# vanguard skill 'point_blank_mastery' remains locked for skirmisher
	var val_vang: Dictionary = PilotSkillSys.validate_unlock("point_blank_mastery")
	_check(not bool(val_vang.get("allowed", false)) and str(val_vang.get("reason", "")) == "specialization_locked",
		"point_blank_mastery remains specialization_locked for skirmisher pilot")


# --- [5] Combat Modifier Resolver Channels & Stacking ---
func _test_combat_modifier_resolver_channels_and_stacking() -> void:
	print("\n-- [5] CombatModifierResolver Channels, Additive & Multiplicative Stacking --")
	GlobalData.reset_run_data()

	# Neutral baseline
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 1.0), "Neutral dash energy is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.0), "Neutral precision window is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_damage_multiplier(), 1.0), "Neutral damage is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_spread_multiplier(), 1.0), "Neutral spread is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_heat_generation_multiplier(), 1.0), "Neutral heat is 1.0")
	_check(is_equal_approx(CombatModRes.resolve_pilot_movement_speed_multiplier(), 1.0), "Neutral movement speed is 1.0")

	# Unlock tactical_dash (0.85)
	GlobalData.pilot.progression["unlocked_skills"] = ["tactical_dash"]
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.85), "tactical_dash yields exact 0.85 dash energy")

	# Add slipstream_dash (0.70) -> Multiplicative reduction: 0.85 * 0.70 = 0.595
	GlobalData.pilot.progression["unlocked_skills"] = ["tactical_dash", "slipstream_dash"]
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.595), "tactical_dash + slipstream_dash multiplies to 0.595")

	# evasive_reflexes (1.25)
	GlobalData.pilot.progression["unlocked_skills"] = ["evasive_reflexes"]
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.25), "evasive_reflexes yields 1.25 precision window")

	# Damage skills: kinetic_tuning (+0.10), point_blank_mastery (+0.20) -> Additive: 1.0 + 0.10 + 0.20 = 1.30
	GlobalData.pilot.progression["unlocked_skills"] = ["kinetic_tuning", "point_blank_mastery"]
	_check(is_equal_approx(CombatModRes.resolve_pilot_damage_multiplier(), 1.30), "kinetic_tuning + point_blank_mastery adds to 1.30")

	# ballistic_calibration (0.75 spread)
	GlobalData.pilot.progression["unlocked_skills"] = ["ballistic_calibration"]
	_check(is_equal_approx(CombatModRes.resolve_pilot_spread_multiplier(), 0.75), "ballistic_calibration yields 0.75 spread")

	# heat_venting_drills (0.85 heat)
	GlobalData.pilot.progression["unlocked_skills"] = ["heat_venting_drills"]
	_check(is_equal_approx(CombatModRes.resolve_pilot_heat_generation_multiplier(), 0.85), "heat_venting_drills yields 0.85 heat generation")

	# combat_strides (1.10 speed)
	GlobalData.pilot.progression["unlocked_skills"] = ["combat_strides"]
	_check(is_equal_approx(CombatModRes.resolve_pilot_movement_speed_multiplier(), 1.10), "combat_strides yields 1.10 movement speed")


# --- [6] Legacy Precognitive Flow Preservation ---
func _test_precognitive_flow_preservation() -> void:
	print("\n-- [6] Legacy precognitive_flow Preservation & Stacking --")
	GlobalData.reset_run_data()

	# Enable precognitive_flow via recruited character
	GlobalData.hangar.recruited_characters = ["vagrant_ace"]
	_check(CombatModRes.has_pilot_perk("precognitive_flow"), "precognitive_flow is active")
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.50), "precognitive_flow alone yields 0.50 dash energy")
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.50), "precognitive_flow alone yields 1.50 precision window")

	# Stack with tactical_dash (0.85) -> 0.5 * 0.85 = 0.425
	GlobalData.pilot.progression["unlocked_skills"] = ["tactical_dash"]
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.425), "precognitive_flow + tactical_dash yields 0.425 dash energy")

	# Stack with evasive_reflexes (1.25) -> 1.5 * 1.25 = 1.875
	GlobalData.pilot.progression["unlocked_skills"] = ["evasive_reflexes"]
	_check(is_equal_approx(CombatModRes.resolve_dash_precision_window_multiplier(), 1.875), "precognitive_flow + evasive_reflexes yields 1.875 precision window")


# --- [7] Technology & Equipment Boundaries ---
func _test_technology_and_equipment_boundaries() -> void:
	print("\n-- [7] Technology & Equipment Gating Invariants --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	# Max out pilot level and unlock all skills
	GlobalData.pilot.progression["level"] = 10
	GlobalData.pilot.progression["unlocked_skills"] = ["kinetic_tuning", "point_blank_mastery", "ballistic_calibration"]
	GlobalData.pilot.progression["specialization"] = "artillery"

	# Verify technology_locked weapons remain strictly blocked
	var locked_tech_item := {
		"name": "Beam Carbine",
		"tech_id": "tech_beam_weaponry",
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres"
	}
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.UNKNOWN,
		"tech_beam_weaponry starts UNKNOWN")

	var val_locked: Dictionary = LoadoutSys.validate_equip_request("weapon_right", locked_tech_item)
	_check(not bool(val_locked.get("can_equip", true)), "Max Level pilot CANNOT equip locked beam rifle")
	_check(str(val_locked.get("reason", "")) == "technology_locked", "Rejection reason is strictly 'technology_locked'")

	# Verify physical frame compatibility remains strictly enforced
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.USABLE)
	GlobalData.weapons.equipped_frames["arm_right"] = {
		"id": "frame_tank_valkren",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": ["ballistic", "power"]
	}
	GlobalData.weapons.frame_modules = {}

	var val_incomp: Dictionary = LoadoutSys.validate_equip_request("weapon_right", locked_tech_item)
	_check(not bool(val_incomp.get("can_equip", true)), "LoadoutSystem rejects incompatible frame regardless of pilot level")
	_check(str(val_incomp.get("reason", "")) == "physically_incompatible", "Rejection reason is strictly 'physically_incompatible'")


# --- [8] Save/Load Persistence & Schema Preservation ---
func _test_save_load_persistence_and_schema_preservation() -> void:
	print("\n-- [8] Save / Load Persistence & Array[String] Schema Integrity --")
	GlobalData.reset_run_data()

	GlobalData.pilot.progression["level"] = 5
	GlobalData.pilot.progression["xp"] = 180
	GlobalData.pilot.progression["skill_points"] = 2
	GlobalData.pilot.progression["unlocked_skills"] = ["tactical_dash", "evasive_reflexes", "combat_strides"]
	GlobalData.pilot.progression["specialization"] = "skirmisher"

	var serialized: Dictionary = PilotSys.serialize_progression()
	_check(int(serialized.get("level", 0)) == 5, "Serialized level is 5")
	_check(int(serialized.get("xp", 0)) == 180, "Serialized XP is 180")
	_check(int(serialized.get("skill_points", 0)) == 2, "Serialized skill points is 2")
	_check(serialized.get("unlocked_skills", null) is Array, "Serialized unlocked_skills is Array")
	_check((serialized.get("unlocked_skills", []) as Array).size() == 3, "Serialized unlocked_skills has 3 entries")
	_check(str(serialized.get("specialization", "")) == "skirmisher", "Serialized specialization is 'skirmisher'")

	# Reset and deserialize
	GlobalData.reset_run_data()
	PilotSys.deserialize_progression(serialized)

	_check(PilotSkillSys.get_level() == 5, "Deserialized level is 5")
	_check(PilotSkillSys.get_xp() == 180, "Deserialized XP is 180")
	_check(PilotSkillSys.get_skill_points() == 2, "Deserialized skill points is 2")
	_check(PilotSkillSys.get_unlocked_skills().has("tactical_dash"), "Deserialized contains 'tactical_dash'")
	_check(PilotSkillSys.get_specialization() == "skirmisher", "Deserialized specialization is 'skirmisher'")

	# Unknown skill ID in save data does not crash
	var corrupted_save := {
		"level": 3,
		"xp": 50,
		"skill_points": 1,
		"unlocked_skills": ["tactical_dash", "deprecated_removed_skill"],
		"specialization": "vanguard"
	}
	PilotSys.deserialize_progression(corrupted_save)
	_check(PilotSkillSys.is_skill_unlocked("tactical_dash"), "Valid skill in save remains unlocked")
	_check(is_equal_approx(CombatModRes.resolve_dash_energy_multiplier(), 0.85), "Combat modifier resolves safely with unknown skill in save")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-18 PILOT SKILL VERIFICATION SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	print("==================================================")
