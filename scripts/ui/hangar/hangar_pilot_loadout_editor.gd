class_name HangarPilotLoadoutEditor
extends CanvasLayer

## PILOT LOADOUT editor (opened from a pilot row's LOADOUT button). Manages the
## pilot's PERSONAL gear — the weapons / ammo / items they carry on their body
## when out of the mech — completely separate from any berth's weapon loadout:
##   - Equip/unequip personal weapons from the depot weapon stash
##   - Top up personal ammo from the convoy's ammo reserve
##   - View / use healing items (medkits)
## All state goes through PilotSystem so the hangar and the eject-combat pilot
## share one source of truth.

var controller  # hangar_controller.gd
var _pilot_id: String = ""
var _root: Control = null
var _weapon_list: VBoxContainer = null
var _ammo_label: Label = null
var _item_label: Label = null
var _status_label: Label = null


func open(pilot_id: String, pilot_name: String) -> void:
	_pilot_id = pilot_id
	visible = true
	if _root == null:
		_build_ui()
	_refresh_ui()
	if _status_label:
		_status_label.text = "Editing %s's personal loadout (what they carry on foot)." % pilot_name


func close() -> void:
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = -280
	panel.offset_bottom = 280
	_root.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.16, 0.97)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 1.0, 0.5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PILOT LOADOUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "Personal gear for when this pilot fights on foot (out of the mech): weapons, personal ammo, and healing items. Separate from any mech's loadout."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 11)
	vbox.add_child(desc)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var section := Label.new()
	section.text = "PERSONAL WEAPONS (click to equip/unequip)"
	section.add_theme_font_size_override("font_size", 13)
	section.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vbox.add_child(section)

	var budget_label := Label.new()
	budget_label.name = "BudgetLabel"
	budget_label.add_theme_font_size_override("font_size", 12)
	budget_label.add_theme_color_override("font_color", Color(0.75, 0.9, 0.75))
	vbox.add_child(budget_label)

	var weapon_scroll := ScrollContainer.new()
	weapon_scroll.custom_minimum_size = Vector2(0, 180)
	weapon_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(weapon_scroll)

	_weapon_list = VBoxContainer.new()
	_weapon_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_list.add_theme_constant_override("separation", 4)
	weapon_scroll.add_child(_weapon_list)

	var ammo_title := Label.new()
	ammo_title.text = "PERSONAL AMMO (top up from convoy reserve)"
	ammo_title.add_theme_font_size_override("font_size", 13)
	ammo_title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vbox.add_child(ammo_title)

	_ammo_label = Label.new()
	_ammo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ammo_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_ammo_label)

	var item_title := Label.new()
	item_title.text = "HEALING ITEMS"
	item_title.add_theme_font_size_override("font_size", 13)
	item_title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vbox.add_child(item_title)

	_item_label = Label.new()
	_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_item_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox.add_child(_status_label)

	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 32)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)


func _refresh_ui() -> void:
	if _weapon_list == null:
		return
	for child in _weapon_list.get_children():
		child.queue_free()

	# --- Carry budget readout: X / 7 points spent (big=3, medium=2, small=1).
	var budget_label := _find_budget_label()
	if budget_label:
		budget_label.text = "CARRY POINTS: %d / %d used  (%d left)" % [
			PilotSystem.get_pilot_carry_used(),
			PilotSystem.get_pilot_carry_points(),
			PilotSystem.get_pilot_carry_remaining(),
		]

	# --- Weapons: the PILOT WEAPON DATABASE is the only gear a pilot can carry
	# on foot (mech weapons are never equipable here). Each row shows its size
	# and point cost; equipping is blocked when it would exceed the budget.
	var equipped_paths: Array = []
	for path in GlobalData.pilot_weapons:
		equipped_paths.append(str(path))

	var added_weapons := 0
	for entry in PilotSystem.get_pilot_weapon_db():
		var wpath := str(entry.get("path", ""))
		if wpath == "" or not ResourceLoader.exists(wpath):
			continue
		var res = load(wpath)
		if not (res is WeaponPart):
			continue
		added_weapons += 1
		var is_eq := wpath in equipped_paths
		var size := str(entry.get("size", "?"))
		var points := int(entry.get("points", 0))
		var fits := PilotSystem.can_equip_pilot_weapon(wpath)
		var row := Button.new()
		row.text = ("[E] " if is_eq else "    ") + str(res.weapon_name) + "  [%s %dp]" % [size.capitalize(), points]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.disabled = not is_eq and not fits
		row.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if is_eq else Color(0.85, 0.9, 0.95))
		if not is_eq and not fits:
			row.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
		row.tooltip_text = "Personal weapon carried on foot. Click to %s." % ("unequip" if is_eq else "equip")
		row.pressed.connect(_toggle_weapon.bind(wpath))
		_weapon_list.add_child(row)
	if added_weapons == 0:
		var empty := Label.new()
		empty.text = "No pilot weapons available."
		empty.add_theme_font_size_override("font_size", 11)
		_weapon_list.add_child(empty)

	# --- Ammo: per-type personal ammo with a top-up button drawing from the
	# convoy's ammo reserve (the same reserve the mech loadout draws from).
	var ammo_rows := VBoxContainer.new()
	ammo_rows.add_theme_constant_override("separation", 4)
	_ammo_label.add_child(ammo_rows)
	for ammo_type in ["kinetic", "energy", "explosive", "missile"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		ammo_rows.add_child(row)
		var info := Label.new()
		info.custom_minimum_size = Vector2(200, 0)
		info.text = "%s: %d" % [ammo_type.capitalize(), PilotSystem.get_ammo(ammo_type)]
		info.add_theme_font_size_override("font_size", 11)
		row.add_child(info)
		var reserve := LoadoutSystem.get_reserve_ammo(ammo_type)
		var topup := Button.new()
		topup.text = "+20 (reserve: %d)" % reserve
		topup.custom_minimum_size = Vector2(140, 24)
		topup.focus_mode = Control.FOCUS_NONE
		topup.disabled = reserve <= 0
		topup.pressed.connect(_top_up_ammo.bind(ammo_type))
		row.add_child(topup)

	# --- Items: healing items in the pilot's inventory; USE spends one.
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 4)
	_item_label.add_child(items)
	var any_items := false
	for item in PilotSystem.get_items():
		var item_id := str(item.get("id", ""))
		var def := PilotSystem.get_heal_item(item_id)
		if def.is_empty():
			continue
		any_items = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		items.add_child(row)
		var info := Label.new()
		info.custom_minimum_size = Vector2(260, 0)
		info.text = "%s x%d — %s" % [def.get("name", item_id), int(item.get("count", 0)), def.get("desc", "")]
		info.add_theme_font_size_override("font_size", 11)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		var use_btn := Button.new()
		use_btn.text = "USE"
		use_btn.custom_minimum_size = Vector2(56, 24)
		use_btn.focus_mode = Control.FOCUS_NONE
		use_btn.pressed.connect(_use_item.bind(item_id))
		row.add_child(use_btn)
	if not any_items:
		var empty := Label.new()
		empty.text = "No healing items. Buy medkits at city nodes."
		empty.add_theme_font_size_override("font_size", 11)
		items.add_child(empty)


func _toggle_weapon(wpath: String) -> void:
	var is_eq := GlobalData.pilot_weapons.has(wpath)
	if is_eq:
		PilotSystem.remove_weapon(wpath)
		if _status_label:
			_status_label.text = "Weapon unequipped."
	else:
		if PilotSystem.add_weapon(wpath):
			if _status_label:
				_status_label.text = "Weapon equipped as a personal sidearm."
		else:
			if _status_label:
				_status_label.text = "Cannot equip: over the carry point budget (%d/%d)." % [
					PilotSystem.get_pilot_carry_used(),
					PilotSystem.get_pilot_carry_points(),
				]
	GlobalData.save_run()
	_refresh_ui()


# Finds the carry-points label wherever the built tree put it (panel layout
# may vary across versions).
func _find_budget_label() -> Label:
	if _root == null:
		return null
	var found: Array = []
	_find_label_named(_root, "BudgetLabel", found)
	return found[0] if not found.is_empty() else null


func _find_label_named(node: Node, label_name: String, out: Array) -> void:
	for child in node.get_children():
		if child is Label and child.name == label_name:
			out.append(child)
			return
		_find_label_named(child, label_name, out)


func _top_up_ammo(ammo_type: String) -> void:
	var amount := mini(20, LoadoutSystem.get_reserve_ammo(ammo_type))
	if amount <= 0:
		return
	LoadoutSystem.consume_reserve_ammo(ammo_type, amount)
	PilotSystem.add_ammo(ammo_type, amount)
	if _status_label:
		_status_label.text = "+%d %s ammo moved to the pilot's personal reserve." % [amount, ammo_type]
	GlobalData.save_run()
	_refresh_ui()


func _use_item(item_id: String) -> void:
	var restored := PilotSystem.use_heal_item(item_id)
	if _status_label:
		if restored > 0.0:
			_status_label.text = "Healed %d HP." % int(restored)
		else:
			_status_label.text = "Could not use that item now (already full HP?)."
	GlobalData.save_run()
	_refresh_ui()
