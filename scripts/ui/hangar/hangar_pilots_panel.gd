class_name HangarPilotsPanel
extends RefCounted

## PILOTS page (pilot roster): lists everyone riding with the convoy — the
## player driver plus every researched fleet pilot — with their live status
## (HP / wounded countdown / destroyed), the mech they drive, and a HEAL
## shortcut for recovering pilots.
##
## It is the read-mostly counterpart of the roster page's per-berth PILOT
## picker: both read the same pilot list (GlobalData.get_hangar_pilots) so the
## page never drifts from the options offered when assigning a pilot (including
## the REGISTER dialog, which reuses the same list as its picker).

var controller  # hangar_controller.gd

var pilots_panel: PanelContainer = null
var pilot_list: VBoxContainer = null
var pilots_status_label: Label = null


func build(root: Control) -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top = 128
	panel.offset_bottom = -20
	panel.offset_left = 20
	panel.custom_minimum_size = Vector2(540, 0)
	panel.visible = false
	pilots_panel = panel
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.94)
	style.corner_radius_top_left = 8
	style.corner_radius_bottom_left = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var title = Label.new()
	title.text = "PILOT ROSTER (นักบินในกองยาน)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	box.add_child(title)

	var desc = Label.new()
	desc.text = "Everyone riding with the convoy — the driver plus every researched fleet pilot. Pilots can be seated in any parked mech from the ROSTER page (PILOT ▾) or while assembling a new frame (REGISTER)."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	box.add_child(desc)

	var sep = HSeparator.new()
	box.add_child(sep)

	pilot_list = VBoxContainer.new()
	pilot_list.add_theme_constant_override("separation", 6)
	pilot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(pilot_list)

	pilots_status_label = Label.new()
	pilots_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pilots_status_label.add_theme_font_size_override("font_size", 11)
	box.add_child(pilots_status_label)


func set_panel_visible(v: bool) -> void:
	if pilots_panel:
		pilots_panel.visible = v


func show_page() -> void:
	set_panel_visible(true)
	refresh()


func hide_page() -> void:
	set_panel_visible(false)


# Rebuilds the pilot rows from the single source of truth
# (GlobalData.get_hangar_pilots) — the same list the roster page and the
# REGISTER dialog use, so every surface always shows the same pilots.
func refresh() -> void:
	if pilot_list == null:
		return
	for child in pilot_list.get_children():
		child.queue_free()

	var pilots := GlobalData.get_hangar_pilots()
	for pilot in pilots:
		_build_row(pilot)

	if pilots_status_label:
		var fleet := GlobalData.get_hangar_fleet_size()
		var capacity := GlobalData.get_hangar_capacity()
		var convoy := "SOLO CONVOY · 1 trailer · 2 berths" if fleet <= 1 else \
			"FLEET CONVOY · %d pilots · %d trucks · %d berths" % [fleet, ceili(fleet / 2.0), capacity]
		var affiliation := GlobalData.get_run_affiliation()
		pilots_status_label.text = "%s · %s\n%d pilot%s in the convoy · %d/%d berths filled" % [
			affiliation.get("name", "Mech Convoy"),
			convoy,
			pilots.size(), "s" if pilots.size() != 1 else "",
			GlobalData.get_hangar_mechs().size(), capacity,
		]


func _build_row(pilot: Dictionary) -> void:
	var pilot_id := str(pilot.get("id", ""))
	var name := str(pilot.get("name", "?"))
	var status := GlobalData.get_hangar_pilot_status(pilot_id)
	var is_wounded := status.contains("WOUNDED")
	var is_destroyed := status.contains("DESTROYED")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pilot_list.add_child(row)

	var marker := "⛔ " if is_destroyed else ("⚠ " if is_wounded else "")
	var name_lbl := Label.new()
	name_lbl.text = "%s%s%s%s" % [marker, name, status, _mech_label(pilot_id)]
	name_lbl.custom_minimum_size = Vector2(380, 0)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.5) if is_wounded or is_destroyed else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	# Wounded fleet pilots can be healed from here — same credit cost and rule
	# as the roster page's HEAL (single source: GlobalData.heal_wounded_pilot).
	if pilot_id.begins_with("fleet_"):
		var template_id := pilot_id.trim_prefix("fleet_")
		var heal_cost := GlobalData.get_wound_heal_cost(template_id)
		if heal_cost > 0:
			var heal_btn := Button.new()
			heal_btn.text = "HEAL (%dcr)" % heal_cost
			heal_btn.custom_minimum_size = Vector2(96, 28)
			heal_btn.focus_mode = Control.FOCUS_NONE
			heal_btn.tooltip_text = "Spend %d credits to heal this pilot now (full HP, back in the field)." % heal_cost
			heal_btn.pressed.connect(func(): _heal(template_id))
			row.add_child(heal_btn)


# Which parked mech this pilot drives (" · Mech 01"), or " · (no mech)".
func _mech_label(pilot_id: String) -> String:
	for mech in GlobalData.get_hangar_mechs():
		if str(mech.get("pilot", "")) == pilot_id:
			return " · %s" % str(mech.get("name", "Mech"))
	return " · (no mech)"


func _heal(template_id: String) -> void:
	var cost := GlobalData.get_wound_heal_cost(template_id)
	if cost <= 0:
		if controller and controller.status_message_label:
			controller.status_message_label.text = "That pilot is not wounded — nothing to heal."
		return
	if not GlobalData.heal_wounded_pilot(template_id):
		# The heal spends the credits itself; a failure here means the price
		# moved (or resources were drained while the page was open).
		if controller and controller.status_message_label:
			controller.status_message_label.text = "Need %d credits to heal this pilot." % cost \
				if GlobalData.credits < cost else "The pilot could not be healed."
		return
	GlobalData.save_run()
	var unit := GlobalData.get_fleet_unit(template_id)
	if controller and controller.status_message_label:
		controller.status_message_label.text = "%s is healed and ready to fight (-%d credits)." % [
			str(unit.get("name", "The pilot")), cost]
	refresh()
