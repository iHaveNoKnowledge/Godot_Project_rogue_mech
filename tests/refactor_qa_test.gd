extends Node

var _failed := 0
var _passed := 0


func _ready() -> void:
	_clear_global_state()
	_test_part_stat()
	_test_durability_helpers()
	_test_repair_cost_consistency()
	_test_loadout_weight()
	_test_slot_paths()
	_test_run_reset_is_clean()
	_test_roll_random_start()
	_test_theme_event_pool()
	_test_reputation_gate()
	_test_theme_switch_once()
	_test_event_effects()
	_test_tech_escalation()
	_test_tech_escalation_anti_turtle()
	print("REPAIR_QA_RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _clear_global_state() -> void:
	GlobalData.part_damage.clear()
	GlobalData.equipped_parts.clear()
	GlobalData.equipped_frames.clear()
	GlobalData.weapon_loadout.clear()
	GlobalData.reset_run_data()


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + name)


func _test_part_stat() -> void:
	var dict_entry := {"hp": 40.0, "armor": 20.0, "weight": 3.5}
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "hp"), 40.0), "part_stat dict hp")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "max_hp"), 40.0), "part_stat dict max_hp alias")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "armor"), 20.0), "part_stat dict armor")
	_check(is_equal_approx(GlobalData.part_stat(dict_entry, "weight"), 3.5), "part_stat dict weight")

	var inst := GlobalData.get_armor_instance("qa_part")
	inst["hp"] = 55.0
	_check(is_equal_approx(GlobalData.part_stat(inst, "max_hp"), 55.0), "part_stat instance max_hp")

	var empty: Dictionary = {}
	_check(is_equal_approx(GlobalData.part_stat(empty, "hp", 7.0), 7.0), "part_stat default fallback")


func _test_durability_helpers() -> void:
	var inst := GlobalData.get_armor_instance("qa_durability")
	inst["durability"] = 0.4
	_check(is_equal_approx(GlobalData.get_durability_ratio(inst), 0.4), "get_durability_ratio reads durability")

	GlobalData.part_damage["head"] = 0.25
	GlobalData.part_damage["head_frame"] = 0.5
	_check(is_equal_approx(GlobalData.get_part_durability("head"), 0.75), "get_part_durability live cache")
	_check(is_equal_approx(GlobalData.get_part_durability("body"), 1.0), "get_part_durability undamaged default")


func _test_repair_cost_consistency() -> void:
	GlobalData.part_damage.clear()
	var inst := GlobalData.get_armor_instance("qa_repair")
	inst["hp"] = 50.0
	inst["max_hp"] = 50.0
	GlobalData.equipped_parts["head"] = inst
	GlobalData.equipped_frames["head"] = {"hp": 30.0, "max_hp": 30.0, "weight": 3.0}

	GlobalData.part_damage["head"] = 0.0
	GlobalData.part_damage["head_frame"] = 0.0
	_check(GlobalData.get_repair_cost("head") == 0, "repair cost 0 when undamaged")

	GlobalData.part_damage["head"] = 1.0
	GlobalData.part_damage["head_frame"] = 0.0
	var expected_armor := int(ceil(1.0 * 50.0 * GlobalData.REPAIR_COST_PER_HP))
	_check(GlobalData.get_repair_cost("head") == maxi(1, expected_armor), "armor-only cost matches safehouse formula")

	GlobalData.part_damage["head_frame"] = 1.0
	var expected_frame := int(ceil(1.0 * 30.0 * GlobalData.REPAIR_COST_PER_HP))
	_check(GlobalData.get_repair_cost("head") == maxi(1, expected_armor + expected_frame), "armor+frame cost summed")

	# 25% armor damage on a 50 HP part should cost 25 * 0.5 = 12.5 -> 13
	GlobalData.part_damage["head"] = 0.25
	GlobalData.part_damage["head_frame"] = 0.0
	_check(GlobalData.get_repair_cost("head") == maxi(1, int(ceil(0.25 * 50.0 * 0.5))), "25% dmg cost")


func _test_loadout_weight() -> void:
	GlobalData.weapon_loadout.clear()
	var left = load(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	var right = load(GlobalData.DEFAULT_RIGHT_WEAPON_PATH)
	var carry = load(GlobalData.DEFAULT_CARRY_WEAPON_PATH)
	GlobalData.set_hand_weapon("left", GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	GlobalData.set_hand_weapon("right", GlobalData.DEFAULT_RIGHT_WEAPON_PATH)
	GlobalData.add_carry_weapon(GlobalData.DEFAULT_CARRY_WEAPON_PATH)
	var expected := float(left.weight) + float(right.weight) + float(carry.weight)
	_check(is_equal_approx(GlobalData.get_loadout_weapons_total(), expected), "loadout weight sums weapons")
	_check(is_equal_approx(GlobalData.get_loadout_weapon_weight(), GlobalData.get_loadout_weapons_total()), "weight alias matches")


func _test_slot_paths() -> void:
	_check(GlobalData.get_slot_node_path("head") == "Head", "slot path head")
	_check(GlobalData.get_slot_node_path("arm_left") == "ArmLeft", "slot path arm_left")
	_check(GlobalData.get_slot_node_path("bogus") == "", "slot path unknown empty")
	_check(GlobalData.MECHA_SLOTS.size() == 6, "MECHA_SLOTS has 6 slots")
	_check("leg_right" in GlobalData.MECHA_SLOTS, "MECHA_SLOTS contains leg_right")


func _test_run_reset_is_clean() -> void:
	GlobalData.reset_run_data()
	_check(GlobalData.fleet_roster.is_empty(), "reset clears fleet roster")
	_check(GlobalData.research_projects.is_empty(), "reset clears research projects")
	_check(GlobalData.research_unlocked.is_empty(), "reset clears research unlocks")
	_check(GlobalData.theme_id == "soldier", "reset defaults theme to soldier")
	_check(GlobalData.reputation == 0, "reset zeroes reputation")
	_check(GlobalData.theme_switched == false, "reset clears theme switch flag")
	_check(GlobalData.ceasefire_turns == 0, "reset clears ceasefire counter")
	_check(GlobalData.blocked_intermission == false, "reset clears intermission block")
	_check(GlobalData.chassis_id == "standard", "reset defaults chassis to standard")
	_check(GlobalData.equipped_frames.size() == 6, "reset restores 6 default frames")


func _test_roll_random_start() -> void:
	GlobalData.reset_run_data()
	GlobalData.theme_id = "gundam_merc"
	GlobalData.roll_random_start()
	_check(GlobalData.equipped_parts.size() == 6, "roll_start equips all 6 slots")
	_check(GlobalData.armor_inventory.size() >= 6, "roll_start creates armor instances")
	var all_instances := true
	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		if not (part is Dictionary) or not part.has("uid"):
			all_instances = false
	_check(all_instances, "roll_start parts are instance dicts")
	_check(GlobalData.equipped_frames.size() == 6, "roll_start sets 6 frames")
	var left_weapon: String = GlobalData.weapon_loadout.get("left", "")
	_check(left_weapon != "", "roll_start sets a left weapon")
	_check(GlobalData.theme_id == "gundam_merc", "roll_start keeps selected theme")


func _test_theme_event_pool() -> void:
	GlobalData.reset_run_data()
	GlobalData.theme_id = "soldier"
	GlobalData.reputation = 0
	var pool := GlobalData.get_theme_event_pool()
	_check(not pool.is_empty(), "soldier theme has event pool")
	var has_soldier_event := false
	var has_common_event := false
	for event in pool:
		var themes = event.get("themes", [])
		if themes is Array and "soldier" in themes:
			has_soldier_event = true
		if themes is Array and themes.is_empty():
			has_common_event = true
	_check(has_soldier_event, "soldier pool includes soldier-specific events")
	_check(has_common_event, "soldier pool includes common events")

	GlobalData.theme_id = "scavenger"
	GlobalData.reputation = 3
	var scav_pool := GlobalData.get_theme_event_pool()
	var has_military_commission := false
	for event in scav_pool:
		if event.get("id", "") == "military_commission":
			has_military_commission = true
	_check(has_military_commission, "scavenger pool includes military_commission")


func _test_reputation_gate() -> void:
	GlobalData.reset_run_data()
	GlobalData.theme_id = "scavenger"
	GlobalData.reputation = 0
	var pool_low := GlobalData.get_theme_event_pool()
	var has_commission_low := false
	for event in pool_low:
		if event.get("id", "") == "military_commission":
			has_commission_low = true
	_check(not has_commission_low, "military_commission gated below rep 3")

	GlobalData.reputation = 3
	var pool_high := GlobalData.get_theme_event_pool()
	var has_commission_high := false
	for event in pool_high:
		if event.get("id", "") == "military_commission":
			has_commission_high = true
	_check(has_commission_high, "military_commission available at rep 3")


func _test_theme_switch_once() -> void:
	GlobalData.reset_run_data()
	GlobalData.theme_id = "scavenger"
	_check(GlobalData.switch_theme("soldier"), "first theme switch succeeds")
	_check(GlobalData.theme_id == "soldier", "theme switched to soldier")
	_check(not GlobalData.switch_theme("gundam_merc"), "second theme switch blocked")
	_check(GlobalData.theme_id == "soldier", "theme unchanged after blocked switch")


func _test_event_effects() -> void:
	GlobalData.reset_run_data()
	GlobalData.credits = 0
	GlobalData.apply_event_effect({"effect": "credits", "amount": 50})
	_check(GlobalData.credits == 50, "credits effect adds credits")

	GlobalData.apply_event_effect({"effect": "reputation", "amount": 2})
	_check(GlobalData.reputation == 2, "reputation effect adds reputation")

	GlobalData.apply_event_effect({"effect": "ceasefire", "amount": 0, "params": {"turns": 3}})
	_check(GlobalData.ceasefire_turns == 3, "ceasefire effect sets counter")

	GlobalData.apply_event_effect({"effect": "add_ally", "params": {"unit_id": "ally_gm"}})
	_check(GlobalData.has_ally_unit("ally_gm"), "add_ally effect adds unit")

	var forced := GlobalData.apply_event_effect({"effect": "force_combat", "params": {"combat_type": "grunt"}})
	_check(forced, "force_combat effect returns true")
	_check(GlobalData.blocked_intermission, "force_combat blocks intermission")


func _test_tech_escalation() -> void:
	GlobalData.reset_run_data()
	# Give the player a gundam-tier frame so the enemy perceives a threat.
	GlobalData.equipped_frames["body"] = GlobalData.get_frame_catalog_entry("frame_body_02")
	GlobalData.enemy_tech_tier = 1
	GlobalData.tech_copy_progress = 0.0
	GlobalData.tiles_since_combat = 0
	var cfg := GlobalData.get_escalation_config()
	_check(GlobalData.get_player_mech_tier() >= 4, "gundam frame raises player mech tier")

	var escalated := false
	var guard := 0
	while not escalated and guard < 300:
		guard += 1
		var before := GlobalData.enemy_tech_tier
		GlobalData.tick_tech_copy()
		# A win gives fresh observation (resets the anti-turtle counter) and
		# accelerates reverse-engineering.
		GlobalData.on_combat_ended_for_tech(true)
		if GlobalData.enemy_tech_tier > before:
			escalated = true
	_check(escalated, "copy countdown completes over tiles + combat observation")
	_check(GlobalData.enemy_tech_tier >= 2, "enemy tier increased after copy completes")
	_check(GlobalData.get_enemy_tech_multiplier() > 1.0, "tech multiplier scales spawns")

	GlobalData.enemy_tech_tier = 3
	_check(GlobalData.get_enemy_tech_multiplier() > 1.0, "multiplier grows with tier")


func _test_tech_escalation_anti_turtle() -> void:
	GlobalData.reset_run_data()
	GlobalData.equipped_frames["body"] = GlobalData.get_frame_catalog_entry("frame_body_02")
	GlobalData.enemy_tech_tier = 1
	GlobalData.tech_copy_progress = 0.0
	GlobalData.tiles_since_combat = 999  # camping too long
	var cfg := GlobalData.get_escalation_config()
	_check(not GlobalData.tick_tech_copy(), "camping stalls the copy countdown")
	_check(GlobalData.enemy_tech_tier == 1, "enemy does not tier up while camping")

	# A fresh combat observation resets the turtle counter.
	GlobalData.tiles_since_combat = 0
	var escalated := false
	var guard := 0
	while not escalated and guard < 300:
		guard += 1
		var before := GlobalData.enemy_tech_tier
		GlobalData.tick_tech_copy()
		GlobalData.on_combat_ended_for_tech(true)
		if GlobalData.enemy_tech_tier > before:
			escalated = true
	_check(escalated, "copy resumes after fresh combat observation")

	# A mech equal to or below the enemy tier is no threat — no copying.
	GlobalData.reset_run_data()
	GlobalData.enemy_tech_tier = 2
	GlobalData.tech_copy_progress = 0.0
	GlobalData.tiles_since_combat = 0
	var base_tier := GlobalData.get_player_mech_tier()
	_check(not GlobalData.tick_tech_copy(), "weak mech does not trigger copying")
