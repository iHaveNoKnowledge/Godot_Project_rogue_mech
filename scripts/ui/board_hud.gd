extends CanvasLayer

const _BoardSystem = preload("res://scripts/systems/board_system.gd")
const _DNS = preload("res://scripts/systems/day_night_system.gd")
const _PPS = preload("res://scripts/systems/part_penalty_system.gd")

## Board HUD (GDD v4.0 §7 Master Scene Tree):
##   - TopBar_GlobalResources: Energy (bar, rate, roller toggle), Convoy (HP, reserve, backups), Consumables (Quick Fuel)
##   - TopRight_ThreatRadar: Alert Level, Objective & Turn counter, Weather Hazards
##   - BottomLeft_UnitStatus: Live Mech Armor HP & Frame Durability for all 6 limbs + Engine dirt
##   - BottomRight_TileInspector: Inspects hovered/targeted tile (MP, Energy cost, ZoC, Danger zone)
##   - ScreenFX_Overlay: Low energy warning vignette (< 20% energy) + visual cues

# Root Container
var _root: Control

# TopBar Global Resources
var _top_bar: HBoxContainer
var _energy_label: Label
var _energy_bar: ProgressBar
var _roller_toggle_btn: Button
var _convoy_hp_label: Label
var _convoy_hp_bar: ProgressBar
var _convoy_reserve_label: Label
var _backup_count_label: Label
var _quick_fuel_btn: Button
var _credits_label: Label
var _scrap_label: Label
var _cores_label: Label

var _panel: Control:
	get:
		return _root

# TopRight Threat Radar
var _threat_radar: VBoxContainer
var _day_label: Label
var _mp_label: Label
var _mp_bar: ProgressBar
var _alert_label: Label
var _alert_bar: ProgressBar
var _objective_panel: PanelContainer
var _objective_label: Label
var _ceasefire_panel: PanelContainer
var _ceasefire_label: Label
var _reserved_panel: PanelContainer
var _hazard_label: Label
var _cloak_warn_label: Label

# BottomLeft Unit Status
var _unit_status_panel: PanelContainer
var _part_status_labels: Dictionary = {}
var _part_penalty_icons: Dictionary = {}
var _dirt_label: Label

# BottomRight Tile Inspector
var _inspector_panel: PanelContainer
var _inspector_title: Label
var _inspector_costs: Label
var _inspector_fleet: Label
var _inspector_warnings: Label

# Fuel type inventory label (GDD §4.2)
var _fuel_inv_label: Label

# Clock / Time display (GDD §3.1 Day/Night Cycle)
var _clock_label: Label

# GDD §6.2: Thermal Cloak charge warning
var _cloak_warn_label: Label
var _cloak_warn_time: float = 0.0

# ScreenFX Overlay
var _screen_fx: Control
var _low_energy_vignette: ColorRect
var _vignette_time: float = 0.0

# GDD §6.1: HUD Glitch (scanlines + static) when head durability < 50%
var _glitch_scanlines: ColorRect
var _glitch_static: ColorRect
var _glitch_active: bool = false
var _glitch_time: float = 0.0

# GDD §8: DynamicPathLine — Line2D projection showing predicted path + costs
var _path_layer: CanvasLayer
var _path_line: Line2D
var _path_time_label: Label
var _path_energy_label: Label
var _path_hovered_pos: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()
	_refresh()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_screen_fx()
	_build_path_line()
	_build_top_bar()
	_build_threat_radar()
	_build_unit_status()
	_build_tile_inspector()


# -----------------------------------------------------------------------------
# 1. SCREEN FX OVERLAY (Vignette for low energy < 20%)
# -----------------------------------------------------------------------------
func _build_screen_fx() -> void:
	_screen_fx = Control.new()
	_screen_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_screen_fx)

	_low_energy_vignette = ColorRect.new()
	_low_energy_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_low_energy_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_low_energy_vignette.color = Color(0.9, 0.1, 0.1, 0.0)
	_screen_fx.add_child(_low_energy_vignette)

	# GDD §6.1: HUD Glitch — scanlines (horizontal green lines)
	_glitch_scanlines = ColorRect.new()
	_glitch_scanlines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_scanlines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_scanlines.color = Color(0.0, 1.0, 0.3, 0.0)
	_glitch_scanlines.visible = false
	_screen_fx.add_child(_glitch_scanlines)

	# GDD §6.1: HUD Glitch — static noise (white flash overlay)
	_glitch_static = ColorRect.new()
	_glitch_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glitch_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glitch_static.color = Color(1.0, 1.0, 1.0, 0.0)
	_glitch_static.visible = false
	_screen_fx.add_child(_glitch_static)


# -----------------------------------------------------------------------------
# 1b. DYNAMIC PATH LINE (GDD §8) — projected path with time + energy costs
# -----------------------------------------------------------------------------
func _build_path_line() -> void:
	_path_layer = CanvasLayer.new()
	_path_layer.layer = 8  # Between 3D board (0) and HUD (10)
	add_child(_path_layer)

	var path_root := Control.new()
	path_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	path_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_layer.add_child(path_root)

	# Line2D for the predicted path
	_path_line = Line2D.new()
	_path_line.width = 3.0
	_path_line.default_color = Color(0.3, 0.85, 1.0, 0.7)
	_path_line.antialiased = true
	_path_line.visible = false
	path_root.add_child(_path_line)

	# Time cost label (centered on path midpoint)
	_path_time_label = Label.new()
	_path_time_label.text = ""
	_path_time_label.add_theme_font_size_override("font_size", 12)
	_path_time_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3, 0.9))
	_path_time_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_path_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_path_time_label.visible = false
	path_root.add_child(_path_time_label)

	# Energy cost label
	_path_energy_label = Label.new()
	_path_energy_label.text = ""
	_path_energy_label.add_theme_font_size_override("font_size", 12)
	_path_energy_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0, 0.9))
	_path_energy_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_path_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_path_energy_label.visible = false
	path_root.add_child(_path_energy_label)


## Converts a 3D world position to screen-space Vector2 for the Line2D.
func _world_to_screen(world_pos: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-100, -100)
	var screen := cam.unproject_position(world_pos)
	return screen


## Updates the dynamic path line from convoy pos to hovered tile.
func _update_path_line() -> void:
	var tile := _get_hovered_tile_node()
	if tile == null:
		_path_line.visible = false
		_path_time_label.visible = false
		_path_energy_label.visible = false
		return

	var target_pos: Vector2i = tile.get_meta("grid_pos", Vector2i(-1, -1))
	var convoy_pos: Vector2i = GlobalData.fuel.convoy_pos

	# Don't draw path if hovering over the convoy itself or invalid pos
	if target_pos == convoy_pos or target_pos == Vector2i(-1, -1):
		_path_line.visible = false
		_path_time_label.visible = false
		_path_energy_label.visible = false
		return

	# Only draw when in convoy mode (the convoy moves on the board)
	if GlobalData.fuel.traversal_mode != "convoy":
		_path_line.visible = false
		_path_time_label.visible = false
		_path_energy_label.visible = false
		return

	# Build simple straight-line path from convoy to target
	var path_points: Array[Vector2] = []
	var start_3d := Vector3(convoy_pos.x * 4.0, 0.5, convoy_pos.y * 4.0)
	var end_3d := Vector3(target_pos.x * 4.0, 0.5, target_pos.y * 4.0)
	path_points.append(_world_to_screen(start_3d))
	path_points.append(_world_to_screen(end_3d))

	_path_line.points = path_points
	_path_line.visible = true

	# Calculate costs
	var dx := absi(target_pos.x - convoy_pos.x)
	var dy := absi(target_pos.y - convoy_pos.y)
	var manhattan := dx + dy
	var terrain := str(tile.get_meta("terrain", "plain"))
	var costs := GlobalData.fuel.get_mode_step_cost(terrain)
	var total_time: float = float(costs.get("mp", 1)) * float(manhattan)
	var total_energy: float = float(costs.get("energy", 0)) + float(costs.get("fuel", 0)) + float(costs.get("stamina", 0))
	total_energy *= float(manhattan)

	# Position labels at midpoint of path
	var mid_screen := (path_points[0] + path_points[1]) * 0.5
	_path_time_label.text = "⏱ %.0f hours" % total_time
	_path_time_label.position = mid_screen + Vector2(-50, -25)
	_path_time_label.visible = true

	_path_energy_label.text = "⛽ %.0f" % total_energy
	_path_energy_label.position = mid_screen + Vector2(-50, 5)
	_path_energy_label.visible = true


## Helper to get the hovered tile node (same raycast as board_manager).
func _get_hovered_tile_node() -> Node:
	var board = get_parent()
	if board == null or not board.has_method("_hovered_tile"):
		return null
	return board._hovered_tile()


# -----------------------------------------------------------------------------
# 2. TOP BAR: GLOBAL RESOURCES (Energy, Convoy, Quick Actions)
# -----------------------------------------------------------------------------
func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 32
	_top_bar.offset_right = -350 # Leave room for Threat Radar
	_top_bar.offset_top = 18
	_top_bar.offset_bottom = 82
	_top_bar.add_theme_constant_override("separation", 12)
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_top_bar)

	# --- Energy Panel ---
	var energy_panel = _make_panel(260, 60)
	var e_vbox = VBoxContainer.new()
	e_vbox.add_theme_constant_override("separation", 4)
	energy_panel.add_child(e_vbox)

	var e_header = HBoxContainer.new()
	_energy_label = Label.new()
	_energy_label.text = "ENERGY: 1000/1000"
	_energy_label.add_theme_font_size_override("font_size", 14)
	_energy_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_energy_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_energy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e_header.add_child(_energy_label)

	_roller_toggle_btn = Button.new()
	_roller_toggle_btn.text = "ROLLER: OFF"
	_roller_toggle_btn.add_theme_font_size_override("font_size", 12)
	_roller_toggle_btn.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_roller_toggle_btn.pressed.connect(_on_roller_toggle_pressed)
	e_header.add_child(_roller_toggle_btn)
	e_vbox.add_child(e_header)

	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0.0
	_energy_bar.max_value = 1000.0
	_energy_bar.value = 1000.0
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(0, 6)
	var e_fill := StyleBoxFlat.new()
	e_fill.bg_color = Color(0.88, 0.88, 0.88, 1.0)
	e_fill.corner_radius_top_left = 0
	e_fill.corner_radius_top_right = 0
	e_fill.corner_radius_bottom_left = 0
	e_fill.corner_radius_bottom_right = 0
	_energy_bar.add_theme_stylebox_override("fill", e_fill)
	var e_bg := StyleBoxFlat.new()
	e_bg.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	e_bg.corner_radius_top_left = 0
	e_bg.corner_radius_top_right = 0
	e_bg.corner_radius_bottom_left = 0
	e_bg.corner_radius_bottom_right = 0
	_energy_bar.add_theme_stylebox_override("background", e_bg)
	e_vbox.add_child(_energy_bar)

	# GDD §4.2: Fuel type inventory breakdown
	_fuel_inv_label = Label.new()
	_fuel_inv_label.text = ""
	_fuel_inv_label.add_theme_font_size_override("font_size", 10)
	_fuel_inv_label.add_theme_color_override("font_color", Color(0.70, 0.78, 0.60, 1.0))
	_fuel_inv_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	e_vbox.add_child(_fuel_inv_label)

	_top_bar.add_child(energy_panel)

	# --- Convoy Panel ---
	var convoy_panel = _make_panel(260, 60)
	var c_vbox = VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 4)
	convoy_panel.add_child(c_vbox)

	var c_header = HBoxContainer.new()
	_convoy_hp_label = Label.new()
	_convoy_hp_label.text = "CONVOY: 100 HP"
	_convoy_hp_label.add_theme_font_size_override("font_size", 14)
	_convoy_hp_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_convoy_hp_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_convoy_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_header.add_child(_convoy_hp_label)

	_backup_count_label = Label.new()
	_backup_count_label.text = "RESERVE: 1"
	_backup_count_label.add_theme_font_size_override("font_size", 12)
	_backup_count_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1.0))
	_backup_count_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	c_header.add_child(_backup_count_label)
	c_vbox.add_child(c_header)

	_convoy_hp_bar = ProgressBar.new()
	_convoy_hp_bar.min_value = 0.0
	_convoy_hp_bar.max_value = 100.0
	_convoy_hp_bar.value = 100.0
	_convoy_hp_bar.show_percentage = false
	_convoy_hp_bar.custom_minimum_size = Vector2(0, 6)
	var c_fill := StyleBoxFlat.new()
	c_fill.bg_color = Color(0.78, 0.78, 0.78, 1.0)
	c_fill.corner_radius_top_left = 0
	c_fill.corner_radius_top_right = 0
	c_fill.corner_radius_bottom_left = 0
	c_fill.corner_radius_bottom_right = 0
	_convoy_hp_bar.add_theme_stylebox_override("fill", c_fill)
	var c_bg := StyleBoxFlat.new()
	c_bg.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	c_bg.corner_radius_top_left = 0
	c_bg.corner_radius_top_right = 0
	c_bg.corner_radius_bottom_left = 0
	c_bg.corner_radius_bottom_right = 0
	_convoy_hp_bar.add_theme_stylebox_override("background", c_bg)
	c_vbox.add_child(_convoy_hp_bar)

	_convoy_reserve_label = Label.new()
	_convoy_reserve_label.text = "Fuel Reserve: 100 / 200"
	_convoy_reserve_label.add_theme_font_size_override("font_size", 11)
	_convoy_reserve_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 1.0))
	_convoy_reserve_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	c_vbox.add_child(_convoy_reserve_label)
	_top_bar.add_child(convoy_panel)

	# --- Resources / Finances Panel ---
	var res_panel = _make_panel(210, 60)
	var r_vbox = VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 2)
	res_panel.add_child(r_vbox)

	var r_header = HBoxContainer.new()
	_credits_label = Label.new()
	_credits_label.text = "¢ 0"
	_credits_label.add_theme_font_size_override("font_size", 14)
	_credits_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1.0))
	_credits_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_header.add_child(_credits_label)

	_scrap_label = Label.new()
	_scrap_label.text = "⚙ 0"
	_scrap_label.add_theme_font_size_override("font_size", 14)
	_scrap_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70, 1.0))
	_scrap_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	r_header.add_child(_scrap_label)
	r_vbox.add_child(r_header)

	_cores_label = Label.new()
	_cores_label.text = "DATA CORES: 0"
	_cores_label.add_theme_font_size_override("font_size", 11)
	_cores_label.add_theme_color_override("font_color", Color(0.60, 0.60, 0.60, 1.0))
	_cores_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	r_vbox.add_child(_cores_label)
	_top_bar.add_child(res_panel)

	# --- Quick Actions ---
	var actions_panel = _make_panel(140, 60)
	var a_vbox = VBoxContainer.new()
	a_vbox.add_theme_constant_override("separation", 4)
	actions_panel.add_child(a_vbox)

	_quick_fuel_btn = Button.new()
	_quick_fuel_btn.text = "TRANSFER FUEL"
	_quick_fuel_btn.add_theme_font_size_override("font_size", 12)
	_quick_fuel_btn.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_quick_fuel_btn.pressed.connect(_on_quick_fuel_pressed)
	a_vbox.add_child(_quick_fuel_btn)
	_top_bar.add_child(actions_panel)


# -----------------------------------------------------------------------------
# 3. TOP RIGHT: THREAT RADAR & OBJECTIVE
# -----------------------------------------------------------------------------
func _build_threat_radar() -> void:
	_threat_radar = VBoxContainer.new()
	_threat_radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_threat_radar.offset_left = -312
	_threat_radar.offset_right = -32
	_threat_radar.offset_top = 18
	_threat_radar.add_theme_constant_override("separation", 8)
	_threat_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_threat_radar)

	# MP & Day Card
	var mp_panel = _make_panel(270, 64)
	var mp_vbox = VBoxContainer.new()
	mp_vbox.add_theme_constant_override("separation", 4)
	mp_panel.add_child(mp_vbox)

	var mp_header = HBoxContainer.new()
	_day_label = Label.new()
	_day_label.text = "DAY 1 — SUBURB"
	_day_label.add_theme_font_size_override("font_size", 14)
	_day_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_day_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_header.add_child(_day_label)

	_mp_label = Label.new()
	_mp_label.text = "MP 8/8"
	_mp_label.add_theme_font_size_override("font_size", 14)
	_mp_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_mp_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	mp_header.add_child(_mp_label)
	mp_vbox.add_child(mp_header)

	_mp_bar = ProgressBar.new()
	_mp_bar.min_value = 0.0
	_mp_bar.max_value = 8.0
	_mp_bar.value = 8.0
	_mp_bar.show_percentage = false
	_mp_bar.custom_minimum_size = Vector2(0, 6)
	var mp_fill := StyleBoxFlat.new()
	mp_fill.bg_color = Color(0.88, 0.88, 0.88, 1.0)
	mp_fill.corner_radius_top_left = 0
	mp_fill.corner_radius_top_right = 0
	mp_fill.corner_radius_bottom_left = 0
	mp_fill.corner_radius_bottom_right = 0
	_mp_bar.add_theme_stylebox_override("fill", mp_fill)
	var mp_bg := StyleBoxFlat.new()
	mp_bg.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	mp_bg.corner_radius_top_left = 0
	mp_bg.corner_radius_top_right = 0
	mp_bg.corner_radius_bottom_left = 0
	mp_bg.corner_radius_bottom_right = 0
	_mp_bar.add_theme_stylebox_override("background", mp_bg)
	mp_vbox.add_child(_mp_bar)

	# GDD §3.1: Clock / Time display with day/night phase
	_clock_label = Label.new()
	_clock_label.text = "08:00 — DAY 1 ☀"
	_clock_label.add_theme_font_size_override("font_size", 12)
	_clock_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_clock_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	mp_vbox.add_child(_clock_label)

	_threat_radar.add_child(mp_panel)

	# Threat / Alert Card
	var alert_panel = _make_panel(270, 50)
	var a_vbox = VBoxContainer.new()
	a_vbox.add_theme_constant_override("separation", 4)
	alert_panel.add_child(a_vbox)

	_alert_label = Label.new()
	_alert_label.text = "ALERT LEVEL: 0 (TIER 1)"
	_alert_label.add_theme_font_size_override("font_size", 13)
	_alert_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_alert_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	a_vbox.add_child(_alert_label)

	_alert_bar = ProgressBar.new()
	_alert_bar.min_value = 0.0
	_alert_bar.max_value = 4.0
	_alert_bar.value = 0.0
	_alert_bar.show_percentage = false
	_alert_bar.custom_minimum_size = Vector2(0, 6)
	var a_fill := StyleBoxFlat.new()
	a_fill.bg_color = Color(0.75, 0.25, 0.20, 1.0)
	a_fill.corner_radius_top_left = 0
	a_fill.corner_radius_top_right = 0
	a_fill.corner_radius_bottom_left = 0
	a_fill.corner_radius_bottom_right = 0
	_alert_bar.add_theme_stylebox_override("fill", a_fill)
	var a_bg := StyleBoxFlat.new()
	a_bg.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	a_bg.corner_radius_top_left = 0
	a_bg.corner_radius_top_right = 0
	a_bg.corner_radius_bottom_left = 0
	a_bg.corner_radius_bottom_right = 0
	_alert_bar.add_theme_stylebox_override("background", a_bg)
	a_vbox.add_child(_alert_bar)
	_threat_radar.add_child(alert_panel)

	# Objective Card
	_objective_panel = _make_panel(270, 75)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 13)
	_objective_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	_objective_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_objective_panel.add_child(_objective_label)
	_threat_radar.add_child(_objective_panel)

	# Ceasefire Card (Countdown slot)
	_ceasefire_panel = _make_panel(270, 30)
	_ceasefire_label = Label.new()
	_ceasefire_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ceasefire_label.add_theme_font_size_override("font_size", 12)
	_ceasefire_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65, 1.0))
	_ceasefire_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	_ceasefire_panel.add_child(_ceasefire_label)
	_threat_radar.add_child(_ceasefire_panel)

	# Reserved Card (Third slot)
	_reserved_panel = _make_panel(270, 30)
	_threat_radar.add_child(_reserved_panel)

	# Hazard Card
	_hazard_label = Label.new()
	_hazard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hazard_label.add_theme_font_size_override("font_size", 11)
	_hazard_label.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	_hazard_label.visible = false
	_threat_radar.add_child(_hazard_label)

	# Cloak Charge Warning Label
	_cloak_warn_label = Label.new()
	_cloak_warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cloak_warn_label.add_theme_font_size_override("font_size", 11)
	_cloak_warn_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	_cloak_warn_label.visible = false
	_threat_radar.add_child(_cloak_warn_label)


# -----------------------------------------------------------------------------
# 4. BOTTOM LEFT: UNIT STATUS (Armor HP & Frame Durability)
# -----------------------------------------------------------------------------
func _build_unit_status() -> void:
	_unit_status_panel = _make_panel(300, 160)
	_unit_status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_unit_status_panel.offset_left = 32
	_unit_status_panel.offset_right = 332
	_unit_status_panel.offset_bottom = -36
	_unit_status_panel.offset_top = -196
	_root.add_child(_unit_status_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_unit_status_panel.add_child(vbox)

	var title = Label.new()
	title.text = "MECH SYSTEM INTEGRITY"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	title.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	vbox.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(grid)

	var slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var names := ["Head", "Torso", "L-Arm", "R-Arm", "L-Leg", "R-Leg"]
	for i in range(slots.size()):
		var lbl = Label.new()
		lbl.text = "%s: 100%%" % names[i]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
		grid.add_child(lbl)
		_part_status_labels[slots[i]] = lbl
		# GDD §6.1: Part penalty warning icon
		var icon = Label.new()
		icon.text = ""
		icon.add_theme_font_size_override("font_size", 14)
		icon.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
		icon.custom_minimum_size = Vector2(50, 0)
		grid.add_child(icon)
		_part_penalty_icons[slots[i]] = icon

	_dirt_label = Label.new()
	_dirt_label.text = "Engine Dirt: 0%"
	_dirt_label.add_theme_font_size_override("font_size", 13)
	_dirt_label.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68, 1.0))
	_dirt_label.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	vbox.add_child(_dirt_label)


# -----------------------------------------------------------------------------
# 5. BOTTOM RIGHT: TILE INSPECTOR
# -----------------------------------------------------------------------------
func _build_tile_inspector() -> void:
	_inspector_panel = _make_panel(400, 240)
	_inspector_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inspector_panel.offset_left = -432
	_inspector_panel.offset_right = -32
	_inspector_panel.offset_bottom = -36
	_inspector_panel.offset_top = -276
	_root.add_child(_inspector_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	_inspector_panel.add_child(vbox)

	_inspector_title = Label.new()
	_inspector_title.text = "TILE RECON"
	_inspector_title.add_theme_font_size_override("font_size", 15)
	_inspector_title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_inspector_title.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	vbox.add_child(_inspector_title)

	_inspector_costs = Label.new()
	_inspector_costs.text = "Move Cost: 1 MP | -10 Energy\nTerrain: Plain"
	_inspector_costs.add_theme_font_size_override("font_size", 13)
	_inspector_costs.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78, 1.0))
	_inspector_costs.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	vbox.add_child(_inspector_costs)

	_inspector_fleet = Label.new()
	_inspector_fleet.text = ""
	_inspector_fleet.add_theme_font_size_override("font_size", 13)
	_inspector_fleet.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	_inspector_fleet.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Regular.ttf"))
	_inspector_fleet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_inspector_fleet)

	_inspector_warnings = Label.new()
	_inspector_warnings.text = ""
	_inspector_warnings.add_theme_font_size_override("font_size", 13)
	_inspector_warnings.add_theme_color_override("font_color", Color(0.85, 0.35, 0.30, 1.0))
	_inspector_warnings.add_theme_font_override("font", preload("res://resources/fonts/ChakraPetch-Medium.ttf"))
	_inspector_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_inspector_warnings)


func _make_panel(w: int, h: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.09, 0.09, 0.09, 0.96)
	s.corner_radius_top_left = 0
	s.corner_radius_top_right = 0
	s.corner_radius_bottom_left = 0
	s.corner_radius_bottom_right = 0
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.22, 0.22, 0.22, 1.0)
	panel.add_theme_stylebox_override("panel", s)
	return panel


func _process(delta: float) -> void:
	var bm = get_parent()
	var intermission_open := false
	var modal_open := false

	if bm != null:
		var intermission = bm.get_node_or_null("IntermissionUI")
		if intermission != null and intermission.visible:
			intermission_open = true
		for modal_name in ["EventUI", "SafehouseUI", "CityShopUI", "ResearchLabUI", "DeployTeamUI"]:
			var node = bm.get_node_or_null(modal_name)
			if node != null and node.visible:
				modal_open = true
				break

	if modal_open:
		# During center event popup, safehouse, shop or lab: hide all HUD panels completely
		_root.visible = false
	elif intermission_open:
		# During Intermission menu: show only Threat Radar in top right; hide left/bottom panels
		_root.visible = true
		_top_bar.visible = false
		_unit_status_panel.visible = false
		_inspector_panel.visible = false
		_threat_radar.visible = true
	else:
		# Normal Board mode: all 4 HUD corners active
		_root.visible = true
		_top_bar.visible = true
		_unit_status_panel.visible = true
		_inspector_panel.visible = true
		_threat_radar.visible = true

	_refresh()
	_update_screen_fx(delta)
	_update_path_line()


func _refresh() -> void:
	if _energy_bar == null:
		return

	# Multi-Tier Traversal Energy Panel
	var mode: String = GlobalData.fuel.traversal_mode
	match mode:
		"mecha":
			var cur_e := GlobalData.fuel.mech_energy
			var max_e := GlobalData.fuel.mech_max_energy
			_energy_label.text = "🤖 MECHA BATTERY: %d / %d" % [int(cur_e), int(max_e)]
			_energy_bar.max_value = max_e
			_energy_bar.value = cur_e
			_energy_bar.modulate = Color(0.3, 0.85, 1.0)
			_roller_toggle_btn.text = "MODE: [DEPLOY PILOT]"
		"pilot":
			var cur_s := GlobalData.fuel.pilot_stamina
			var max_s := GlobalData.fuel.pilot_max_stamina
			_energy_label.text = "🏃 PILOT STAMINA: %d / %d" % [int(cur_s), int(max_s)]
			_energy_bar.max_value = max_s
			_energy_bar.value = cur_s
			_energy_bar.modulate = Color(0.4, 1.0, 0.4)
			_roller_toggle_btn.text = "MODE: [MOUNT MECHA]"
		_: # "convoy"
			var cur_f := GlobalData.fuel.convoy_fuel
			var max_f := GlobalData.fuel.convoy_max_fuel
			_energy_label.text = "🚚 CONVOY FUEL: %d / %d" % [int(cur_f), int(max_f)]
			_energy_bar.max_value = max_f
			_energy_bar.value = cur_f
			_energy_bar.modulate = Color(1.0, 0.88, 0.2)
			_roller_toggle_btn.text = "MODE: [DEPLOY MECHA]"

	# GDD §4.2: Show fuel type inventory breakdown
	if _fuel_inv_label:
		var inv_display := ""
		match mode:
			"mecha":
				inv_display = GlobalData.fuel.mech_fuel_display()
			"convoy":
				inv_display = GlobalData.fuel.convoy_fuel_display()
			_:
				inv_display = ""
			if inv_display != "" and inv_display != "EMPTY":
				_fuel_inv_label.text = "📦 %s" % inv_display
				_fuel_inv_label.visible = true
			else:
				_fuel_inv_label.visible = false

	# Convoy Panel
	var c_hp := GlobalData.board.convoy_hp
	var c_max_hp := GlobalData.board.convoy_hp_max
	_convoy_hp_label.text = "CONVOY: %d HP" % int(c_hp)
	_convoy_hp_bar.max_value = c_max_hp
	_convoy_hp_bar.value = c_hp
	_convoy_reserve_label.text = "Supply Reserve: %.0f / %.0f" % [
		GlobalData.fuel.convoy_fuel_reserve, GlobalData.fuel.convoy_fuel_max
	]
	var backups := GlobalData.hangar.hangar_mechs.size() - 1 if GlobalData.hangar.hangar_mechs.size() > 1 else 0
	var trucks := 1
	if HangarManager:
		trucks = clampi(int(ceil(float(HangarManager.get_fleet_size()) / 2.0)), 1, 3)
	_backup_count_label.text = "RESERVE: %d | TRUCKS: %d" % [backups, trucks]

	# Resources / Finances
	if _credits_label:
		_credits_label.text = "¢ %s CREDITS" % str(GlobalData.currency.credits)
	if _scrap_label:
		_scrap_label.text = "⚙ %s SCRAP" % str(GlobalData.currency.scrap)
	if _cores_label:
		_cores_label.text = "💾 DATA CORES: %s" % str(GlobalData.currency.data_cores)

	# MP & Threat Radar
	var mp := maxi(GlobalData.board.board_mp, 0)
	var mp_max := maxi(GlobalData.board.board_mp_max, 1)
	_day_label.text = "DAY %d — %s" % [GlobalData.board.board_day, str(GlobalData.board.board_theme_id).to_upper()]
	# GDD §3.1: Clock with time, day, and day/night phase
	var dns_time := _DNS.time_string()
	var dns_day := _DNS.current_day()
	var dns_phase := _DNS.phase_name()
	var phase_icon := "☀" if _DNS.is_daytime() else "☽"
	var phase_color := Color(0.95, 0.85, 0.3) if _DNS.is_daytime() else Color(0.45, 0.55, 0.85)
	if _clock_label:
		_clock_label.text = "%s — Day %d %s (%s)" % [dns_time, dns_day, phase_icon, dns_phase]
		_clock_label.modulate = phase_color
	_mp_label.text = "MP %d/%d" % [mp, mp_max]
	_mp_bar.max_value = float(mp_max)
	_mp_bar.value = float(mp)
	_mp_bar.modulate = Color(1.0, 0.4, 0.35) if mp <= 0 else Color.WHITE

	var alert := GlobalData.board.patrol_alert
	_alert_label.text = "ALERT LEVEL: %d (TIER %d)" % [alert, GlobalData.narrative.enemy_tech_tier]
	_alert_bar.value = float(alert)

	var obj: Dictionary = _BoardSystem.get_objective()
	var prog := GlobalData.board.board_objective_progress
	var req := GlobalData.board.board_objective_required
	var pct := int(float(prog) / maxi(req, 1) * 100.0)
	_objective_label.text = "OBJECTIVE: %s (%d%%)\n%d / %d — %s" % [
		obj.get("name", "Objective"), pct, prog, req, _BoardSystem.objective_desc()
	]

	# Ceasefire Status
	if _ceasefire_label:
		if GlobalData.narrative.ceasefire_turns > 0:
			_ceasefire_label.text = "CEASEFIRE: %d TURNS LEFT" % GlobalData.narrative.ceasefire_turns
		else:
			_ceasefire_label.text = ""

	# Hazard Status
	if GlobalData.board.current_hazard != "":
		_hazard_label.visible = true
		_hazard_label.text = "HAZARD: %s IN EFFECT" % GlobalData.board.current_hazard.to_upper().replace("_", " ")
	else:
		_hazard_label.visible = false

	# Cloak Charge Warning
	if GlobalData.thermal_cloak != null and GlobalData.thermal_cloak.is_cloak_active():
		_cloak_warn_label.visible = true
		var charge: float = GlobalData.thermal_cloak.charge
		var pct: int = int(charge)
		if charge <= 10.0:
			_cloak_warn_label.text = "◈ CLOAK CRITICAL: %d%%" % pct
			_cloak_warn_label.modulate = Color(1.0, 0.2, 0.2)
		elif charge <= 30.0:
			_cloak_warn_label.text = "◈ CLOAK LOW: %d%%" % pct
			_cloak_warn_label.modulate = Color(1.0, 0.65, 0.15)
		else:
			_cloak_warn_label.text = "◈ CLOAK: %d%%" % pct
			_cloak_warn_label.modulate = Color(0.4, 0.8, 1.0)
	else:
		_cloak_warn_label.visible = false

	# Unit Status
	var names := {"head": "Head", "body": "Torso", "arm_left": "L-Arm", "arm_right": "R-Arm", "leg_left": "L-Leg", "leg_right": "R-Leg"}
	for slot in _part_status_labels:
		var dmg: float = float(GlobalData.weapons.part_damage.get(slot, 0.0))
		var health_pct: int = int((1.0 - dmg) * 100.0)
		var label: Label = _part_status_labels[slot]
		label.text = "%s: %d%%" % [names.get(slot, slot), health_pct]
		label.modulate = Color(1.0, 0.35, 0.35) if health_pct < 30 else (Color(1.0, 0.85, 0.4) if health_pct < 70 else Color.WHITE)
		# GDD §6.1: Part penalty warning icons
		var icon: Label = _part_penalty_icons.get(slot)
		if icon:
			if dmg >= 0.80:
				icon.text = "⚠⚠⚠"
				icon.modulate = Color(1.0, 0.25, 0.2)
			elif dmg >= 0.60:
				icon.text = "⚠⚠"
				icon.modulate = Color(1.0, 0.55, 0.2)
			elif dmg >= 0.40:
				icon.text = "⚠"
				icon.modulate = Color(1.0, 0.85, 0.4)
			else:
				icon.text = ""
				icon.modulate = Color.WHITE

	_dirt_label.text = "Engine Dirt: %d%%" % int(GlobalData.fuel.engine_dirt * 100.0)


func _update_screen_fx(delta: float) -> void:
	# Low energy vignette (< 20%)
	var ratio := GlobalData.fuel.mech_energy / maxf(GlobalData.fuel.mech_max_energy, 1.0)
	if ratio < 0.2:
		_vignette_time += delta * 3.5
		var alpha := (sin(_vignette_time) * 0.5 + 0.5) * 0.35
		_low_energy_vignette.color = Color(0.9, 0.1, 0.1, alpha)
	else:
		_low_energy_vignette.color = Color(0.9, 0.1, 0.1, 0.0)

	# GDD §6.1: HUD Glitch when head durability < 50%
	var should_glitch := _PPS.head_hud_glitching()
	if should_glitch != _glitch_active:
		_glitch_active = should_glitch
		_glitch_scanlines.visible = should_glitch
		_glitch_static.visible = should_glitch
		if should_glitch:
			_glitch_time = 0.0

	if _glitch_active:
		_glitch_time += delta
		# Scanlines: horizontal green lines that scroll and flicker
		var scan_alpha := 0.06 + 0.04 * sin(_glitch_time * 18.0)
		_glitch_scanlines.color = Color(0.0, 1.0, 0.3, scan_alpha)
		# Static noise: random white flashes that pulse
		var static_roll := randf()
		if static_roll < 0.15:
			# Brief bright flash
			_glitch_static.color = Color(1.0, 1.0, 1.0, 0.12)
		elif static_roll < 0.25:
			# Dim green tint
			_glitch_static.color = Color(0.2, 0.8, 0.3, 0.06)
		else:
			_glitch_static.color = Color(1.0, 1.0, 1.0, 0.0)


func _on_roller_toggle_pressed() -> void:
	var cur_mode: String = GlobalData.fuel.traversal_mode
	if cur_mode == "convoy":
		GlobalData.fuel.deploy_mecha()
		EventBus.event_triggered.emit({
			"name": "DEPLOYED MECHA",
			"effect": "none",
			"amount": 0,
			"desc": "Deployed Mecha from the Convoy! Base truck remains parked. Operating on mech battery.",
		})
	elif cur_mode == "mecha":
		GlobalData.fuel.deploy_pilot()
		EventBus.event_triggered.emit({
			"name": "DEPLOYED PILOT",
			"effect": "none",
			"amount": 0,
			"desc": "Pilot dismounted on foot! Ultra-stealth profile active. Operating on stamina.",
		})
	elif cur_mode == "pilot":
		if GlobalData.board.current_tile == GlobalData.fuel.convoy_pos and GlobalData.fuel.convoy_is_deployed:
			GlobalData.fuel.reembark_convoy()
			EventBus.event_triggered.emit({
				"name": "RE-EMBARKED CONVOY",
				"effect": "none",
				"amount": 0,
				"desc": "Re-embarked onto the Convoy truck! Base camp restored to mobile mode.",
			})
		else:
			GlobalData.fuel.traversal_mode = "mecha"
			EventBus.event_triggered.emit({
				"name": "MOUNTED MECHA",
				"effect": "none",
				"amount": 0,
				"desc": "Pilot entered the active Mecha! Operating on mech battery.",
			})
	_refresh()


func _on_quick_fuel_pressed() -> void:
	if GlobalData.fuel.convoy_fuel_reserve <= 0.0:
		EventBus.event_triggered.emit({
			"name": "CONVOY FUEL EMPTY",
			"effect": "none",
			"amount": 0,
			"desc": "The convoy truck has no fuel reserve remaining.",
		})
		return
	var deficit := GlobalData.fuel.mech_max_energy - GlobalData.fuel.mech_energy
	if deficit <= 0.0:
		EventBus.event_triggered.emit({
			"name": "ENERGY FULL",
			"effect": "none",
			"amount": 0,
			"desc": "The mech's energy tank is already at full capacity.",
		})
		return
	var transferred := minf(GlobalData.fuel.convoy_fuel_reserve, minf(60.0, deficit))
	GlobalData.fuel.convoy_fuel_reserve -= transferred
	GlobalData.fuel.mech_energy += transferred
	EventBus.event_triggered.emit({
		"name": "QUICK FUEL TRANSFER",
		"effect": "none",
		"amount": 0,
		"desc": "Transferred +%.0f fuel from convoy truck." % transferred,
	})


# Called by board_manager on tile hover/inspect
func update_tile_inspector(tile_name: String, mp_cost: int, energy_cost: float, is_zoc: bool, is_artillery_danger: bool, terrain_type: String = "", patrol_info: String = "") -> void:
	if _inspector_title == null:
		return
	_inspector_title.text = "TILE RECON: %s" % tile_name.to_upper()
	var mode_text := "Roller (-5)" if GlobalData.fuel.board_roller_mode else "Walk (-%d)" % int(energy_cost)
	_inspector_costs.text = "Terrain: %s | Cost: %d MP (%s)" % [
		terrain_type.capitalize() if terrain_type != "" else "Plain", mp_cost, mode_text
	]
	_inspector_fleet.text = patrol_info
	_inspector_fleet.visible = patrol_info != ""

	var warnings := ""
	if is_zoc:
		warnings += "[ZONE OF CONTROL - MP CUT TO 0!]\n"
	if is_artillery_danger:
		warnings += "[WARNING: IN ARTILLERY BOMBARD RANGE!]\n"
	_inspector_warnings.text = warnings
	_inspector_warnings.visible = warnings != ""
