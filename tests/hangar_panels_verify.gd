extends Node

## Headless verification of the panels extracted from hangar_controller.gd:
##   HangarPartText  — pure stat-card text helpers
##   HangarAmmoPanel — ammo-to-carry loadout build/adjust/refresh
## Run: godot --headless --path . res://tests/hangar_panels_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	_verify_text_helpers()
	await _verify_ammo_panel()
	print("HANGAR_PANELS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _verify_text_helpers() -> void:
	_check(HangarPartText.weapon_type_label(0) == "Beam Weapon", "weapon_type_label beam")
	_check(HangarPartText.weapon_type_label(4) == "Melee Weapon", "weapon_type_label melee")
	_check(HangarPartText.weapon_type_label(99) == "Unknown", "weapon_type_label unknown")

	var rifle = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	_check(rifle != null, "stock beam rifle resource loads")
	var wcap := HangarPartText.weapon_capability_text(rifle)
	_check(wcap.contains("TYPE: "), "weapon_capability_text has TYPE line")
	_check(HangarPartText.weapon_capability_text(null) == "", "weapon_capability_text null -> empty")

	var fcap := HangarPartText.frame_capability_text({"type": "Inner Frame", "hp": 50.0, "weight": 3.0, "carry_bonus": 5.0})
	_check(fcap.contains("FRAME HP: 50"), "frame_capability_text has HP line")
	_check(fcap.contains("FIELD PACK BONUS: +5.0 kg"), "frame_capability_text has carry bonus")
	_check(HangarPartText.frame_capability_text({}) == "", "frame_capability_text empty dict -> empty")

	var acap := HangarPartText.armor_capability_text({"type": "Plate", "max_hp": 100.0, "weight": 4.0}, 0.5)
	_check(acap.contains("ARMOR HP: 50 / 100"), "armor_capability_text applies passed durability")
	_check(HangarPartText.armor_capability_text({}, 1.0) == "", "armor_capability_text empty dict -> empty")


func _verify_ammo_panel() -> void:
	GlobalData.reset_run_data()
	# reset_run_data grants a starter loadout + reserve; force a clean slate for
	# the panel so the assertions are deterministic.
	GlobalData.set_loadout_ammo("kinetic", 0)
	GlobalData.add_reserve_ammo("kinetic", 50)
	await get_tree().process_frame

	var panel := HangarAmmoPanel.new()
	var box := VBoxContainer.new()
	add_child(box)
	var status_lbl := Label.new()
	add_child(status_lbl)
	panel.build(box)
	panel.status_label = status_lbl

	_check(panel.ammo_loadout_box != null, "ammo panel builds a loadout box")
	_check(panel.ammo_value_labels.size() == 4, "ammo panel tracks 4 ammo types")
	_check(panel.ammo_loadout_box.visible == false, "loadout box starts hidden")

	panel.adjust("kinetic", 10)
	_check(GlobalData.get_loadout_ammo("kinetic") == 10, "adjust adds to loadout")
	_check(status_lbl.text == "Kinetic ammo to carry: 10", "adjust reports via status label")

	panel.adjust("kinetic", -5)
	_check(GlobalData.get_loadout_ammo("kinetic") == 5, "adjust subtracts loadout")

	# A huge request clamps to what is owned in reserve (350: starter 300 + 50).
	panel.adjust("kinetic", 999)
	_check(GlobalData.get_loadout_ammo("kinetic") == 350, "adjust clamps to owned reserve")

	panel.refresh()
	var value_lbl: Label = panel.ammo_value_labels["kinetic"]
	_check(value_lbl.text == "350 / 350", "refresh repaints carried / owned labels")

	box.queue_free()
	status_lbl.queue_free()
