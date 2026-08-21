class_name HangarSortiePanel
extends RefCounted

## SORTIE page: pick which piloted hangar mechs tag along into combat.
##
## Feature 7 rule: combat allies come ONLY from hangar mechs with a pilot seated
## (a fleet pilot driving a parked berth). Template-only units (researched
## blueprints with no seated driver) no longer fight by themselves — a unit only
## fields once a pilot is assigned to a mech.
##
## The page lists every piloted berth (mech + pilot + archetype + HP/status)
## with a FIELDED / STANDING DOWN toggle. The toggle drives the pilot's fleet
## unit `fielded` flag (single source of truth shared with the intermission
## fleet panel), and wounded/destroyed pilots are locked like everywhere else.

var controller  # hangar_controller.gd

var sortie_panel: PanelContainer = null
var sortie_list: VBoxContainer = null
var sortie_status_label: Label = null

var _archetype_names := [
	"Rusher", "Ranged", "Heavy", "Support",
]


func build(root: Control) -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_top = 128
	panel.offset_bottom = -20
	panel.offset_left = 20
	panel.custom_minimum_size = Vector2(540, 0)
	panel.visible = false
	sortie_panel = panel
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
	title.text = "SORTIE (เลือกคนลงสนาม)"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	box.add_child(title)

	var desc = Label.new()
	desc.text = "Who tags along into the next battle. ONLY piloted hangar mechs can field — assign a pilot from the ROSTER page, then flag them here. FIELDED units spawn beside you in combat; STANDING DOWN stay parked."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	box.add_child(desc)

	var sep = HSeparator.new()
	box.add_child(sep)

	sortie_list = VBoxContainer.new()
	sortie_list.add_theme_constant_override("separation", 6)
	sortie_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sortie_list)

	sortie_status_label = Label.new()
	sortie_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sortie_status_label.add_theme_font_size_override("font_size", 11)
	box.add_child(sortie_status_label)


func set_panel_visible(v: bool) -> void:
	if sortie_panel:
		sortie_panel.visible = v


func show_page() -> void:
	set_panel_visible(true)
	refresh()


func hide_page() -> void:
	set_panel_visible(false)


# Rebuilds the sortie rows from the single source of truth: every hangar berth
# with a pilot seated (the active/player mech is the machine the player pilots
# and is not a tag-along ally, so it is listed but read-only).
func refresh() -> void:
	if sortie_list == null:
		return
	for child in sortie_list.get_children():
		child.queue_free()

	var active_id := str(HangarManager.get_active_mech().get("id", ""))
	var piloted_count := 0
	var fielded_count := 0
	for mech in HangarManager.get_mechs():
		if not (mech is Dictionary):
			continue
		var pilot_id := str(mech.get("pilot", ""))
		if pilot_id == "":
			continue
		var is_active := str(mech.get("id", "")) == active_id
		piloted_count += 1
		var fielded := is_active
		if pilot_id.begins_with("fleet_"):
			var unit := FleetSystem.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
			fielded = is_active or bool(unit.get("fielded", true))
			if is_active:
				fielded_count += 1
			elif fielded and not bool(unit.get("destroyed", false)) and not bool(unit.get("wounded", false)):
				fielded_count += 1
		elif is_active:
			# The player's own mech is always on the field.
			fielded_count += 1
		_build_row(mech, pilot_id, is_active, fielded)

	if sortie_status_label:
		var capacity := HangarManager.get_capacity()
		sortie_status_label.text = "%d/%d berths filled · %d mech%s on sortie\nAssign pilots via the ROSTER page, then toggle who fields here." % [
			piloted_count, capacity,
			fielded_count, "s" if fielded_count != 1 else "",
		]


func _build_row(mech: Dictionary, pilot_id: String, is_active: bool, fielded: bool) -> void:
	var mech_id := str(mech.get("id", ""))
	var archetype := HangarManager.get_archetype(mech_id)
	var archetype_name: String = _archetype_names[clampi(archetype, 0, 3)]
	var destroyed := false
	var wounded := false
	var hp_text := ""
	if pilot_id.begins_with("fleet_"):
		var unit := FleetSystem.get_fleet_unit(pilot_id.trim_prefix("fleet_"))
		destroyed = bool(unit.get("destroyed", false))
		wounded = bool(unit.get("wounded", false))
		var hp := float(unit.get("hp", 0.0))
		var max_hp := float(unit.get("max_hp", 0.0))
		hp_text = "%d/%d HP" % [int(hp), int(max_hp)]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	sortie_list.add_child(row)

	var marker := ""
	if is_active:
		marker = "★ "
	elif destroyed:
		marker = "⛔ "
	elif wounded:
		marker = "⚠ "

	var name_lbl := Label.new()
	name_lbl.text = "%s%s · %s [%s] %s" % [
		marker,
		str(mech.get("name", "Mech")),
		HangarManager.get_pilot_name(pilot_id),
		archetype_name,
		hp_text,
	]
	name_lbl.custom_minimum_size = Vector2(300, 0)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color",
		Color(1.0, 0.5, 0.5) if destroyed or wounded else Color(0.85, 0.9, 0.95))
	row.add_child(name_lbl)

	# The player's active mech is always in the field (they pilot it) — shown
	# as a read-only badge, no toggle.
	if is_active:
		var badge := Button.new()
		badge.text = "★ PILOTED"
		badge.disabled = true
		badge.custom_minimum_size = Vector2(110, 28)
		badge.focus_mode = Control.FOCUS_NONE
		badge.tooltip_text = "This is the mech you pilot — always on the field."
		row.add_child(badge)
		return

	# A parked berth piloted by the player (only possible outside the active
	# mech) has no fleet-unit flag to toggle — show it read-only.
	if pilot_id == HangarManager.PLAYER_PILOT_ID:
		var player_badge := Button.new()
		player_badge.text = "PLAYER BERTH"
		player_badge.disabled = true
		player_badge.custom_minimum_size = Vector2(130, 28)
		player_badge.focus_mode = Control.FOCUS_NONE
		player_badge.tooltip_text = "This berth is piloted by you — it does not field as a separate ally."
		row.add_child(player_badge)
		return

	var toggle := Button.new()
	if fielded:
		toggle.text = "FIELDED"
		toggle.pressed.connect(func(): _set_fielded(mech_id, pilot_id, false))
	else:
		toggle.text = "STANDING DOWN"
		toggle.pressed.connect(func(): _set_fielded(mech_id, pilot_id, true))
	toggle.custom_minimum_size = Vector2(130, 28)
	toggle.focus_mode = Control.FOCUS_NONE
	if destroyed:
		toggle.disabled = true
		toggle.tooltip_text = "This pilot was lost in combat — their mech cannot field."
	elif wounded:
		toggle.disabled = true
		toggle.tooltip_text = "WOUNDED — recovering. Cannot field until healed (HEAL on the roster page)."
	else:
		toggle.tooltip_text = "FIELDED: spawns beside you in combat. STANDING DOWN: stays parked in the hangar."
	row.add_child(toggle)


func _set_fielded(mech_id: String, pilot_id: String, fielded: bool) -> void:
	if not pilot_id.begins_with("fleet_"):
		return
	var template_id := pilot_id.trim_prefix("fleet_")
	FleetSystem.set_unit_fielded(template_id, fielded)
	GlobalData.save_run()
	if controller and controller.status_message_label:
		var unit := FleetSystem.get_fleet_unit(template_id)
		var unit_name := str(unit.get("name", HangarManager.get_pilot_name(pilot_id)))
		controller.status_message_label.text = "%s is %s." % [
			unit_name,
			"FIELDED (will fight alongside you)" if fielded else "STANDING DOWN (will stay parked)",
		]
	refresh()
