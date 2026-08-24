extends Node

## Verification test for:
## 1. Status Panel Penalty Display with Strikethrough Base Values
## 2. Tabletop / Intermission Mech Status showing all 6 limbs (Head, Body, Arm L, Arm R, Leg L, Leg R)

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("PENALTY_VERIFY_OK: %s" % msg)
	else:
		_fails += 1
		print("PENALTY_VERIFY_FAIL: %s" % msg)


func _ready() -> void:
	print("=== Starting Penalty Display & Tabletop 6 Limbs Verification ===")

	GlobalData.reset_run_data()
	GlobalData.weapons._ensure_default_frames()

	# -----------------------------------------------------------------------
	# 1. Test Part Penalty System Formatting with Strikethrough Base Numbers
	# -----------------------------------------------------------------------
	# Pristine -> No active penalties report
	GlobalData.weapons.part_damage.clear()
	var empty_report := PartPenaltySystem.get_detailed_penalty_report()
	_check(empty_report == "", "Pristine mech produces no penalty report")

	# Damage legs (60% damage) -> triggers walk and dash penalties
	GlobalData.weapons.part_damage["leg_left"] = 0.65
	var leg_report := PartPenaltySystem.get_detailed_penalty_report()
	_check(leg_report.contains("LEGS (Walk Speed)"), "Report flags leg walk speed penalty")
	_check(leg_report.contains("[s]100%[/s] -> 75%"), "Report shows strikethrough base 100% and penalty 75% ([s]100%[/s] -> 75%)")
	_check(leg_report.contains("LEGS (Dash Speed)"), "Report flags roller dash penalty")

	# Damage torso (60% damage) -> triggers energy and heat penalties
	GlobalData.weapons.part_damage["body"] = 0.65
	var torso_report := PartPenaltySystem.get_detailed_penalty_report()
	_check(torso_report.contains("TORSO (Max Energy)") and torso_report.contains("[s]100%[/s] -> 75%"), "Report flags torso max energy degradation")
	_check(torso_report.contains("TORSO (Heat Stress)"), "Report flags faster heat accumulation")

	# Format helper test
	var formatted_speed := PartPenaltySystem.format_stat_with_penalty(100.0, 0.75, "%")
	_check(formatted_speed == "[s]100%[/s] 75% (-25%)", "format_stat_with_penalty generates proper strikethrough text (got %s)" % formatted_speed)

	# -----------------------------------------------------------------------
	# 2. Test Intermission Status Bars Rendering All 6 Limbs
	# -----------------------------------------------------------------------
	var intermission = load("res://scenes/ui/intermission_ui.tscn").instantiate()
	add_child(intermission)
	await get_tree().process_frame
	await get_tree().process_frame

	intermission._on_status_pressed()
	await get_tree().process_frame

	var status_bars_container: Node = intermission.get("status_bars_container")
	_check(status_bars_container != null and status_bars_container.visible, "Status bars container is active")

	# Verify that all 6 slots are generated
	for slot in GlobalData.MECHA_SLOTS:
		var found_slot := false
		var cells: Array = []
		_gather_cells(status_bars_container, cells)
		for cell in cells:
			var lbl: Label = cell.get_child(0) as Label
			if lbl != null and str(lbl.text).to_lower().begins_with(slot.to_lower().replace("_", " ")):
				found_slot = true
				break
		_check(found_slot, "Tabletop Mech Status includes limb HP bars for: %s" % slot)

	# Verify status text contains active penalties section
	var status_text: String = intermission._build_mech_status_text()
	_check(status_text.contains("ACTIVE PART PENALTIES"), "Status text embeds active penalties section with crossed-out base numbers")

	print("=== Penalty & Limbs Verification Finished: %d passed, %d failed ===" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _gather_cells(node: Node, out_cells: Array) -> void:
	if node is VBoxContainer and node.get_child_count() >= 3 and node.get_child(0) is Label:
		out_cells.append(node)
		return
	for child in node.get_children():
		_gather_cells(child, out_cells)
