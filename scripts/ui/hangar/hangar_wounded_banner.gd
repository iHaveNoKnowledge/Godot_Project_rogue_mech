class_name HangarWoundedBanner
extends RefCounted
# Persistent banner across every hangar page: whenever any parked mech has a
# wounded fleet pilot assigned, a warning strip at the top of the screen lists
# the recovering drivers. It follows the roster's live state, so healing a
# pilot (or seating/clearing one) updates it immediately.
#
# A wounded pilot can still be ASSIGNED to a berth (the seat waits for them)
# but they never tag into combat until healed — this banner makes that state
# impossible to miss while tuning the mech in the garage.
#
# All node handles stay owned by the controller; this panel only builds them
# and repaints through `controller.`.

var controller  # hangar_controller.gd
var banner_panel: PanelContainer = null
var banner_label: Label = null


# Build the persistent banner into `root` (the full-rect RootControl). It sits
# at offset_top 122: below the 80px header AND below the mode-toggle bar (which
# lives at offset_top 86 on the customize page), so it never covers interactive
# controls. Informational only — mouse presses pass straight through to the 3D
# viewport so the turntable drag keeps working over it.
func build(root: Control) -> void:
	var panel = PanelContainer.new()
	panel.name = "WoundedPilotBanner"
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 122
	panel.offset_left = -330
	panel.offset_right = 330
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.07, 0.06, 0.94)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 0.4, 0.2)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.8))
	label.add_theme_font_size_override("font_size", 12)
	panel.add_child(label)

	banner_panel = panel
	banner_label = label
	refresh()


# Repaint the banner from the live roster: hidden when every seated pilot is
# fit to fight, otherwise one line per wounded driver.
func refresh() -> void:
	if banner_panel == null or not is_instance_valid(banner_panel):
		return
	var lines := _wounded_driver_lines()
	if lines.is_empty():
		banner_panel.visible = false
		banner_label.text = ""
		return
	banner_panel.visible = true
	banner_label.text = "⚠ WOUNDED PILOT ASSIGNED — %s" % "\n".join(lines)


# One short line per parked mech whose driver is a recovering fleet pilot,
# e.g. "Serra Voss (in Vanguard) · 2 moves left · will not fight until healed".
func _wounded_driver_lines() -> Array[String]:
	var lines: Array[String] = []
	for mech in HangarManager.get_mechs():
		if not (mech is Dictionary):
			continue
		var pilot_id := str(mech.get("pilot", ""))
		if not pilot_id.begins_with("fleet_"):
			continue
		var unit := FleetSystem.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
		if unit.is_empty() or not bool(unit.get("wounded", false)):
			continue
		var turns := maxi(int(unit.get("wound_turns", 1)), 1)
		lines.append("%s (in %s) · %d move%s left · will not fight until healed" % [
			str(unit.get("name", pilot_id)),
			str(mech.get("name", "a parked mech")),
			turns,
			"s" if turns != 1 else "",
		])
	return lines
