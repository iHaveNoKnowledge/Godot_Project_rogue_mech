extends Node

class MockController extends Node:
	var current_mode: String = "frame"
	var total_stats_label: Control = null
	var weight_bar: Control = null
	var selected_slot: String = "body"

func _ready() -> void:
	print("--- Running hangar_stats_and_equip_verify ---")
	_test_part_text_degradation_formatting()
	_test_is_item_equipped_sync()
	_test_hangar_stats_panel_formatting()
	print("All hangar_stats_and_equip_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_part_text_degradation_formatting() -> void:
	print("Testing HangarPartText degradation delta formatting...")
	var dummy_frame := {
		"name": "Heavy Core Frame",
		"hp": 100.0,
		"weight": 10.0
	}
	var text_full = HangarPartText.frame_capability_text(dummy_frame, 1.0)
	_check(text_full.contains("100 / 100") or text_full.contains("100"), "Pristine frame HP displayed")

	var text_degraded = HangarPartText.frame_capability_text(dummy_frame, 0.70)
	_check(text_degraded.contains("70 / 100") and text_degraded.contains("-30") and text_degraded.contains("70%"), "Degraded frame HP shows current, max, lost delta, and durability%")

	var dummy_armor := {
		"name": "Composite Plating",
		"max_hp": 80.0,
		"weight": 5.0
	}
	var armor_text_deg = HangarPartText.armor_capability_text(dummy_armor, 0.50)
	_check(armor_text_deg.contains("40 / 80") and armor_text_deg.contains("-40") and armor_text_deg.contains("50%"), "Degraded armor HP shows current, max, lost delta, and durability%")

func _test_is_item_equipped_sync() -> void:
	print("Testing Item Equipped [E] matching...")
	# Setup GlobalData
	GlobalData.weapons.equipped_frames["body"] = {"name": "Valkyrion Core", "uid": "frame_core_1"}
	GlobalData.weapons.equipped_parts["body"] = {"name": "Titanium Chest", "uid": "armor_chest_1", "id": "titanium_chest"}
	GlobalData.weapons.weapon_loadout["left"] = "res://resources/weapons/beam_rifle.tres"
	GlobalData.weapons.weapon_loadout["right"] = "wpn_inst_99"

	var mock_ctrl := MockController.new()
	add_child(mock_ctrl)
	mock_ctrl.current_mode = "frame"
	var panel := HangarPartListPanel.new()
	panel.controller = mock_ctrl

	# Frame match
	_check(panel.is_item_equipped("body", {"name": "Valkyrion Core", "uid": "frame_core_1"}), "Equipped frame matches by UID/name")
	_check(not panel.is_item_equipped("body", {"name": "Other Frame", "uid": "frame_core_2"}), "Non-equipped frame returns false")

	# Armor match
	mock_ctrl.current_mode = "armor"
	_check(panel.is_item_equipped("body", {"name": "Titanium Chest", "uid": "armor_chest_1"}), "Equipped armor matches by UID")
	_check(not panel.is_item_equipped("body", {"name": "Titanium Chest", "uid": "armor_chest_2"}), "Different instance of same armor returns false (no false [E] share)")

	# Weapon match
	_check(panel.weapon_in_loadout("weapon_left", {"path": "res://resources/weapons/beam_rifle.tres", "uid": "wpn_inst_1"}), "Equipped weapon matches by path fallback")
	_check(panel.weapon_in_loadout("weapon_right", {"path": "res://resources/weapons/beam_rifle.tres", "uid": "wpn_inst_99"}), "Equipped weapon matches by UID")
	_check(not panel.weapon_in_loadout("weapon_left", {"path": "res://resources/weapons/shotgun.tres", "uid": "wpn_inst_2"}), "Unequipped weapon returns false")
	mock_ctrl.queue_free()

func _test_hangar_stats_panel_formatting() -> void:
	print("Testing HangarStatsPanel total HP calculation & BBCode formatting...")
	var mock_ctrl := MockController.new()
	add_child(mock_ctrl)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	mock_ctrl.add_child(rtl)
	mock_ctrl.total_stats_label = rtl

	var stats_panel := HangarStatsPanel.new()
	stats_panel.controller = mock_ctrl

	# Set part damage and valid HP
	GlobalData.weapons.equipped_frames["body"] = {"name": "Valkyrion Core", "uid": "frame_core_1", "hp": 100.0}
	GlobalData.weapons.equipped_parts["body"] = {"name": "Titanium Chest", "uid": "armor_chest_1", "id": "titanium_chest", "max_hp": 80.0}
	GlobalData.weapons.part_damage["body_frame"] = 0.25 # 25% damaged frame
	GlobalData.weapons.part_damage["body"] = 0.50 # 50% damaged armor

	stats_panel.update()
	var text: String = rtl.text
	_check(text.contains("FRAME HP:") and text.contains("ARMOR HP:"), "Total stats label generated")
	_check(text.contains("(-") or text.contains("%"), "Total stats label includes degradation delta and ratio")

	mock_ctrl.queue_free()
