extends CanvasLayer
## War Inventory — I overlay (แยกจาก war_hud.gd)
## ใช้ Action: war_inventory (I)

var _overlay: Control = null


func _ready() -> void:
	layer = 10


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("war_inventory"):
		_toggle()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_I:
		_toggle()


func _toggle() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null
		return
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.55, 0.65, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "INVENTORY (I to close) — Parts / Modules / Backpack / Weapons"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	panel.add_child(lbl)
	add_child(panel)
	_overlay = panel
