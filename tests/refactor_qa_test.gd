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
	_test_combat_damage_tracking()
	_test_fleet_security()
	_test_spy_event()
	_test_enemy_research_node()
	_test_enemy_base_tile_reset()
	_test_board_has_no_random_enemy_base()
	_test_tech_escalation()
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


func _test_combat_damage_tracking() -> void:
	GlobalData.reset_run_data()
	GlobalData.set_combat_hp_snapshot(200.0)
	GlobalData._combat_friendly_damage = 50.0
	GlobalData._compute_last_combat_damage_ratio()
	_check(is_equal_approx(GlobalData.last_combat_damage_ratio, 0.25), "damage ratio 50/200 = 0.25")
	_check(GlobalData.was_decisive_victory(), "25% damage is a decisive victory")

	GlobalData._combat_friendly_damage = 120.0
	GlobalData._compute_last_combat_damage_ratio()
	_check(is_equal_approx(GlobalData.last_combat_damage_ratio, 0.6), "damage ratio 120/200 = 0.6")
	_check(not GlobalData.was_decisive_victory(), "60% damage is NOT decisive")

	# Exactly 50% counts as decisive (<= threshold).
	GlobalData._combat_friendly_damage = 100.0
	GlobalData._compute_last_combat_damage_ratio()
	_check(GlobalData.was_decisive_victory(), "exactly 50% counts as decisive")

	# No friendly units fielded -> ratio 0, decisive (avoid divide-by-zero).
	GlobalData.set_combat_hp_snapshot(0.0)
	GlobalData._compute_last_combat_damage_ratio()
	_check(is_equal_approx(GlobalData.last_combat_damage_ratio, 0.0), "no fielded units yields ratio 0")

	# friendly_damage_received accumulates through the event bus.
	GlobalData.set_combat_hp_snapshot(100.0)
	EventBus.friendly_damage_received.emit(30.0)
	EventBus.friendly_damage_received.emit(20.0)
	_check(is_equal_approx(GlobalData.get_combat_friendly_damage(), 50.0), "bus accumulates friendly damage")


func _test_fleet_security() -> void:
	GlobalData.reset_run_data()
	_check(is_equal_approx(GlobalData.get_fleet_security(), 25.0), "default security is 25")
	_check(GlobalData.security_upgrade_level == 1, "default hardening level is 1")
	var base_counter := GlobalData.get_spy_counter_chance()
	_check(base_counter >= 0.10 and base_counter <= 0.90, "spy counter chance in valid range")

	# Upgrade requires credits.
	var cost := GlobalData.get_security_upgrade_cost()
	GlobalData.credits = cost - 1
	_check(not GlobalData.upgrade_fleet_security(), "cannot upgrade without enough credits")
	_check(GlobalData.security_upgrade_level == 1, "level unchanged when poor")

	GlobalData.credits = cost
	var level_before := GlobalData.security_upgrade_level
	_check(GlobalData.upgrade_fleet_security(), "upgrade succeeds with credits")
	_check(GlobalData.security_upgrade_level == level_before + 1, "hardening level increased")
	_check(is_equal_approx(GlobalData.get_fleet_security(), 37.0), "security raised by upgrade")

	# Upgrades are progressively more expensive.
	var next_cost := GlobalData.get_security_upgrade_cost()
	_check(next_cost > cost, "later upgrades cost more")

	# Security raises the spy counter chance.
	var high_counter := GlobalData.get_spy_counter_chance()
	_check(high_counter > base_counter, "more security -> stronger spy counter")


func _test_spy_event() -> void:
	GlobalData.reset_run_data()
	GlobalData.theme_id = "soldier"
	GlobalData.enemy_tech_tier = 1
	var low := GlobalData.get_spy_attempt_chance()
	GlobalData.enemy_tech_tier = 3
	var high := GlobalData.get_spy_attempt_chance()
	_check(high > low, "higher enemy tier raises spy attempt chance")
	_check(low >= 0.0 and low <= 1.0, "spy chance within [0,1]")

	# Max security makes catches overwhelmingly likely.
	GlobalData.enemy_tech_tier = 1
	GlobalData.fleet_security = 100.0
	var attempts := 0
	var caught := 0
	var leaked := 0
	for i in range(200):
		var ev := GlobalData.roll_spy_event()
		if not ev.is_empty():
			attempts += 1
			if ev.get("name", "") == "SPY CAUGHT":
				caught += 1
			elif ev.get("name", "") == "DATA STOLEN":
				leaked += 1
	_check(attempts > 0, "spy events fire under forced chance")
	_check(caught > leaked, "high security catches more spies than it misses")

	# Zero security -> spies get through and research advances.
	GlobalData.fleet_security = 0.0
	GlobalData.enemy_research_progress = 0.0
	GlobalData.enemy_base_active = false
	var stolen := false
	var guard := 0
	while not stolen and guard < 200:
		guard += 1
		var ev := GlobalData.roll_spy_event()
		if ev.get("name", "") == "DATA STOLEN":
			stolen = true
	_check(stolen, "no security lets spies steal data")
	_check(GlobalData.enemy_research_progress > 0.0, "successful theft advances enemy research")


func _test_enemy_research_node() -> void:
	GlobalData.reset_run_data()
	_check(not GlobalData.enemy_base_active, "no research node by default")

	# Spy thefts fill research; when full, a spawn request is queued.
	GlobalData.enemy_tech_tier = 1
	GlobalData.fleet_security = 0.0
	var attempts := 0
	while not GlobalData.enemy_base_active and attempts < 200:
		attempts += 1
		GlobalData.roll_spy_event()
	_check(GlobalData.enemy_base_active, "stolen data coalesces into a research node")
	_check(GlobalData.consume_enemy_base_spawn_request(), "spawn request queued when node forms")
	_check(not GlobalData.consume_enemy_base_spawn_request(), "spawn request consumed once")

	# Progress ticks per board move; completion rolls an outcome.
	GlobalData._combat_friendly_damage = 0.0
	var completed := false
	var guard := 0
	while not completed and guard < 100:
		guard += 1
		if GlobalData.tick_enemy_base_progress(1.0):
			completed = true
	_check(completed, "research node completes after enough moves")
	_check(not GlobalData.enemy_base_active, "node inactive after completion")
	_check(GlobalData.enemy_copy_outcome in ["grunt_mk2", "special_ace", "gundam_copy"], "completion rolls a valid outcome")
	_check(GlobalData.consume_pending_enemy_base_outcome(), "outcome event pending after completion")

	# Outcomes apply their reward.
	if GlobalData.enemy_copy_outcome == "grunt_mk2":
		_check(GlobalData.enemy_grunt_upgrade_level >= 2, "MKII grants grunt upgrade")
	else:
		_check(GlobalData.enemy_special_units.size() >= 1, "special/copy outcome fields a unit")
		_check(GlobalData.stalking_aces.has(GlobalData.enemy_copy_outcome), "deployed counter-unit hunts the player")

	# Destroying an active node yields only a partial grunt upgrade.
	GlobalData.reset_run_data()
	GlobalData.enemy_base_active = true
	GlobalData.enemy_base_progress = 2.0
	GlobalData.enemy_base_required = 8.0
	var upgrade_before := GlobalData.enemy_grunt_upgrade_level
	GlobalData.destroy_enemy_base()
	_check(not GlobalData.enemy_base_active, "destroyed node is inactive")
	_check(GlobalData.enemy_grunt_upgrade_level == upgrade_before + 1, "destroyed node grants partial grunt upgrade")
	_check(GlobalData.enemy_copy_outcome == "", "destroyed node produces no counter-unit")
	_check(GlobalData.consume_pending_enemy_base_destroyed(), "destroyed event pending")

	# Grunt multiplier scales with partial upgrades.
	GlobalData.reset_run_data()
	var base_mult := GlobalData.get_enemy_grunt_multiplier()
	GlobalData.enemy_grunt_upgrade_level = 2
	_check(GlobalData.get_enemy_grunt_multiplier() > base_mult, "grunt multiplier rises with salvaged upgrades")


func _test_enemy_base_tile_reset() -> void:
	GlobalData.reset_run_data()
	GlobalData.enemy_base_active = true
	GlobalData.enemy_base_tile_pos = Vector2i(3, 1)
	var pos_before := GlobalData.enemy_base_tile_pos
	GlobalData.destroy_enemy_base()
	_check(GlobalData.enemy_base_tile_pos == Vector2i(-1, -1), "destroy clears node tile pos")
	_check(GlobalData.consume_enemy_base_tile_reset() == pos_before, "destroy queues tile reset at node pos")
	_check(GlobalData.consume_enemy_base_tile_reset() == Vector2i(-1, -1), "tile reset consumed once")

	# The counter-unit completion path also queues a reset so the stale tile is
	# reverted even though the player never stepped on it.
	GlobalData.reset_run_data()
	GlobalData.enemy_base_active = true
	GlobalData.enemy_base_progress = GlobalData.enemy_base_required - 0.9
	GlobalData.enemy_base_tile_pos = Vector2i(4, 2)
	var cpos := GlobalData.enemy_base_tile_pos
	GlobalData.tick_enemy_base_progress(1.0)
	_check(not GlobalData.enemy_base_active, "completion deactivates node")
	_check(GlobalData.consume_enemy_base_tile_reset() == cpos, "completion queues tile reset")

	# Stepping on a resolved node tile must NOT re-trigger a raid: the guard
	# treats an inactive node's tile as a plain combat tile.
	GlobalData.reset_run_data()
	GlobalData.enemy_base_active = false
	_check(GlobalData.enemy_base_tile_pos == Vector2i(-1, -1), "inactive node has no tile pos")


func _test_board_has_no_random_enemy_base() -> void:
	GlobalData.reset_run_data()
	GlobalData.board_seed = 12345
	var gen = load("res://scripts/board/board_generator.gd").new()
	var data = gen.generate_board()
	var found := false
	for key in data["nodes"]:
		if data["nodes"][key].get_meta("tile_type", "") == "enemy_base":
			found = true
		data["nodes"][key].free()
	_check(not found, "board generation never places a random enemy_base tile")
	gen.free()


func _test_tech_escalation() -> void:
	GlobalData.reset_run_data()
	GlobalData.enemy_tech_tier = 1
	var cfg := GlobalData.get_escalation_config()
	_check(GlobalData.get_enemy_tech_multiplier() == 1.0, "tier 1 yields no spawn multiplier")

	# A decisive victory (<=50% damage) escalates exactly one tier.
	GlobalData.set_combat_hp_snapshot(200.0)
	GlobalData._combat_friendly_damage = 50.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(true)
	_check(GlobalData.enemy_tech_tier == 2, "decisive win escalates one tier")
	_check(GlobalData.get_enemy_tech_multiplier() > 1.0, "tech multiplier scales spawns")

	# Non-decisive win: no escalation.
	GlobalData._combat_friendly_damage = 150.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(true)
	_check(GlobalData.enemy_tech_tier == 2, "non-decisive win does not escalate")

	# Loss: no escalation.
	GlobalData._combat_friendly_damage = 10.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(false)
	_check(GlobalData.enemy_tech_tier == 2, "loss does not escalate")

	# Exactly 50% counts as decisive.
	GlobalData._combat_friendly_damage = 100.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(true)
	_check(GlobalData.enemy_tech_tier == 3, "exactly 50% damage escalates")

	# Max tier caps escalation.
	var max_tier := int(cfg.get("max_tier", 4))
	GlobalData.enemy_tech_tier = max_tier
	GlobalData._combat_friendly_damage = 0.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(true)
	_check(GlobalData.enemy_tech_tier == max_tier, "escalation capped at max tier")

	# Pending event flag is set on escalation and consumed once.
	GlobalData.reset_run_data()
	GlobalData.enemy_tech_tier = 1
	GlobalData._combat_friendly_damage = 0.0
	GlobalData._compute_last_combat_damage_ratio()
	GlobalData.on_combat_ended_for_tech(true)
	_check(GlobalData.enemy_tech_tier == 2, "escalation from clean win")
	_check(GlobalData.consume_pending_escalation_event(), "pending escalation flag set")
	_check(not GlobalData.consume_pending_escalation_event(), "pending flag consumed once")
