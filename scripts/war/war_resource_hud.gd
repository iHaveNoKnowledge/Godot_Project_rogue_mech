extends CanvasLayer
## War Resource HUD — Tab overlay (แยกจาก war_hud.gd)
## ใช้ Action: war_resource_view (Tab)

var _overlay: Control = null


func _ready() -> void:
	layer = 10


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("war_resource_view"):
		_show()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("war_resource_view"):
		_hide()
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_TAB:
		_hide()


func _show() -> void:
	if _overlay and is_instance_valid(_overlay):
		return
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 20
	panel.offset_bottom = 80
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 1.0, 0.9)
	panel.add_theme_stylebox_override("panel", style)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	var credits: int = GlobalData.currency.credits if GlobalData.currency else 0
	var scrap: int = GlobalData.currency.scrap if GlobalData.currency else 0
	var fuel_txt: String = "FUEL: %.0f" % GlobalData.fuel.mech_energy if GlobalData.fuel else "FUEL: 0"
	for txt in ["CREDITS: %d" % credits, "SCRAP: %d" % scrap, fuel_txt]:
		var lbl := Label.new()
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		hbox.add_child(lbl)
	add_child(panel)
	_overlay = panel


func _hide() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
