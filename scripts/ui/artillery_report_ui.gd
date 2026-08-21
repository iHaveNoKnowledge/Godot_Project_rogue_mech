extends CanvasLayer
class_name ArtilleryReportUI

## ARTILLERY IMPACT REPORT UI — Minimalist squad damage summary overlay
## Displays live before/after HP for the Player Mech, deployed Squadmates,
## and Convoy Truck after an artillery shell strike lands on the tabletop.

signal report_closed

var _root: Control
var _panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _cards_box: HBoxContainer
var _scroll: ScrollContainer
var _continue_btn: Button
var _anim_tweens: Array[Tween] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	visible = false
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -440
	_panel.offset_right = 440
	_panel.offset_bottom = -28
	_panel.offset_top = -268
	_root.add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.13, 0.96)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 14
	panel_style.content_margin_bottom = 14
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.95, 0.3, 0.2, 0.9)
	_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# --- Header Row ---
	var header_box := HBoxContainer.new()
	header_box.add_theme_constant_override("separation", 10)
	vbox.add_child(header_box)

	var header_vbox := VBoxContainer.new()
	header_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_vbox.add_theme_constant_override("separation", 2)
	header_box.add_child(header_vbox)

	_title_label = Label.new()
	_title_label.text = "⚠ ARTILLERY BOMBARDMENT IMPACT REPORT"
	_title_label.add_theme_font_size_override("font_size", 14)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	header_vbox.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = "Hostile Artillery Fleet in range executed a bombardment strike!"
	_subtitle_label.add_theme_font_size_override("font_size", 11)
	_subtitle_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	header_vbox.add_child(_subtitle_label)

	_continue_btn = Button.new()
	_continue_btn.text = "CONTINUE"
	_continue_btn.custom_minimum_size = Vector2(130, 34)
	_continue_btn.add_theme_font_size_override("font_size", 12)
	_continue_btn.pressed.connect(_on_continue_pressed)
	header_box.add_child(_continue_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# --- Unit Cards Scrollable Area ---
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 140)
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(_scroll)

	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 12)
	_cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_cards_box)


## Populates and presents the squad damage transition report.
func show_report(
	fleet_name: String,
	strike_idx: int,
	total_strikes: int,
	player_unit: Dictionary,
	squad_units: Array[Dictionary],
	convoy_unit: Dictionary
) -> void:
	for tw in _anim_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_anim_tweens.clear()

	for child in _cards_box.get_children():
		child.queue_free()

	_title_label.text = "⚠ ARTILLERY IMPACT REPORT (%d/%d) — %s" % [
		strike_idx, total_strikes, fleet_name.to_upper()
	]
	_subtitle_label.text = "Direct bombardment landed on your position! Inspect squad integrity below."

	# 1. Player Active Mech Card
	_build_unit_card(
		"★ ACTIVE MECH",
		player_unit.get("name", "Mech 01"),
		"Pilot: You",
		player_unit.get("old_hp", 100),
		player_unit.get("new_hp", 88),
		player_unit.get("max_hp", 100),
		"-%d Energy" % int(player_unit.get("energy_loss", 30)),
		Color(1.0, 0.85, 0.35)
	)

	# 2. Fielded Squadmates / Hangar Allies
	for ally in squad_units:
		_build_unit_card(
			"🛡 SQUADMATE",
			ally.get("name", "Ally Mech"),
			"Pilot: %s (%s)" % [ally.get("pilot_name", "Pilot"), ally.get("role", "SUPPORT")],
			ally.get("old_hp", 100),
			ally.get("new_hp", 90),
			ally.get("max_hp", 100),
			"Chipped Armor",
			Color(0.4, 0.85, 1.0)
		)

	# 3. Convoy Truck Card
	if not convoy_unit.is_empty():
		_build_unit_card(
			"🚚 CONVOY TRUCK",
			"Supply Convoy",
			"Reinforcement Unit",
			convoy_unit.get("old_hp", 100),
			convoy_unit.get("new_hp", 90),
			convoy_unit.get("max_hp", 100),
			"-%d HP" % int(convoy_unit.get("hp_loss", 10)),
			Color(0.9, 0.75, 0.3)
		)

	visible = true
	_continue_btn.grab_focus()


func _build_unit_card(
	badge: String,
	unit_name: String,
	sub_info: String,
	old_hp: float,
	new_hp: float,
	max_hp: float,
	extra_info: String,
	accent_color: Color
) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(195, 130)

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.11, 0.18, 0.95)
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 10
	card_style.content_margin_right = 10
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card_style.border_width_left = 1
	card_style.border_width_right = 1
	card_style.border_width_top = 1
	card_style.border_width_bottom = 1
	card_style.border_color = accent_color * 0.75
	card.add_theme_stylebox_override("panel", card_style)

	var cvbox := VBoxContainer.new()
	cvbox.add_theme_constant_override("separation", 3)
	card.add_child(cvbox)

	var badge_lbl := Label.new()
	badge_lbl.text = badge
	badge_lbl.add_theme_font_size_override("font_size", 10)
	badge_lbl.add_theme_color_override("font_color", accent_color)
	cvbox.add_child(badge_lbl)

	var name_lbl := Label.new()
	name_lbl.text = unit_name
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	cvbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub_info
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	cvbox.add_child(sub_lbl)

	# --- Animated HP Bar ---
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = max_hp
	bar.value = old_hp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.85, 0.45, 0.95) if (new_hp / max_hp) > 0.4 else Color(0.9, 0.25, 0.2, 0.95)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	bar.add_theme_stylebox_override("fill", fill_style)
	cvbox.add_child(bar)

	var hp_text_lbl := Label.new()
	hp_text_lbl.text = "HP: %d / %d" % [int(old_hp), int(max_hp)]
	hp_text_lbl.add_theme_font_size_override("font_size", 10)
	hp_text_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	cvbox.add_child(hp_text_lbl)

	if extra_info != "":
		var extra_lbl := Label.new()
		extra_lbl.text = extra_info
		extra_lbl.add_theme_font_size_override("font_size", 10)
		extra_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
		cvbox.add_child(extra_lbl)

	_cards_box.add_child(card)

	# Animate HP Bar depletion transition
	var tw := card.create_tween()
	tw.set_parallel(false)
	tw.tween_interval(0.3)
	tw.tween_property(bar, "value", new_hp, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		hp_text_lbl.text = "HP: %d / %d (%+d)" % [int(new_hp), int(max_hp), int(new_hp - old_hp)]
		if (new_hp / max_hp) <= 0.35:
			hp_text_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	)
	_anim_tweens.append(tw)


func _on_continue_pressed() -> void:
	visible = false
	report_closed.emit()
