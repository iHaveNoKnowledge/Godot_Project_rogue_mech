extends Node

var _failed := 0
var _passed := 0


func _ready() -> void:
	_clear_global_state()
	_test_part_stat()
	_test_durability_helpers()
	_test_repair_cost_consistency()
	_test_loadout_weight()
	_test_weapon_duplicate_items()
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
	_test_blueprint_gated_gundam_armor()
	_test_location_based_damage()
	_test_driver_repair_skill()
	_test_emergency_scrap_patch()
	_test_scrap_primitive_json_safety()
	_test_professional_repair()
	_test_hangar_mech_roster()
	# The hangar test is async (it awaits a frame while building the scene), so
	# it must be awaited to completion before the result is printed; otherwise
	# later reset_run_data() calls would mutate GlobalData under its pending
	# sidestream comparison and the final tally would miss its late FAIL lines.
	await _test_hangar_selection_preserves_loadout()
	await _test_hangar_menu_flow()
	_test_save_load_roundtrip()
	_test_escape_zone()
	_test_battle_loadout_persistence()
	_test_battle_pickup_weight()
	await _test_scrap_editor_silences_movement()
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


func _test_weapon_duplicate_items() -> void:
	# Regression: same-model weapons are DISTINCT items. Two copies of one weapon
	# id must be two inventory counts, two carry slots, and double the field-pack
	# weight — never merged into one (which made a single carried weapon show
	# "[E]" on several list rows).
	GlobalData.reset_run_data()
	GlobalData.weapon_inventory.clear()
	GlobalData.weapon_loadout.clear()

	# register_weapon dedupes by path but keeps a count; it also uses the real
	# weapon name instead of any caller-supplied label like "Starter".
	GlobalData.register_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH, "Starter")
	GlobalData.register_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH, "Starter")
	_check(GlobalData.weapon_inventory.size() == 1, "registering same weapon twice keeps one inventory row")
	_check(int(GlobalData.weapon_inventory[0].get("count", 0)) == 2, "inventory count tracks both copies")
	var real_name = load(GlobalData.DEFAULT_LEFT_WEAPON_PATH).weapon_name
	_check(str(GlobalData.weapon_inventory[0].get("name", "")) == str(real_name), "inventory shows real weapon name, not 'Starter'")

	# Carrying both copies is allowed and both are counted.
	GlobalData.add_carry_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	GlobalData.add_carry_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	_check(GlobalData.is_weapon_in_carry(GlobalData.DEFAULT_LEFT_WEAPON_PATH), "weapon is in carry")
	_check(GlobalData.count_carry_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH) == 2, "carry counts both copies")

	# Field-pack weight reflects both physical copies.
	var one_weight := float(load(GlobalData.DEFAULT_LEFT_WEAPON_PATH).weight)
	_check(is_equal_approx(GlobalData.get_loadout_weapons_total(), one_weight * 2.0), "two carried copies weigh double")

	# Dropping one copy removes exactly one.
	GlobalData.remove_carry_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	_check(GlobalData.count_carry_weapon(GlobalData.DEFAULT_LEFT_WEAPON_PATH) == 1, "drop removes a single copy")


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
	_check(is_equal_approx(GlobalData.get_fleet_security(), 39.0), "security raised by upgrade")

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


func _test_hangar_selection_preserves_loadout() -> void:
	# Regression: rapidly clicking part category tabs / sub-modes must never
	# mutate the equipped loadout. Previously _on_part_item_selected() used
	# .clear() on selection dicts that held LIVE references into GlobalData
	# (armor instances, catalog frames), wiping equipped parts/frames.
	GlobalData.reset_run_data()
	GlobalData.roll_random_start()

	var before_parts := {}
	for slot in GlobalData.equipped_parts:
		var p = GlobalData.equipped_parts[slot]
		before_parts[slot] = p.get("uid", "") if p is Dictionary else str(p)
	var before_frames := {}
	for slot in GlobalData.equipped_frames:
		var f = GlobalData.equipped_frames[slot]
		before_frames[slot] = str(f.get("name", "") if f is Dictionary else f)
	var before_left: Variant = GlobalData.weapon_loadout.get("left")
	var before_right: Variant = GlobalData.weapon_loadout.get("right")

	var hangar = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(hangar)
	await get_tree().process_frame

	var slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right",
		"weapon_left", "weapon_right", "weapon_carry"]
	var modes := ["armor", "frame", "attachment"]
	for round in range(2):
		for idx in range(slots.size()):
			hangar._select_slot_tab(slots[idx])
			hangar._switch_custom_mode(modes[idx % modes.size()])
	hangar.queue_free()

	var parts_ok := true
	for slot in before_parts:
		var p = GlobalData.equipped_parts.get(slot)
		if (p.get("uid", "") if p is Dictionary else str(p)) != before_parts[slot]:
			parts_ok = false
	_check(parts_ok, "hangar tab switching keeps equipped_parts intact")

	var frames_ok := true
	for slot in before_frames:
		var f = GlobalData.equipped_frames.get(slot)
		if (str(f.get("name", "") if f is Dictionary else f)) != before_frames[slot]:
			frames_ok = false
	_check(frames_ok, "hangar tab switching keeps equipped_frames intact")

	_check(GlobalData.weapon_loadout.get("left") == before_left, "hangar tab switching keeps left weapon")
	_check(GlobalData.weapon_loadout.get("right") == before_right, "hangar tab switching keeps right weapon")


func _test_hangar_menu_flow() -> void:
	# New hangar UX: entering the hangar shows the landing sub-menu first, the
	# customize page only appears after picking a topic, and the CHASSIS tab was
	# moved out of the customize page into the catalog.
	GlobalData.reset_run_data()
	GlobalData.roll_random_start()

	var hangar = load("res://scenes/ui/hangar_scene.tscn").instantiate()
	add_child(hangar)
	await get_tree().process_frame

	# Landing: only the sub-menu rail is visible; the customize page is hidden.
	_check(hangar.submenu_rail != null and hangar.submenu_rail.visible, "hangar shows the landing sub-menu first")
	_check(not hangar.left_panel.visible, "customize part panel hidden on landing")
	_check(not hangar.right_panel.visible, "stats panel hidden on landing")
	_check(not hangar.tab_container.visible, "slot tabs hidden on landing")

	# The CHASSIS slot tab no longer exists on the customize page.
	_check(not hangar.slot_tab_buttons.has("chassis"), "CHASSIS tab removed from the customize page")

	# Picking CUSTOMIZE opens the customize page.
	hangar._select_hangar_submenu("customize")
	_check(not hangar.submenu_rail.visible, "sub-menu hides after choosing a page")
	_check(hangar.left_panel.visible, "customize page part panel is shown")
	_check(hangar.right_panel.visible, "customize page stats panel is shown")

	# Catalog lets the driver switch the chassis model.
	var before_chassis: String = GlobalData.chassis_id
	hangar._select_hangar_submenu("catalog")
	_check(hangar.catalog_window != null and is_instance_valid(hangar.catalog_window), "catalog window opens with chassis section")
	var alt_key := ""
	for key in GlobalData.chassis_catalog:
		if str(key) != before_chassis:
			alt_key = key
			break
	if alt_key != "":
		hangar._apply_chassis_from_catalog(alt_key)
		_check(GlobalData.chassis_id == alt_key, "catalog chassis selection switches the chassis model")

	# BACK TO MENU returns to the landing screen.
	hangar._on_back_to_menu_pressed()
	_check(hangar.submenu_rail.visible, "back-to-menu returns to the landing screen")

	hangar.queue_free()
	await get_tree().process_frame


func _test_battle_loadout_persistence() -> void:
	# Regression: weapons picked up / swapped during a battle must be written
	# back into GlobalData.weapon_loadout so the next battle starts with them.
	# Previously only the battle-local WeaponManager state changed and the next
	# battle always reloaded the run-start weapons.
	GlobalData.reset_run_data()
	GlobalData.roll_random_start()

	var wm = preload("res://scripts/mecha/weapon_manager.gd").new()
	var rifle := preload("res://resources/mech/stock/weapon_beam_rifle.tres")
	var blade := preload("res://resources/mech/stock/weapon_heat_blade.tres")
	var shotgun := preload("res://resources/mech/stock/weapon_combat_shotgun.tres")
	wm.left_hand = rifle
	wm.right_hand = blade
	wm.carry.append(shotgun)
	wm.carry.append(rifle)
	wm.sync_loadout_to_global()

	_check(GlobalData.weapon_loadout.get("left", "") == rifle.resource_path, "battle pickup persists left hand to loadout")
	_check(GlobalData.weapon_loadout.get("right", "") == blade.resource_path, "battle pickup persists right hand to loadout")
	var carry: Array = GlobalData.weapon_loadout.get("carry", [])
	_check(carry.size() == 2 and shotgun.resource_path in carry and rifle.resource_path in carry, "battle pickup persists back-carry to loadout")

	# Dropping a weapon clears the hand slot in the loadout.
	wm.left_hand = null
	wm.sync_loadout_to_global()
	_check(GlobalData.weapon_loadout.get("left", "") == "", "battle drop clears left hand in loadout")


func _test_battle_pickup_weight() -> void:
	# Regression: picking up a weapon mid-battle must raise the FIELD PACK weight
	# the HUD shows (GlobalData.weapon_loadout) AND the battle-local pack weight.
	# The mech's live weight (speed/turn) also includes loadout weapons, so the
	# weight system must respond to pickups, not just the hidden label.
	GlobalData.reset_run_data()
	GlobalData.weapon_loadout.clear()
	GlobalData.set_hand_weapon("left", GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	GlobalData.set_hand_weapon("right", GlobalData.DEFAULT_RIGHT_WEAPON_PATH)

	var wm = preload("res://scripts/mecha/weapon_manager.gd").new()
	wm.left_hand = load(GlobalData.DEFAULT_LEFT_WEAPON_PATH)
	wm.right_hand = load(GlobalData.DEFAULT_RIGHT_WEAPON_PATH)

	var global_before := GlobalData.get_field_pack_weight()
	var battle_before := wm.get_battle_field_pack_weight()

	var shotgun := preload("res://resources/mech/stock/weapon_combat_shotgun.tres")
	wm.add_weapon(shotgun)

	_check(wm.get_battle_field_pack_weight() > battle_before, "battle pack weight rises after pickup")
	_check(GlobalData.get_field_pack_weight() > global_before, "HUD field pack weight rises after pickup")
	_check(is_equal_approx(GlobalData.get_field_pack_weight() - global_before, float(shotgun.weight)), "global weight rises exactly by weapon weight")
	_check(GlobalData.get_loadout_weapon_weight() == GlobalData.get_field_pack_weight(), "mech live weight counts the same weapons as field pack")

	# Dropping the weapon back out removes that weight again.
	wm.carry.erase(shotgun)
	wm.sync_loadout_to_global()
	_check(is_equal_approx(GlobalData.get_field_pack_weight(), global_before), "global weight returns after drop")


func _test_scrap_editor_silences_movement() -> void:
	# Regression: the emergency repair editor is a modal — while it is open the
	# board camera / mech must not keep moving (WASD pan + dash + jump all
	# silenced), and closing it must restore the exact original keybindings.
	var editor = preload("res://scripts/ui/scrap_repair_editor.gd").new()
	add_child(editor)
	await get_tree().process_frame

	var before_fwd := InputMap.action_get_events("move_forward").size()
	var before_left := InputMap.action_get_events("move_left").size()
	var before_dash := InputMap.action_get_events("dash").size()
	var before_cam := InputMap.action_get_events("camera_unlock").size()
	var before_jump := InputMap.action_get_events("jump").size()

	editor.open("")

	_check(InputMap.action_get_events("move_forward").is_empty(), "editor silences move_forward while open")
	_check(InputMap.action_get_events("move_left").is_empty(), "editor silences move_left while open")
	_check(InputMap.action_get_events("move_back").is_empty(), "editor silences move_back while open")
	_check(InputMap.action_get_events("move_right").is_empty(), "editor silences move_right while open")
	_check(InputMap.action_get_events("dash").is_empty(), "editor silences dash while open")
	_check(InputMap.action_get_events("jump").is_empty(), "editor silences jump while open")
	_check(InputMap.action_get_events("camera_unlock").is_empty(), "editor silences camera pan while open")

	editor.close()

	_check(InputMap.action_get_events("move_forward").size() == before_fwd, "close restores move_forward bindings")
	_check(InputMap.action_get_events("move_left").size() == before_left, "close restores move_left bindings")
	_check(InputMap.action_get_events("dash").size() == before_dash, "close restores dash bindings")
	_check(InputMap.action_get_events("camera_unlock").size() == before_cam, "close restores camera_unlock bindings")
	_check(InputMap.action_get_events("jump").size() == before_jump, "close restores jump bindings")

	editor.queue_free()


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


func _test_blueprint_gated_gundam_armor() -> void:
	GlobalData.reset_run_data()
	var gundam := GlobalData.get_armor_catalog_entry("body_003_gundam")
	_check(not gundam.is_empty(), "gundam armor exists in catalog")
	_check(bool(gundam.get("blueprint_only", false)), "gundam part is blueprint_only")
	_check(gundam.get("blueprint_id", "") == "bp_gundam_armor", "gundam part points at gundam armor project")
	var standard := GlobalData.get_armor_catalog_entry("body_001")
	_check(not GlobalData.entry_is_blueprint_locked(standard), "standard armor is never blueprint-locked")

	# Fresh run: blueprint NOT researched -> locked, crafting blocked.
	_check(GlobalData.entry_is_blueprint_locked(gundam), "unresearched gundam part is locked")
	GlobalData.scrap = 999
	GlobalData.credits = 999
	var before_instances := GlobalData.armor_inventory.size()
	var crafted := GlobalData.try_craft_armor_from_catalog("body_003_gundam")
	_check(crafted.is_empty(), "crafting a locked gundam part is refused")
	_check(GlobalData.armor_inventory.size() == before_instances, "no instance created while locked")

	# Random start loadouts never include blueprint-only parts.
	GlobalData.roll_random_start()
	var has_gundam_part := false
	for slot in GlobalData.equipped_parts:
		var part = GlobalData.equipped_parts[slot]
		var id = part.get("db_id", part.get("id", "")) if part is Dictionary else ""
		if str(id).ends_with("_gundam"):
			has_gundam_part = true
	_check(not has_gundam_part, "random start never assigns gundam parts")

	# Researching the blueprint unlocks crafting.
	GlobalData.reset_run_data()
	GlobalData.data_cores = 10
	GlobalData.scrap = 999
	GlobalData.credits = 999
	GlobalData.start_research("bp_gundam_armor")
	var guard := 0
	while GlobalData.research_projects.has("bp_gundam_armor") and guard < 100:
		guard += 1
		GlobalData.tick_research(1)
	_check("bp_gundam_armor" in GlobalData.research_unlocked, "researching gundam armor blueprint unlocks it")
	_check(not GlobalData.entry_is_blueprint_locked(gundam), "researched gundam part is unlocked")
	crafted = GlobalData.try_craft_armor_from_catalog("body_003_gundam")
	_check(not crafted.is_empty(), "researched gundam part can be crafted")


func _test_location_based_damage() -> void:
	# Regression: a projectile's impact point must decide WHICH part surface
	# (armor plate vs exposed frame) takes the damage. Builds a minimal mecha
	# whose Head has an armor box, a frame spike that pokes THROUGH the armor
	# (overlapping AABB -> armor shields it) and a spike mounted BESIDE the
	# armor (no overlap -> exposed frame).
	var mecha := Node3D.new()
	mecha.name = "QA_Mecha"
	add_child(mecha)

	var health = load("res://scripts/mecha/mecha_health.gd").new()
	health.is_player = false
	mecha.add_child(health)
	health.is_player = false
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 3, 0)
	mecha.add_child(head)

	var armor_container := Node3D.new()
	armor_container.name = "ArmorMesh"
	head.add_child(armor_container)
	var armor_mesh := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(1, 1, 1)
	armor_mesh.mesh = plate
	armor_container.add_child(armor_mesh)

	var frame_container := Node3D.new()
	frame_container.name = "FrameMesh"
	head.add_child(frame_container)
	# Spike mounted BESIDE the armor: AABB [1.75,2.25] never overlaps [-0.5,0.5]
	# (kept clear of the shielded spike's boundary to avoid edge cases).
	var frame_mesh := MeshInstance3D.new()
	var spike := BoxMesh.new()
	spike.size = Vector3(0.5, 0.5, 0.5)
	frame_mesh.mesh = spike
	frame_mesh.position = Vector3(2.0, 0, 0)
	frame_container.add_child(frame_mesh)
	# Spike poking THROUGH the armor: AABB [0.0,1.5]x[-0.2,0.2]^2 overlaps the
	# armor box, so its exposed tip is still covered by the armor.
	var shielded_mesh := MeshInstance3D.new()
	var sh_spike := BoxMesh.new()
	sh_spike.size = Vector3(1.5, 0.4, 0.4)
	shielded_mesh.mesh = sh_spike
	shielded_mesh.position = Vector3(0.75, 0, 0)
	frame_container.add_child(shielded_mesh)

	var head_part = health.parts["head"]
	var armor0: float = head_part["armor_hp"]
	var frame0: float = head_part["frame_hp"]

	# Explicit layer routing.
	health.take_damage_to_part("head", 12.0, "kinetic", "armor")
	_check(is_equal_approx(head_part["armor_hp"], armor0 - 12.0 / head_part["armor_class"]), "layer=armor reduces armor HP")
	_check(is_equal_approx(head_part["frame_hp"], frame0), "layer=armor leaves frame untouched")

	health.take_damage_to_part("head", 7.0, "kinetic", "frame")
	_check(is_equal_approx(head_part["frame_hp"], frame0 - 7.0), "layer=frame reduces frame HP")
	_check(is_equal_approx(head_part["armor_hp"], armor0 - 12.0 / head_part["armor_class"]), "layer=frame leaves armor untouched")

	# Armor passes damage through once it is broken.
	head_part["armor_hp"] = 0.0
	head_part["armor_broken"] = true
	var frame_before: float = head_part["frame_hp"]
	health.take_damage_to_part("head", 5.0, "kinetic", "armor")
	_check(is_equal_approx(head_part["frame_hp"], frame_before - 5.0), "broken armor lets armor-layer hit reach the frame")

	# Point-based resolution.
	head_part["armor_broken"] = false
	head_part["armor_hp"] = head_part["max_armor"]
	var armor_before: float = head_part["armor_hp"]
	var frame_before_point: float = head_part["frame_hp"]

	health.take_damage_at_point(10.0, head.global_position)
	_check(is_equal_approx(head_part["armor_hp"], armor_before - 10.0 / head_part["armor_class"]), "impact inside armor AABB hits armor")
	_check(is_equal_approx(head_part["frame_hp"], frame_before_point), "impact inside armor AABB misses frame")

	# The frame spike that pokes through the armor (AABB overlaps armor) is
	# still covered by the armor -> its exposed tip damages armor, not frame.
	var armor_before_shielded: float = head_part["armor_hp"]
	var frame_before_shielded: float = head_part["frame_hp"]
	var shielded_tip := mecha.to_global(Vector3(1.0, 3.0, 0.0))
	health.take_damage_at_point(6.0, shielded_tip)
	_check(is_equal_approx(head_part["armor_hp"], armor_before_shielded - 6.0 / head_part["armor_class"]), "frame poking through armor is still armored")
	_check(is_equal_approx(head_part["frame_hp"], frame_before_shielded), "frame poking through armor never hits frame")

	# The spike mounted BESIDE the armor has no overlap -> exposed frame.
	var armor_after_point: float = head_part["armor_hp"]
	var frame_after_point: float = head_part["frame_hp"]
	health.take_damage_at_point(4.0, frame_mesh.global_position)
	_check(is_equal_approx(head_part["frame_hp"], frame_after_point - 4.0), "impact on exposed frame spike hits frame")
	_check(is_equal_approx(head_part["armor_hp"], armor_after_point), "impact on exposed frame spike misses armor")

	# Enemy-style variant: slot passed in, layer resolved from the world point.
	var frame_after_at: float = head_part["frame_hp"]
	health.take_damage_to_part_at("head", 3.0, frame_mesh.global_position)
	_check(is_equal_approx(head_part["frame_hp"], frame_after_at - 3.0), "take_damage_to_part_at resolves frame layer from impact point")

	mecha.queue_free()


func _test_driver_repair_skill() -> void:
	GlobalData.reset_run_data()
	_check(GlobalData.driver_repair_skill == 1, "driver repair skill starts at tier 1")
	_check(GlobalData.driver_repair_xp == 0, "driver repair xp starts at 0")
	_check(GlobalData.get_scrap_armor_tier() == 1, "scrap armor tier starts at 1")
	_check(is_equal_approx(GlobalData.get_scrap_armor_stat_scale(), 0.40), "tier 1 scrap armor is 40% of real stats")

	# XP to level 2 is REPAIR_XP_BASE (30). Gaining exactly that levels up.
	_check(GlobalData.gain_repair_xp(GlobalData.get_repair_skill_xp_for_next(1)), "enough xp levels the skill up")
	_check(GlobalData.driver_repair_skill == 2, "skill advanced to tier 2")
	_check(GlobalData.driver_repair_xp == 0, "xp resets after leveling")
	_check(is_equal_approx(GlobalData.get_scrap_armor_stat_scale(), 0.50), "tier 2 scrap armor is 50% of real stats")

	# Overflow carries into the next tier; gain returns false only at max.
	GlobalData.driver_repair_skill = 5
	GlobalData.driver_repair_xp = 0
	_check(not GlobalData.gain_repair_xp(1000), "maxed skill rejects further xp")
	_check(GlobalData.driver_repair_skill == 5, "skill stays capped at tier 5")
	_check(is_equal_approx(GlobalData.get_scrap_armor_stat_scale(), 0.80), "tier 5 scrap armor is 80% of real stats")

	# New run resets the skill.
	GlobalData.reset_run_data()
	_check(GlobalData.driver_repair_skill == 1, "reset_run_data restores skill to tier 1")
	_check(GlobalData.driver_repair_xp == 0, "reset_run_data clears repair xp")


func _test_emergency_scrap_patch() -> void:
	GlobalData.reset_run_data()
	GlobalData.driver_repair_skill = 1
	GlobalData.driver_repair_xp = 0
	GlobalData.scrap = 50

	GlobalData.part_damage.clear()
	_check(GlobalData.get_emergency_repair_scrap_cost("head") == 0, "undamaged slot has zero emergency cost")
	_check(GlobalData.apply_emergency_repair("head").is_empty(), "apply refuses a fully healthy slot")

	# Damage the slot; the cost scales with how much is broken.
	GlobalData.part_damage["head"] = 0.5
	GlobalData.part_damage["head_frame"] = 0.3
	var cost := GlobalData.get_emergency_repair_scrap_cost("head")
	_check(cost > 0, "damaged slot has a positive emergency cost")

	# Too little scrap -> refused, nothing patched.
	GlobalData.scrap = maxi(cost - 1, 0)
	_check(GlobalData.apply_emergency_repair("head").is_empty(), "apply refused when scrap is insufficient")
	_check(not GlobalData.has_scrap_patch("head"), "no patch recorded when unaffordable")

	# Enough scrap -> tier 1 patch at 40% of real armor stats.
	GlobalData.scrap = 500
	var patch := GlobalData.apply_emergency_repair("head", [{"shape": "box", "pos": Vector3.ZERO}])
	_check(not patch.is_empty(), "apply creates a scrap patch")
	_check(int(patch.get("tier", 0)) == 1, "patch tier matches driver skill tier 1")
	_check(is_equal_approx(float(patch.get("stat_scale", 0.0)), 0.40), "patch stat scale is 0.40 at tier 1")
	_check(GlobalData.has_scrap_patch("head"), "patch is tracked per slot")
	var armor_max := GlobalData.part_stat(GlobalData.equipped_parts.get("head"), "max_hp", 50.0)
	_check(is_equal_approx(float(patch.get("scrap_armor_hp", 0.0)), armor_max * 0.40), "scrap armor hp is 40% of real armor")
	_check(not GlobalData.part_damage.has("head"), "patch clears armor damage")
	_check(not GlobalData.part_damage.has("head_frame"), "patch clears frame damage")

	# Higher driver skill builds stronger scrap armor.
	GlobalData.driver_repair_skill = 4
	GlobalData.scrap = 500
	GlobalData.part_damage["head"] = 0.5
	var better := GlobalData.apply_emergency_repair("head")
	_check(is_equal_approx(float(better.get("stat_scale", 0.0)), 0.70), "tier 4 scrap armor is 70% of real stats")

	# Professional repair removes the patch.
	GlobalData.remove_scrap_patch("head")
	_check(not GlobalData.has_scrap_patch("head"), "remove_scrap_patch clears the patch")

	# Integration: a scrap-patched slot loads into combat with scrap stats.
	GlobalData.scrap = 500
	GlobalData.driver_repair_skill = 2
	GlobalData.part_damage["head"] = 0.5
	var ipatch := GlobalData.apply_emergency_repair("head")
	var iarmor: float = ipatch.get("scrap_armor_hp", 0.0)
	var mecha := Node3D.new()
	mecha.name = "QA_PatchMecha"
	add_child(mecha)
	var health = load("res://scripts/mecha/mecha_health.gd").new()
	health.is_player = false
	mecha.add_child(health)
	health.is_player = false
	var head_part = health.parts["head"]
	_check(is_equal_approx(head_part["max_armor"], iarmor), "combat load uses scrap armor hp for patched slot")
	_check(not head_part["destroyed"], "patched slot is not destroyed in combat")
	mecha.queue_free()

	# New run resets all patches.
	GlobalData.scrap_patches["head"] = patch
	GlobalData.reset_run_data()
	_check(GlobalData.scrap_patches.is_empty(), "reset_run_data clears scrap patches")


func _test_scrap_primitive_json_safety() -> void:
	GlobalData.reset_run_data()
	GlobalData.driver_repair_skill = 1
	GlobalData.scrap = 500

	GlobalData.part_damage["body"] = 0.6
	var patch := GlobalData.apply_emergency_repair("body", [{
		"shape": "box",
		"pos": Vector3(1.0, 2.0, 3.0),
		"rot": Vector3.ZERO,
		"scale": Vector3(2.0, 2.0, 2.0),
		"color": Color(1.0, 0.0, 0.0, 1.0),
	}])
	_check(not patch.is_empty(), "json-safe patch applies")

	var stored: Array = patch.get("primitives", [])
	_check(stored.size() == 1, "patch keeps its primitive")
	_check(stored[0].get("pos") is Array, "Vector3 pos is stored as a JSON-safe array")
	_check(stored[0].get("color") is Array, "Color is stored as a JSON-safe array")

	var pos: Vector3 = GlobalData.scrap_primitive_pos(stored[0])
	_check(pos.is_equal_approx(Vector3(1.0, 2.0, 3.0)), "scrap_primitive_pos reads back the array")
	var col: Color = GlobalData.scrap_primitive_color(stored[0])
	_check(col.is_equal_approx(Color(1.0, 0.0, 0.0, 1.0)), "scrap_primitive_color reads back the array")
	_check(GlobalData.scrap_primitive_scale(stored[0]).is_equal_approx(Vector3(2.0, 2.0, 2.0)), "scrap_primitive_scale reads back the array")

	# JSON.stringify must not silently drop the primitive into an empty object.
	var json := JSON.stringify({"patches": GlobalData.scrap_patches})
	_check(not json.contains("{}"), "scrap patches survive JSON.stringify without data loss")


func _test_professional_repair() -> void:
	GlobalData.reset_run_data()
	GlobalData.driver_repair_skill = 1
	GlobalData.scrap = 500
	GlobalData.credits = 0

	GlobalData.part_damage["body"] = 0.6
	var patch := GlobalData.apply_emergency_repair("body", [{"shape": "box"}])
	_check(not patch.is_empty(), "set up a scrap patch for professional repair")
	_check(GlobalData.has_scrap_patch("body"), "patch exists before professional repair")

	var armor_max := GlobalData.part_stat(GlobalData.equipped_parts.get("body"), "max_hp", 50.0)
	var frame_max := GlobalData.part_stat(GlobalData.equipped_frames.get("body"), "max_hp", 50.0)
	var expected := maxi(1, int(ceil(armor_max * 1.0 + frame_max * 0.75)))
	var cost := GlobalData.get_professional_repair_cost("body")
	_check(cost == expected, "professional cost prices the full catalog rebuild")

	_check(not GlobalData.apply_professional_repair("body"), "professional repair refused with no credits")
	_check(GlobalData.has_scrap_patch("body"), "patch survives an unaffordable attempt")

	GlobalData.credits = cost
	_check(GlobalData.apply_professional_repair("body"), "professional repair succeeds with credits")
	_check(GlobalData.credits == 0, "professional repair charges the credits")
	_check(not GlobalData.has_scrap_patch("body"), "professional repair removes the scrap patch")
	_check(not GlobalData.part_damage.has("body"), "professional repair clears armor damage")
	_check(not GlobalData.part_damage.has("body_frame"), "professional repair clears frame damage")


func _test_hangar_mech_roster() -> void:
	GlobalData.reset_run_data()
	GlobalData.ensure_hangar_roster()
	_check(GlobalData.hangar_mechs.size() == 1, "new run creates one active hangar mech")
	_check(GlobalData.active_hangar_mech_id != "", "active hangar mech has an id")
	_check(GlobalData.get_backup_hangar_mech_id() == "", "no backup exists before building a second mech")

	var built := GlobalData.build_hangar_mech("Scout Frame")
	_check(not built.is_empty(), "body and both leg frames can build a hangar mech")
	_check(GlobalData.hangar_mechs.size() == 2, "hangar stores multiple built mechs")
	var backup_id := GlobalData.get_backup_hangar_mech_id()
	_check(backup_id != "", "second built mech is available as backup")
	_check(GlobalData.switch_hangar_mech(backup_id), "hangar can switch to another built mech")
	_check(GlobalData.active_hangar_mech_id == backup_id, "switch updates active hangar mech")
	_check(GlobalData.get_active_hangar_mech().get("name", "") == "Scout Frame", "switch loads the selected mech snapshot")


# Round-trips a distinctive run state through save_run()/load_run() to prove the
# persistence layer survives refactors. Backs up any existing save file first so
# a real playthrough save is never destroyed by the QA suite.
func _test_save_load_roundtrip() -> void:
	var save_path := "user://savegame.json"
	var backup := ""
	if FileAccess.file_exists(save_path):
		var f := FileAccess.open(save_path, FileAccess.READ)
		if f:
			backup = f.get_as_text()

	GlobalData.reset_run_data()
	GlobalData.chassis_id = "titan"
	GlobalData.credits = 777
	GlobalData.scrap = 321
	GlobalData.data_cores = 9
	GlobalData.theme_id = "scavenger"
	GlobalData.heat = 42
	GlobalData.wanted_level = 3
	GlobalData.current_sector = 4
	GlobalData.part_damage["body"] = 0.5
	GlobalData.part_damage["body_frame"] = 1.0
	GlobalData.save_run()

	GlobalData.reset_run_data()
	_check(GlobalData.chassis_id != "titan", "state reset before load")
	_check(GlobalData.credits == 110, "reset grants the standard starting credits")

	var loaded := GlobalData.load_run()
	_check(loaded, "load_run returns true after save")
	_check(GlobalData.chassis_id == "titan", "load restores chassis id")
	_check(GlobalData.credits == 777, "load restores credits")
	_check(GlobalData.scrap == 321, "load restores scrap")
	_check(GlobalData.data_cores == 9, "load restores data cores")
	_check(GlobalData.theme_id == "scavenger", "load restores theme id")
	_check(GlobalData.heat == 42, "load restores heat")
	_check(GlobalData.wanted_level == 3, "load restores wanted level")
	_check(GlobalData.current_sector == 4, "load restores sector")
	_check(is_equal_approx(GlobalData.part_damage.get("body", 0.0), 0.5), "load restores armor damage cache")
	_check(is_equal_approx(GlobalData.part_damage.get("body_frame", 0.0), 1.0), "load restores frame damage cache")

	if backup != "":
		var wf := FileAccess.open(save_path, FileAccess.WRITE)
		if wf:
			wf.store_string(backup)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _test_escape_zone() -> void:
	GameManager.is_escaping = false

	# A fake "mecha" body with a live health system, so the zone can detect it.
	var fake := CharacterBody3D.new()
	fake.name = "FakeMecha"
	fake.add_to_group("mecha")
	var hs := preload("res://scripts/mecha/mecha_health_base.gd").new()
	hs.name = "HealthSystem"
	hs.is_destroyed = false
	fake.add_child(hs)
	add_child(fake)

	# Zones are kept out of the tree so the real physics process can't add
	# uncontrolled delta to the manually-driven hold timer.
	var zone := preload("res://scripts/arena/escape_zone.gd").new()
	zone.escape_time = 0.5

	var escaped_fired := [false]
	var escaped_listener := func() -> void: escaped_fired[0] = true
	EventBus.combat_escaped.connect(escaped_listener)

	# Standing inside builds the timer; it must not fire early.
	zone._on_body_entered(fake)
	zone._physics_process(0.2)
	_check(not zone._escaped, "escape does not fire before the hold time")
	_check(is_equal_approx(zone._time_inside, 0.2), "hold timer accumulates while standing inside")

	zone._physics_process(0.4)
	_check(zone._escaped, "escape fires after the hold time")
	_check(GameManager.is_escaping, "escape flags GameManager.is_escaping")
	_check(escaped_fired[0], "escape emits EventBus.combat_escaped")
	EventBus.combat_escaped.disconnect(escaped_listener)
	GameManager.is_escaping = false

	# Leaving the zone resets the accumulated timer.
	var zone2 := preload("res://scripts/arena/escape_zone.gd").new()
	zone2.escape_time = 0.5
	zone2._on_body_entered(fake)
	zone2._physics_process(0.3)
	zone2._on_body_exited(fake)
	zone2._physics_process(0.3)
	_check(not zone2._escaped, "leaving the zone resets the hold timer")
	_check(is_equal_approx(zone2._time_inside, 0.0), "hold timer resets to zero on exit")

	# A destroyed mech can no longer retreat.
	hs.is_destroyed = true
	var zone3 := preload("res://scripts/arena/escape_zone.gd").new()
	zone3.escape_time = 0.5
	zone3._on_body_entered(fake)
	zone3._physics_process(0.6)
	_check(not zone3._escaped, "a destroyed mech cannot escape")

	zone.free()
	zone2.free()
	zone3.free()
	fake.queue_free()
	GameManager.is_escaping = false
