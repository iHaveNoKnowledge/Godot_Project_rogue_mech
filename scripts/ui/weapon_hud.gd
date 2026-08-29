extends CanvasLayer

var weapon_manager: Node = null
var root_control: Control

var left_panel: PanelContainer
var left_name_label: Label
var left_ammo_label: Label
var left_reserve_label: Label
var left_type_label: Label
var left_heat_bar: ProgressBar

var right_panel: PanelContainer
var right_name_label: Label
var right_ammo_label: Label
var right_reserve_label: Label
var right_type_label: Label
var right_heat_bar: ProgressBar

var carry_panel: PanelContainer
var carry_container: VBoxContainer
var hand_label: Label

var left_holding: bool = false
var right_holding: bool = false

# --- Pickup prompt / Field Loot UI ---
var pickup_prompt: PanelContainer
var pickup_prompt_label: Label
var nearby_pickup = null
var _pickup_prompt_tween: Tween = null
var field_loot_modal: CanvasLayer = null
var _reload_flash_rect: ColorRect = null
var _reload_flash_tween: Tween = null

var _bg_color: Color = Color(0.08, 0.08, 0.12, 0.85)
var _accent_color: Color = Color(0.3, 0.6, 1.0, 1)
var _highlight_color: Color = Color(1.0, 0.9, 0.3, 1)
var _dim_color: Color = Color(0.5, 0.5, 0.5, 1)

# Bare-fist punch cadence readout: the shared fist WeaponCore sets a cooldown
# after every punch (both hands share it), so an empty hand shows that cooldown
# as a draining gold bar in the heat-bar slot plus a READY / seconds label.
var _fist_cd_style: StyleBoxFlat = null
const FIST_READY_COLOR: Color = Color(0.45, 0.95, 0.45)
const FIST_COOLING_COLOR: Color = Color(1.0, 0.85, 0.3)

const WEAPON_ICONS: Dictionary = {
	0: "[RIFLE]", 1: "[MG]", 2: "[MISSILE]",
	3: "[SPREAD]", 4: "[BLADE]", 5: "[SHIELD]",
	6: "[RAIL]", 7: "[MG2]",
}

# Reserve ammo warning: tint label amber when reserve < this fraction of max_ammo.
const LOW_RESERVE_RATIO: float = 0.20
const LOW_RESERVE_COLOR: Color = Color(1.0, 0.65, 0.2)  # amber/orange
const NORMAL_RESERVE_COLOR: Color = Color(0.6, 0.8, 0.6) # muted green


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_root()
	_create_left_panel()
	_create_right_panel()
	_create_carry_ui()
	_create_pickup_ui()
	_create_reload_flash()
	_try_connect_weapon_manager()
	if EventBus:
		EventBus.combat_ended.connect(_on_combat_ended)


func _on_combat_ended(_victory: bool) -> void:
	if field_loot_modal != null and is_instance_valid(field_loot_modal) and field_loot_modal.is_open:
		field_loot_modal.close_modal()


func _process(_delta: float) -> void:
	# Hide weapon HUD entirely when the pilot has ejected — only mech
	# weapons are shown here; on foot the pilot uses pilot weapons.
	var is_eject := GameManager.current_state == GameManager.State.EJECT
	if root_control:
		root_control.visible = not is_eject
	if weapon_manager == null:
		_try_connect_weapon_manager()
	if is_eject:
		return
	_update_nearby_pickup()
	_update_fist_cooldown()


func _get_fist_cd_style() -> StyleBoxFlat:
	if _fist_cd_style == null:
		_fist_cd_style = StyleBoxFlat.new()
		_fist_cd_style.bg_color = Color(0.95, 0.75, 0.2, 0.95)
		_fist_cd_style.corner_radius_top_left = 0
		_fist_cd_style.corner_radius_top_right = 0
		_fist_cd_style.corner_radius_bottom_left = 0
		_fist_cd_style.corner_radius_bottom_right = 0
	return _fist_cd_style


# Polls the SHARED bare-fist core every frame and renders its cooldown on every
# empty hand's panel (both hands punch on the same cadence, so both panels show
# the same bar). Equipped hands keep their normal ammo/heat display untouched.
func _update_fist_cooldown() -> void:
	if weapon_manager == null:
		return
	if weapon_manager.left_hand != null and weapon_manager.right_hand != null:
		return
	var fist_core: WeaponCore = weapon_manager._core_for_weapon(weapon_manager._fist())
	if fist_core == null:
		return
	if weapon_manager.left_hand == null:
		_set_fist_cd_ui(left_heat_bar, left_ammo_label, fist_core)
	if weapon_manager.right_hand == null:
		_set_fist_cd_ui(right_heat_bar, right_ammo_label, fist_core)


func _set_fist_cd_ui(bar: ProgressBar, ammo_label: Label, core: WeaponCore) -> void:
	var cooling: bool = core.cooldown > 0.0
	bar.max_value = maxf(core.fire_interval, 0.01)
	bar.value = core.cooldown
	bar.visible = cooling
	if cooling:
		bar.add_theme_stylebox_override("fill", _get_fist_cd_style())
		ammo_label.text = "%.1fs" % core.cooldown
		ammo_label.modulate = FIST_COOLING_COLOR
	else:
		ammo_label.text = "READY"
		ammo_label.modulate = FIST_READY_COLOR


# Screen-edge flash overlay shown when reload fails — a brief red vignette
# that fades out so the player gets a strong peripheral visual cue.
func _create_reload_flash() -> void:
	_reload_flash_rect = ColorRect.new()
	_reload_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reload_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reload_flash_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_reload_flash_rect.z_index = 100  # above all HUD panels
	root_control.add_child(_reload_flash_rect)


func _flash_reload_error() -> void:
	if _reload_flash_rect == null:
		return
	if _reload_flash_tween != null and _reload_flash_tween.is_valid():
		_reload_flash_tween.kill()
	# Instant red flash, then fade out
	_reload_flash_rect.color = Color(0.9, 0.15, 0.1, 0.30)
	_reload_flash_tween = create_tween()
	_reload_flash_tween.tween_property(_reload_flash_rect, "color:a", 0.0, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _try_connect_weapon_manager() -> void:
	var mecha = GameManager.get_player_mecha()
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
	if weapon_manager.has_signal("heat_changed"):
		weapon_manager.heat_changed.connect(_on_heat_changed)
	if weapon_manager.has_signal("reload_progress"):
		weapon_manager.reload_progress.connect(_on_reload_progress)
	if weapon_manager.has_signal("reload_failed"):
		weapon_manager.reload_failed.connect(_on_reload_failed)
	weapon_manager.carry_updated.connect(_on_carry_updated)
	weapon_manager._emit_initial_state()
	_update_display()


func _input(event: InputEvent) -> void:
	if weapon_manager == null:
		return

	if field_loot_modal != null and is_instance_valid(field_loot_modal) and field_loot_modal.is_open:
		# While the field loot modal is open, don't act on weapon inputs.
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


func _make_heat_style() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.6, 0.1, 0.05, 0.9)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	return style


func _create_left_panel() -> void:
	left_panel = PanelContainer.new()
	left_panel.anchor_left = 0.0
	left_panel.anchor_top = 1.0
	left_panel.anchor_right = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 32
	left_panel.offset_right = 232
	left_panel.offset_top = -186
	left_panel.offset_bottom = -36
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
	left_name_label.text = "BARE FIST — punch"
	left_name_label.add_theme_font_size_override("font_size", 16)
	left_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(left_name_label)

	left_ammo_label = Label.new()
	left_ammo_label.text = ""
	left_ammo_label.add_theme_font_size_override("font_size", 22)
	left_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(left_ammo_label)

	left_reserve_label = Label.new()
	left_reserve_label.text = ""
	left_reserve_label.add_theme_font_size_override("font_size", 11)
	left_reserve_label.add_theme_color_override("font_color", NORMAL_RESERVE_COLOR)
	vbox.add_child(left_reserve_label)

	left_heat_bar = ProgressBar.new()
	left_heat_bar.min_value = 0.0
	left_heat_bar.max_value = 100.0
	left_heat_bar.value = 0.0
	left_heat_bar.custom_minimum_size = Vector2(0, 10)
	left_heat_bar.show_percentage = false
	left_heat_bar.visible = true
	var heat_style = StyleBoxFlat.new()
	heat_style.bg_color = Color(0.85, 0.28, 0.08, 0.95)
	heat_style.corner_radius_top_left = 0
	heat_style.corner_radius_top_right = 0
	heat_style.corner_radius_bottom_left = 0
	heat_style.corner_radius_bottom_right = 0
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	bg_style.corner_radius_top_left = 0
	bg_style.corner_radius_top_right = 0
	bg_style.corner_radius_bottom_left = 0
	bg_style.corner_radius_bottom_right = 0
	left_heat_bar.add_theme_stylebox_override("fill", _make_heat_style())
	left_heat_bar.add_theme_stylebox_override("background", bg_style)
	vbox.add_child(left_heat_bar)
	var key_hint = Label.new()
	key_hint.text = "[LMB] Fire  |  [1] Switch  |  [X] Drop"
	key_hint.add_theme_font_size_override("font_size", 9)
	key_hint.add_theme_color_override("font_color", _dim_color)
	vbox.add_child(key_hint)


func _create_right_panel() -> void:
	right_panel = PanelContainer.new()
	right_panel.anchor_left = 1.0
	right_panel.anchor_top = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -232
	right_panel.offset_right = -32
	right_panel.offset_top = -186
	right_panel.offset_bottom = -36
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
	right_name_label.text = "BARE FIST — punch"
	right_name_label.add_theme_font_size_override("font_size", 16)
	right_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(right_name_label)

	right_ammo_label = Label.new()
	right_ammo_label.text = ""
	right_ammo_label.add_theme_font_size_override("font_size", 22)
	right_ammo_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(right_ammo_label)

	right_reserve_label = Label.new()
	right_reserve_label.text = ""
	right_reserve_label.add_theme_font_size_override("font_size", 11)
	right_reserve_label.add_theme_color_override("font_color", NORMAL_RESERVE_COLOR)
	vbox.add_child(right_reserve_label)

	right_heat_bar = ProgressBar.new()
	right_heat_bar.min_value = 0.0
	right_heat_bar.max_value = 100.0
	right_heat_bar.value = 0.0
	right_heat_bar.custom_minimum_size = Vector2(0, 10)
	right_heat_bar.show_percentage = false
	right_heat_bar.visible = true
	var rheat_style = StyleBoxFlat.new()
	rheat_style.bg_color = Color(0.85, 0.28, 0.08, 0.95)
	rheat_style.corner_radius_top_left = 0
	rheat_style.corner_radius_top_right = 0
	rheat_style.corner_radius_bottom_left = 0
	rheat_style.corner_radius_bottom_right = 0
	var rbg_style = StyleBoxFlat.new()
	rbg_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	rbg_style.corner_radius_top_left = 0
	rbg_style.corner_radius_top_right = 0
	rbg_style.corner_radius_bottom_left = 0
	rbg_style.corner_radius_bottom_right = 0
	right_heat_bar.add_theme_stylebox_override("fill", _make_heat_style())
	right_heat_bar.add_theme_stylebox_override("background", rbg_style)
	vbox.add_child(right_heat_bar)

	var key_hint = Label.new()
	key_hint.text = "[RMB] Fire  |  [3] Switch  |  [X] Drop"
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
	carry_panel.offset_top = -120
	carry_panel.offset_bottom = 120
	carry_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.08, 0.12, 0.92)))
	carry_panel.visible = false
	root_control.add_child(carry_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	carry_panel.add_child(vbox)

	hand_label = Label.new()
	hand_label.text = "SELECT WEAPON"
	hand_label.add_theme_font_size_override("font_size", 11)
	hand_label.add_theme_color_override("font_color", _accent_color)
	vbox.add_child(hand_label)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	carry_container = VBoxContainer.new()
	carry_container.add_theme_constant_override("separation", 4)
	vbox.add_child(carry_container)


func _create_pickup_ui() -> void:
	# Bottom center prompt: "[F] Field Loot / Salvage"
	pickup_prompt = PanelContainer.new()
	pickup_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pickup_prompt.offset_left = -170
	pickup_prompt.offset_right = 170
	pickup_prompt.offset_top = -130
	pickup_prompt.offset_bottom = -75
	pickup_prompt.add_theme_stylebox_override("panel", _make_panel_style(Color(0.08, 0.10, 0.16, 0.92)))
	root_control.add_child(pickup_prompt)
	pickup_prompt.visible = false

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	pickup_prompt.add_child(vbox)

	pickup_prompt_label = Label.new()
	pickup_prompt_label.text = "[F] Field Loot / Salvage"
	pickup_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_prompt_label.add_theme_font_size_override("font_size", 14)
	pickup_prompt_label.add_theme_color_override("font_color", _highlight_color)
	vbox.add_child(pickup_prompt_label)

	var hint = Label.new()
	hint.text = "Press [F] to inspect loot, equip, or stash into Field Pack"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.75, 0.85, 0.75))
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.State.COMBAT and GameManager.current_state != GameManager.State.EJECT:
		return
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F or event.physical_keycode == KEY_F)):
		if field_loot_modal != null and is_instance_valid(field_loot_modal) and field_loot_modal.is_open:
			get_viewport().set_input_as_handled()
			field_loot_modal.close_modal()
			return
		if nearby_pickup != null and is_instance_valid(nearby_pickup):
			get_viewport().set_input_as_handled()
			_open_field_loot_modal()


func _open_field_loot_modal() -> void:
	if field_loot_modal == null or not is_instance_valid(field_loot_modal):
		var loot_scene = preload("res://scenes/ui/field_loot_modal.tscn")
		field_loot_modal = loot_scene.instantiate()
		add_child(field_loot_modal)
	var player = GameManager.get_player_mecha()
	if player == null:
		player = get_tree().get_first_node_in_group("pilot")
	_set_prompt_visible(false)
	field_loot_modal.open_modal(player)


func _update_nearby_pickup() -> void:
	if field_loot_modal != null and is_instance_valid(field_loot_modal) and field_loot_modal.is_open:
		_set_prompt_visible(false)
		return
	var player: Node3D = GameManager.get_player_mecha()
	if player == null:
		player = get_tree().get_first_node_in_group("pilot")
	if player == null:
		_set_prompt_visible(false)
		nearby_pickup = null
		return

	var best = null
	var best_dist := INF
	for pickup in get_tree().get_nodes_in_group("weapon_pickup"):
		if pickup == null or not is_instance_valid(pickup):
			continue
		var is_near = false
		if pickup.has_method("is_near_player"):
			is_near = pickup.is_near_player()
		elif pickup.has_method("is_near_mecha"):
			is_near = pickup.is_near_mecha()

		var d = pickup.global_position.distance_to(player.global_position)
		if is_near or d <= 4.5:
			if d < best_dist:
				best_dist = d
				best = pickup

	nearby_pickup = best
	if best:
		var wname = best.weapon_resource.weapon_name if (best.get("weapon_resource") and best.weapon_resource) else "Weapon Salvage"
		pickup_prompt_label.text = "[F] Field Loot / Salvage: %s" % wname
	_set_prompt_visible(best != null)


func _set_prompt_visible(show: bool) -> void:
	if pickup_prompt:
		pickup_prompt.visible = show
		if show:
			# Fade-in pop so the prompt registers in peripheral vision.
			if _pickup_prompt_tween and _pickup_prompt_tween.is_valid():
				_pickup_prompt_tween.kill()
			pickup_prompt.modulate.a = 0.0
			_pickup_prompt_tween = create_tween()
			_pickup_prompt_tween.tween_property(pickup_prompt, "modulate:a", 1.0, 0.15)


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

		# The "press X to drop" hint rides on the HIGHLIGHTED row so it follows
		# the selection as the player scrolls. It points toward the screen
		# center: a left-hand list shows it on the row's right end, a right-hand
		# list on the row's left end.
		if is_highlighted:
			var hint := Label.new()
			hint.text = "[X] DROP"
			hint.add_theme_font_size_override("font_size", 10)
			hint.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
			hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
			hint.add_theme_constant_override("shadow_offset_x", 1)
			hint.add_theme_constant_override("shadow_offset_y", 1)
			row.add_child(hint)
			if hand != "left":
				row.move_child(hint, 0)

		var color: Color = _highlight_color if is_highlighted else _dim_color
		indicator.add_theme_color_override("font_color", color)
		icon_label.add_theme_color_override("font_color", color)
		name_label.add_theme_color_override("font_color", color)
		ammo_label.add_theme_color_override("font_color", color)

	# --- Bare Fist / Unarmed Row (Index = list.size()) ---
	var fist_highlighted = is_selecting and (highlight_idx == list.size())
	var fist_row = HBoxContainer.new()
	fist_row.add_theme_constant_override("separation", 6)
	carry_container.add_child(fist_row)

	var fist_ind = Label.new()
	fist_ind.text = ">>" if fist_highlighted else "  "
	fist_ind.add_theme_font_size_override("font_size", 12)
	fist_row.add_child(fist_ind)

	var fist_icon = Label.new()
	fist_icon.text = "[FIST]"
	fist_icon.add_theme_font_size_override("font_size", 10)
	fist_icon.custom_minimum_size = Vector2(55, 0)
	fist_row.add_child(fist_icon)

	var fist_name = Label.new()
	fist_name.text = "BARE FIST (Unarmed / Holster)"
	fist_name.add_theme_font_size_override("font_size", 12)
	fist_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fist_row.add_child(fist_name)

	var fist_ammo = Label.new()
	fist_ammo.text = "melee"
	fist_ammo.add_theme_font_size_override("font_size", 10)
	fist_ammo.custom_minimum_size = Vector2(45, 0)
	fist_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fist_row.add_child(fist_ammo)

	var fcolor: Color = _highlight_color if fist_highlighted else _dim_color
	fist_ind.add_theme_color_override("font_color", fcolor)
	fist_icon.add_theme_color_override("font_color", fcolor)
	fist_name.add_theme_color_override("font_color", fcolor)
	fist_ammo.add_theme_color_override("font_color", fcolor)


func _on_reload_progress(hand: String, partial_text: String, reserve_ammo: int, _percent: float) -> void:
	var max_ammo := 0
	if weapon_manager:
		var w = weapon_manager.left_hand if hand == "left" else weapon_manager.right_hand
		if w:
			max_ammo = w.max_ammo
	if hand == "left":
		left_ammo_label.modulate = Color(1.0, 0.3, 0.3)
		left_ammo_label.text = "%s / %d" % [partial_text, max_ammo]
		left_reserve_label.text = "Reserve: %d" % reserve_ammo
		_apply_reserve_tint(left_reserve_label, reserve_ammo, max_ammo)
	elif hand == "right":
		right_ammo_label.modulate = Color(1.0, 0.3, 0.3)
		right_ammo_label.text = "%s / %d" % [partial_text, max_ammo]
		right_reserve_label.text = "Reserve: %d" % reserve_ammo
		_apply_reserve_tint(right_reserve_label, reserve_ammo, max_ammo)


var _reload_fail_tween_left: Tween = null
var _reload_fail_tween_right: Tween = null


func _on_reload_failed(hand: String, reason: String) -> void:
	# Audio: dry click so the player hears the failure
	if AudioManager:
		AudioManager.play_ui_click()
	# Screen-edge red flash for strong peripheral feedback
	_flash_reload_error()
	# Visual: flash the ammo label red with the reason, then reset
	var label: Label = left_ammo_label if hand == "left" else right_ammo_label
	var tween_ref: String = "_reload_fail_tween_left" if hand == "left" else "_reload_fail_tween_right"
	# Kill any in-flight failure tween so rapid presses don't stack
	var old_tw: Tween = get(tween_ref)
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	label.modulate = Color(1.0, 0.3, 0.3)
	label.text = reason
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(_update_display)
	set(tween_ref, tw)


func _on_weapon_switched(_hand: String, _weapon_name: String) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _on_ammo_changed(_hand: String, _current: int, _max_ammo: int) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")


func _on_heat_changed(hand: String, current: float, _max_heat: float, overheated: bool) -> void:
	var bar: ProgressBar = left_heat_bar if hand == "left" else right_heat_bar
	if bar == null:
		return
	bar.max_value = maxf(_max_heat, 1.0)
	bar.value = current
	bar.visible = true
	bar.modulate = Color(1.0, 0.4, 0.4) if overheated else Color.WHITE


func _apply_reserve_tint(label: Label, reserve: int, max_ammo: int) -> void:
	if max_ammo <= 0 or max_ammo >= 999:
		label.add_theme_color_override("font_color", NORMAL_RESERVE_COLOR)
	else:
		var color: Color = LOW_RESERVE_COLOR if reserve < int(max_ammo * LOW_RESERVE_RATIO) else NORMAL_RESERVE_COLOR
		label.add_theme_color_override("font_color", color)


func _update_display() -> void:
	if weapon_manager == null:
		return

	if weapon_manager.left_hand:
		var w = weapon_manager.left_hand
		left_name_label.text = w.weapon_name
		left_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		if w.uses_heat():
			left_heat_bar.visible = true
			left_heat_bar.max_value = maxf(w.heat_capacity, 1.0)
			left_heat_bar.value = weapon_manager._get_heat(w)
			left_heat_bar.modulate = Color(1.0, 0.4, 0.4) if weapon_manager.is_overheated("left") else Color.WHITE
		else:
			# Keep bar visible (dim) so player knows where heat appears for heat weapons
			left_heat_bar.visible = true
			left_heat_bar.max_value = 100.0
			left_heat_bar.value = 0.0
			left_heat_bar.modulate = Color(1,1,1,0.35)
		var ammo = weapon_manager._get_ammo(w)
		if not weapon_manager.get("reloading_left"):
			left_ammo_label.modulate = Color.WHITE
			if w.max_ammo >= 999:
				left_ammo_label.text = "inf"
				left_reserve_label.text = ""
			else:
				var res = weapon_manager.get_battle_reserve(w.get_ammo_type())
				left_ammo_label.text = "%d / %d" % [ammo, w.max_ammo]
				left_reserve_label.text = "Reserve: %d" % res
				_apply_reserve_tint(left_reserve_label, res, w.max_ammo)
	else:
		left_name_label.text = "BARE FIST — punch"
		left_type_label.text = ""
		left_ammo_label.text = ""
		left_ammo_label.modulate = Color.WHITE
		left_reserve_label.text = ""
		left_heat_bar.visible = false

	if weapon_manager.right_hand:
		var w = weapon_manager.right_hand
		right_name_label.text = w.weapon_name
		right_type_label.text = WEAPON_ICONS.get(w.weapon_type, "[?]")
		if w.uses_heat():
			right_heat_bar.visible = true
			right_heat_bar.max_value = maxf(w.heat_capacity, 1.0)
			right_heat_bar.value = weapon_manager._get_heat(w)
			right_heat_bar.modulate = Color(1.0, 0.4, 0.4) if weapon_manager.is_overheated("right") else Color.WHITE
		else:
			right_heat_bar.visible = true
			right_heat_bar.max_value = 100.0
			right_heat_bar.value = 0.0
			right_heat_bar.modulate = Color(1,1,1,0.35)
		var ammo = weapon_manager._get_ammo(w)
		if not weapon_manager.get("reloading_right"):
			right_ammo_label.modulate = Color.WHITE
			if w.max_ammo >= 999:
				right_ammo_label.text = "inf"
				right_reserve_label.text = ""
			else:
				var res = weapon_manager.get_battle_reserve(w.get_ammo_type())
				right_ammo_label.text = "%d / %d" % [ammo, w.max_ammo]
				right_reserve_label.text = "Reserve: %d" % res
				_apply_reserve_tint(right_reserve_label, res, w.max_ammo)
	else:
		right_name_label.text = "BARE FIST — punch"
		right_type_label.text = ""
		right_ammo_label.text = ""
		right_ammo_label.modulate = Color.WHITE
		right_reserve_label.text = ""
		right_heat_bar.visible = false


func _on_carry_updated(_carry_list: Array) -> void:
	_update_display()
	if carry_panel.visible:
		_update_carry_display("left" if left_holding else "right")
