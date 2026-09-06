class_name ExtractionSummaryModal
extends CanvasLayer

signal extraction_confirmed

var _overlay: Control
var _title_label: Label
var _details_label: Label
var _loot_label: Label
var _btn_extract: Button

func _init() -> void:
	layer = 125

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

func _build_ui() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.04, 0.06, 0.96)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.06, 0.09, 0.12, 0.98)
	p_style.border_color = Color(0.2, 0.8, 0.4, 1.0)
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
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 18)
	margin.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "🚁 EXTRACTION SUCCESSFUL!"
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	vbox.add_child(_title_label)

	_details_label = Label.new()
	_details_label.text = "Operation Completed. Extraction dropship secured LZ perimeter."
	_details_label.add_theme_font_size_override("font_size", 14)
	_details_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_details_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(660, 260)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_loot_label = Label.new()
	_loot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loot_label.add_theme_font_size_override("font_size", 13)
	_loot_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	scroll.add_child(_loot_label)

	_btn_extract = Button.new()
	_btn_extract.text = "SECURE SALVAGE & RETURN TO BASE"
	_btn_extract.custom_minimum_size = Vector2(280, 48)
	_btn_extract.pressed.connect(_on_confirm_pressed)
	vbox.add_child(_btn_extract)

func show_summary(contract: Dictionary, credits_gained: int, scrap_gained: int, heat_survived: int) -> void:
	visible = true
	var c_name := str(contract.get("name", "Sector Extraction"))
	_title_label.text = "🚁 EXTRACTION SUCCESSFUL — %s" % c_name.to_upper()

	var summary_text := "════════════════════ MISSION REPORT ════════════════════\n\n"
	summary_text += "• Sector Threat Peak: %d★ Wanted Stars\n" % heat_survived
	summary_text += "• Primary Objective: COMPLETED (Verified by HQ)\n"
	summary_text += "• Contract Bounty: +%d Credits, +%d Scrap\n" % [credits_gained, scrap_scrap(contract)]
	summary_text += "\n════════════════════ SECURED ASSETS ════════════════════\n"
	summary_text += "• Current Total Credits: %d\n" % GlobalData.currency.credits
	summary_text += "• Current Total Scrap: %d\n" % GlobalData.currency.scrap
	summary_text += "• Convoy Status: Operational (HP: %.0f/%.0f)\n" % [GlobalData.board.convoy_hp, GlobalData.board.convoy_hp_max]
	summary_text += "\nAll acquired weapons, modifications, and salvaged parts have been safely transferred to Hangar storage."

	_loot_label.text = summary_text

func scrap_scrap(contract: Dictionary) -> int:
	return int(contract.get("reward_scrap", 50))

func _on_confirm_pressed() -> void:
	visible = false
	extraction_confirmed.emit()
