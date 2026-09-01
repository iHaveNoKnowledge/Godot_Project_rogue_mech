extends CanvasLayer

## War HUD — Tab (resource) + I (inventory) overlay. Minimal for Phase 1.

var _resource_overlay: Control = null
var _inventory_overlay: Control = null


func _ready() -> void:
	layer = 10


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("war_resource_view"):
		_show_resource_overlay()
	elif event.is_action_pressed("war_inventory"):
		_toggle_inventory()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_TAB:
			_show_resource_overlay()
		elif event.keycode == KEY_I:
			_toggle_inventory()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("war_resource_view"):
		_hide_resource_overlay()
	elif event is InputEventKey and not event.pressed and event.keycode == KEY_TAB:
		_hide_resource_overlay()


func _show_resource_overlay() -> void:
	if _resource_overlay and is_instance_valid(_resource_overlay):
		return
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top = 20
	panel.offset_bottom = 80
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 1.0, 0.9)
	panel.add_theme_stylebox_override("panel", style)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	var credits = GlobalData.currency.credits if GlobalData.currency else 0
	var scrap = GlobalData.currency.scrap if GlobalData.currency else 0
	for txt in ["CREDITS: %d" % credits, "SCRAP: %d" % scrap, "FUEL: %.0f" % GlobalData.fuel.mech_energy if GlobalData.fuel else "FUEL: 0"]:
		var lbl = Label.new()
		lbl.text = txt
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		hbox.add_child(lbl)
	add_child(panel)
	_resource_overlay = panel


func _hide_resource_overlay() -> void:
	if _resource_overlay and is_instance_valid(_resource_overlay):
		_resource_overlay.queue_free()
	_resource_overlay = null


func _toggle_inventory() -> void:
	if _inventory_overlay and is_instance_valid(_inventory_overlay):
		_inventory_overlay.queue_free()
		_inventory_overlay = null
		return
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(600, 400)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.09, 0.11, 0.96)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.55, 0.65, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	var lbl = Label.new()
	lbl.text = "INVENTORY (I to close) — Phase 1 placeholder\nParts / Modules / Backpack / Weapons"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	panel.add_child(lbl)
	add_child(panel)
	_inventory_overlay = panel
