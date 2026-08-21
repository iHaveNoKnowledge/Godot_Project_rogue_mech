extends Node

## Headless verification of the intermission "Mech Status" live HP bars:
##   1. Opening Mech Status builds one bar row per equipped part (armor + frame).
##   2. Bar values reflect live part_damage ratios (armor at slot, frame at
##      slot+"_frame"), scaled against the equipped frame + upgrade bonus.
##   3. With no mech (mech_less), the status view shows a plain notice instead.
##   4. The info panel actually renders ON-SCREEN and stays clear of the BoardHUD
##      right column (regression: RIGHT_WIDE anchors pushed it off-screen, so the
##      Mech Status view "opened" but was invisible).
## Run: godot --headless --path . res://tests/intermission_mech_status_bars_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("STATUS_OK: " + name)
	else:
		_fails += 1
		printerr("STATUS_FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	GlobalData.narrative.mech_less = false
	GlobalData.weapons._ensure_default_frames()
	var armor = load("res://resources/mech/stock/head_standard.tres")
	GlobalData.weapons.equipped_parts["head"] = armor

	var intermission = load("res://scenes/ui/intermission_ui.tscn").instantiate()
	add_child(intermission)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(intermission.has_method("_on_status_pressed"), "controller exposes the status button handler")

	# No damage yet -> armor bar full (ratio ~1.0) vs the HpPartBar's own ratio.
	intermission._on_status_pressed()
	await get_tree().process_frame
	_check(intermission.current_view == "status", "Mech Status becomes the current view")
	var bars_container: Node = intermission.get("status_bars_container")
	_check(bars_container != null and bars_container.visible, "status bars container is shown")
	var full_ratio := _find_bar_ratio(bars_container, "head")
	_check(absf(full_ratio - 1.0) < 0.02, "undamaged armor bar reads ~100%% (got %.2f)" % full_ratio)

	# Regression: the info panel must render fully inside the viewport and must
	# not slide underneath the BoardHUD right column (~270px from the right edge).
	var info_panel: Control = intermission.get("info_panel")
	var vp_rect: Rect2 = intermission.get_viewport().get_visible_rect()
	if info_panel != null:
		var info_rect := info_panel.get_global_rect()
		_check(info_rect.position.x >= 0.0 and info_rect.position.y >= 0.0
			and info_rect.end.x <= vp_rect.size.x + 0.5 and info_rect.end.y <= vp_rect.size.y + 0.5,
			"info panel renders fully on-screen (got %s)" % str(info_rect))
		_check(info_rect.end.x <= vp_rect.size.x - 250.0,
			"info panel stays clear of the BoardHUD right column (right edge %.0f)" % info_rect.end.x)

	# Apply live damage: armor at 50%, frame at 20% remaining.
	GlobalData.weapons.part_damage["head"] = 0.5
	GlobalData.weapons.part_damage["head_frame"] = 0.8
	intermission._rebuild_status_bars()
	await get_tree().process_frame
	var armor_ratio := _find_bar_ratio(bars_container, "head", 1)
	var frame_ratio := _find_bar_ratio(bars_container, "head", 2)
	_check(absf(armor_ratio - 0.5) < 0.02, "armor bar follows slot damage (got %.2f)" % armor_ratio)
	_check(absf(frame_ratio - 0.2) < 0.02, "frame bar follows slot_frame damage (got %.2f)" % frame_ratio)

	# Destroyed part -> its HpPartBar should read destroyed (ratio 0).
	GlobalData.weapons.part_damage["head"] = 1.0
	intermission._rebuild_status_bars()
	await get_tree().process_frame
	var destroyed_ratio := _find_bar_ratio(bars_container, "head", 1)
	_check(destroyed_ratio <= 0.01, "destroyed armor bar reads empty (got %.2f)" % destroyed_ratio)

	# Text summary totals also mirror the damage.
	GlobalData.weapons.part_damage["head"] = 0.5
	var status_text: String = intermission._build_mech_status_text()
	_check(status_text.contains("ARMOR:"), "status text includes the ARMOR total line")
	_check(status_text.contains("FRAME:"), "status text includes the FRAME total line")

	# Fleet readout: EVERY parked mech's HP appears, not just the piloted one.
	var spare := HangarManager.build("Spare 02", 2)
	_check(not spare.is_empty(), "a spare mech can be parked for the fleet readout")
	var spare_id := str(spare.get("id", ""))
	if spare_id != "":
		# Wreck every slot inside the spare's OWN snapshot so its fleet totals
		# read 0% (a clearly different line than the piloted mech's 84%).
		for i in range(GlobalData.hangar.hangar_mechs.size()):
			if str(GlobalData.hangar.hangar_mechs[i].get("id", "")) == spare_id:
				var spare_damage: Dictionary = {}
				for slot in GlobalData.MECHA_SLOTS:
					spare_damage[slot] = 1.0
					spare_damage[slot + "_frame"] = 1.0
				GlobalData.hangar.hangar_mechs[i]["damage"] = spare_damage
				break
		GlobalData.save_run()
	var fleet_text: String = intermission._build_mech_status_text()
	_check(fleet_text.contains("HANGAR FLEET"), "status text includes the HANGAR FLEET section")
	_check(fleet_text.contains("Spare 02"), "fleet readout names every parked mech")
	_check(fleet_text.contains("SLOT 2"), "fleet readout shows the spare's slot")
	_check(fleet_text.contains("ARMOR: 0% (0/"), "fleet readout reflects the wrecked spare's armor")
	_check(fleet_text.contains("FRAME: 0% (0/"), "fleet readout reflects the wrecked spare's frame")

	# Mechless: pressing status must NOT crash and shows a notice instead of bars.
	GlobalData.narrative.mech_less = true
	intermission._on_status_pressed()
	await get_tree().process_frame
	_check(intermission.current_view == "status", "Mech Status works while on foot")
	_check(_find_bar_ratio(bars_container, "head") == -1.0, "no HP bars are built while on foot")

	print("INTERMISSION_MECH_STATUS_BARS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


# Walks the status_bars_container looking for a HpPartBar whose header matches
# the given slot. bar_index picks which HpPartBar in that cell to return ratio
# of (1 = armor, 2 = frame). Returns -1.0 when nothing matches.
func _find_bar_ratio(container: Node, slot_name: String, bar_index: int = 1) -> float:
	if container == null:
		return -1.0
	for cell in container.get_children():
		var header: Label = cell.get_child(0) if cell.get_child_count() > 0 else null
		if header == null or not (header is Label):
			continue
		if not str(header.text).begins_with(slot_name.capitalize()):
			continue
		var found := 0
		for row in cell.get_children():
			if row is HBoxContainer:
				found += 1
				if found == bar_index:
					for child in row.get_children():
						if child is Control and child.get_script() != null:
							if str(child.get_script().resource_path).ends_with("hp_part_bar.gd"):
								return float(child.get("ratio"))
	return -1.0