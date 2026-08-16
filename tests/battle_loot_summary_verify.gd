extends Node

## Headless verification of the post-battle loot summary:
##   1. Enemy weapon & armor drops go into GlobalData.battle_loot (the post-
##      battle pool) instead of spawning walk-over pickups.
##   2. The victory rewards UI builds a two-column picker: BATTLE DROPS on the
##      left, TAKE BACK on the right.
##   3. Clicking an item moves it from DROPS to TAKE BACK (and back).
##   4. Continue grants the TAKE BACK side (weapon registered / armor appended)
##      and discards the left side, clearing the battle pool.
## Run: godot --headless --path . res://tests/battle_loot_summary_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LOOT_OK: " + name)
	else:
		_fails += 1
		printerr("LOOT_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GameManager.combat_node_type = "grunt"
	GameManager.is_boss_combat = false

	await _verify_drops_route_to_pool()
	await _verify_picker_and_grant()
	await _verify_unclaimed_salvage()
	await _verify_rarity_tier_pricing()

	print("BATTLE_LOOT_SUMMARY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().paused = false
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# spawn_enemy_loot must hold weapon/armor drops for the post-battle summary and
# keep ammo/scrap/repair as physical pickups. Force the archetype weapon pool so
# a weapon entry is guaranteed on the table.
func _verify_drops_route_to_pool() -> void:
	GlobalData.battle_loot.clear()
	var loot := Node3D.new()
	loot.set_script(load("res://scripts/systems/loot_system.gd"))
	loot.name = "LootSystem"
	add_child(loot)
	loot.spawn_enemy_loot(Vector3.ZERO, 1)  # archetype 1 = ranged weapon pool
	await get_tree().process_frame

	# Every pooled entry must be a weapon or armor part (no ammo/scrap/repair).
	var only_parts := true
	for entry in GlobalData.battle_loot:
		var t := str(entry.get("type", ""))
		if t != "weapon" and t != "armor":
			only_parts = false
	_check(only_parts, "battle_loot pool holds only weapon/armor drops")
	# Physical pickups spawned this frame may exist (ammo/scrap/repair), but
	# none of them may be weapon/armor pickups.
	var pickup_ok := true
	for pickup in get_tree().get_nodes_in_group("loot_pickup"):
		var data: Dictionary = pickup.get_meta("loot_data", {})
		var t := str(data.get("type", "ammo"))
		if t == "weapon" or t == "armor":
			pickup_ok = false
	_check(pickup_ok, "no weapon/armor walk-over pickups spawn from enemy drops")
	loot.queue_free()
	await get_tree().process_frame


# The rewards UI shows the pool on the left, moving items to the right, and
# Continue grants exactly the right side.
func _verify_picker_and_grant() -> void:
	GlobalData.battle_loot.clear()
	var weapon_res: WeaponPart = load("res://resources/mech/stock/weapon_pile_bunker.tres")
	var armor_inst := {
		"uid": "loot_test_armor_1",
		"db_id": "zaku_plate",
		"name": "Zaku Plate",
		"slot": "body",
		"type": "armor",
		"hp": 40.0, "armor": 25.0, "weight": 6.0,
		"color": Color(0.2, 0.6, 0.3),
		"durability": 0.8, "upgrade_level": 1, "equipped": false,
	}
	GlobalData.battle_loot.append({"type": "weapon", "weapon": weapon_res})
	GlobalData.battle_loot.append({"type": "armor", "instance": armor_inst})

	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	rewards_ui._show_victory_rewards()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(rewards_ui.visible, "victory rewards screen is visible")
	_check(rewards_ui._left_items.size() == 2, "both drops start on the BATTLE DROPS side")
	_check(rewards_ui._right_items.is_empty(), "TAKE BACK starts empty")
	_check(loot_left_row_count(rewards_ui) == 2, "left column renders 2 item rows")
	_check(loot_right_row_count(rewards_ui) == 0, "right column starts empty")

	# Click the first left row (Pile Bunker) → moves to TAKE BACK.
	var left_buttons := _loot_buttons(rewards_ui.loot_left_list)
	_check(left_buttons.size() == 2, "found the left column buttons")
	if left_buttons.size() >= 1:
		left_buttons[0].pressed.emit()
		await get_tree().process_frame
		_check(rewards_ui._left_items.size() == 1, "clicking a drop moves it out of BATTLE DROPS")
		_check(rewards_ui._right_items.size() == 1, "clicking a drop adds it to TAKE BACK")
		_check(str(rewards_ui._right_items[0].get("type", "")) == "weapon", "the moved item is the weapon")
		_check(loot_right_row_count(rewards_ui) == 1, "right column renders the moved item")

		# Click it back → returns to the left.
		var right_buttons := _loot_buttons(rewards_ui.loot_right_list)
		if right_buttons.size() >= 1:
			right_buttons[0].pressed.emit()
			await get_tree().process_frame
			_check(rewards_ui._right_items.is_empty(), "clicking a taken item returns it to BATTLE DROPS")
			_check(rewards_ui._left_items.size() == 2, "both drops are back on the left")

		# Move both to TAKE BACK and verify the grant path grants exactly them.
		# Re-query the list after each click: repopulating frees the old buttons.
		for i in range(2):
			var current := _loot_buttons(rewards_ui.loot_left_list)
			if current.is_empty():
				break
			current[0].pressed.emit()
			await get_tree().process_frame
		_check(rewards_ui._right_items.size() == 2, "both items moved to TAKE BACK")

		var stash_before: int = GlobalData.weapon_inventory.size()
		var armor_before: int = GlobalData.armor_inventory.size()
		rewards_ui._grant_take_back_loot()
		await get_tree().process_frame
		_check(GlobalData.weapon_inventory.size() == stash_before + 1, "weapon granted into the depot stash")
		_check(GlobalData.armor_inventory.size() == armor_before + 1, "armor part granted into the armor inventory")
		_check(GlobalData.battle_loot.is_empty(), "battle loot pool cleared after granting")
		_check(rewards_ui._left_items.is_empty() and rewards_ui._right_items.is_empty(), "picker state cleared after grant")

	rewards_ui.queue_free()
	await get_tree().process_frame


# Items the player does NOT take back must not be wasted: they are auto-
# salvaged into scrap (armor priced with the same formula the craftery uses,
# weapons by weight/damage/rarity), and a run notice tells the player.
func _verify_unclaimed_salvage() -> void:
	GlobalData.battle_loot.clear()
	var weapon_res: WeaponPart = load("res://resources/mech/stock/weapon_pile_bunker.tres")
	var armor_inst := {
		"uid": "loot_test_salvage_1",
		"db_id": "zaku_plate",
		"name": "Zaku Plate",
		"slot": "body",
		"type": "armor",
		"hp": 40.0, "armor": 25.0, "weight": 6.0,
		"color": Color(0.2, 0.6, 0.3),
		"durability": 0.8, "upgrade_level": 1, "equipped": false,
	}
	# Weapon is taken back; armor is left unclaimed.
	GlobalData.battle_loot.append({"type": "weapon", "weapon": weapon_res})
	GlobalData.battle_loot.append({"type": "armor", "instance": armor_inst})

	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame
	rewards_ui._show_victory_rewards()
	await get_tree().process_frame
	await get_tree().process_frame

	# The summary must tell the player unclaimed drops are stripped for scrap.
	_check(rewards_ui.rewards_label.text.contains("stripped for +"), "victory summary announces unclaimed salvage")
	# Baseline AFTER the victory screen (it grants its own credit/scrap rewards).
	var scrap_before: int = GlobalData.scrap
	# Both drops start unclaimed — the summary must show their COMBINED scrap.
	var both_scrap := 0
	for e in rewards_ui._left_items:
		both_scrap += int(rewards_ui._salvage_value(e))
	_check(both_scrap > 0, "combined unclaimed scrap is positive (%d)" % both_scrap)
	_check(rewards_ui.rewards_label.text.contains("stripped for +%d" % both_scrap), "summary shows combined scrap for all unclaimed drops")

	# Take back only the weapon (first row) — the figure must DROP to just the
	# armor's value in real time (no re-opening the screen needed).
	var left := _loot_buttons(rewards_ui.loot_left_list)
	if left.size() >= 1:
		left[0].pressed.emit()
		await get_tree().process_frame
	_check(rewards_ui._right_items.size() == 1, "weapon moved to TAKE BACK, armor stays unclaimed")

	var expected_scrap: int = int(rewards_ui._salvage_value(rewards_ui._left_items[0]))
	_check(expected_scrap > 0, "unclaimed armor has a positive scrap value (%d)" % expected_scrap)
	_check(expected_scrap < both_scrap, "taking a weapon back lowers the unclaimed scrap total (%d -> %d)" % [both_scrap, expected_scrap])
	_check(rewards_ui.rewards_label.text.contains("stripped for +%d" % expected_scrap), "summary updates live to the new unclaimed scrap total")
	_check(not rewards_ui.rewards_label.text.contains("stripped for +%d" % both_scrap), "summary no longer shows the old combined total")

	# Move the armor back to TAKE BACK too — nothing unclaimed left.
	var left_after := _loot_buttons(rewards_ui.loot_left_list)
	if left_after.size() >= 1:
		left_after[0].pressed.emit()
		await get_tree().process_frame
	_check(rewards_ui._left_items.is_empty(), "both items moved to TAKE BACK, nothing unclaimed")
	_check(rewards_ui.rewards_label.text.contains("No salvage dropped"), "summary flips to 'no unclaimed drops' when everything is taken")

	# Reset to the unclaimed-armor state so the grant check below is exact:
	# right = [weapon] (taken back), left = [armor] (unclaimed). Right now right
	# holds [weapon, armor] in click order, so return the SECOND row (armor).
	var right_buttons := _loot_buttons(rewards_ui.loot_right_list)
	if right_buttons.size() >= 2:
		right_buttons[1].pressed.emit()
		await get_tree().process_frame
	_check(rewards_ui._right_items.size() == 1, "weapon stays on TAKE BACK, armor returned to BATTLE DROPS")
	var stash_before: int = GlobalData.weapon_inventory.size()
	rewards_ui._grant_take_back_loot()
	await get_tree().process_frame
	_check(GlobalData.weapon_inventory.size() == stash_before + 1, "taken weapon still granted to the depot stash")
	_check(GlobalData.scrap == scrap_before + expected_scrap, "unclaimed armor stripped into scrap (+%d)" % expected_scrap)
	_check(GlobalData.run_notice.contains("salvaged for +%d" % expected_scrap), "board run-notice reports the salvaged scrap")
	_check(GlobalData.battle_loot.is_empty(), "battle pool cleared after salvage")

	rewards_ui.queue_free()
	await get_tree().process_frame


# Rarity tier must drive salvage pricing: legendary/rare loot is worth several
# times a common piece, and the per-row label shows the scrap value.
func _verify_rarity_tier_pricing() -> void:
	GlobalData.battle_loot.clear()
	var knife: WeaponPart = load("res://resources/mech/stock/weapon_combat_knife.tres")  # rarity 0
	var railgun: WeaponPart = load("res://resources/mech/stock/weapon_railgun.tres")      # rarity 3
	var standard_armor := {
		"uid": "loot_test_tier_std", "db_id": "std_plate", "name": "Standard Plate",
		"slot": "body", "type": "Standard Armor",
		"hp": 25.0, "armor": 15.0, "weight": 6.0,
		"color": Color(0.9, 0.9, 0.95), "durability": 1.0, "upgrade_level": 1, "equipped": false,
	}
	var gundam_armor := {
		"uid": "loot_test_tier_gundam", "db_id": "gundam_plate", "name": "Gundam Plate",
		"slot": "body", "type": "Gundam Armor",
		"hp": 40.0, "armor": 30.0, "weight": 5.0,
		"color": Color(0.9, 0.2, 0.25), "durability": 1.0, "upgrade_level": 1, "equipped": false,
	}

	var rewards_ui = load("res://scenes/ui/combat_rewards_ui.tscn").instantiate()
	add_child(rewards_ui)
	await get_tree().process_frame

	# Weapons: rarity 3 must salvage for clearly more than rarity 0.
	var common_val := int(rewards_ui._salvage_value({"type": "weapon", "weapon": knife}))
	var legendary_val := int(rewards_ui._salvage_value({"type": "weapon", "weapon": railgun}))
	_check(common_val >= 2, "common weapon has a base scrap value (%d)" % common_val)
	_check(legendary_val > common_val * 2, "legendary weapon sells for >2x a common weapon (%d vs %d)" % [legendary_val, common_val])

	# Armor: gundam-tier must sell for clearly more than standard armor.
	var std_val := int(rewards_ui._salvage_value({"type": "armor", "instance": standard_armor}))
	var gundam_val := int(rewards_ui._salvage_value({"type": "armor", "instance": gundam_armor}))
	_check(std_val >= 1, "standard armor has a base scrap value (%d)" % std_val)
	_check(gundam_val > std_val * 2, "gundam armor sells for >2x standard armor (%d vs %d)" % [gundam_val, std_val])

	# The per-row label advertises the scrap value so tier pricing is visible.
	var label: String = rewards_ui._loot_entry_label({"type": "weapon", "weapon": railgun})
	_check(label.contains("(%d scrap)" % legendary_val), "weapon row shows its scrap value (%s)" % label)
	var armor_label: String = rewards_ui._loot_entry_label({"type": "armor", "instance": gundam_armor})
	_check(armor_label.contains("(%d scrap)" % gundam_val), "armor row shows its scrap value (%s)" % armor_label)

	rewards_ui.queue_free()
	await get_tree().process_frame


func loot_left_row_count(ui: Node) -> int:
	return _loot_buttons(ui.loot_left_list).size()


func loot_right_row_count(ui: Node) -> int:
	return _loot_buttons(ui.loot_right_list).size()


func _loot_buttons(list: Node) -> Array:
	var out: Array = []
	if list == null:
		return out
	for child in list.get_children():
		if child is Button:
			out.append(child)
	return out
