extends Node

class MockFullHangarController extends Control:
	var selected_slot: String = "body"
	var current_mode: String = "armor"
	var tab_container: HBoxContainer
	var sub_toggle_container: HBoxContainer
	var left_panel: PanelContainer
	var right_panel: PanelContainer
	var part_item_list: ItemList
	var stats_label: Control
	var total_stats_label: Control
	var currency_label: Control
	var header_mech_summary_label: Control
	var weight_bar: ProgressBar
	var stats_hp_bar_box: VBoxContainer
	var toast_container: Control
	var tier_label: Label = null
	var tier_pips_label: Label = null
	var tier_effect_label: Label = null
	var equip_button: Button
	var craft_button: Button
	var frame_upgrade_button: Button
	var repair_part_button: Button
	var full_repair_button: Button
	var overhaul_part_button: Button
	var close_button: Button
	var status_message_label: Label
	var back_to_menu_button: Button
	var slot_tab_buttons: Dictionary = {}
	var mode_buttons: Dictionary = {}
	var selected_frame_info: Dictionary = {}
	var selected_salvage_info: Dictionary = {}
	var selected_part_path: String = ""
	var selected_part_id: String = ""
	var selected_weapon_uid: String = ""
	var frame_catalog: Dictionary = {}
	var armor_catalog: Dictionary = {}
	var visible_weapon_indices: Array = []
	var visible_salvage_indices: Array = []
	var visible_frame_indices: Array = []

	var roster_panel_ui = null
	var catalog_panel = null
	var garage_panel = null
	var repair_panel = null
	var nav_panel = null
	var exit_panel = null
	var stats_panel = null
	var slot_panel = null
	var action_panel = null
	var part_list_panel = null

	func _init() -> void:
		name = "RootControl"

	func show_toast(message: String, is_warning: bool = false, duration: float = 2.5) -> void:
		if toast_container == null or not is_instance_valid(toast_container):
			var tc := Control.new()
			tc.name = "ToastContainer"
			add_child(tc)
			toast_container = tc

		var toast := PanelContainer.new()
		toast.name = "Toast"
		var lbl := Label.new()
		lbl.text = message
		lbl.set_meta("is_warning", is_warning)
		toast.add_child(lbl)
		toast_container.add_child(toast)

	func refresh_after_part_mutation(_slot: String = "") -> void:
		pass

	func update_tier_display(_info: Dictionary, _slot: String = "") -> void:
		pass

func _ready() -> void:
	print("--- Running hangar_ui_overhaul_verify ---")
	_test_hp_part_bar_durability_mode()
	_test_hangar_header_and_stats_separation()
	_test_hangar_right_panel_and_durability_bars()
	_test_toast_notification_trigger()
	print("All hangar_ui_overhaul_verify tests passed successfully!")
	get_tree().quit(0)

func _check(condition: bool, msg: String) -> void:
	if condition:
		print("  PASS: %s" % msg)
	else:
		push_error("  FAIL: %s" % msg)
		assert(condition, msg)

func _test_hp_part_bar_durability_mode() -> void:
	print("Testing HPPartBar durability mode...")
	var row = HPPartBar.create_row("Durability", 85.0, 100.0, false, false, 240, 10, 11, true)
	add_child(row)
	var val_lbl = row.get_node_or_null("ValueLabel") as Label
	_check(val_lbl != null, "ValueLabel exists in durability row")
	_check(val_lbl.text == "85%", "ValueLabel displays correct percentage '85%'")
	row.queue_free()

func _test_hangar_header_and_stats_separation() -> void:
	print("Testing Header Currency & Mech Overview...")
	var ctrl = MockFullHangarController.new()
	add_child(ctrl)

	# Mock sub-panels
	var roster_p := HangarRosterPanel.new()
	roster_p.controller = ctrl
	ctrl.roster_panel_ui = roster_p

	var cat_p := HangarCatalogPanel.new()
	cat_p.controller = ctrl
	ctrl.catalog_panel = cat_p

	var header_panel = HangarHeaderPanel.new()
	header_panel.controller = ctrl
	header_panel.build(ctrl)

	_check(ctrl.currency_label != null, "Header contains currency_label")
	_check(ctrl.header_mech_summary_label != null, "Header contains header_mech_summary_label")
	_check(ctrl.weight_bar != null, "Header contains weight_bar")

	GlobalData.currency.credits = 1450
	GlobalData.currency.scrap = 320

	var stats_p = HangarStatsPanel.new()
	stats_p.controller = ctrl
	ctrl.stats_panel = stats_p
	stats_p.update()

	var cur_text: String = ctrl.currency_label.text
	_check(cur_text.contains("1450 CR"), "Currency label formatted credits '1450 CR'")
	_check(cur_text.contains("320 SCRAP"), "Currency label formatted scrap '320 SCRAP'")

	var summary_text: String = ctrl.header_mech_summary_label.text
	_check(summary_text.contains("PILOT:"), "Header summary contains PILOT")
	_check(summary_text.contains("FRAME HP:"), "Header summary contains FRAME HP")
	_check(summary_text.contains("ARMOR HP:"), "Header summary contains ARMOR HP")
	_check(summary_text.contains("WEIGHT:"), "Header summary contains WEIGHT")

	ctrl.queue_free()

func _test_hangar_right_panel_and_durability_bars() -> void:
	print("Testing Right Panel layout and Part Durability Bars...")
	var ctrl = MockFullHangarController.new()
	add_child(ctrl)

	var roster_p := HangarRosterPanel.new()
	roster_p.controller = ctrl
	ctrl.roster_panel_ui = roster_p

	var cat_p := HangarCatalogPanel.new()
	cat_p.controller = ctrl
	ctrl.catalog_panel = cat_p

	var right_p = HangarRightPanel.new()
	right_p.controller = ctrl
	right_p.build(ctrl)

	_check(ctrl.stats_label != null, "Right panel contains stats_label")
	_check(ctrl.stats_hp_bar_box != null, "Right panel contains stats_hp_bar_box")
	_check(ctrl.repair_part_button != null, "Right panel contains repair_part_button")
	_check(ctrl.overhaul_part_button != null, "Right panel contains overhaul_part_button")

	# Populate HP and Durability bars
	ctrl.stats_hp_bar_box.add_child(HPPartBar.create_row("Armor HP", 40.0, 50.0, false, false, 240, 10, 11))
	ctrl.stats_hp_bar_box.add_child(HPPartBar.create_row("Durability", 80.0, 100.0, false, false, 240, 10, 11, true))

	_check(ctrl.stats_hp_bar_box.get_child_count() == 2, "stats_hp_bar_box has 2 rows (Armor HP + Durability)")

	ctrl.queue_free()

func _test_toast_notification_trigger() -> void:
	print("Testing Toast Notification System...")
	var ctrl = MockFullHangarController.new()
	add_child(ctrl)

	ctrl.show_toast("Need 50 credits!", true)
	_check(ctrl.toast_container != null, "Toast container created")
	_check(ctrl.toast_container.get_child_count() > 0, "Toast instance spawned")

	var toast_lbl = ctrl.toast_container.get_child(0).get_child(0) as Label
	_check(toast_lbl.text == "Need 50 credits!", "Toast text matches message")
	_check(bool(toast_lbl.get_meta("is_warning")) == true, "Toast marked as warning")

	ctrl.queue_free()
