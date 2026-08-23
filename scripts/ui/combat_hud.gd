extends CanvasLayer

var panel: PanelContainer
var status_label: Label

# Top-of-screen RETREAT indicator: replaces the old world-space "RETREAT ZONE"
# label with a slim banner pinned to the top edge of the screen (inside the
# viewport). It appears while the player stands in an escape zone and shows the
# hold countdown, ramping cyan -> amber -> red as the escape charges.
var retreat_panel: PanelContainer
var retreat_label: Label
var _retreat_fill: StyleBoxFlat

# Temporary announcement banner (reserve-mech delivery, alerts). Shown at the
# top-center below the retreat indicator, fades after `announce()` duration.
var announce_panel: PanelContainer
var announce_label: Label
var _announce_tween: Tween = null

# Countdown Extraction HUD (GDD §7.3): red pulsing banner when area bombing
# is imminent.
var _countdown_panel: PanelContainer
var _countdown_label: Label
var _countdown_fill: StyleBoxFlat
var _countdown_flash_tween: Tween = null


func _ready() -> void:
	layer = 5
	_create_ui()
	_create_retreat_indicator()
	_create_announce_banner()
	_create_countdown_indicator()


func _create_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Sits just below the top edge (not glued to it) so it reads as a status
	# banner instead of part of the screen frame. Width hugs the status text
	# (the longest line is the boss-encounter readout) instead of a wide slab.
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -185
	panel.offset_right = 185
	panel.offset_top = 64
	panel.offset_bottom = 100
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.22, 0.22, 0.22, 1.0)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	status_label = Label.new()
	status_label.text = "COMBAT INITIALIZING..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	panel.add_child(status_label)


func _process(_delta: float) -> void:
	var spawn_mgr = get_tree().current_scene.get_node_or_null("SpawnManager") if get_tree().current_scene else null
	if spawn_mgr:
		var cur_wave = spawn_mgr.get_current_wave()
		var tot_waves = spawn_mgr.get_total_waves()
		var enemies_left = spawn_mgr._get_alive_count()

		if GameManager.is_boss_combat and cur_wave == tot_waves:
			status_label.text = "⚠️ BOSS ENCOUNTER | ENEMIES: %d" % enemies_left
			status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		else:
			status_label.text = "WAVE %d / %d  |  ENEMIES LEFT: %d" % [cur_wave, tot_waves, enemies_left]
			status_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))

	_update_retreat_indicator()
	_update_countdown_indicator()


# Builds the temporary announcement banner pinned under the retreat indicator.
# `announce()` shows a line here (e.g. "RESERVE MECH INBOUND — ETA 30s") that
# fades out automatically. Hidden by default; only appears while announcing.
func _create_announce_banner() -> void:
	announce_panel = PanelContainer.new()
	announce_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	announce_panel.offset_left = -260
	announce_panel.offset_right = 260
	announce_panel.offset_top = 44
	announce_panel.offset_bottom = 74
	announce_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	announce_panel.visible = false
	get_child(0).add_child(announce_panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.09, 0.14, 0.92)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.5, 0.85, 1.0, 0.9)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	announce_panel.add_theme_stylebox_override("panel", style)

	announce_label = Label.new()
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.add_theme_font_size_override("font_size", 15)
	announce_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	announce_panel.add_child(announce_label)


# Shows a temporary banner line at the top of the screen for `duration` seconds
# (then fades out). Replaces any active announcement.
func announce(text: String, duration: float = 3.0) -> void:
	if announce_panel == null or announce_label == null:
		return
	if _announce_tween and _announce_tween.is_valid():
		_announce_tween.kill()
	announce_label.text = text
	announce_panel.visible = true
	announce_panel.modulate = Color.WHITE
	_announce_tween = create_tween()
	_announce_tween.tween_interval(maxf(duration, 0.1))
	_announce_tween.tween_property(announce_panel, "modulate:a", 0.0, 0.6)
	_announce_tween.tween_callback(announce_panel.hide)


# Builds the slim RETREAT banner pinned to the top-center of the screen, above
# the wave/status panel (offset_top 64). Fixed offsets keep it fully inside the
# viewport at every resolution (the project stretches to 1920x1080 logical).
func _create_retreat_indicator() -> void:
	retreat_panel = PanelContainer.new()
	retreat_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	retreat_panel.offset_left = -160
	retreat_panel.offset_right = 160
	retreat_panel.offset_top = 8
	retreat_panel.offset_bottom = 38
	retreat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	retreat_panel.visible = false
	get_child(0).add_child(retreat_panel)

	_retreat_fill = StyleBoxFlat.new()
	_retreat_fill.bg_color = Color(0.08, 0.12, 0.2, 0.9)
	_retreat_fill.border_width_left = 1
	_retreat_fill.border_width_right = 1
	_retreat_fill.border_width_top = 1
	_retreat_fill.border_width_bottom = 1
	_retreat_fill.border_color = Color(0.3, 0.7, 1.0, 0.9)
	_retreat_fill.corner_radius_top_left = 0
	_retreat_fill.corner_radius_top_right = 0
	_retreat_fill.corner_radius_bottom_left = 0
	_retreat_fill.corner_radius_bottom_right = 0
	retreat_panel.add_theme_stylebox_override("panel", _retreat_fill)

	retreat_label = Label.new()
	retreat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	retreat_label.add_theme_font_size_override("font_size", 15)
	retreat_label.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	retreat_panel.add_child(retreat_label)


# Polls every escape zone; shows the banner while the player is inside one (or
# while a retreat is completing) and paints the countdown + color ramp.
func _update_retreat_indicator() -> void:
	if retreat_panel == null or retreat_label == null:
		return
	var zones := get_tree().get_nodes_in_group("escape_zone")
	var shown := false
	var progress := 0.0
	var remaining := 0.0
	var completing := false
	for zone in zones:
		if not is_instance_valid(zone):
			continue
		if zone.has_method("is_escape_complete") and zone.is_escape_complete():
			completing = true
			remaining = 0.0
			progress = 1.0
			shown = true
			break
		if zone.has_method("is_player_inside") and zone.is_player_inside():
			progress = zone.get_hold_progress()
			remaining = zone.get_hold_remaining()
			shown = true
			break

	if not shown:
		retreat_panel.visible = false
		return
	retreat_panel.visible = true

	if completing:
		retreat_label.text = "RETREATING..."
		retreat_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
		_retreat_fill.border_color = Color(1.0, 0.3, 0.25, 0.9)
	else:
		retreat_label.text = "RETREAT — HOLD %.1fs" % remaining
		var c := Color(0.5, 0.9, 1.0).lerp(Color(1.0, 0.85, 0.25), progress)
		if progress > 0.5:
			c = c.lerp(Color(1.0, 0.3, 0.25), (progress - 0.5) * 2.0)
		retreat_label.add_theme_color_override("font_color", c)
		_retreat_fill.border_color = Color(c.r, c.g, c.b, 0.9)


# --- Countdown Extraction HUD (GDD §7.3) ------------------------------------
func _create_countdown_indicator() -> void:
	_countdown_panel = PanelContainer.new()
	_countdown_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_countdown_panel.offset_left = -140
	_countdown_panel.offset_right = 140
	_countdown_panel.offset_top = 32
	_countdown_panel.offset_bottom = 58
	_countdown_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_panel.visible = false
	var root = get_child(0) if get_child_count() > 0 else null
	if root and root is Control:
		root.add_child(_countdown_panel)
	_countdown_fill = StyleBoxFlat.new()
	_countdown_fill.bg_color = Color(0.8, 0.1, 0.1, 0.9)
	_countdown_fill.corner_radius_top_left = 0
	_countdown_fill.corner_radius_top_right = 0
	_countdown_fill.corner_radius_bottom_left = 0
	_countdown_fill.corner_radius_bottom_right = 0
	_countdown_panel.add_theme_stylebox_override("panel", _countdown_fill)
	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 14)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_countdown_panel.add_child(_countdown_label)


func _update_countdown_indicator() -> void:
	if _countdown_panel == null or _countdown_label == null:
		return
	if not GlobalData.board.mid_battle_countdown_active:
		_countdown_panel.visible = false
		if _countdown_flash_tween and _countdown_flash_tween.is_valid():
			_countdown_flash_tween.kill()
			_countdown_panel.modulate.a = 1.0
		return
	_countdown_panel.visible = true
	var remaining = GlobalData.board.mid_battle_countdown_timer
	var max_time = GlobalData.board.mid_battle_countdown_max
	var progress = 1.0 - clampf(remaining / max_time, 0.0, 1.0)
	_countdown_label.text = "☢ EXTRACTION — %.1fs" % maxf(remaining, 0.0)
	# Color ramps from amber to red as time runs out.
	var c := Color(1.0, 0.85, 0.25).lerp(Color(1.0, 0.15, 0.1), progress)
	_countdown_label.add_theme_color_override("font_color", c)
	_countdown_fill.border_color = Color(c.r, c.g, c.b, 0.9)
	# Pulse when under 10 seconds.
	if remaining < 10.0 and (_countdown_flash_tween == null or not _countdown_flash_tween.is_valid()):
		_countdown_flash_tween = create_tween().set_loops()
		_countdown_flash_tween.tween_property(_countdown_panel, "modulate:a", 0.5, 0.3)
		_countdown_flash_tween.tween_property(_countdown_panel, "modulate:a", 1.0, 0.3)
