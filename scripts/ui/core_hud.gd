extends CanvasLayer

@onready var armor_bars: Dictionary = {
	"head": %HeadArmorBar,
	"body": %BodyArmorBar,
	"arm_left": %ArmLArmorBar,
	"leg_left": %LegLArmorBar,
	"arm_right": %ArmRArmorBar,
	"leg_right": %LegRArmorBar,
}

@onready var frame_bars: Dictionary = {
	"head": %HeadFrameBar,
	"body": %BodyFrameBar,
	"arm_left": %ArmLFrameBar,
	"leg_left": %LegLFrameBar,
	"arm_right": %ArmRFrameBar,
	"leg_right": %LegRFrameBar,
}

@onready var armor_values: Dictionary = {
	"head": %HeadArmorValue,
	"body": %BodyArmorValue,
	"arm_left": %ArmLArmorValue,
	"leg_left": %LegLArmorValue,
	"arm_right": %ArmRArmorValue,
	"leg_right": %LegRArmorValue,
}

@onready var frame_values: Dictionary = {
	"head": %HeadFrameValue,
	"body": %BodyFrameValue,
	"arm_left": %ArmLFrameValue,
	"leg_left": %LegLFrameValue,
	"arm_right": %ArmRFrameValue,
	"leg_right": %LegRFrameValue,
}

var health_system: Node = null

# Hit feedback: a red full-screen flash + camera shake whenever the player's
# mech takes damage, so getting shot is impossible to miss.
var _hit_flash: ColorRect = null
var _hit_flash_tween: Tween = null

# Energy readout: the mech's boost pool (see mecha_controller) shown as a slim
# cyan bar in the same bottom-center cluster as the HP tubes.
var energy_bar: ProgressBar = null
var energy_label: Label = null
var _player_mecha: Node = null
var _energy_fill: StyleBoxFlat = null
var _energy_bg: StyleBoxFlat = null

# Drop tank HUD indicator (GDD §2.4): shows external fuel canister HP +
# fuel level. Appears only when drop tanks are equipped. Flashes PURGE
# warning text when the detonation countdown starts.
var _dt_container: VBoxContainer = null
var _dt_label: Label = null
var _dt_hp_bar: ProgressBar = null
var _dt_hp_fill: StyleBoxFlat = null
var _dt_fuel_label: Label = null
var _dt_purge_label: Label = null
var _dt_purge_flash_tween: Tween = null

# Precision Dash HUD indicator (GDD §3.2): flashes "PRECISION!" text when the
# player dodges an attack at the last moment during a dash.
var _precision_label: Label = null
var _precision_flash_tween: Tween = null
var _precision_was_dodged: bool = false

# Bond indicator (GDD §5): shows the pilot-mech bond level.
var _bond_label: Label = null
var _bond_bar: ProgressBar = null
var _bond_fill: StyleBoxFlat = null


func _ready() -> void:
	_create_hit_flash()
	_create_energy_row()
	_create_drop_tank_row()
	_create_precision_row()
	_create_bond_row()
	EventBus.damage_received.connect(_on_player_damaged)
	if get_viewport():
		get_viewport().size_changed.connect(_fit_panel_to_content)
	# Two frames so the container layout resolves bar/label minimum sizes.
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_panel_to_content()
	var mecha = GameManager.get_player_mecha()
	if mecha:
		_player_mecha = mecha
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			health_system.armor_broken.connect(_on_armor_broken)
			health_system.part_destroyed.connect(_on_part_destroyed)
			_update_all_bars()


# The HP panel is bottom-anchored with a fixed height, but the per-slot
# armor + frame bars can outgrow that height. Grow the panel upward from its
# bottom anchor so every row (including the LEG HP bars) stays INSIDE the
# panel frame instead of poking out of it — and off the bottom of the
# viewport. The height is clamped to the viewport (never taller than the
# screen allows) and the panel clips its children, so no bar can ever render
# below the bottom edge no matter how short the window is.
func _fit_panel_to_content() -> void:
	var panel = get_node_or_null("Panel")
	if panel == null:
		return
	var vp_h := get_viewport().get_visible_rect().size.y
	var min_height: float = panel.get_combined_minimum_size().y
	var max_height := maxf(vp_h - 100.0, 40.0)
	var fit_h := clampf(min_height, 40.0, max_height)
	# Set a clean 36px bottom margin so the HP panel stays comfortably inside the screen.
	panel.offset_bottom = -36.0
	panel.offset_top = panel.offset_bottom - fit_h
	panel.clip_contents = true


# Adds the ENERGY row (label + slim cyan bar) at the bottom of the HP panel's
# grid, so the mech's boost pool reads as part of the same status cluster.
func _create_energy_row() -> void:
	var grid = get_node_or_null("Panel/Grid")
	if grid == null:
		return
	var row := VBoxContainer.new()
	row.name = "EnergyCell"
	row.add_theme_constant_override("separation", 1)
	grid.add_child(row)

	energy_label = Label.new()
	energy_label.text = "ENERGY:"
	energy_label.add_theme_font_size_override("font_size", 9)
	energy_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	row.add_child(energy_label)

	energy_bar = ProgressBar.new()
	energy_bar.custom_minimum_size = Vector2(120, 8)
	energy_bar.max_value = 100.0
	energy_bar.value = 100.0
	energy_bar.show_percentage = false
	_energy_fill = StyleBoxFlat.new()
	_energy_fill.bg_color = Color(0.2, 0.75, 1.0)
	_energy_fill.corner_radius_top_left = 2
	_energy_fill.corner_radius_top_right = 2
	_energy_fill.corner_radius_bottom_left = 2
	_energy_fill.corner_radius_bottom_right = 2
	energy_bar.add_theme_stylebox_override("fill", _energy_fill)
	_energy_bg = StyleBoxFlat.new()
	_energy_bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	_energy_bg.corner_radius_top_left = 2
	_energy_bg.corner_radius_top_right = 2
	_energy_bg.corner_radius_bottom_left = 2
	_energy_bg.corner_radius_bottom_right = 2
	energy_bar.add_theme_stylebox_override("background", _energy_bg)
	row.add_child(energy_bar)


# Pilot HP label — shown instead of mech HP when the pilot ejects.
var _pilot_hp_label: Label = null
var _pilot_hp_bar: ProgressBar = null
var _pilot_hp_fill: StyleBoxFlat = null
var _mech_panel: Control = null  # reference to the mech HP Panel node


# Polls the mech's boost pool every frame (the mech can be re-created by
# eject/backup spawns) and paints the energy bar, tinting it orange when the
# tank runs low.
func _process(_delta: float) -> void:
	var is_eject := GameManager.current_state == GameManager.State.EJECT
	_update_eject_hud(is_eject)
	if _player_mecha == null or not is_instance_valid(_player_mecha):
		_player_mecha = GameManager.get_player_mecha()
		if _player_mecha == null and not is_eject:
			return
	if not is_eject:
		_update_energy_bar()
		_update_drop_tank_indicator()
	_update_precision_indicator()
	_update_bond_indicator()


func _update_energy_bar() -> void:
	if energy_bar == null or energy_label == null:
		return
	if _player_mecha == null or not is_instance_valid(_player_mecha) or not ("energy" in _player_mecha):
		return
	# Read energy state from the mecha's energy_system subsystem.
	var es = _player_mecha.get("energy_system")
	var max_e: float = 100.0
	var cur_e: float = max_e
	if es:
		max_e = maxf(es.max_energy, 1.0)
		cur_e = clampf(es.energy, 0.0, max_e)
	energy_bar.max_value = max_e
	energy_bar.value = cur_e
	energy_label.text = "ENERGY: %d%%" % int(cur_e / max_e * 100.0)
	if _energy_fill:
		var ratio := cur_e / max_e
		_energy_fill.bg_color = Color(1.0, 0.65, 0.2) if ratio < 0.25 else Color(0.2, 0.75, 1.0)


# A transparent full-screen ColorRect sits above the HUD and flashes red on hit.
func _create_hit_flash() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.name = "HitFlash"
	_hit_flash.color = Color(1.0, 0.05, 0.02, 0.0)
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_flash)
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)


func _on_player_damaged(_slot_name: String, _amount: float, _damage_type: String) -> void:
	if _hit_flash == null:
		return
	# Screen flash: briefly show a strong red, then fade out.
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_hit_flash.color.a = 0.5
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash, "color:a", 0.0, 0.35)

	# Distinct audio cue that the player is under fire.
	if AudioManager:
		AudioManager.play_player_hit()

	# Camera shake so the impact is felt, not just seen.
	var rig = get_tree().get_first_node_in_group("camera_rig")
	if rig and rig.has_method("add_shake"):
		rig.add_shake(0.35)


func _on_health_changed(slot_name: String, _layer: String, _current_hp: float, _max_hp: float) -> void:
	_refresh(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	_refresh(slot_name)


func _on_part_destroyed(slot_name: String) -> void:
	_refresh(slot_name)


func _refresh(slot_name: String) -> void:
	if not armor_bars.has(slot_name) or health_system == null:
		return
	if not health_system.parts.has(slot_name):
		return
	var part = health_system.parts[slot_name]
	armor_bars[slot_name].setup(part["armor_hp"], part["max_armor"], part["destroyed"])
	frame_bars[slot_name].setup(part["frame_hp"], part["max_frame"], part["destroyed"])
	armor_values[slot_name].text = "%d" % int(part["armor_hp"])
	frame_values[slot_name].text = "%d" % int(part["frame_hp"])


func _update_all_bars() -> void:
	for slot_name in armor_bars:
		_refresh(slot_name)


# ---------------------------------------------------------------------------
# DROP TANK HUD INDICATOR (GDD §2.4)
# Shows external fuel canister HP + fuel level + purge warning. The whole
# row is hidden when no drop tanks are equipped.
# ---------------------------------------------------------------------------

func _create_drop_tank_row() -> void:
	var grid = get_node_or_null("Panel/Grid")
	if grid == null:
		return
	_dt_container = VBoxContainer.new()
	_dt_container.name = "DropTankCell"
	_dt_container.add_theme_constant_override("separation", 1)
	_dt_container.visible = false  # hidden until drop tanks are equipped
	grid.add_child(_dt_container)

	# Header label: "DROP TANK" in amber.
	_dt_label = Label.new()
	_dt_label.text = "DROP TANK"
	_dt_label.add_theme_font_size_override("font_size", 9)
	_dt_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.1))
	_dt_container.add_child(_dt_label)

	# HP bar: amber fill, shrinks as the tanks take damage.
	_dt_hp_bar = ProgressBar.new()
	_dt_hp_bar.custom_minimum_size = Vector2(120, 6)
	_dt_hp_bar.max_value = 100.0
	_dt_hp_bar.value = 100.0
	_dt_hp_bar.show_percentage = false
	_dt_hp_fill = StyleBoxFlat.new()
	_dt_hp_fill.bg_color = Color(0.85, 0.55, 0.1)
	_dt_hp_fill.corner_radius_top_left = 2
	_dt_hp_fill.corner_radius_top_right = 2
	_dt_hp_fill.corner_radius_bottom_left = 2
	_dt_hp_fill.corner_radius_bottom_right = 2
	_dt_hp_bar.add_theme_stylebox_override("fill", _dt_hp_fill)
	var dt_bg := StyleBoxFlat.new()
	dt_bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	dt_bg.corner_radius_top_left = 2
	dt_bg.corner_radius_top_right = 2
	dt_bg.corner_radius_bottom_left = 2
	dt_bg.corner_radius_bottom_right = 2
	_dt_hp_bar.add_theme_stylebox_override("background", dt_bg)
	_dt_container.add_child(_dt_hp_bar)

	# Fuel level label: how much fuel remains in the tanks.
	_dt_fuel_label = Label.new()
	_dt_fuel_label.text = "FUEL: 0"
	_dt_fuel_label.add_theme_font_size_override("font_size", 9)
	_dt_fuel_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.4))
	_dt_container.add_child(_dt_fuel_label)

	# Purge warning label: blinks red when detonation countdown starts.
	_dt_purge_label = Label.new()
	_dt_purge_label.text = ""
	_dt_purge_label.add_theme_font_size_override("font_size", 10)
	_dt_purge_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
	_dt_purge_label.visible = false
	_dt_container.add_child(_dt_purge_label)


func _update_drop_tank_indicator() -> void:
	if _dt_container == null:
		return
	if _player_mecha == null or not is_instance_valid(_player_mecha):
		return
	# Read drop tank state from the mecha controller's energy system.
	var es = _player_mecha.get("energy_system")
	var active: bool = es._drop_tank_active if es else false
	if not active:
		_dt_container.visible = false
		return
	_dt_container.visible = true

	# HP bar.
	var max_hp: float = 60.0  # 2 tanks * 30 HP default
	var hp: float = es._drop_tank_hp if es else 0.0
	# Derive max HP from GlobalData.
	var attached_raw = GlobalData.get("drop_tanks_attached")
	var attached: int = int(attached_raw) if attached_raw != null else 0
	max_hp = attached * 30.0  # DROP_TANK_HP_PER_TANK
	if max_hp <= 0.0:
		max_hp = 60.0
	_dt_hp_bar.max_value = max_hp
	_dt_hp_bar.value = maxf(hp, 0.0)
	# Tint: green > orange > red as HP drops.
	var hp_ratio := clampf(hp / max_hp, 0.0, 1.0)
	if _dt_hp_fill:
		if hp_ratio < 0.25:
			_dt_hp_fill.bg_color = Color(0.9, 0.15, 0.1)
		elif hp_ratio < 0.5:
			_dt_hp_fill.bg_color = Color(0.9, 0.55, 0.1)
		else:
			_dt_hp_fill.bg_color = Color(0.4, 0.75, 0.2)
	_dt_label.text = "DROP TANK: %d" % int(hp)

	# Fuel level.
	var fuel_raw = GlobalData.get("drop_tank_fuel")
	var fuel: float = float(fuel_raw) if fuel_raw != null else 0.0
	_dt_fuel_label.text = "FUEL: %d" % int(fuel)

	# Purge warning: show and blink when detonation countdown is active.
	var detonating: bool = es._drop_tank_detonating if es else false
	if detonating:
		if not _dt_purge_label.visible:
			_dt_purge_label.visible = true
			_start_purge_flash()
	else:
		if _dt_purge_label.visible:
			_dt_purge_label.visible = false
			if _dt_purge_flash_tween and _dt_purge_flash_tween.is_valid():
				_dt_purge_flash_tween.kill()
				_dt_purge_label.modulate.a = 1.0


func _start_purge_flash() -> void:
	if _dt_purge_label == null:
		return
	_dt_purge_label.text = "⚠ PURGE [E]"
	if _dt_purge_flash_tween and _dt_purge_flash_tween.is_valid():
		_dt_purge_flash_tween.kill()
	_dt_purge_flash_tween = create_tween().set_loops()
	_dt_purge_flash_tween.tween_property(_dt_purge_label, "modulate:a", 0.15, 0.25)
	_dt_purge_flash_tween.tween_property(_dt_purge_label, "modulate:a", 1.0, 0.25)


# --- Precision Dash HUD (GDD §3.2) ------------------------------------------
# Shows a green "PRECISION!" flash when the player dodges an attack at the
# last moment during a dash, confirming the energy refund.
func _create_precision_row() -> void:
	_precision_label = Label.new()
	_precision_label.text = ""
	_precision_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_precision_label.custom_minimum_size = Vector2(120, 12)
	_precision_label.visible = false
	_precision_label.add_theme_font_size_override("font_size", 11)
	_precision_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	_precision_label.add_theme_stylebox_override("normal", style)
	# Insert after the energy row.
	var grid = get_node_or_null("Panel/Grid")
	if grid:
		grid.add_child(_precision_label)


func _update_precision_indicator() -> void:
	if _precision_label == null or _player_mecha == null:
		return
	if not is_instance_valid(_player_mecha):
		return
	var ds = _player_mecha.get("dash_system")
	var dodged: bool = ds._precision_dodged if ds else false
	if dodged and not _precision_was_dodged:
		# Just triggered — flash the indicator.
		_precision_label.text = "+4 PRECISION!"
		_precision_label.visible = true
		_precision_label.modulate.a = 1.0
		if _precision_flash_tween and _precision_flash_tween.is_valid():
			_precision_flash_tween.kill()
		_precision_flash_tween = create_tween()
		_precision_flash_tween.tween_interval(0.8)
		_precision_flash_tween.tween_property(_precision_label, "modulate:a", 0.0, 0.3)
		_precision_flash_tween.tween_callback(_precision_label.hide)
	_precision_was_dodged = dodged


# --- Bond HUD (GDD §5) -----------------------------------------------------
# Shows the pilot-mech bond level as a slim bar with a heart icon.
func _create_bond_row() -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bond_label = Label.new()
	_bond_label.text = "♥ BOND"
	_bond_label.add_theme_font_size_override("font_size", 9)
	_bond_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.6))
	row.add_child(_bond_label)
	_bond_bar = ProgressBar.new()
	_bond_bar.custom_minimum_size = Vector2(80, 6)
	_bond_bar.max_value = 100.0
	_bond_bar.value = 0.0
	_bond_bar.show_percentage = false
	_bond_fill = StyleBoxFlat.new()
	_bond_fill.bg_color = Color(1.0, 0.4, 0.5)
	_bond_fill.corner_radius_top_left = 2
	_bond_fill.corner_radius_top_right = 2
	_bond_fill.corner_radius_bottom_left = 2
	_bond_fill.corner_radius_bottom_right = 2
	_bond_bar.add_theme_stylebox_override("fill", _bond_fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	_bond_bar.add_theme_stylebox_override("background", bg)
	row.add_child(_bond_bar)
	# Insert into the grid.
	var grid = get_node_or_null("Panel/Grid")
	if grid:
		grid.add_child(row)


func _update_bond_indicator() -> void:
	if _bond_bar == null:
		return
	_bond_bar.value = GlobalData.narrative.mech_bond
	# Tint: pink when low, red when high.
	if _bond_fill:
		var ratio := GlobalData.narrative.mech_bond / 100.0
		_bond_fill.bg_color = Color(1.0, 0.5, 0.6).lerp(Color(1.0, 0.15, 0.2), ratio)


# ---------------------------------------------------------------------------
# EJECT HUD — pilot stats replace mech HUD when the pilot dismounts
# ---------------------------------------------------------------------------

func _update_eject_hud(is_eject: bool) -> void:
	# Lazy-create the pilot HP UI on first eject.
	if _pilot_hp_label == null and is_eject:
		_create_pilot_hp_ui()
	if _pilot_hp_label == null:
		return
	var panel = get_node_or_null("Panel")
	if panel == null:
		return
	# Hide mech-specific rows (armor/frame/energy) when on foot.
	var grid = panel.get_node_or_null("Grid")
	if grid:
		for child in grid.get_children():
			if child.name in ["HeadCell", "BodyCell", "ArmLCell", "ArmRCell", "LegLCell", "LegRCell", "EnergyCell", "DropTankCell"]:
				child.visible = not is_eject
	# Pilot HP bar shows pilot health from PilotSystem.
	_pilot_hp_label.visible = is_eject
	_pilot_hp_bar.visible = is_eject
	if is_eject:
		var hp: float = PilotSystem.get_hp()
		var max_hp: float = PilotSystem.get_max_hp()
		if max_hp <= 0.0:
			max_hp = 100.0
			hp = 100.0
		_pilot_hp_bar.max_value = max_hp
		_pilot_hp_bar.value = hp
		var ratio := clampf(hp / max_hp, 0.0, 1.0)
		if _pilot_hp_fill:
			if ratio < 0.25:
				_pilot_hp_fill.bg_color = Color(0.9, 0.15, 0.1)
			elif ratio < 0.5:
				_pilot_hp_fill.bg_color = Color(0.9, 0.55, 0.1)
			else:
				_pilot_hp_fill.bg_color = Color(0.2, 0.8, 0.3)
		_pilot_hp_label.text = "PILOT: %d / %d" % [int(hp), int(max_hp)]


func _create_pilot_hp_ui() -> void:
	var panel = get_node_or_null("Panel")
	if panel == null:
		return
	var grid = panel.get_node_or_null("Grid")
	if grid == null:
		return
	# Pilot HP label.
	_pilot_hp_label = Label.new()
	_pilot_hp_label.text = "PILOT: 100 / 100"
	_pilot_hp_label.add_theme_font_size_override("font_size", 11)
	_pilot_hp_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.7))
	_pilot_hp_label.visible = false
	grid.add_child(_pilot_hp_label)
	# Pilot HP bar.
	_pilot_hp_bar = ProgressBar.new()
	_pilot_hp_bar.custom_minimum_size = Vector2(140, 8)
	_pilot_hp_bar.max_value = 100.0
	_pilot_hp_bar.value = 100.0
	_pilot_hp_bar.show_percentage = false
	_pilot_hp_bar.visible = false
	_pilot_hp_fill = StyleBoxFlat.new()
	_pilot_hp_fill.bg_color = Color(0.2, 0.8, 0.3)
	_pilot_hp_fill.corner_radius_top_left = 2
	_pilot_hp_fill.corner_radius_top_right = 2
	_pilot_hp_fill.corner_radius_bottom_left = 2
	_pilot_hp_fill.corner_radius_bottom_right = 2
	_pilot_hp_bar.add_theme_stylebox_override("fill", _pilot_hp_fill)
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	bg.corner_radius_top_left = 2
	bg.corner_radius_top_right = 2
	bg.corner_radius_bottom_left = 2
	bg.corner_radius_bottom_right = 2
	_pilot_hp_bar.add_theme_stylebox_override("background", bg)
	grid.add_child(_pilot_hp_bar)
