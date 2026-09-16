extends CanvasLayer

## Tactical Field Loot & Salvage Modal (Real-time in Battle)
## Layout:
##   - Left Panel: Ground Loot & Salvage (within 6.0m) with Unload Ammo & Convoy Tag (Sandwich Triangle 📐/🔺)
##   - Right Panel:
##       - Top Row (Compact): [Left Hand] | [Right Hand] side-by-side
##       - Bottom Section: Field Pack Carrier (Backpack) with live weight limit preview & reordering
##   - Ultra-smooth Drag & Drop / Swap system across Ground, Hands, and Carrier Pack.

signal closed

const WeaponPickupScript = preload("res://scripts/mecha/weapon_pickup.gd")

var is_open: bool = false
var player_entity: Node3D = null

# UI Elements
var root_control: Control
var left_panel: PanelContainer
var left_content_box: VBoxContainer
var right_panel: PanelContainer
var right_content_box: VBoxContainer
var ground_list_container: VBoxContainer
var left_hand_card: PanelContainer
var right_hand_card: PanelContainer
var carrier_list_container: VBoxContainer
var weight_bar: ProgressBar
var weight_label: Label
var close_button: Button
var ammo_hbox: HBoxContainer = null

# Drag & Drop State
var _drag_data: Dictionary = {}
var _drag_ghost: PanelContainer = null
var _hovered_drop_target: String = "" # "ground", "hand_left", "hand_right", "carrier"
var _carrier_hover_idx: int = -1

# Color Palette (Cyberpunk Tactical Glass)
const BG_GLASS = Color(0.04, 0.07, 0.12, 0.88)
const ACCENT_CYAN = Color(0.18, 0.84, 0.95)
const ACCENT_AMBER = Color(1.0, 0.72, 0.15)
const ACCENT_GREEN = Color(0.25, 0.90, 0.40)
const ACCENT_RED = Color(0.95, 0.28, 0.25)
const CARD_BG = Color(0.08, 0.13, 0.20, 0.92)
const CARD_BG_HOVER = Color(0.12, 0.20, 0.30, 0.95)


func _ready() -> void:
	layer = 75
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F or event.keycode == KEY_ESCAPE or event.is_action_pressed("pause"):
			get_viewport().set_input_as_handled()
			close_modal()


func _process(delta: float) -> void:
	if not is_open or not visible:
		return
	_update_drag_ghost_position()


func open_modal(player: Node3D = null) -> void:
	if player != null:
		player_entity = player
	else:
		player_entity = GameManager.get_player_mecha()
		if player_entity == null:
			player_entity = get_tree().get_first_node_in_group("pilot")

	is_open = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_all()


func close_modal() -> void:
	_cancel_drag()
	is_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _create_ui() -> void:
	root_control = Control.new()
	root_control.name = "LootRoot"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_control)

	# Main Backdrop Dimmer (subtle dark vignette)
	var backdrop = ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.02, 0.05, 0.65)
	backdrop.mouse_filter = Control.MOUSE_FILTER_PASS
	root_control.add_child(backdrop)

	# Main Container (HBox for Left Panel & Right Panel)
	var main_margin = MarginContainer.new()
	main_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_margin.add_theme_constant_override("margin_left", 60)
	main_margin.add_theme_constant_override("margin_right", 60)
	main_margin.add_theme_constant_override("margin_top", 40)
	main_margin.add_theme_constant_override("margin_bottom", 40)
	root_control.add_child(main_margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	main_margin.add_child(main_vbox)

	# Top Header Bar (Title + Close Button)
	var header_bar = HBoxContainer.new()
	var title_lbl = Label.new()
	title_lbl.text = "FIELD LOOT & SALVAGE  //  การจัดการยุทโธปกรณ์ในสนามรบ"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
	header_bar.add_child(title_lbl)

	var sub_lbl = Label.new()
	sub_lbl.text = "  [Hardcore Real-Time Mode]"
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	header_bar.add_child(sub_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_bar.add_child(spacer)

	close_button = Button.new()
	close_button.text = " RESUME COMBAT [F / ESC] "
	close_button.custom_minimum_size = Vector2(180, 36)
	close_button.add_theme_font_size_override("font_size", 14)
	close_button.pressed.connect(close_modal)
	_style_cyber_button(close_button, ACCENT_AMBER)
	header_bar.add_child(close_button)

	main_vbox.add_child(header_bar)

	# Columns Split (Left: Ground, Right: Hands + Carrier)
	var hsplit = HBoxContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 24)
	main_vbox.add_child(hsplit)

	# LEFT PANEL: Ground Salvage
	var left_res = _build_panel_frame("GROUND SALVAGE (ซากอาวุธ/ของบนพื้น)", ACCENT_AMBER)
	left_panel = left_res["panel"]
	left_content_box = left_res["content"]
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.45
	hsplit.add_child(left_panel)

	var ground_scroll = ScrollContainer.new()
	ground_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ground_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ground_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	left_content_box.add_child(ground_scroll)

	ground_list_container = VBoxContainer.new()
	ground_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground_list_container.add_theme_constant_override("separation", 10)
	ground_list_container.mouse_filter = Control.MOUSE_FILTER_PASS
	ground_scroll.add_child(ground_list_container)

	# Setup drop detection on left panel (Drop to ground)
	left_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	left_panel.mouse_entered.connect(func(): _hovered_drop_target = "ground")
	left_panel.mouse_exited.connect(func(): if _hovered_drop_target == "ground": _hovered_drop_target = "")

	# RIGHT PANEL: Player Loadout (Hands on top row, Carrier below)
	var right_res = _build_panel_frame("OPERATIONAL LOADOUT (อาวุธหุ่น & สัมภาระ)", ACCENT_CYAN)
	right_panel = right_res["panel"]
	right_content_box = right_res["content"]
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.55
	hsplit.add_child(right_panel)

	right_content_box.add_theme_constant_override("separation", 14)

	# --- TOP ROW: Equipped Hands (Left | Right) ---
	var hands_sec_lbl = Label.new()
	hands_sec_lbl.text = "EQUIPPED HANDS (อาวุธที่กำลังถือในมือ)"
	hands_sec_lbl.add_theme_font_size_override("font_size", 13)
	hands_sec_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	right_content_box.add_child(hands_sec_lbl)

	var hands_hbox = HBoxContainer.new()
	hands_hbox.custom_minimum_size = Vector2(0, 85) # Compact height
	hands_hbox.add_theme_constant_override("separation", 14)
	right_content_box.add_child(hands_hbox)

	left_hand_card = _build_hand_slot_card("LEFT HAND (มือซ้าย)")
	left_hand_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_hand_card.mouse_entered.connect(func(): _hovered_drop_target = "hand_left")
	left_hand_card.mouse_exited.connect(func(): if _hovered_drop_target == "hand_left": _hovered_drop_target = "")
	hands_hbox.add_child(left_hand_card)

	right_hand_card = _build_hand_slot_card("RIGHT HAND (มือขวา)")
	right_hand_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hand_card.mouse_entered.connect(func(): _hovered_drop_target = "hand_right")
	right_hand_card.mouse_exited.connect(func(): if _hovered_drop_target == "hand_right": _hovered_drop_target = "")
	hands_hbox.add_child(right_hand_card)

	# --- SEPARATOR ---
	var hsep = HSeparator.new()
	hsep.add_theme_constant_override("separation", 10)
	right_content_box.add_child(hsep)

	# --- AMMO RESERVES SECTION (INVENTORY POOL) ---
	var ammo_panel = PanelContainer.new()
	var ap_style = StyleBoxFlat.new()
	ap_style.bg_color = Color(0.06, 0.10, 0.16, 0.9)
	ap_style.border_width_left = 1
	ap_style.border_width_right = 1
	ap_style.border_width_top = 1
	ap_style.border_width_bottom = 1
	ap_style.border_color = ACCENT_CYAN.lerp(Color.BLACK, 0.6)
	ap_style.corner_radius_top_left = 4
	ap_style.corner_radius_top_right = 4
	ap_style.corner_radius_bottom_left = 4
	ap_style.corner_radius_bottom_right = 4
	ammo_panel.add_theme_stylebox_override("panel", ap_style)

	var ap_margin = MarginContainer.new()
	ap_margin.add_theme_constant_override("margin_left", 8)
	ap_margin.add_theme_constant_override("margin_right", 8)
	ap_margin.add_theme_constant_override("margin_top", 4)
	ap_margin.add_theme_constant_override("margin_bottom", 4)
	ammo_panel.add_child(ap_margin)

	ammo_hbox = HBoxContainer.new()
	ammo_hbox.add_theme_constant_override("separation", 12)
	ap_margin.add_child(ammo_hbox)
	right_content_box.add_child(ammo_panel)

	var hsep2 = HSeparator.new()
	hsep2.add_theme_constant_override("separation", 10)
	right_content_box.add_child(hsep2)

	# --- BOTTOM SECTION: Field Pack Carrier ---
	var carrier_header = HBoxContainer.new()
	var carrier_lbl = Label.new()
	carrier_lbl.text = "FIELD PACK CARRIER (สัมภาระสะพายหลัง)"
	carrier_lbl.add_theme_font_size_override("font_size", 13)
	carrier_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	carrier_header.add_child(carrier_lbl)

	var c_spacer = Control.new()
	c_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carrier_header.add_child(c_spacer)

	weight_label = Label.new()
	weight_label.text = "WEIGHT: 0.0 / 80.0 kg"
	weight_label.add_theme_font_size_override("font_size", 13)
	weight_label.add_theme_color_override("font_color", ACCENT_CYAN)
	carrier_header.add_child(weight_label)

	right_content_box.add_child(carrier_header)

	weight_bar = ProgressBar.new()
	weight_bar.custom_minimum_size = Vector2(0, 10)
	weight_bar.show_percentage = false
	var wb_style = StyleBoxFlat.new()
	wb_style.bg_color = ACCENT_CYAN
	wb_style.corner_radius_top_left = 3
	wb_style.corner_radius_top_right = 3
	wb_style.corner_radius_bottom_left = 3
	wb_style.corner_radius_bottom_right = 3
	weight_bar.add_theme_stylebox_override("fill", wb_style)
	right_content_box.add_child(weight_bar)

	var carrier_scroll = ScrollContainer.new()
	carrier_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carrier_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_content_box.add_child(carrier_scroll)

	carrier_list_container = VBoxContainer.new()
	carrier_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	carrier_list_container.add_theme_constant_override("separation", 8)
	carrier_scroll.add_child(carrier_list_container)

	carrier_scroll.mouse_entered.connect(func(): _hovered_drop_target = "carrier")
	carrier_scroll.mouse_exited.connect(func(): if _hovered_drop_target == "carrier": _hovered_drop_target = "")


func _build_panel_frame(title: String, border_color: Color) -> Dictionary:
	var p = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = BG_GLASS
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = border_color.lerp(Color.BLACK, 0.4)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	p.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	p.add_child(m)

	var vb = VBoxContainer.new()
	vb.name = "ContentBox"
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)

	var h = Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", border_color)
	vb.add_child(h)

	var sep = HSeparator.new()
	vb.add_child(sep)

	return {"panel": p, "content": vb}


func _build_hand_slot_card(slot_name: String) -> PanelContainer:
	var p = PanelContainer.new()
	p.name = slot_name
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_CYAN.lerp(Color.BLACK, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	p.add_child(m)

	var vb = VBoxContainer.new()
	vb.name = "SlotVBox"
	vb.add_theme_constant_override("separation", 4)
	m.add_child(vb)

	var slot_lbl = Label.new()
	slot_lbl.name = "SlotHeader"
	slot_lbl.text = slot_name
	slot_lbl.add_theme_font_size_override("font_size", 11)
	slot_lbl.add_theme_color_override("font_color", Color(0.6, 0.75, 0.85))
	vb.add_child(slot_lbl)

	var item_lbl = Label.new()
	item_lbl.name = "ItemName"
	item_lbl.text = "[EMPTY / มือเปล่า]"
	item_lbl.add_theme_font_size_override("font_size", 14)
	item_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	vb.add_child(item_lbl)

	var sub_lbl = Label.new()
	sub_lbl.name = "ItemSub"
	sub_lbl.text = "Drag weapon here to equip"
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
	vb.add_child(sub_lbl)

	p.set_meta("header_lbl", slot_lbl)
	p.set_meta("name_lbl", item_lbl)
	p.set_meta("sub_lbl", sub_lbl)

	return p


func _refresh_all() -> void:
	_refresh_ground_panel()
	_refresh_hands_panel()
	_refresh_carrier_panel()
	_refresh_ammo_display()
	_update_weight_display()


func _refresh_ammo_display() -> void:
	if ammo_hbox == null or not is_instance_valid(ammo_hbox):
		return
	for c in ammo_hbox.get_children():
		c.queue_free()

	var wm = _get_weapon_manager()
	var ammo_types: Array = []
	for ammo_id in AmmoSystem.ORDER:
		ammo_types.append({"type": ammo_id, "label": AmmoSystem.display_name(ammo_id).to_upper(), "color": AmmoSystem.chip_color(ammo_id)})

	var title_lbl = Label.new()
	title_lbl.text = "AMMO RESERVES:"
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	ammo_hbox.add_child(title_lbl)

	for at in ammo_types:
		var type_str: String = at["type"]
		var count: int = 0
		if wm:
			count = wm.get_battle_reserve(type_str)
		elif LoadoutSystem:
			count = LoadoutSystem.get_reserve_ammo(type_str)

		var chip = Label.new()
		chip.text = "[%s: %d]" % [at["label"], count]
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", at["color"])
		ammo_hbox.add_child(chip)


# ---------------------------------------------------------------------------
# GROUND SALVAGE PANEL
# ---------------------------------------------------------------------------
func _refresh_ground_panel() -> void:
	for child in ground_list_container.get_children():
		child.queue_free()

	var nearby_weapons: Array = []
	var player_pos: Vector3 = player_entity.global_position if player_entity != null else Vector3.ZERO

	for node in get_tree().get_nodes_in_group("weapon_pickup"):
		if node and is_instance_valid(node):
			var dist = node.global_position.distance_to(player_pos)
			if dist <= 8.0:
				nearby_weapons.append(node)

	if nearby_weapons.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No weapons on nearby ground.\n(ไม่มีซากอาวุธในระยะใกล้ตัว)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		ground_list_container.add_child(empty_lbl)
		return

	for pickup in nearby_weapons:
		var card = _build_ground_item_card(pickup)
		ground_list_container.add_child(card)


func _build_ground_item_card(pickup: Node3D) -> PanelContainer:
	var p = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_width_left = 2
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_AMBER.lerp(Color.BLACK, 0.5)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", style)

	var w: WeaponPart = pickup.get("weapon_resource")
	var wname := w.weapon_name if w else "Weapon Wreckage"
	var wtype := w.get_ammo_type() if w else "bullet"
	var wweight := float(w.weight) if w else 8.0
	var cur_ammo := int(pickup.get("current_ammo")) if pickup.get("current_ammo") != null else (w.max_ammo if w else 0)
	var is_tagged := bool(pickup.get("is_tagged_for_convoy")) if pickup.get("is_tagged_for_convoy") != null else false

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	p.add_child(m)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	m.add_child(vb)

	# Row 1: Name + Sandwich Triangle Badge
	var top_row = HBoxContainer.new()
	var name_lbl = Label.new()
	name_lbl.text = wname
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	top_row.add_child(name_lbl)

	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(sp)

	var tag_badge = Label.new()
	tag_badge.name = "TagBadge"
	tag_badge.text = "▲ [SALVAGE TAGGED] ▲" if is_tagged else ""
	tag_badge.add_theme_font_size_override("font_size", 11)
	tag_badge.add_theme_color_override("font_color", ACCENT_AMBER)
	tag_badge.visible = is_tagged
	top_row.add_child(tag_badge)

	vb.add_child(top_row)

	# Row 2: Stats (Type, Weight, Ammo)
	var stats_lbl = Label.new()
	stats_lbl.text = "TYPE: %s  |  WEIGHT: %.1f kg  |  AMMO: %d" % [wtype.to_upper(), wweight, cur_ammo]
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vb.add_child(stats_lbl)

	# Row 3: Action Buttons (Quick Stash, Equip Left, Equip Right, Unload Ammo, Tag Convoy)
	var actions_row = HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 6)

	var stash_btn = Button.new()
	stash_btn.text = "🎒 เก็บใส่เป้"
	stash_btn.add_theme_font_size_override("font_size", 11)
	_style_cyber_button(stash_btn, ACCENT_GREEN)
	stash_btn.pressed.connect(func():
		take_weapon_to_carrier(pickup)
	)
	actions_row.add_child(stash_btn)

	var equip_l_btn = Button.new()
	equip_l_btn.text = "✋ มือซ้าย"
	equip_l_btn.add_theme_font_size_override("font_size", 11)
	_style_cyber_button(equip_l_btn, ACCENT_CYAN)
	equip_l_btn.pressed.connect(func():
		take_weapon_to_hand("left", pickup)
	)
	actions_row.add_child(equip_l_btn)

	var equip_r_btn = Button.new()
	equip_r_btn.text = "✋ มือขวา"
	equip_r_btn.add_theme_font_size_override("font_size", 11)
	_style_cyber_button(equip_r_btn, ACCENT_CYAN)
	equip_r_btn.pressed.connect(func():
		take_weapon_to_hand("right", pickup)
	)
	actions_row.add_child(equip_r_btn)

	var unload_btn = Button.new()
	unload_btn.text = "⚡ ปลดกระสุน (%d)" % cur_ammo
	unload_btn.disabled = (cur_ammo <= 0)
	unload_btn.add_theme_font_size_override("font_size", 11)
	_style_cyber_button(unload_btn, ACCENT_CYAN.lerp(Color.WHITE, 0.2))
	unload_btn.pressed.connect(func():
		if pickup and is_instance_valid(pickup):
			var drained = pickup.unload_ammo_to_player(player_entity)
			if drained > 0 and AudioManager and AudioManager.has_method("play_ui_confirm"):
				AudioManager.play_ui_confirm()
			_refresh_all()
	)
	actions_row.add_child(unload_btn)

	var tag_btn = Button.new()
	tag_btn.text = "▲ Tag กู้" if not is_tagged else "✓ ปลด Tag"
	tag_btn.add_theme_font_size_override("font_size", 11)
	_style_cyber_button(tag_btn, ACCENT_AMBER if not is_tagged else ACCENT_GREEN)
	tag_btn.pressed.connect(func():
		if pickup and is_instance_valid(pickup):
			var new_tag = not is_tagged
			pickup.tag_for_convoy(new_tag)
			_refresh_all()
	)
	actions_row.add_child(tag_btn)

	vb.add_child(actions_row)

	# Drag & Drop interaction on the card
	p.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_start_drag({
					"source": "ground",
					"pickup_node": pickup,
					"weapon": w,
					"ammo": cur_ammo
				})
			else:
				_finish_drag()
	)

	return p


# ---------------------------------------------------------------------------
# EQUIPPED HANDS PANEL (Top Row Compact)
# ---------------------------------------------------------------------------
func _refresh_hands_panel() -> void:
	var wm = _get_weapon_manager()
	var left_w: WeaponPart = wm.left_hand if wm else null
	var right_w: WeaponPart = wm.right_hand if wm else null

	_update_hand_slot_card(left_hand_card, "LEFT HAND (มือซ้าย)", left_w, "hand_left")
	_update_hand_slot_card(right_hand_card, "RIGHT HAND (มือขวา)", right_w, "hand_right")


func _update_hand_slot_card(card: PanelContainer, slot_title: String, w: WeaponPart, slot_id: String) -> void:
	if card == null or not is_instance_valid(card):
		return
	var header_lbl: Label = card.get_meta("header_lbl", null)
	var name_lbl: Label = card.get_meta("name_lbl", null)
	var sub_lbl: Label = card.get_meta("sub_lbl", null)
	if header_lbl == null or name_lbl == null or sub_lbl == null:
		return

	header_lbl.text = slot_title

	var style: StyleBoxFlat = card.get_theme_stylebox("panel")

	if w != null:
		name_lbl.text = w.weapon_name
		name_lbl.add_theme_color_override("font_color", ACCENT_CYAN)
		sub_lbl.text = "DMG: %d  |  WT: %.1f kg  |  AMMO: %d/%d" % [w.damage, w.weight, w.max_ammo, w.max_ammo]
		sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		style.border_color = ACCENT_CYAN
		style.bg_color = CARD_BG_HOVER
	else:
		name_lbl.text = "[EMPTY / มือเปล่า]"
		name_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		sub_lbl.text = "Drag weapon here to equip"
		sub_lbl.add_theme_color_override("font_color", Color(0.35, 0.4, 0.5))
		style.border_color = Color(0.25, 0.35, 0.45)
		style.bg_color = CARD_BG

	# Drag & drop on hand slot
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and w != null:
				_start_drag({
					"source": slot_id,
					"weapon": w,
					"ammo": w.max_ammo
				})
			elif not ev.pressed:
				_finish_drag()
	)


# ---------------------------------------------------------------------------
# FIELD PACK CARRIER PANEL (Backpack)
# ---------------------------------------------------------------------------
func _refresh_carrier_panel() -> void:
	for child in carrier_list_container.get_children():
		child.queue_free()

	var carried_list: Array = _get_carrier_weapons()

	if carried_list.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Carrier backpack is empty.\n(กระเป๋าสะพายหลังว่างเปล่า - ลากอาวุธมาเก็บที่นี่ได้)"
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
		carrier_list_container.add_child(empty_lbl)
		return

	for i in range(carried_list.size()):
		var w = carried_list[i]
		if w is WeaponPart:
			var card = _build_carrier_item_card(w, i)
			carrier_list_container.add_child(card)


func _build_carrier_item_card(w: WeaponPart, index: int) -> PanelContainer:
	var p = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_width_left = 2
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_CYAN.lerp(Color.BLACK, 0.6)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	p.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	p.add_child(m)

	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	m.add_child(hb)

	var num_lbl = Label.new()
	num_lbl.text = "#%d" % (index + 1)
	num_lbl.add_theme_font_size_override("font_size", 12)
	num_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.8))
	hb.add_child(num_lbl)

	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)

	var name_lbl = Label.new()
	name_lbl.text = w.weapon_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vb.add_child(name_lbl)

	var stat_lbl = Label.new()
	stat_lbl.text = "WT: %.1f kg  |  DMG: %d  |  AMMO: %d" % [w.weight, w.damage, w.max_ammo]
	stat_lbl.add_theme_font_size_override("font_size", 11)
	stat_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	vb.add_child(stat_lbl)

	p.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_start_drag({
					"source": "carrier",
					"index": index,
					"weapon": w,
					"ammo": w.max_ammo
				})
			else:
				_finish_drag()
	)

	return p


# Battle pack weight that BOTH the weight display and the pickup gates agree
# on: the live battle loadout (hands + carrier). The hangar LoadoutSystem
# number silently adds ~30kg of allocated ammo on top, which used to reject
# pickups the display said should fit. Falls back to the hangar number when
# no battle WeaponManager is present (E-pickup path parity).
func _current_battle_pack_weight() -> float:
	var cur_w := LoadoutSystem.get_field_pack_weight()
	var wm = _get_weapon_manager()
	if wm and wm.has_method("get_battle_field_pack_weight"):
		cur_w = wm.get_battle_field_pack_weight()
	return cur_w


func _update_weight_display(preview_add_weight: float = 0.0) -> void:
	if weight_bar == null or weight_label == null:
		return

	var cur_w := _current_battle_pack_weight()

	var cap := LoadoutSystem.get_field_pack_capacity()
	var eff_w := cur_w + preview_add_weight
	var ratio := clampf(eff_w / maxf(cap, 1.0), 0.0, 1.0)

	weight_bar.value = ratio * 100.0
	var wb_style: StyleBoxFlat = weight_bar.get_theme_stylebox("fill")

	if eff_w > cap:
		weight_label.text = "WEIGHT: %.1f (+%.1f) / %.1f kg [OVERLOAD!]" % [cur_w, preview_add_weight, cap]
		weight_label.add_theme_color_override("font_color", ACCENT_RED)
		wb_style.bg_color = ACCENT_RED
	elif preview_add_weight > 0.0:
		weight_label.text = "WEIGHT: %.1f (+%.1f) / %.1f kg" % [cur_w, preview_add_weight, cap]
		weight_label.add_theme_color_override("font_color", ACCENT_GREEN)
		wb_style.bg_color = ACCENT_GREEN
	else:
		weight_label.text = "WEIGHT: %.1f / %.1f kg" % [cur_w, cap]
		weight_label.add_theme_color_override("font_color", ACCENT_CYAN)
		wb_style.bg_color = ACCENT_CYAN


# ---------------------------------------------------------------------------
# DRAG & DROP / SWAP SYSTEM
# ---------------------------------------------------------------------------
func _start_drag(data: Dictionary) -> void:
	_drag_data = data
	_create_drag_ghost(data.get("weapon"))


func _create_drag_ghost(w: WeaponPart) -> void:
	if _drag_ghost and is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()

	_drag_ghost = PanelContainer.new()
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_ghost.z_index = 200

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.22, 0.35, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = ACCENT_CYAN
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_drag_ghost.add_theme_stylebox_override("panel", style)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 8)
	_drag_ghost.add_child(m)

	var lbl = Label.new()
	lbl.text = "✦ %s (%.1f kg)" % [w.weapon_name if w else "Item", w.weight if w else 0.0]
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	m.add_child(lbl)

	root_control.add_child(_drag_ghost)
	_update_drag_ghost_position()


func _update_drag_ghost_position() -> void:
	if _drag_ghost and is_instance_valid(_drag_ghost):
		_drag_ghost.global_position = root_control.get_global_mouse_position() + Vector2(16, 16)


func take_weapon_to_carrier(pickup: Node3D) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	var w: WeaponPart = pickup.get("weapon_resource")
	if w == null:
		return

	var cur_w := _current_battle_pack_weight()
	var cap := LoadoutSystem.get_field_pack_capacity()
	if cur_w + float(w.weight) > cap:
		_show_weight_overload_toast(float(w.weight))
		return

	# Remove from ground and group immediately
	pickup.remove_from_group("weapon_pickup")
	pickup.remove_from_group("loot_pickup")
	pickup.queue_free()

	# Register unique UID instance in inventory
	LoadoutSystem.register_weapon(w.resource_path, w.weapon_name)

	# Add to carrier
	_add_to_carrier(w)
	_refresh_all()


func take_weapon_to_hand(hand: String, pickup: Node3D) -> void:
	if pickup == null or not is_instance_valid(pickup):
		return
	var w: WeaponPart = pickup.get("weapon_resource")
	if w == null:
		return

	# Remove from ground and group immediately
	pickup.remove_from_group("weapon_pickup")
	pickup.remove_from_group("loot_pickup")
	pickup.queue_free()

	# Register unique UID instance in inventory
	LoadoutSystem.register_weapon(w.resource_path, w.weapon_name)

	var wm = _get_weapon_manager()
	if wm:
		var old_weapon: WeaponPart = wm.left_hand if hand == "left" else wm.right_hand
		if hand == "left":
			wm.left_hand = w
		else:
			wm.right_hand = w
		if old_weapon != null and old_weapon != w:
			_add_to_carrier(old_weapon)
		_sync_weapon_manager(wm)

	_refresh_all()


func _finish_drag() -> void:
	if _drag_data.is_empty():
		_cancel_drag()
		return

	var target := _hovered_drop_target
	var src: String = _drag_data.get("source", "")
	var w: WeaponPart = _drag_data.get("weapon")

	if target == "hand_left":
		_equip_to_hand("left", w, src)
	elif target == "hand_right":
		_equip_to_hand("right", w, src)
	elif target == "carrier":
		_store_to_carrier(w, src)
	elif target == "ground":
		_drop_to_ground(w, src)

	_cancel_drag()
	_refresh_all()


func _equip_to_hand(hand: String, weapon_to_equip: WeaponPart, src: String) -> void:
	var wm = _get_weapon_manager()
	if wm == null or weapon_to_equip == null:
		return

	var old_weapon: WeaponPart = wm.left_hand if hand == "left" else wm.right_hand

	# Remove from source
	_remove_from_source(src, weapon_to_equip)

	# Equip new weapon
	if hand == "left":
		wm.left_hand = weapon_to_equip
	else:
		wm.right_hand = weapon_to_equip

	# If there was an old weapon, place in carrier
	if old_weapon != null and old_weapon != weapon_to_equip:
		_add_to_carrier(old_weapon)

	_sync_weapon_manager(wm)


func _store_to_carrier(w: WeaponPart, src: String) -> void:
	if w == null:
		return
	if src == "carrier":
		return # Already in carrier

	# Check weight (same battle numbers as the display: hands + carrier).
	var cur_w := _current_battle_pack_weight()
	var cap := LoadoutSystem.get_field_pack_capacity()
	if cur_w + float(w.weight) > cap:
		_show_weight_overload_toast(float(w.weight))
		return

	_remove_from_source(src, w)
	_add_to_carrier(w)


func _drop_to_ground(w: WeaponPart, src: String) -> void:
	if w == null or src == "ground":
		return

	_remove_from_source(src, w)

	# Spawn physical 3D pickup at player's feet
	var drop_pos := player_entity.global_position + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)) if player_entity != null else Vector3(0, 0.5, 0)
	var pickup := Area3D.new()
	pickup.set_script(WeaponPickupScript)
	pickup.weapon_resource = w
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = drop_pos


func _remove_from_source(src: String, w: WeaponPart) -> void:
	var wm = _get_weapon_manager()
	if src == "ground":
		var node: Node = _drag_data.get("pickup_node")
		if node and is_instance_valid(node):
			node.remove_from_group("weapon_pickup")
			node.remove_from_group("loot_pickup")
			node.queue_free()
		if w != null:
			LoadoutSystem.register_weapon(w.resource_path, w.weapon_name)
	elif src == "hand_left":
		if wm: wm.left_hand = null
	elif src == "hand_right":
		if wm: wm.right_hand = null
	elif src == "carrier":
		var idx: int = _drag_data.get("index", -1)
		_remove_from_carrier_at(idx, w)


func _cancel_drag() -> void:
	_drag_data.clear()
	if _drag_ghost and is_instance_valid(_drag_ghost):
		_drag_ghost.queue_free()
		_drag_ghost = null
	_update_weight_display(0.0)


# ---------------------------------------------------------------------------
# HELPERS & SYNC
# ---------------------------------------------------------------------------
func _get_weapon_manager() -> Node:
	if player_entity == null or not is_instance_valid(player_entity):
		return null
	return player_entity.get_node_or_null("WeaponManager")


func _get_carrier_weapons() -> Array:
	var wm = _get_weapon_manager()
	if wm and "carry" in wm:
		return wm.carry
	return []


func _add_to_carrier(w: WeaponPart) -> void:
	var wm = _get_weapon_manager()
	if wm and "carry" in wm:
		wm.carry.append(w)
	_sync_weapon_manager(wm)


func _remove_from_carrier_at(index: int, w: WeaponPart) -> void:
	var wm = _get_weapon_manager()
	if wm and "carry" in wm:
		if index >= 0 and index < wm.carry.size():
			wm.carry.remove_at(index)
		else:
			wm.carry.erase(w)
	_sync_weapon_manager(wm)


func _sync_weapon_manager(wm: Node) -> void:
	if wm:
		if wm.has_method("_rebuild_visuals"):
			wm._rebuild_visuals()
		if wm.has_method("_recalculate_weight"):
			wm._recalculate_weight()
		if wm.has_method("sync_loadout_to_global"):
			wm.sync_loadout_to_global()
	EventBus.weight_changed.emit(LoadoutSystem.get_field_pack_weight())


func _show_weight_overload_toast(attempted_weight: float = 0.0) -> void:
	if weight_label == null:
		return
	# Say WHY in numbers, not just a red blink: the display already shows the
	# same battle weight, so a rejection always explains itself.
	var cur_w := _current_battle_pack_weight()
	var cap := LoadoutSystem.get_field_pack_capacity()
	weight_label.text = "WEIGHT: %.1f (+%.1f) / %.1f kg [OVERLOAD!]" % [cur_w, attempted_weight, cap]
	weight_label.add_theme_color_override("font_color", ACCENT_RED)
	var tw = create_tween()
	weight_label.modulate = Color(1.5, 0.3, 0.3)
	tw.tween_property(weight_label, "modulate", Color.WHITE, 0.4)


func _style_cyber_button(btn: Button, border_color: Color) -> void:
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.14, 0.22, 0.90)
	normal.border_width_left = 1
	normal.border_width_right = 1
	normal.border_width_top = 1
	normal.border_width_bottom = 1
	normal.border_color = border_color
	normal.corner_radius_top_left = 4
	normal.corner_radius_top_right = 4
	normal.corner_radius_bottom_left = 4
	normal.corner_radius_bottom_right = 4
	btn.add_theme_stylebox_override("normal", normal)

	var hover = normal.duplicate()
	hover.bg_color = border_color.lerp(Color.BLACK, 0.7)
	hover.border_color = border_color.lightened(0.3)
	btn.add_theme_stylebox_override("hover", hover)
