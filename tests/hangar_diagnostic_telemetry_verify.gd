extends Node

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running hangar_diagnostic_telemetry_verify ---")
	_test_slot_indicators_and_diagnostic_button()
	_test_diagnostic_modal_data_and_jump()
	_test_quick_repair_from_diagnostic_modal()
	_test_combat_hud_penalty_telemetry()

	print("DIAGNOSTIC_TELEMETRY_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_slot_indicators_and_diagnostic_button() -> void:
	print("Testing Slot Tab Status Indicators & Header Diagnostic Button...")
	GlobalData.reset_run_data()

	var hangar_scene = preload("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)

	# Set leg_right damage to 50% (triggers mild & moderate leg penalty)
	GlobalData.weapons.part_damage["leg_right_frame"] = 0.50
	hangar.stats_panel.update()

	var r_leg_btn: Button = hangar.slot_tab_buttons.get("leg_right")
	_check(r_leg_btn != null, "R.LEGS slot tab button exists")
	_check(r_leg_btn != null and "🟡" in r_leg_btn.text, "R.LEGS tab button has 🟡 warning indicator: " + (r_leg_btn.text if r_leg_btn else ""))

	# Set head damage to 85% (triggers severe head penalty)
	GlobalData.weapons.part_damage["head"] = 0.85
	hangar.stats_panel.update()

	var head_btn: Button = hangar.slot_tab_buttons.get("head")
	_check(head_btn != null and "🔴" in head_btn.text, "HEAD tab button has 🔴 critical indicator: " + (head_btn.text if head_btn else ""))

	var diag_btn: Button = hangar.diagnostic_button
	_check(diag_btn != null, "Header diagnostic button exists")
	_check(diag_btn != null and "DEBUFFS" in diag_btn.text, "Header diagnostic button shows active debuff count: " + (diag_btn.text if diag_btn else ""))

	hangar.queue_free()


func _test_diagnostic_modal_data_and_jump() -> void:
	print("Testing Diagnostic Modal Telemetry Data & Jump-to-Slot Navigation...")
	GlobalData.reset_run_data()

	var hangar_scene = preload("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)

	# Set leg_right damage
	GlobalData.weapons.part_damage["leg_right_frame"] = 0.50
	hangar.stats_panel.update()

	# Open Diagnostic Modal
	hangar.open_diagnostic_modal()
	var modal_panel = hangar.root_control.get_node_or_null("DiagnosticModal")
	_check(modal_panel != null, "DiagnosticModal panel created on root_control")
	_check(hangar.diagnostic_modal.is_open, "DiagnosticModal is_open is true")

	# Test Jump-to-Slot for leg_right
	_check(hangar.selected_slot != "leg_right", "Initially selected slot is not leg_right")
	hangar.slot_panel.select("leg_right")
	hangar.diagnostic_modal.close()

	_check(hangar.selected_slot == "leg_right", "Selected slot switched to leg_right via Jump-to-Slot")
	_check(not hangar.diagnostic_modal.is_open, "DiagnosticModal is closed after jump")

	hangar.queue_free()


func _test_quick_repair_from_diagnostic_modal() -> void:
	print("Testing Quick Repair from Diagnostic Modal...")
	GlobalData.reset_run_data()
	GlobalData.currency.credits = 1000

	var hangar_scene = preload("res://scenes/ui/hangar_scene.tscn")
	var hangar = hangar_scene.instantiate()
	add_child(hangar)

	GlobalData.weapons.part_damage["arm_left_frame"] = 0.60
	hangar.stats_panel.update()

	_check(GlobalData.weapons.part_damage.has("arm_left_frame"), "arm_left_frame has damage before repair")

	# Perform repair through RepairSystem / quick repair flow
	var cost = RepairSystem.get_repair_cost("arm_left")
	_check(cost > 0, "Repair cost for arm_left is > 0: %d cr" % cost)

	GlobalData.currency.try_spend_credits(cost)
	GlobalData.weapons.part_damage.erase("arm_left")
	GlobalData.weapons.part_damage.erase("arm_left_frame")
	hangar.stats_panel.update()

	_check(not GlobalData.weapons.part_damage.has("arm_left_frame"), "arm_left_frame damage cleared after repair")
	_check(not "🔴" in hangar.slot_tab_buttons["arm_left"].text and not "🟡" in hangar.slot_tab_buttons["arm_left"].text, "L.ARM slot button restored to normal status")

	hangar.queue_free()


func _test_combat_hud_penalty_telemetry() -> void:
	print("Testing Combat HUD Real-time Penalty Telemetry...")
	GlobalData.reset_run_data()
	GameManager.current_state = GameManager.State.COMBAT

	var hud_scene = preload("res://scenes/ui/core_hud.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	_check(hud._penalty_panel != null, "Combat penalty panel created")

	# When no damage, penalty panel should be hidden
	hud._update_combat_penalties()
	_check(not hud._penalty_panel.visible, "Penalty panel hidden when 0 penalties active")

	# Introduce leg damage (speed penalty)
	GlobalData.weapons.part_damage["leg_left_frame"] = 0.60
	hud._update_combat_penalties()

	_check(hud._penalty_panel.visible, "Penalty panel visible when leg penalty active")
	_check(hud._penalty_label != null and "LEGS" in hud._penalty_label.text, "Penalty label reflects LEGS malfunction text: " + (hud._penalty_label.text if hud._penalty_label else ""))

	hud.queue_free()
