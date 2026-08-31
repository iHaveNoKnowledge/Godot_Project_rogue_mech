extends CanvasLayer
class_name WarMinimap

## Minimap + Fog of War (per PLAN.md Phase3)

var _map_size: Vector2 = Vector2(2000, 2000)
var _fog_enabled: bool = true
var _revealed: Dictionary = {}


func _ready() -> void:
	layer = 11
	_build_minimap()


func _build_minimap() -> void:
	var panel = PanelContainer.new()
	panel.name = "Minimap"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -220
	panel.offset_top = 20
	panel.offset_right = -20
	panel.offset_bottom = 220
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.9)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	var map_rect = ColorRect.new()
	map_rect.custom_minimum_size = Vector2(200, 200)
	map_rect.color = Color(0.12, 0.14, 0.12)
	panel.add_child(map_rect)
	# Friendly base dot
	var f_dot = ColorRect.new()
	f_dot.color = Color(0.2, 0.6, 1.0)
	f_dot.custom_minimum_size = Vector2(8, 8)
	f_dot.position = Vector2(96, 180)
	map_rect.add_child(f_dot)
	# Enemy base dot
	var e_dot = ColorRect.new()
	e_dot.color = Color(0.85, 0.2, 0.2)
	e_dot.custom_minimum_size = Vector2(8, 8)
	e_dot.position = Vector2(96, 20)
	map_rect.add_child(e_dot)
	add_child(panel)
	# Fog overlay texture (simple dark rect with holes revealed)
	if _fog_enabled:
		var fog = ColorRect.new()
		fog.name = "Fog"
		fog.color = Color(0, 0, 0, 0.55)
		fog.set_anchors_preset(Control.PRESET_FULL_RECT)
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map_rect.add_child(fog)


func _process(_delta: float) -> void:
	# Reveal around player
	var player = get_tree().get_first_node_in_group("mecha")
	if player and player is Node3D:
		var pos = (player as Node3D).global_position
		var key = "%d_%d" % [int(pos.x / 100), int(pos.z / 100)]
		_revealed[key] = true
