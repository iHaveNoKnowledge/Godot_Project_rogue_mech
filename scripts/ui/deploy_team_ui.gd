extends CanvasLayer

## DEPLOY SQUAD — pre-combat team selection shown on the board when the player
## runs into enemies (patrol fleets, combat tiles, enemy bases). Lists every
## parked hangar mech with its pilot, role and fielded toggle, so the player
## decides WHO tags into the fight instead of the game silently fielding (or
## skipping) roster mechs. Confirming applies the toggles and enters combat.

var _panel: PanelContainer
var _title_label: Label
var _roster_box: VBoxContainer
var _status_label: Label
var _confirm_button: Button
var _cancel_button: Button

var _pending_combat_type: String = "grunt"
var _pending_toggles: Dictionary = {}  # template_id -> CheckButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -320
	_panel.offset_right = 320
	_panel.offset_top = -260
	_panel.offset_bottom = 260
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.13, 0.97)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.8, 0.3, 0.2, 0.9)
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "DEPLOY SQUAD"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	vbox.add_child(_title_label)

	var desc := Label.new()
	desc.text = "Enemy contact! Choose which hangar mechs tag into the battle.\nThe piloted (active) mech always fights — parked mechs need a seated pilot to field."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	vbox.add_child(desc)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 6)
	_roster_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_roster_box)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	_confirm_button = Button.new()
	_confirm_button.text = "DEPLOY — FIGHT!"
	_confirm_button.custom_minimum_size = Vector2(180, 40)
	_confirm_button.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_button)

	_cancel_button = Button.new()
	_cancel_button.text = "CANCEL"
	_cancel_button.custom_minimum_size = Vector2(120, 40)
	_cancel_button.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_button)


# True when at least one NON-active hangar mech has a seated pilot — i.e. there
# is a decision to make about who fields. Solo convoys skip the deploy screen.
func has_ally_candidates() -> bool:
	for mech in HangarManager.get_mechs():
		if not (mech is Dictionary):
			continue
		if str(mech.get("id", "")) == GlobalData.hangar.active_hangar_mech_id:
			continue
		if str(mech.get("pilot", "")) != "":
			return true
	return false


# Opens the deploy screen for the given combat type and pauses the board.
func open_deploy(combat_type: String) -> void:
	_pending_combat_type = combat_type
	_pending_toggles.clear()
	_repopulate_roster()
	visible = true
	if get_tree():
		get_tree().paused = true
	_confirm_button.grab_focus()


func _repopulate_roster() -> void:
	for child in _roster_box.get_children():
		child.queue_free()
	_pending_toggles.clear()

	_title_label.text = "DEPLOY SQUAD — %s" % _pending_combat_type.to_upper()

	var mechs := HangarManager.get_mechs()
	mechs.sort_custom(func(a, b): return int(a.get("slot", 99)) < int(b.get("slot", 99)))

	var active_id := str(GlobalData.hangar.active_hangar_mech_id)
	var fielded_count := 0
	for mech in mechs:
		if not (mech is Dictionary):
			continue
		var mech_id := str(mech.get("id", ""))
		var mech_name := str(mech.get("name", "Mech"))
		var pilot_id := str(mech.get("pilot", ""))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_roster_box.add_child(row)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(220, 0)
		name_label.add_theme_font_size_override("font_size", 14)
		row.add_child(name_label)

		var info_label := Label.new()
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_label.add_theme_font_size_override("font_size", 12)
		row.add_child(info_label)

		if mech_id == active_id:
			name_label.text = "★ %s" % mech_name
			name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
			info_label.text = "YOU — piloted mech (always fights)"
			info_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
			continue

		var pilot_name := HangarManager.get_pilot_name(pilot_id)
		# Indexing an untyped array literal yields Variant, so `:=` can't infer
		# the type — annotate explicitly.
		var role_label: String = ["RUSHER", "RANGED", "HEAVY", "SUPPORT"][clampi(HangarManager.get_archetype(mech_id), 0, 3)]
		var status := HangarManager.get_pilot_status(pilot_id)

		if pilot_id == "":
			name_label.text = mech_name
			name_label.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
			info_label.text = "NO PILOT — assign one in the hangar to field this mech"
			info_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
			continue

		# Fleet pilots map to a fleet unit (fielded/wounded/destroyed live there).
		var template_id := pilot_id.trim_prefix("fleet_")
		var unit := FleetSystem.get_fleet_unit(template_id)
		var can_field := pilot_id == HangarManager.PLAYER_PILOT_ID or not unit.is_empty()
		var fielded := true
		if not unit.is_empty():
			fielded = bool(unit.get("fielded", true))
			can_field = not bool(unit.get("destroyed", false)) and not bool(unit.get("wounded", false))

		var check := CheckButton.new()
		check.text = "FIELD"
		check.custom_minimum_size = Vector2(70, 0)
		check.disabled = not can_field
		check.button_pressed = fielded and can_field
		if fielded and can_field:
			fielded_count += 1
		if can_field:
			check.toggled.connect(_on_toggle_changed.bind(template_id))
			_pending_toggles[template_id] = check
		else:
			# Disabled checkbox keeps the check state (or shows ⛔ for a lost pilot).
			check.button_pressed = false
		row.add_child(check)

		name_label.text = mech_name
		name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
		var note := ""
		if not can_field:
			note = " — cannot field"
			if not unit.is_empty():
				if bool(unit.get("destroyed", false)):
					note = " — DESTROYED pilot"
				elif bool(unit.get("wounded", false)):
					note = " — wounded, recovering"
		info_label.text = "PILOT: %s%s · ROLE: %s%s" % [pilot_name, status, role_label, note]
		info_label.add_theme_color_override("font_color",
			Color(0.55, 0.8, 1.0) if can_field else Color(0.6, 0.4, 0.4))

	_status_label.text = "Fielded: %d ally mech(s) will fight beside you." % fielded_count


func _on_toggle_changed(_pressed: bool, template_id: String) -> void:
	var count := 0
	for key in _pending_toggles:
		if _pending_toggles[key].button_pressed:
			count += 1
	if _status_label:
		_status_label.text = "Fielded: %d ally mech(s) will fight beside you." % count


func _on_confirm() -> void:
	if not is_inside_tree():
		return
	# Apply the chosen fielded flags (source of truth shared with the hangar
	# SORTIE page and the intermission fleet panel).
	for template_id in _pending_toggles:
		var check: CheckButton = _pending_toggles[template_id]
		FleetSystem.set_unit_fielded(template_id, check.button_pressed)
	GlobalData.save_run()
	visible = false
	if get_tree():
		get_tree().paused = false
	GameManager.enter_combat(_pending_combat_type)


func _on_cancel() -> void:
	if not is_inside_tree():
		return
	visible = false
	if get_tree():
		get_tree().paused = false
	# The patrol the player stepped onto is NOT consumed by cancelling — they
	# can back away or re-engage by stepping on it again.
	GlobalData.board.board_patrol_engagement = -1
