extends CanvasLayer

var weapon_manager: Node = null
var root_control: Control

var left_panel: PanelContainer
var left_name_label: Label
var left_ammo_label: Label
var left_type_label: Label

var right_panel: PanelContainer
var right_name_label: Label
var right_ammo_label: Label
var right_type_label: Label

var carry_panel: PanelContainer
var carry_container: VBoxContainer
var hand_label: Label

var left_holding: bool = false
var right_holding: bool = false

# --- Pickup prompt / choice UI ---
var pickup_prompt: PanelContainer
var pickup_prompt_label: Label
var pickup_choice_panel: PanelContainer
var pickup_choice_label: Label
var pack_info_label: Label
var take_weapon_btn: Button
var take_ammo_btn: Button
var depot_btn: Button
var nearby_pickup = null
var pickup_menu_open: bool = false

var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1)

const WEAPON_ICONS: Dictionary = {
	0: "[RIFLE]", 1: "[MG]", 2: "[MISSILE]",
	3: "[SPREAD]", 4: "[BLADE]", 5: "[SHIELD]",
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_root()
	_create_left_panel()
	_create_right_panel()
	_create_carry_ui()
	_create_pickup_ui()
	_try_connect_weapon_manager()
	if has_node("/root/EventBus"):
		EventBus.combat_ended.connect(_on_combat_ended)


func _on_combat_ended(_victory: bool) -> void:
	# Never leave the decision menu (and its mouse lock) open past combat.
	if pickup_menu_open:
		_close_pickup_menu()


func _process(_delta: float) -> void:
	if weapon_manager == null:
		_try_connect_weapon_manager()
	_update_nearby_pickup()


func _try_connect_weapon_manager() -> void:
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha == null:
		return
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		return
	if weapon_manager == wm:
		return
	weapon_manager = wm
	weapon_manager.weapon_switched.connect(_on_weapon_switched)
	weapon_manager.ammo_changed.connect(_on_ammo_changed)
	if weapon_manager.has_signal("reload_progress"):
		weapon_manager.reload_progress.connect(_on_reload_progress)
	weapon_manager.carry_updated.connect(_on_carry_updated)
	weapon_manager._emit_initial_state()
	_update_display()


func _input(event: InputEvent) -> void:
	if weapon_manager == null:
		return

	if event.is_action_pressed("interact"):
		_toggle_pickup_menu()
		return

	if pickup_menu_open:
		# While the pickup choice menu is open, don't act on weapon inputs.
		return

	if event.is_action_pressed("weapon_left"):
		left_holding = true
		_show_carry("left")
	elif event.is_action_released("weapon_left"):
		left_holding = false
		_hide_carry()

	if event.is_action_pressed("weapon_right"):
		right_holding = true
		_show_carry("right")
	elif event.is_action_released("weapon_right"):
		right_holding = false
		_hide_carry()

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if left_holding or right_holding:
				_update_carry_display("left" if left_holding else "right")


func _create_root() -> void:
	root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(root_control)


func _make_panel_style(bg_color: Color = _bg_color, corner: int = 8) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = corner
	style.corner_radius_top_right = corner
	style.corner_radius_bottom_left = corner
	style.corner_radius_bottom_right = corner
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.4, 0.6, 0.4)
	return style


func _create_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 1.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 20
	left_panel.offset_right = 220
	left_panel.offset_top = -155
	left_panel.offset_bottom = -65
	left_panel.add_theme_stylebox_override("panel", _make_panel_style())
	left_panel.visible = true
	root_control.add_child(left_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	left_panel.add_child(vbox)

	left_type_label = Label.new()
	left_type_label.text = ""
	left_type_label.add_theme_font_size_override("font_size", 10)
	left_type_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(left_type_label)

	left_name_label = Label.new()
	left_name_label.text = "--- EMPTY ---"
	left_name_label.add_theme_font_size_override("font_size", 16)
	left_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(left_name_label)

	left_ammo_label = Label.new()
	left_ammo_label.text = ""
	left_ammo_label.add_theme_font_size_override("font_size", 22)
	left_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(left_ammo_label)

	var key_hint = Label.new()
	key_hint.text = "[LMB] Fire  |  [1] Switch"
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(key_hint)


func _create_right_panel() -> void:
	right_panel = PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -220
	right_panel.offset_right = -20
	right_panel.offset_top = -155
	right_panel.offset_bottom = -65
	right_panel.add_theme_stylebox_override("panel", _make_panel_style())
	right_panel.visible = true
	root_control.add_child(right_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	right_panel.add_child(vbox)

	right_type_label = Label.new()
	right_type_label.text = ""
	right_type_label.add_theme_font_size_override("font_size", 10)
	right_type_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(right_type_label)

	right_name_label = Label.new()
	right_name_label.text = "--- EMPTY ---"
	right_name_label.add_theme_font_size_override("font_size", 16)
	right_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(right_name_label)

	right_ammo_label = Label.new()
	right_ammo_label.text = ""
	right_ammo_label.add_theme_font_size_override("font_size", 22)
	right_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(right_ammo_label)

	var key_hint = Label.new()
	key_hint.text = "[RMB] Fire  |  [3] Switch"
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(key_hint)


func _create_carry_ui() -> void:
	carry_panel = PanelContainer.new()
	carry_panel.anchor_left = 0.0
	carry_panel.anchor_top = 0.5
	carry_panel.anchor_right = 0.0
	carry_panel.anchor_bottom = 0.5
	carry_panel.offset_left = 20
	carry_panel.offset_right = 260
	carry_panel.offset_top = -150
	carry_panel.offset_bottom = 150
	carry_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.05, 0.1, 0.92)))
	root_control.add_child(carry_panel)
	carry_panel.visible = false

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	carry_panel.add_child(vbox)

	hand_label = Label.new()
	hand_label.text = "LEFT HAND"
	hand_label.add_theme_font_size_override("font_size", 14)
	hand_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(hand_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	carry_container = VBoxContainer.new()
	carry_container.add_theme_constant_override("separation", 1)
	vbox.add_child(carry_container)


func _create_pickup_ui() -> void:
	# Bottom-center prompt: "[F] Pickup: WeaponName" (F = interact action).
	pickup_prompt = PanelContainer.new()
	pickup_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pickup_prompt.offset_left = -170
	pickup_prompt.offset_right = 170
	pickup_prompt.offset_top = -60
	pickup_prompt.offset_bottom = -20
	pickup_prompt.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.1, 0.08, 0.92)))
	root_control.add_child(pickup_prompt)
	pickup_prompt.visible = false

	var vbox = VBoxContainer.new()
	pickup_prompt.add_child(vbox)

	pickup_prompt_label = Label.new()
	pickup_prompt_label.text = "[F] Pickup: ???"
	pickup_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_prompt_label.add_theme_font_size_override("font_size", 16)
	pickup_prompt_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(pickup_prompt_label)

	var hint = Label.new()
	hint.text = "Press F to decide: carry it, stash it, or scrap it for ammo + material"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	vbox.add_child(hint)

	# Center choice modal: FIELD PACK / DEPOT / AMMO ONLY / CANCEL.
	pickup_choice_panel = PanelContainer.new()
	pickup_choice_panel.set_anchors_preset(Control.PRESET_CENTER)
	pickup_choice_panel.offset_left = -190
	pickup_choice_panel.offset_right = 190
	pickup_choice_panel.offset_top = -150
	pickup_choice_panel.offset_bottom = 150
	pickup_choice_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.06, 0.12, 0.96)))
	root_control.add_child(pickup_choice_panel)
	pickup_choice_panel.visible = false

	var cbox = VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 10)
	pickup_choice_panel.add_child(cbox)

	pickup_choice_label = Label.new()
	pickup_choice_label.text = "PICKUP: ???"
	pickup_choice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_choice_label.add_theme_font_size_override("font_size", 16)
	pickup_choice_label.add_theme_color_override("font_color", _accent_color)
	cbox.add_child(pickup_choice_label)

	pack_info_label = Label.new()
	pack_info_label.text = "FIELD PACK: %.1f / %.1f kg" % [GlobalData.get_field_pack_weight(), GlobalData.get_field_pack_capacity()]
	pack_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pack_info_label.add_theme_font_size_override("font_size", 11)
	pack_info_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	cbox.add_child(pack_info_label)

	take_weapon_btn = Button.new()
	take_weapon_btn.text = "ADD TO FIELD PACK (ใส่สนาม)"
	take_weapon_btn.custom_minimum_size = Vector2(0, 38)
	take_weapon_btn.pressed.connect(_on_take_weapon_pressed)
	cbox.add_child(take_weapon_btn)

	depot_btn = Button.new()
	depot_btn.text = "SEND TO DEPOT (ส่งคลัง)"
	depot_btn.custom_minimum_size = Vector2(0, 38)
	depot_btn.pressed.connect(_on_send_to_depot_pressed)
	cbox.add_child(depot_btn)

	take_ammo_btn = Button.new()
	take_ammo_btn.text = "TAKE AMMO ONLY + SCRAP (เอาแค่กระสุน)"
	take_ammo_btn.custom_minimum_size = Vector2(0, 38)
	take_ammo_btn.pressed.connect(_on_take_ammo_only_pressed)
	cbox.add_child(take_ammo_btn)

	var cancel_btn = Button.new()
	cancel_btn.text = "CANCEL"
	cancel_btn.custom_minimum_size = Vector2(0, 32)
	cancel_btn.pressed.connect(_close_pickup_menu)
	cbox.add_child(cancel_btn)


func _update_nearby_pickup() -> void:
	if pickup_menu_open:
		# Keep the menu open even if the mech nudges out of the radius.
		return
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha == null:
		_set_prompt_visible(false)
		nearby_pickup = null
		return

	var best = null
	var best_dist := INF
	for pickup in get_tree().get_nodes_in_group("weapon_pickup"):
		if pickup == null or not is_instance_valid(pickup):
			continue
		if not pickup.is_near_mecha():
			continue
		var d = pickup.global_position.distance_to(mecha.global_position)
		if d < best_dist:
			best_dist = d
			best = pickup

	if best != nearby_pickup:
		nearby_pickup = best
		if best:
			var wname = best.weapon_resource.weapon_name if best.weapon_resource else "Weapon"
			pickup_prompt_label.text = "[F] Pickup: %s" % wname
			pickup_choice_label.text = "PICKUP: %s" % wname
	_set_prompt_visible(best != null)


func _set_prompt_visible(show: bool) -> void:
	if pickup_prompt:
		pickup_prompt.visible = show


func _toggle_pickup_menu() -> void:
	if pickup_menu_open:
		_close_pickup_menu()
		return
	if nearby_pickup == null or not is_instance_valid(nearby_pickup):
		return
	if not nearby_pickup.is_near_mecha():
		return
	pickup_menu_open = true
	pickup_choice_panel.visible = true
	_set_prompt_visible(false)
	# The F-menu is a decision modal: real-time, so the battle keeps running, but
	# the mouse must be freed from camera-look to click a choice (weapon_manager
	# ignores firing while this menu is open).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var can_carry: bool = nearby_pickup.can_take_to_field_pack()
	if take_weapon_btn:
		take_weapon_btn.disabled = not can_carry
		take_weapon_btn.text = "ADD TO FIELD PACK (ใส่สนาม)"
	if pack_info_label:
		pack_info_label.text = "FIELD PACK: %.1f / %.1f kg" % [GlobalData.get_field_pack_weight(), GlobalData.get_field_pack_capacity()]
		if not can_carry:
			pack_info_label.text += "\nFIELD PACK FULL!"


func _close_pickup_menu() -> void:
	pickup_menu_open = false
	if pickup_choice_panel:
		pickup_choice_panel.visible = false
	# Hand the mouse back to the camera look.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_take_weapon_pressed() -> void:
	var pickup = nearby_pickup
	_close_pickup_menu()
	if pickup and is_instance_valid(pickup):
		if not pickup.take_weapon():
			return
	nearby_pickup = null


func _on_send_to_depot_pressed() -> void:
	var pickup = nearby_pickup
	_close_pickup_menu()
	if pickup and is_instance_valid(pickup):
		pickup.send_to_depot()
	nearby_pickup = null


func _on_take_ammo_only_pressed() -> void:
	var pickup = nearby_pickup
	_close_pickup_menu()
	if pickup and is_instance_valid(pickup):
		pickup.take_ammo_only()
	nearby_pickup = null


func _show_carry(hand: String) -> void:
	if weapon_manager == null:
		return

	carry_panel.visible = true

	var viewport_width = get_viewport().get_visible_rect().size.x
	if hand == "left":
		carry_panel.anchor_left = 0.0
		carry_panel.anchor_right = 0.0
		carry_panel.offset_left = 20
		carry_panel.offset_right = 260
		hand_label.text = "LEFT HAND"
	else:
		carry_panel.anchor_left = 1.0
		carry_panel.anchor_right = 1.0
		carry_panel.offset_left = -260
		carry_panel.offset_right = -20
		hand_label.text = "RIGHT HAND"

	_update_carry_display(hand)


func _hide_carry() -> void:
	carry_panel.visible = false


func _update_carry_display(hand: String) -> void:
	if weapon_manager == null:
		return

	for child in carry_container.get_children():
		child.queue_free()

	var list: Array = weapon_manager.carry
	var highlight_idx = weapon_manager._select_idx_left if hand == "left" else weapon_manager._select_idx_right
	var is_selecting = weapon_manager._selecting_left if hand == "left" else weapon_manager._selecting_right

	if list.is_empty():
		var empty = Label.new()
		empty.text = "(no extra weapons)"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", _dim_color)
		carry_container.add_child(empty)
		return

	for i in range(list.size()):
		var weapon: WeaponPart = list[i]
		var is_highlighted = is_selecting and (i == highlight_idx)

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		carry_container.add_child(row)

		var indicator = Label.new()
		indicator.text = ">>" if is_highlighted else "  "
		indicator.add_theme_font_size_override("font_size", 12)
		row.add_child(indicator)

		var icon_label = Label.new()
		icon_label.text = WEAPON_ICONS.get(weapon.weapon_type, "[?]")
		icon_label.add_theme_font_size_override("font_size", 10)
		icon_label.custom_minimum_size = Vector2(55, 0)
		row.add_child(icon_label)

		var name_label = Label.new()
		name_label.text = weapon.weapon_name
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var ammo_label = Label.new()
		var current_ammo = weapon_manager._get_ammo(weapon)
		if weapon.max_ammo >= 999:
			ammo_label.text = "inf"
		else:
			ammo_label.text = "%d/%d" % [current_ammo, weapon.max_ammo]
		ammo_label.add_theme_font_size_override("font_size", 10)
		ammo_label.custom_minimum_size = Vector2(45, 0)
		ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(ammo_label)

		var color: Color = _highlight_color if is_highlighted else _dim_color
		indicator.add_theme_color_override("font_color", color)
		icon_label.add_theme_color_override("font_color", color)
		name_label.add_theme_color_override("font_color", color)
		ammo_label.add_theme_color_override("font_color", color)


func _on_reload_progress(hand: String, partial_text: String, reserve_ammo: int, _percent: float) -> void:
	if hand == "left":
		left_ammo_label.modulate = Color(1.0, 0.3, 0.3)
		left_ammo_label.text = "%s/%d" % [partial_text, reserve_ammo]
	elif hand == "right":
		right_ammo_label.modulate = Color(1.0, 0.3, 0.3)
		right_ammo_label.text = "%s/%d" % [partial_text, reserve_ammo]


func _on_weapon_switched(_hand: String, _weapon_name: String) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _on_ammo_changed(_hand: String, _current: int, _max_ammo: int) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _update_display() -> void:
	if weapon_manager == null:
		return

	if weapon_manager.left_hand:
		var w = weapon_manager.left_hand
		left_name_label.text = w.weapon_name
		left_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		var ammo = weapon_manager._get_ammo(w)
		if not weapon_manager.get("reloading_left"):
			left_ammo_label.modulate = Color.WHITE
			if w.max_ammo >= 999:
				left_ammo_label.text = "inf"
			else:
				var res = weapon_manager.get_battle_reserve(w.get_ammo_type())
				left_ammo_label.text = "%d / %d [Res: %d]" % [ammo, w.max_ammo, res]
	else:
		left_name_label.text = "--- EMPTY ---"
		left_type_label.text = ""
		left_ammo_label.text = ""
		left_ammo_label.modulate = Color.WHITE

	if weapon_manager.right_hand:
		var w = weapon_manager.right_hand
		right_name_label.text = w.weapon_name
		right_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		var ammo = weapon_manager._get_ammo(w)
		if not weapon_manager.get("reloading_right"):
			right_ammo_label.modulate = Color.WHITE
			if w.max_ammo >= 999:
				right_ammo_label.text = "inf"
			else:
				var res = weapon_manager.get_battle_reserve(w.get_ammo_type())
				right_ammo_label.text = "%d / %d [Res: %d]" % [ammo, w.max_ammo, res]
	else:
		right_name_label.text = "--- EMPTY ---"
		right_type_label.text = ""
		right_ammo_label.text = ""
		right_ammo_label.modulate = Color.WHITE


func _on_carry_updated(_carry_list: Array) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")
