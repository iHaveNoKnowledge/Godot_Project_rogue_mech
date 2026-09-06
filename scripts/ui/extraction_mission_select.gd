class_name ExtractionMissionSelect
extends CanvasLayer

signal contract_selected(contract: Dictionary)

var _overlay: Control
var _contract_list: VBoxContainer
var _contracts: Array[Dictionary] = []

func _init() -> void:
	layer = 120

func _ready() -> void:
	_build_ui()
	visible = false

func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.08, 0.94)
	_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(850, 580)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	p_style.border_color = Color(0.25, 0.45, 0.70, 1.0)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.corner_radius_top_left = 8
	p_style.corner_radius_top_right = 8
	p_style.corner_radius_bottom_left = 8
	p_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "🚁 SELECT EXTRACTION CONTRACT"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Deploy into hostile territory, accomplish primary objectives, survive escalating heat, and reach the extraction LZ to bank all salvage."
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 420)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_contract_list = VBoxContainer.new()
	_contract_list.add_theme_constant_override("separation", 12)
	_contract_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_contract_list)

func open_select(sector: int = 1) -> void:
	visible = true
	_contracts = BoardConfig.get_contracts_for_sector(sector)
	_populate_contracts()

func _populate_contracts() -> void:
	for c in _contract_list.get_children():
		c.queue_free()

	for contract in _contracts:
		var c_box := PanelContainer.new()
		var box_style := StyleBoxFlat.new()
		box_style.bg_color = Color(0.12, 0.15, 0.20, 0.95)
		box_style.border_color = Color(0.25, 0.35, 0.45)
		box_style.border_width_left = 1
		box_style.border_width_top = 1
		box_style.border_width_right = 1
		box_style.border_width_bottom = 1
		box_style.corner_radius_top_left = 6
		box_style.corner_radius_top_right = 6
		box_style.corner_radius_bottom_left = 6
		box_style.corner_radius_bottom_right = 6
		c_box.add_theme_stylebox_override("panel", box_style)
		_contract_list.add_child(c_box)

		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 16)
		m.add_theme_constant_override("margin_top", 14)
		m.add_theme_constant_override("margin_right", 16)
		m.add_theme_constant_override("margin_bottom", 14)
		c_box.add_child(m)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		m.add_child(hbox)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 6)
		hbox.add_child(info_vbox)

		var c_name := str(contract.get("name", "Contract"))
		var min_h := int(contract.get("min_heat", 1))
		var max_h := int(contract.get("max_heat", 5))
		var stars := ""
		for s in range(5):
			stars += "★" if s < min_h else "☆"

		var name_lbl := Label.new()
		name_lbl.text = "%s  [Heat: %s (%d★-%d★)]" % [c_name, stars, min_h, max_h]
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		info_vbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(contract.get("desc", ""))
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(desc_lbl)

		var pri: Dictionary = contract.get("primary", {})
		var pri_lbl := Label.new()
		pri_lbl.text = "🎯 PRIMARY: %s — %s" % [pri.get("name", ""), pri.get("desc", "")]
		pri_lbl.add_theme_font_size_override("font_size", 12)
		pri_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		info_vbox.add_child(pri_lbl)

		var reward_credits := int(contract.get("reward_credits", 500))
		var reward_scrap := int(contract.get("reward_scrap", 50))
		var rew_lbl := Label.new()
		rew_lbl.text = "💰 BOUNTY: +%d Credits | +%d Scrap" % [reward_credits, reward_scrap]
		rew_lbl.add_theme_font_size_override("font_size", 12)
		rew_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		info_vbox.add_child(rew_lbl)

		var btn_vbox := VBoxContainer.new()
		btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(btn_vbox)

		var accept_btn := Button.new()
		accept_btn.text = "ACCEPT RUN"
		accept_btn.custom_minimum_size = Vector2(130, 42)
		var captured_contract := contract
		accept_btn.pressed.connect(func():
			_on_contract_chosen(captured_contract)
		)
		btn_vbox.add_child(accept_btn)

func _on_contract_chosen(contract: Dictionary) -> void:
	visible = false
	contract_selected.emit(contract)
