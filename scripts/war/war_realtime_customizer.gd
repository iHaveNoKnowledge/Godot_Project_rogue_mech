extends CanvasLayer
class_name WarRealtimeCustomizer

## Realtime Mecha Customization Overlay in the Field / Hangar Bay
## Uses existing PartMeshManager and ArmorCatalog architecture without cutting to campaign hangar.
## Allows live swapping of Head, Body, Arms, Legs, and Backpack while standing in the world.

signal closed

var mecha_ref: Node = null
var _selected_slot: String = "body"

var _panel: PanelContainer
var _slot_button_container: VBoxContainer
var _parts_list_container: VBoxContainer
var _stats_label: Label
var _active_slot_label: Label


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_find_player_mecha()
	_build_ui()
	_select_slot("body")
	_update_stats()


func _find_player_mecha() -> void:
	if mecha_ref != null and is_instance_valid(mecha_ref):
		return
	if GameManager and GameManager.has_method("get_player_mecha"):
		mecha_ref = GameManager.get_player_mecha()
	if mecha_ref == null:
		var mechas := get_tree().get_nodes_in_group("player") if get_tree() else []
		if mechas.is_empty():
			mechas = get_tree().get_nodes_in_group("mecha") if get_tree() else []
		for m in mechas:
			if m is CharacterBody3D and m.get_node_or_null("PartMeshManager") != null:
				mecha_ref = m
				break


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(880, 560)
	_panel.offset_left = -440
	_panel.offset_right = 440
	_panel.offset_top = -280
	_panel.offset_bottom = 280

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.65, 0.95, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(main_vbox)

	# --- Header ---
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "VALKREN FIELD WORKSHOP — REALTIME MECHA CUSTOMIZER"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = " [X] EXIT HANGAR "
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)
	main_vbox.add_child(header)

	var sub_label := Label.new()
	sub_label.text = "Live Fitting: Parts instantly equip onto your frame in the field. (Press ESC or F to exit)"
	sub_label.add_theme_font_size_override("font_size", 11)
	sub_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	main_vbox.add_child(sub_label)

	main_vbox.add_child(HSeparator.new())

	# --- Body Columns: Slots (Left), Parts Catalog (Center), Stats (Right) ---
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(body_hbox)

	# Left Column: Slot Buttons
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(180, 0)
	left_col.add_theme_constant_override("separation", 8)
	body_hbox.add_child(left_col)

	var slot_header := Label.new()
	slot_header.text = "FRAME SLOTS"
	slot_header.add_theme_font_size_override("font_size", 13)
	slot_header.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	left_col.add_child(slot_header)

	_slot_button_container = VBoxContainer.new()
	_slot_button_container.add_theme_constant_override("separation", 6)
	left_col.add_child(_slot_button_container)

	for slot in ["head", "body", "arm_left", "arm_right", "legs", "backpack"]:
		var btn := Button.new()
		btn.text = slot.replace("_", " ").to_upper()
		btn.name = "SlotBtn_%s" % slot
		btn.custom_minimum_size = Vector2(170, 36)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func(): _select_slot(slot))
		_slot_button_container.add_child(btn)

	# Center Column: Available Parts for Slot
	var center_col := VBoxContainer.new()
	center_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_col.add_theme_constant_override("separation", 8)
	body_hbox.add_child(center_col)

	_active_slot_label = Label.new()
	_active_slot_label.text = "AVAILABLE PARTS"
	_active_slot_label.add_theme_font_size_override("font_size", 13)
	_active_slot_label.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	center_col.add_child(_active_slot_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_col.add_child(scroll)

	_parts_list_container = VBoxContainer.new()
	_parts_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts_list_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_parts_list_container)

	# Right Column: Diagnostics & Specs
	var right_col := VBoxContainer.new()
	right_col.custom_minimum_size = Vector2(220, 0)
	right_col.add_theme_constant_override("separation", 8)
	body_hbox.add_child(right_col)

	var diag_header := Label.new()
	diag_header.text = "MECHA DIAGNOSTICS"
	diag_header.add_theme_font_size_override("font_size", 13)
	diag_header.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	right_col.add_child(diag_header)

	var stats_panel := PanelContainer.new()
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var st_box := StyleBoxFlat.new()
	st_box.bg_color = Color(0.04, 0.05, 0.08, 0.8)
	st_box.border_width_left = 1
	st_box.border_width_top = 1
	st_box.border_width_right = 1
	st_box.border_width_bottom = 1
	st_box.border_color = Color(0.2, 0.3, 0.4, 0.8)
	st_box.content_margin_left = 10
	st_box.content_margin_right = 10
	st_box.content_margin_top = 10
	st_box.content_margin_bottom = 10
	stats_panel.add_theme_stylebox_override("panel", st_box)
	right_col.add_child(stats_panel)

	_stats_label = Label.new()
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.add_theme_font_size_override("font_size", 11)
	stats_panel.add_child(_stats_label)


func _select_slot(slot: String) -> void:
	_selected_slot = slot
	_active_slot_label.text = "AVAILABLE FOR: %s" % slot.replace("_", " ").to_upper()

	# Clear parts list
	for child in _parts_list_container.get_children():
		child.queue_free()

	var catalog: Dictionary = GlobalData.armor_catalog if (GlobalData and "armor_catalog" in GlobalData) else {}
	var parts: Array = catalog.get(slot, [])

	# Check currently equipped part ID
	var equipped_id := ""
	if GlobalData and GlobalData.weapons and GlobalData.weapons.equipped_parts:
		var eq = GlobalData.weapons.equipped_parts.get(slot, {})
		if eq is Dictionary:
			equipped_id = str(eq.get("id", eq.get("uid", "")))
		elif eq is Resource and "id" in eq:
			equipped_id = str(eq.id)

	if parts.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No compatible parts registered in database."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		_parts_list_container.add_child(empty_lbl)
		return

	for entry in parts:
		if not (entry is Dictionary):
			continue
		var part_id: String = str(entry.get("id", ""))
		var part_name: String = str(entry.get("name", part_id))
		var part_hp: float = float(entry.get("hp", 0.0))
		var part_arm: float = float(entry.get("armor", 0.0))
		var part_wt: float = float(entry.get("weight", 0.0))
		var part_type: String = str(entry.get("type", "Standard"))

		var is_equipped: bool = (part_id == equipped_id)

		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.10, 0.13, 0.18, 0.9) if is_equipped else Color(0.08, 0.10, 0.14, 0.8)
		card_style.border_width_left = 2 if is_equipped else 1
		card_style.border_color = Color(0.2, 0.8, 0.4) if is_equipped else Color(0.2, 0.35, 0.5)
		card_style.content_margin_left = 8
		card_style.content_margin_right = 8
		card_style.content_margin_top = 6
		card_style.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", card_style)

		var card_hbox := HBoxContainer.new()
		card_hbox.add_theme_constant_override("separation", 10)
		card.add_child(card_hbox)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_hbox.add_child(info_vbox)

		var name_lbl := Label.new()
		name_lbl.text = "%s %s" % [part_name, "[EQUIPPED]" if is_equipped else ""]
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5) if is_equipped else Color(0.9, 0.92, 0.95))
		info_vbox.add_child(name_lbl)

		var stats_lbl := Label.new()
		stats_lbl.text = "Type: %s | HP: +%.0f | Armor: +%.0f | Weight: %.1ft" % [part_type, part_hp, part_arm, part_wt]
		stats_lbl.add_theme_font_size_override("font_size", 10)
		stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.82))
		info_vbox.add_child(stats_lbl)

		var equip_btn := Button.new()
		equip_btn.text = "EQUIPPED" if is_equipped else "EQUIP"
		equip_btn.disabled = is_equipped
		equip_btn.custom_minimum_size = Vector2(80, 30)
		equip_btn.pressed.connect(func(): _equip_part(slot, entry))
		card_hbox.add_child(equip_btn)

		_parts_list_container.add_child(card)


func _equip_part(slot: String, part_dict: Dictionary) -> void:
	_find_player_mecha()
	if mecha_ref == null:
		return

	var pmm = mecha_ref.get_node_or_null("PartMeshManager")
	if pmm and pmm.has_method("build_part_for_slot") and pmm.has_method("initialize_slot"):
		var part = pmm.build_part_for_slot(part_dict)
		pmm.initialize_slot(slot, part, false)
		WarFactionVisual.apply_team_tint(mecha_ref, "friendly")

	# Save to persistent storage if available
	if GlobalData and GlobalData.weapons and GlobalData.weapons.equipped_parts:
		GlobalData.weapons.equipped_parts[slot] = part_dict

	if AudioManager and AudioManager.has_method("play_ui_click"):
		AudioManager.play_ui_click()

	_select_slot(slot)
	_update_stats()


func _update_stats() -> void:
	_find_player_mecha()
	if not _stats_label:
		return

	var total_hp: float = 0.0
	var total_arm: float = 0.0
	var total_wt: float = 0.0

	var catalog: Dictionary = GlobalData.armor_catalog if (GlobalData and "armor_catalog" in GlobalData) else {}
	for slot in ["head", "body", "arm_left", "arm_right", "legs", "backpack"]:
		var p_id := ""
		if GlobalData and GlobalData.weapons and GlobalData.weapons.equipped_parts:
			var eq = GlobalData.weapons.equipped_parts.get(slot, {})
			if eq is Dictionary:
				p_id = str(eq.get("id", eq.get("uid", "")))
			elif eq is Resource and "id" in eq:
				p_id = str(eq.id)
		var parts: Array = catalog.get(slot, [])
		for p in parts:
			if str(p.get("id", "")) == p_id:
				total_hp += float(p.get("hp", 0.0))
				total_arm += float(p.get("armor", 0.0))
				total_wt += float(p.get("weight", 0.0))
				break

	if total_hp <= 0.0:
		total_hp = 320.0
		total_arm = 140.0
		total_wt = 28.5

	var speed_rating := "MEDIUM VALKREN"
	if total_wt < 22.0:
		speed_rating = "STRIKE-APEX (FAST)"
	elif total_wt > 35.0:
		speed_rating = "IRON-VANGUARD (HEAVY)"

	_stats_label.text = """CHASSIS SPECS:
Valkren Tactical Combat Frame

FRAME INTEGRITY:
  Total HP: %.0f
  Total Armor: %.0f

WEIGHT & MOBILITY:
  Displacement: %.1f Tons
  Mobility Class: %s

STATUS:
  Operational in Field
  Reactor Online (100%%)
""" % [total_hp, total_arm, total_wt, speed_rating]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		_close()


func _close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()
	queue_free()
