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


func _ready() -> void:
	_create_hit_flash()
	_create_energy_row()
	EventBus.damage_received.connect(_on_player_damaged)
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
	# Keep a safe margin off the top edge; the bottom offset is already a
	# negative (padded) value so the panel stays inside the screen.
	var max_height := maxf(vp_h - 80.0, 40.0)
	var fit_h := clampf(min_height, 40.0, max_height)
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


# Polls the mech's boost pool every frame (the mech can be re-created by
# eject/backup spawns) and paints the energy bar, tinting it orange when the
# tank runs low.
func _process(_delta: float) -> void:
	if _player_mecha == null or not is_instance_valid(_player_mecha):
		_player_mecha = GameManager.get_player_mecha()
		if _player_mecha == null:
			return
	_update_energy_bar()


func _update_energy_bar() -> void:
	if energy_bar == null or energy_label == null:
		return
	if _player_mecha == null or not is_instance_valid(_player_mecha) or not ("energy" in _player_mecha):
		return
	# _player_mecha is a plain Node, so read the mech's energy fields through
	# the 1-arg Object.get() (missing -> null) and fall back to defaults.
	var max_e: float = 100.0
	var max_raw = _player_mecha.get("max_energy")
	if max_raw != null:
		max_e = maxf(float(max_raw), 1.0)
	var cur_raw = _player_mecha.get("energy")
	var cur_e: float = clampf(float(cur_raw) if cur_raw != null else max_e, 0.0, max_e)
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
