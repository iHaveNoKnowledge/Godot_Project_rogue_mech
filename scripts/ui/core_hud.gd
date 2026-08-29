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

# Drop tank HUD indicator (GDD §2.4)
var _dt_container: VBoxContainer = null
var _dt_label: Label = null
var _dt_hp_bar: ProgressBar = null
var _dt_hp_fill: StyleBoxFlat = null
var _dt_fuel_label: Label = null
var _dt_purge_label: Label = null
var _dt_purge_flash_tween: Tween = null

# Precision Dash HUD indicator (GDD §3.2)
var _precision_label: Label = null
var _precision_flash_tween: Tween = null
var _precision_was_dodged: bool = false

# Pilot Mode HUD
var _pilot_panel: PanelContainer = null
var _pilot_hp_label: Label = null
var _pilot_hp_bar: ProgressBar = null
var _pilot_hp_fill: StyleBoxFlat = null
var _pilot_stamina_label: Label = null
var _pilot_stamina_bar: ProgressBar = null
var _pilot_stamina_fill: StyleBoxFlat = null
var _pilot_weapon_label: Label = null
var _pilot_ammo_label: Label = null
var _pilot_reload_bar: ProgressBar = null
var _pilot_reload_fill: StyleBoxFlat = null

# Interaction Prompt Banner
var _interaction_panel: PanelContainer = null
var _interaction_label: Label = null

# Combat Mode / Guard & Pile Bunker Stance Widget
var _mode_label: Label = null
var _guard_badge: Label = null
var _pile_badge: Label = null


func _ready() -> void:
	_create_hit_flash()
	_create_energy_row()
	_create_drop_tank_row()
	_create_precision_row()
	_create_combat_mode_widget()
	_create_pilot_hud_panel()
	_create_interaction_prompt_widget()

	EventBus.damage_received.connect(_on_player_damaged)
	EventBus.combat_mode_toggled.connect(_on_combat_mode_toggled)
	EventBus.guard_state_changed.connect(_on_guard_state_changed)
	EventBus.deflect_triggered.connect(_on_deflect_triggered)
	EventBus.pile_bunker_fired.connect(_on_pile_bunker_fired)
	EventBus.interaction_prompt_updated.connect(_on_interaction_prompt_updated)

	if get_viewport():
		get_viewport().size_changed.connect(_fit_panel_to_content)

	# Two frames so the container layout resolves bar/label minimum sizes.
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_panel_to_content()
	_rebind_to_active_mecha()


func _process(_delta: float) -> void:
	var is_eject := GameManager.current_state == GameManager.State.EJECT
	_update_eject_hud(is_eject)

	if not is_eject:
		var current_mecha := GameManager.get_player_mecha()
		if current_mecha != _player_mecha:
			_rebind_to_active_mecha()

		_update_energy_bar()
		_update_drop_tank_indicator()
		_update_precision_indicator()


func _rebind_to_active_mecha() -> void:
	var mecha := GameManager.get_player_mecha()
	if mecha == null or not is_instance_valid(mecha):
		return

	if health_system and is_instance_valid(health_system):
		if health_system.health_changed.is_connected(_on_health_changed):
			health_system.health_changed.disconnect(_on_health_changed)
		if health_system.armor_broken.is_connected(_on_armor_broken):
			health_system.armor_broken.disconnect(_on_armor_broken)
		if health_system.part_destroyed.is_connected(_on_part_destroyed):
			health_system.part_destroyed.disconnect(_on_part_destroyed)

	_player_mecha = mecha
	health_system = mecha.get_node_or_null("HealthSystem")
	if health_system:
		health_system.health_changed.connect(_on_health_changed)
		health_system.armor_broken.connect(_on_armor_broken)
		health_system.part_destroyed.connect(_on_part_destroyed)
		_update_all_bars()


func _update_eject_hud(is_eject: bool) -> void:
	var mech_panel := get_node_or_null("Panel")
	if mech_panel:
		mech_panel.visible = not is_eject

	if _pilot_panel:
		_pilot_panel.visible = is_eject

	if is_eject:
		# Update Pilot Health
		var hp: float = PilotSystem.get_hp()
		var max_hp: float = PilotSystem.get_max_hp()
		if max_hp <= 0.0:
			max_hp = 100.0
			hp = 100.0
		if _pilot_hp_bar:
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
		if _pilot_hp_label:
			_pilot_hp_label.text = "PILOT HEALTH: %d / %d" % [int(hp), int(max_hp)]

		# Update Pilot Stamina
		var pilots := get_tree().get_nodes_in_group("pilot")
		if not pilots.is_empty() and is_instance_valid(pilots[0]):
			var p = pilots[0]
			var stam_ratio: float = p.get_stamina_ratio() if p.has_method("get_stamina_ratio") else 1.0
			if _pilot_stamina_bar:
				_pilot_stamina_bar.value = stam_ratio * 100.0
			if _pilot_stamina_label:
				_pilot_stamina_label.text = "STAMINA: %d%%" % int(stam_ratio * 100.0)
			if _pilot_weapon_label and p.get("_weapons") != null:
				var weaps: Array = p.get("_weapons")
				var widx: int = int(p.get("_weapon_index")) if p.get("_weapon_index") != null else 0
				if not weaps.is_empty() and widx < weaps.size():
					var w = weaps[widx]
					var wname: String = w.weapon_name if "weapon_name" in w else "Sidearm"
					var atype: String = w.get_ammo_type() if w.has_method("get_ammo_type") else "none"
					var reserve_cnt: int = PilotSystem.get_ammo(atype) if atype != "none" else 999
					var cur_mag: int = p.get_current_magazine() if p.has_method("get_current_magazine") else 0
					var max_mag: int = p.get_max_magazine() if p.has_method("get_max_magazine") else 0
					var is_rel: bool = p.is_currently_reloading() if p.has_method("is_currently_reloading") else false
					var rel_prog: float = p.get_reload_progress() if p.has_method("get_reload_progress") else 0.0

					_pilot_weapon_label.text = "WEAPON: %s" % wname

					if _pilot_ammo_label:
						if atype != "none":
							if is_rel:
								_pilot_ammo_label.text = "⟳ RELOADING... [%d%%]" % int(rel_prog * 100.0)
								_pilot_ammo_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
							else:
								_pilot_ammo_label.text = "AMMO: [ %d / %d ]  (Res: %d) [R]" % [cur_mag, max_mag, reserve_cnt]
								_pilot_ammo_label.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0) if cur_mag > 0 else Color(1.0, 0.3, 0.25))
						else:
							_pilot_ammo_label.text = "AMMO: ∞ (Melee)"
							_pilot_ammo_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))

					if _pilot_reload_bar:
						_pilot_reload_bar.visible = is_rel
						if is_rel:
							_pilot_reload_bar.value = rel_prog * 100.0


func _create_pilot_hud_panel() -> void:
	_pilot_panel = PanelContainer.new()
	_pilot_panel.name = "PilotHUDPanel"
	_pilot_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_pilot_panel.offset_left = -170
	_pilot_panel.offset_right = 170
	_pilot_panel.offset_top = -140
	_pilot_panel.offset_bottom = -30
	_pilot_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pilot_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.8, 1.0, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_pilot_panel.add_theme_stylebox_override("panel", style)
	_pilot_panel.visible = false
	add_child(_pilot_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_pilot_panel.add_child(vbox)

	var title := Label.new()
	title.text = "🧑‍✈️ PILOT ON FOOT [TPS STANCE]"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	vbox.add_child(title)

	# Health Bar
	_pilot_hp_label = Label.new()
	_pilot_hp_label.text = "PILOT HEALTH: 100 / 100"
	_pilot_hp_label.add_theme_font_size_override("font_size", 10)
	_pilot_hp_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.8))
	vbox.add_child(_pilot_hp_label)

	_pilot_hp_bar = ProgressBar.new()
	_pilot_hp_bar.custom_minimum_size = Vector2(200, 8)
	_pilot_hp_bar.max_value = 100.0
	_pilot_hp_bar.value = 100.0
	_pilot_hp_bar.show_percentage = false
	_pilot_hp_fill = StyleBoxFlat.new()
	_pilot_hp_fill.bg_color = Color(0.2, 0.8, 0.3)
	_pilot_hp_bar.add_theme_stylebox_override("fill", _pilot_hp_fill)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	_pilot_hp_bar.add_theme_stylebox_override("background", bg)
	vbox.add_child(_pilot_hp_bar)

	# Stamina Bar
	_pilot_stamina_label = Label.new()
	_pilot_stamina_label.text = "STAMINA: 100%"
	_pilot_stamina_label.add_theme_font_size_override("font_size", 9)
	_pilot_stamina_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vbox.add_child(_pilot_stamina_label)

	_pilot_stamina_bar = ProgressBar.new()
	_pilot_stamina_bar.custom_minimum_size = Vector2(200, 6)
	_pilot_stamina_bar.max_value = 100.0
	_pilot_stamina_bar.value = 100.0
	_pilot_stamina_bar.show_percentage = false
	_pilot_stamina_fill = StyleBoxFlat.new()
	_pilot_stamina_fill.bg_color = Color(0.2, 0.75, 1.0)
	_pilot_stamina_bar.add_theme_stylebox_override("fill", _pilot_stamina_fill)
	var s_bg := StyleBoxFlat.new()
	s_bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	_pilot_stamina_bar.add_theme_stylebox_override("background", s_bg)
	vbox.add_child(_pilot_stamina_bar)

	# Weapon info
	_pilot_weapon_label = Label.new()
	_pilot_weapon_label.text = "WEAPON: Sidearm Submachine Gun"
	_pilot_weapon_label.add_theme_font_size_override("font_size", 10)
	_pilot_weapon_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	vbox.add_child(_pilot_weapon_label)

	# Ammo info & Reload indicator
	_pilot_ammo_label = Label.new()
	_pilot_ammo_label.text = "AMMO: [ 30 / 30 ]  (Res: 120) [R]"
	_pilot_ammo_label.add_theme_font_size_override("font_size", 10)
	_pilot_ammo_label.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	vbox.add_child(_pilot_ammo_label)

	_pilot_reload_bar = ProgressBar.new()
	_pilot_reload_bar.custom_minimum_size = Vector2(200, 4)
	_pilot_reload_bar.max_value = 100.0
	_pilot_reload_bar.value = 0.0
	_pilot_reload_bar.show_percentage = false
	_pilot_reload_bar.visible = false
	_pilot_reload_fill = StyleBoxFlat.new()
	_pilot_reload_fill.bg_color = Color(1.0, 0.75, 0.2)
	_pilot_reload_bar.add_theme_stylebox_override("fill", _pilot_reload_fill)
	_pilot_reload_bar.add_theme_stylebox_override("background", s_bg)
	vbox.add_child(_pilot_reload_bar)


func _fit_panel_to_content() -> void:
	var panel := get_node_or_null("Panel")
	if panel == null:
		return
	var vp_h := get_viewport().get_visible_rect().size.y
	var min_height: float = panel.get_combined_minimum_size().y
	var max_height := maxf(vp_h - 100.0, 40.0)
	var fit_h := clampf(min_height, 40.0, max_height)
	panel.offset_bottom = -36.0
	panel.offset_top = panel.offset_bottom - fit_h
	panel.clip_contents = true


func _create_energy_row() -> void:
	var grid := get_node_or_null("Panel/Grid")
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
	_energy_fill.corner_radius_top_left = 0
	_energy_fill.corner_radius_top_right = 0
	_energy_fill.corner_radius_bottom_left = 0
	_energy_fill.corner_radius_bottom_right = 0
	energy_bar.add_theme_stylebox_override("fill", _energy_fill)
	_energy_bg = StyleBoxFlat.new()
	_energy_bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	_energy_bg.corner_radius_top_left = 0
	_energy_bg.corner_radius_top_right = 0
	_energy_bg.corner_radius_bottom_left = 0
	_energy_bg.corner_radius_bottom_right = 0
	energy_bar.add_theme_stylebox_override("background", _energy_bg)
	row.add_child(energy_bar)


func _update_energy_bar() -> void:
	if energy_bar == null or energy_label == null:
		return
	if _player_mecha == null or not is_instance_valid(_player_mecha):
		return
	var es = _player_mecha.get("energy_system")
	var max_e: float = 100.0
	var cur_e: float = max_e
	if es:
		max_e = maxf(es.max_energy, 1.0)
		cur_e = clampf(es.energy, 0.0, max_e)
	elif "energy" in _player_mecha:
		max_e = maxf(float(_player_mecha.get("max_energy")), 1.0)
		cur_e = clampf(float(_player_mecha.get("energy")), 0.0, max_e)
	elif GlobalData.fuel:
		max_e = maxf(GlobalData.fuel.mech_max_energy, 1.0)
		cur_e = clampf(GlobalData.fuel.mech_energy, 0.0, max_e)

	energy_bar.max_value = max_e
	energy_bar.value = cur_e
	energy_label.text = "ENERGY: %d%%" % int(cur_e / max_e * 100.0)
	if _energy_fill:
		var ratio := cur_e / max_e
		_energy_fill.bg_color = Color(1.0, 0.65, 0.2) if ratio < 0.25 else Color(0.2, 0.75, 1.0)


func _create_hit_flash() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.name = "HitFlash"
	_hit_flash.color = Color(1.0, 0.05, 0.02, 0.0)
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_flash)


func _on_player_damaged(_slot_name: String, _amount: float, _damage_type: String) -> void:
	if _hit_flash == null:
		return
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_hit_flash.color.a = 0.5
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash, "color:a", 0.0, 0.35)

	if AudioManager:
		AudioManager.play_player_hit()

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
	if not armor_bars.has(slot_name) or health_system == null or not is_instance_valid(health_system):
		return
	if not health_system.parts.has(slot_name):
		return
	var part = health_system.parts[slot_name]
	if armor_bars[slot_name]:
		armor_bars[slot_name].setup(part["armor_hp"], part["max_armor"], part["destroyed"])
	if frame_bars[slot_name]:
		frame_bars[slot_name].setup(part["frame_hp"], part["max_frame"], part["destroyed"])
	if armor_values[slot_name]:
		armor_values[slot_name].text = "%d" % int(part["armor_hp"])
	if frame_values[slot_name]:
		frame_values[slot_name].text = "%d" % int(part["frame_hp"])


func _update_all_bars() -> void:
	for slot_name in armor_bars:
		_refresh(slot_name)


func _create_drop_tank_row() -> void:
	var grid := get_node_or_null("Panel/Grid")
	if grid == null:
		return
	_dt_container = VBoxContainer.new()
	_dt_container.name = "DropTankCell"
	_dt_container.add_theme_constant_override("separation", 1)
	_dt_container.visible = false
	grid.add_child(_dt_container)

	_dt_label = Label.new()
	_dt_label.text = "DROP TANK"
	_dt_label.add_theme_font_size_override("font_size", 9)
	_dt_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.1))
	_dt_container.add_child(_dt_label)

	_dt_hp_bar = ProgressBar.new()
	_dt_hp_bar.custom_minimum_size = Vector2(120, 6)
	_dt_hp_bar.max_value = 100.0
	_dt_hp_bar.value = 100.0
	_dt_hp_bar.show_percentage = false
	_dt_hp_fill = StyleBoxFlat.new()
	_dt_hp_fill.bg_color = Color(0.85, 0.55, 0.1)
	_dt_hp_bar.add_theme_stylebox_override("fill", _dt_hp_fill)
	var dt_bg := StyleBoxFlat.new()
	dt_bg.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	_dt_hp_bar.add_theme_stylebox_override("background", dt_bg)
	_dt_container.add_child(_dt_hp_bar)

	_dt_fuel_label = Label.new()
	_dt_fuel_label.text = "FUEL: 0"
	_dt_fuel_label.add_theme_font_size_override("font_size", 9)
	_dt_fuel_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.4))
	_dt_container.add_child(_dt_fuel_label)

	_dt_purge_label = Label.new()
	_dt_purge_label.text = ""
	_dt_purge_label.add_theme_font_size_override("font_size", 10)
	_dt_purge_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
	_dt_purge_label.visible = false
	_dt_container.add_child(_dt_purge_label)


func _update_drop_tank_indicator() -> void:
	if _dt_container == null or _player_mecha == null or not is_instance_valid(_player_mecha):
		return
	var es = _player_mecha.get("energy_system")
	var active: bool = es._drop_tank_active if es else false
	if not active:
		_dt_container.visible = false
		return
	_dt_container.visible = true

	var max_hp: float = 60.0
	var hp: float = es._drop_tank_hp if es else 0.0
	var attached_raw = GlobalData.get("drop_tanks_attached")
	var attached: int = int(attached_raw) if attached_raw != null else 0
	max_hp = attached * 30.0
	if max_hp <= 0.0:
		max_hp = 60.0
	_dt_hp_bar.max_value = max_hp
	_dt_hp_bar.value = maxf(hp, 0.0)
	var hp_ratio := clampf(hp / max_hp, 0.0, 1.0)
	if _dt_hp_fill:
		if hp_ratio < 0.25:
			_dt_hp_fill.bg_color = Color(0.9, 0.15, 0.1)
		elif hp_ratio < 0.5:
			_dt_hp_fill.bg_color = Color(0.9, 0.55, 0.1)
		else:
			_dt_hp_fill.bg_color = Color(0.4, 0.75, 0.2)
	_dt_label.text = "DROP TANK: %d" % int(hp)

	var fuel_raw = GlobalData.get("drop_tank_fuel")
	var fuel: float = float(fuel_raw) if fuel_raw != null else 0.0
	_dt_fuel_label.text = "FUEL: %d" % int(fuel)

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


func _create_precision_row() -> void:
	var grid := get_node_or_null("Panel/Grid")
	if grid == null:
		return
	_precision_label = Label.new()
	_precision_label.name = "PrecisionLabel"
	_precision_label.text = "✦ PRECISION DASH! (+25% Energy)"
	_precision_label.add_theme_font_size_override("font_size", 9)
	_precision_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_precision_label.visible = false
	grid.add_child(_precision_label)


func _update_precision_indicator() -> void:
	if _precision_label == null or _player_mecha == null or not is_instance_valid(_player_mecha):
		return
	var ds = _player_mecha.get("dash_system")
	var dodged: bool = ds._precision_dodged if ds else false
	if dodged and not _precision_was_dodged:
		_precision_was_dodged = true
		_precision_label.visible = true
		_precision_label.modulate.a = 1.0
		if _precision_flash_tween and _precision_flash_tween.is_valid():
			_precision_flash_tween.kill()
		_precision_flash_tween = create_tween()
		_precision_flash_tween.tween_interval(1.2)
		_precision_flash_tween.tween_property(_precision_label, "modulate:a", 0.0, 0.4)
		_precision_flash_tween.tween_callback(func(): _precision_label.visible = false)
	elif not dodged:
		_precision_was_dodged = false


func _create_combat_mode_widget() -> void:
	var panel := get_node_or_null("Panel")
	if panel == null:
		return
	var grid := panel.get_node_or_null("Grid")
	if grid == null:
		return

	var row := HBoxContainer.new()
	row.name = "CombatModeRow"
	row.add_theme_constant_override("separation", 6)
	grid.add_child(row)

	_mode_label = Label.new()
	_mode_label.text = "MODE: BALANCED"
	_mode_label.add_theme_font_size_override("font_size", 10)
	_mode_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	row.add_child(_mode_label)

	_guard_badge = Label.new()
	_guard_badge.text = "[Q] GUARD"
	_guard_badge.add_theme_font_size_override("font_size", 10)
	_guard_badge.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	row.add_child(_guard_badge)

	_pile_badge = Label.new()
	_pile_badge.text = "PILE: READY"
	_pile_badge.add_theme_font_size_override("font_size", 10)
	_pile_badge.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	_pile_badge.visible = false
	row.add_child(_pile_badge)


func _on_combat_mode_toggled(mode: String) -> void:
	if _mode_label == null:
		return
	if mode == "close_combat":
		_mode_label.text = "MODE: CLOSE COMBAT"
		_mode_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	else:
		_mode_label.text = "MODE: BALANCED"
		_mode_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))


func _on_guard_state_changed(is_guarding: bool) -> void:
	if _guard_badge == null:
		return
	if is_guarding:
		_guard_badge.text = "[Q] GUARDING"
		_guard_badge.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	else:
		_guard_badge.text = "[Q] GUARD"
		_guard_badge.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))


func _on_deflect_triggered(_pos: Vector3, is_perfect: bool) -> void:
	if _guard_badge == null:
		return
	_guard_badge.text = "DEFLECT PARRY!" if is_perfect else "DEFLECT"
	_guard_badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.1))
	var tween := create_tween()
	tween.tween_interval(0.6)
	tween.tween_callback(func():
		if _guard_badge:
			_guard_badge.text = "[Q] GUARD"
			_guard_badge.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	)


func _on_pile_bunker_fired(is_loaded_blast: bool, _target_pos: Vector3) -> void:
	if _pile_badge == null:
		return
	_pile_badge.visible = true
	if is_loaded_blast:
		_pile_badge.text = "PILE: BLAST [FIRE]"
		_pile_badge.add_theme_color_override("font_color", Color(1.0, 0.2, 0.0))
	else:
		_pile_badge.text = "PILE: COMBO [HAMMER]"
		_pile_badge.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))


func _create_interaction_prompt_widget() -> void:
	_interaction_panel = PanelContainer.new()
	_interaction_panel.name = "InteractionPromptPanel"
	_interaction_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_interaction_panel.offset_left = -180
	_interaction_panel.offset_right = 180
	_interaction_panel.offset_top = -150
	_interaction_panel.offset_bottom = -105
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.85, 1.0, 0.8)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_interaction_panel.add_theme_stylebox_override("panel", style)
	_interaction_panel.visible = false
	add_child(_interaction_panel)

	_interaction_label = Label.new()
	_interaction_label.text = "[ F ] Board Mecha"
	_interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_label.add_theme_font_size_override("font_size", 14)
	_interaction_label.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	_interaction_panel.add_child(_interaction_label)


func _on_interaction_prompt_updated(prompt_text: String, is_visible: bool) -> void:
	if _interaction_panel == null:
		_create_interaction_prompt_widget()
	if _interaction_panel:
		_interaction_panel.visible = is_visible
		if is_visible and _interaction_label:
			_interaction_label.text = prompt_text
