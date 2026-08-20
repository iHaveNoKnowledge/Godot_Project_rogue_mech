extends CanvasLayer

const _BoardSystem = preload("res://scripts/systems/board_system.gd")

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

# TopRight Threat Radar
var _threat_radar: VBoxContainer
var _day_label: Label
var _mp_label: Label
var _mp_bar: ProgressBar
var _alert_label: Label
var _alert_bar: ProgressBar
var _objective_label: Label
var _hazard_label: Label

# BottomLeft Unit Status
var _unit_status_panel: PanelContainer
var _part_status_labels: Dictionary = {}
var _dirt_label: Label

# BottomRight Tile Inspector
var _inspector_panel: PanelContainer
var _inspector_title: Label
var _inspector_costs: Label
var _inspector_warnings: Label

# ScreenFX Overlay
var _screen_fx: Control
var _low_energy_vignette: ColorRect
var _vignette_time: float = 0.0


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


# -----------------------------------------------------------------------------
# 2. TOP BAR: GLOBAL RESOURCES (Energy, Convoy, Quick Actions)
# -----------------------------------------------------------------------------
func _build_top_bar() -> void:
	_top_bar = HBoxContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_left = 20
	_top_bar.offset_right = -320 # Leave room for Threat Radar
	_top_bar.offset_top = 12
	_top_bar.offset_bottom = 76
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
	_energy_label.add_theme_font_size_override("font_size", 13)
	_energy_label.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	_energy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e_header.add_child(_energy_label)

	_roller_toggle_btn = Button.new()
	_roller_toggle_btn.text = "ROLLER: OFF"
	_roller_toggle_btn.add_theme_font_size_override("font_size", 11)
	_roller_toggle_btn.pressed.connect(_on_roller_toggle_pressed)
	e_header.add_child(_roller_toggle_btn)
	e_vbox.add_child(e_header)

	_energy_bar = ProgressBar.new()
	_energy_bar.min_value = 0.0
	_energy_bar.max_value = 1000.0
	_energy_bar.value = 1000.0
	_energy_bar.show_percentage = false
	_energy_bar.custom_minimum_size = Vector2(0, 8)
	var e_fill := StyleBoxFlat.new()
	e_fill.bg_color = Color(0.2, 0.7, 1.0, 0.95)
	e_fill.corner_radius_top_left = 3
	e_fill.corner_radius_top_right = 3
	e_fill.corner_radius_bottom_left = 3
	e_fill.corner_radius_bottom_right = 3
	_energy_bar.add_theme_stylebox_override("fill", e_fill)
	e_vbox.add_child(_energy_bar)
	_top_bar.add_child(energy_panel)

	# --- Convoy Panel ---
	var convoy_panel = _make_panel(260, 60)
	var c_vbox = VBoxContainer.new()
	c_vbox.add_theme_constant_override("separation", 4)
	convoy_panel.add_child(c_vbox)

	var c_header = HBoxContainer.new()
	_convoy_hp_label = Label.new()
	_convoy_hp_label.text = "CONVOY: 100 HP"
	_convoy_hp_label.add_theme_font_size_override("font_size", 13)
	_convoy_hp_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	_convoy_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c_header.add_child(_convoy_hp_label)

	_backup_count_label = Label.new()
	_backup_count_label.text = "RESERVE: 1"
	_backup_count_label.add_theme_font_size_override("font_size", 11)
	_backup_count_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	c_header.add_child(_backup_count_label)
	c_vbox.add_child(c_header)

	_convoy_hp_bar = ProgressBar.new()
	_convoy_hp_bar.min_value = 0.0
	_convoy_hp_bar.max_value = 100.0
	_convoy_hp_bar.value = 100.0
	_convoy_hp_bar.show_percentage = false
	_convoy_hp_bar.custom_minimum_size = Vector2(0, 8)
	var c_fill := StyleBoxFlat.new()
	c_fill.bg_color = Color(0.85, 0.65, 0.2, 0.95)
	c_fill.corner_radius_top_left = 3
	c_fill.corner_radius_top_right = 3
	c_fill.corner_radius_bottom_left = 3
	c_fill.corner_radius_bottom_right = 3
	_convoy_hp_bar.add_theme_stylebox_override("fill", c_fill)
	c_vbox.add_child(_convoy_hp_bar)

	_convoy_reserve_label = Label.new()
	_convoy_reserve_label.text = "Fuel Reserve: 100 / 200"
	_convoy_reserve_label.add_theme_font_size_override("font_size", 10)
	_convoy_reserve_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	c_vbox.add_child(_convoy_reserve_label)
	_top_bar.add_child(convoy_panel)

	# --- Quick Actions ---
	var actions_panel = _make_panel(140, 60)
	var a_vbox = VBoxContainer.new()
	a_vbox.add_theme_constant_override("separation", 4)
	actions_panel.add_child(a_vbox)

	_quick_fuel_btn = Button.new()
	_quick_fuel_btn.text = "TRANSFER FUEL"
	_quick_fuel_btn.add_theme_font_size_override("font_size", 11)
	_quick_fuel_btn.pressed.connect(_on_quick_fuel_pressed)
	a_vbox.add_child(_quick_fuel_btn)
	_top_bar.add_child(actions_panel)


# -----------------------------------------------------------------------------
# 3. TOP RIGHT: THREAT RADAR & OBJECTIVE
# -----------------------------------------------------------------------------
func _build_threat_radar() -> void:
	_threat_radar = VBoxContainer.new()
	_threat_radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_threat_radar.offset_left = -290
	_threat_radar.offset_right = -20
	_threat_radar.offset_top = 12
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
	_day_label.add_theme_font_size_override("font_size", 13)
	_day_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_header.add_child(_day_label)

	_mp_label = Label.new()
	_mp_label.text = "MP 8/8"
	_mp_label.add_theme_font_size_override("font_size", 13)
	_mp_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	mp_header.add_child(_mp_label)
	mp_vbox.add_child(mp_header)

	_mp_bar = ProgressBar.new()
	_mp_bar.min_value = 0.0
	_mp_bar.max_value = 8.0
	_mp_bar.value = 8.0
	_mp_bar.show_percentage = false
	_mp_bar.custom_minimum_size = Vector2(0, 6)
	var mp_fill := StyleBoxFlat.new()
	mp_fill.bg_color = Color(0.3, 0.7, 1.0, 0.95)
	_mp_bar.add_theme_stylebox_override("fill", mp_fill)
	mp_vbox.add_child(_mp_bar)
	_threat_radar.add_child(mp_panel)

	# Threat / Alert Card
	var alert_panel = _make_panel(270, 50)
	var a_vbox = VBoxContainer.new()
	a_vbox.add_theme_constant_override("separation", 4)
	alert_panel.add_child(a_vbox)

	_alert_label = Label.new()
	_alert_label.text = "ALERT LEVEL: 0 (TIER 1)"
	_alert_label.add_theme_font_size_override("font_size", 12)
	_alert_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	a_vbox.add_child(_alert_label)

	_alert_bar = ProgressBar.new()
	_alert_bar.min_value = 0.0
	_alert_bar.max_value = 4.0
	_alert_bar.value = 0.0
	_alert_bar.show_percentage = false
	_alert_bar.custom_minimum_size = Vector2(0, 6)
	var a_fill := StyleBoxFlat.new()
	a_fill.bg_color = Color(0.9, 0.25, 0.2, 0.95)
	_alert_bar.add_theme_stylebox_override("fill", a_fill)
	a_vbox.add_child(_alert_bar)
	_threat_radar.add_child(alert_panel)

	# Objective Card
	var obj_panel = _make_panel(270, 75)
	_objective_label = Label.new()
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 12)
	obj_panel.add_child(_objective_label)
	_threat_radar.add_child(obj_panel)

	# Hazard Card
	_hazard_label = Label.new()
	_hazard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hazard_label.add_theme_font_size_override("font_size", 11)
	_hazard_label.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	_hazard_label.visible = false
	_threat_radar.add_child(_hazard_label)


# -----------------------------------------------------------------------------
# 4. BOTTOM LEFT: UNIT STATUS (Armor HP & Frame Durability)
# -----------------------------------------------------------------------------
func _build_unit_status() -> void:
	_unit_status_panel = _make_panel(240, 120)
	_unit_status_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_unit_status_panel.offset_left = 20
	_unit_status_panel.offset_right = 260
	_unit_status_panel.offset_bottom = -20
	_unit_status_panel.offset_top = -140
	_root.add_child(_unit_status_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_unit_status_panel.add_child(vbox)

	var title = Label.new()
	title.text = "MECH SYSTEM INTEGRITY"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	vbox.add_child(title)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(grid)

	var slots := ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var names := ["Head", "Torso", "L-Arm", "R-Arm", "L-Leg", "R-Leg"]
	for i in range(slots.size()):
		var lbl = Label.new()
		lbl.text = "%s: 100%%" % names[i]
		lbl.add_theme_font_size_override("font_size", 10)
		grid.add_child(lbl)
		_part_status_labels[slots[i]] = lbl

	_dirt_label = Label.new()
	_dirt_label.text = "Engine Dirt: 0%"
	_dirt_label.add_theme_font_size_override("font_size", 10)
	_dirt_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	vbox.add_child(_dirt_label)


# -----------------------------------------------------------------------------
# 5. BOTTOM RIGHT: TILE INSPECTOR
# -----------------------------------------------------------------------------
func _build_tile_inspector() -> void:
	_inspector_panel = _make_panel(260, 110)
	_inspector_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_inspector_panel.offset_left = -280
	_inspector_panel.offset_right = -20
	_inspector_panel.offset_bottom = -20
	_inspector_panel.offset_top = -130
	_root.add_child(_inspector_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_inspector_panel.add_child(vbox)

	_inspector_title = Label.new()
	_inspector_title.text = "TILE RECON"
	_inspector_title.add_theme_font_size_override("font_size", 12)
	_inspector_title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vbox.add_child(_inspector_title)

	_inspector_costs = Label.new()
	_inspector_costs.text = "Move Cost: 1 MP | -10 Energy\nTerrain: Plain"
	_inspector_costs.add_theme_font_size_override("font_size", 10)
	vbox.add_child(_inspector_costs)

	_inspector_warnings = Label.new()
	_inspector_warnings.text = ""
	_inspector_warnings.add_theme_font_size_override("font_size", 10)
	_inspector_warnings.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	vbox.add_child(_inspector_warnings)


func _make_panel(w: int, h: int) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, h)
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.08, 0.14, 0.9)
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.45, 0.7, 0.4)
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


func _refresh() -> void:
	if _energy_bar == null:
		return

	# Energy Panel
	var cur_e := GlobalData.mech_energy
	var max_e := GlobalData.mech_max_energy
	_energy_label.text = "ENERGY: %d / %d" % [int(cur_e), int(max_e)]
	_energy_bar.max_value = max_e
	_energy_bar.value = cur_e
	_roller_toggle_btn.text = "ROLLER: ON" if GlobalData.board_roller_mode else "ROLLER: OFF"

	# Convoy Panel
	var c_hp := GlobalData.convoy_hp
	var c_max_hp := GlobalData.convoy_hp_max
	_convoy_hp_label.text = "CONVOY: %d HP" % int(c_hp)
	_convoy_hp_bar.max_value = c_max_hp
	_convoy_hp_bar.value = c_hp
	_convoy_reserve_label.text = "Supply Reserve: %.0f / %.0f" % [
		GlobalData.convoy_fuel_reserve, GlobalData.convoy_fuel_max
	]
	var backups := GlobalData.hangar_mechs.size() - 1 if GlobalData.hangar_mechs.size() > 1 else 0
	_backup_count_label.text = "RESERVE: %d" % backups

	# MP & Threat Radar
	var mp := maxi(GlobalData.board_mp, 0)
	var mp_max := maxi(GlobalData.board_mp_max, 1)
	_day_label.text = "DAY %d — %s" % [GlobalData.board_day, str(GlobalData.board_theme_id).to_upper()]
	_mp_label.text = "MP %d/%d" % [mp, mp_max]
	_mp_bar.max_value = float(mp_max)
	_mp_bar.value = float(mp)
	_mp_bar.modulate = Color(1.0, 0.4, 0.35) if mp <= 0 else Color.WHITE

	var alert := GlobalData.patrol_alert
	_alert_label.text = "ALERT LEVEL: %d (TIER %d)" % [alert, GlobalData.enemy_tech_tier]
	_alert_bar.value = float(alert)

	var obj: Dictionary = _BoardSystem.get_objective()
	var prog := GlobalData.board_objective_progress
	var req := GlobalData.board_objective_required
	var pct := int(float(prog) / maxi(req, 1) * 100.0)
	_objective_label.text = "OBJECTIVE: %s (%d%%)\n%d / %d — %s" % [
		obj.get("name", "Objective"), pct, prog, req, _BoardSystem.objective_desc()
	]

	# Hazard Status
	if GlobalData.current_hazard != "":
		_hazard_label.visible = true
		_hazard_label.text = "HAZARD: %s IN EFFECT" % GlobalData.current_hazard.to_upper().replace("_", " ")
	else:
		_hazard_label.visible = false

	# Unit Status
	var names := {"head": "Head", "body": "Torso", "arm_left": "L-Arm", "arm_right": "R-Arm", "leg_left": "L-Leg", "leg_right": "R-Leg"}
	for slot in _part_status_labels:
		var dmg: float = float(GlobalData.part_damage.get(slot, 0.0))
		var health_pct: int = int((1.0 - dmg) * 100.0)
		var label: Label = _part_status_labels[slot]
		label.text = "%s: %d%%" % [names.get(slot, slot), health_pct]
		label.modulate = Color(1.0, 0.35, 0.35) if health_pct < 30 else (Color(1.0, 0.85, 0.4) if health_pct < 70 else Color.WHITE)

	_dirt_label.text = "Engine Dirt: %d%%" % int(GlobalData.engine_dirt * 100.0)


func _update_screen_fx(delta: float) -> void:
	var ratio := GlobalData.mech_energy / maxf(GlobalData.mech_max_energy, 1.0)
	if ratio < 0.2:
		_vignette_time += delta * 3.5
		var alpha := (sin(_vignette_time) * 0.5 + 0.5) * 0.35
		_low_energy_vignette.color = Color(0.9, 0.1, 0.1, alpha)
	else:
		_low_energy_vignette.color = Color(0.9, 0.1, 0.1, 0.0)


func _on_roller_toggle_pressed() -> void:
	GlobalData.board_roller_mode = not GlobalData.board_roller_mode
	var mode_name := "ROLLER DASH MODE (FAST ROAD: -5 Energy)" if GlobalData.board_roller_mode else "BIPEDAL MODE (STANDARD: -10..25 Energy)"
	EventBus.event_triggered.emit({
		"name": "MOVEMENT MODE",
		"effect": "none",
		"amount": 0,
		"desc": "Switched to %s." % mode_name,
	})


func _on_quick_fuel_pressed() -> void:
	if GlobalData.convoy_fuel_reserve <= 0.0:
		EventBus.event_triggered.emit({
			"name": "CONVOY FUEL EMPTY",
			"effect": "none",
			"amount": 0,
			"desc": "The convoy truck has no fuel reserve remaining.",
		})
		return
	var deficit := GlobalData.mech_max_energy - GlobalData.mech_energy
	if deficit <= 0.0:
		EventBus.event_triggered.emit({
			"name": "ENERGY FULL",
			"effect": "none",
			"amount": 0,
			"desc": "The mech's energy tank is already at full capacity.",
		})
		return
	var transferred := minf(GlobalData.convoy_fuel_reserve, minf(60.0, deficit))
	GlobalData.convoy_fuel_reserve -= transferred
	GlobalData.mech_energy += transferred
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
	var mode_text := "Roller (-5)" if GlobalData.board_roller_mode else "Walk (-%d)" % int(energy_cost)
	_inspector_costs.text = "Terrain: %s | Cost: %d MP (%s)" % [
		terrain_type.capitalize() if terrain_type != "" else "Plain", mp_cost, mode_text
	]
	var warnings := ""
	if patrol_info != "":
		warnings += "CONTACT: %s\n" % patrol_info
	if is_zoc:
		warnings += "[ZONE OF CONTROL - MP WILL DEPLETE!]\n"
	if is_artillery_danger:
		warnings += "[WARNING: IN ARTILLERY RANGE!]\n"
	_inspector_warnings.text = warnings
