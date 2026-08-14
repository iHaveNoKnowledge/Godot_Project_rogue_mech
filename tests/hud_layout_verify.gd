extends Node

## Headless verification of the combat HUD layout:
##   - the HP panel (core_hud.tscn) anchors to the bottom-center of the screen,
##     stays padded off the bottom edge, renders with a solid dark backing that
##     only fades at the corners, and keeps its original shape: head/body bars
##     span the full container while limb bars sit in half-width columns.
##   - the squad panel (squad_hud.gd) anchors to the top-left corner so it no
##     longer overlaps the bottom-left hand-weapon panel.
## Run: godot --headless --path . res://tests/hud_layout_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_hp_panel()
	await _verify_squad_panel()
	print("HUD_LAYOUT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _verify_hp_panel() -> void:
	var core = load("res://scenes/ui/core_hud.tscn").instantiate()
	add_child(core)
	# Three frames: _ready builds the hit flash + awaits twice, then auto-fits the
	# panel height to its content; one more frame applies that layout pass so the
	# measured rect reflects the fitted size.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var panel = core.get_node_or_null("Panel")
	_check(panel != null, "core HUD builds its Panel")
	if panel:
		# Anchored to the horizontal center of the screen.
		_check(is_equal_approx(panel.anchor_left, 0.5) and is_equal_approx(panel.anchor_right, 0.5), "HP panel anchors to the horizontal center")
		# Anchored to the bottom of the screen.
		_check(is_equal_approx(panel.anchor_top, 1.0) and is_equal_approx(panel.anchor_bottom, 1.0), "HP panel anchors to the bottom")
		# Padded off the bottom screen edge (negative bottom offset).
		_check(panel.offset_bottom < 0.0, "HP panel is padded away from the bottom screen edge")
		# Dark translucent backing with faded corners: the panel stylebox is a
		# texture stylebox drawing a radial GradientTexture2D that is mostly
		# solid in the middle (so the tubes read opaque) and only fades near
		# the corners.
		var style = panel.get_theme_stylebox("panel")
		_check(style is StyleBoxTexture, "HP panel background uses a texture stylebox")
		if style is StyleBoxTexture:
			var tex = style.texture
			_check(tex is GradientTexture2D, "HP panel background uses a gradient texture")
			if tex is GradientTexture2D and tex.gradient != null:
				var colors: PackedColorArray = tex.gradient.colors
				_check(colors.size() > 0 and colors[0].a > 0.7, "HP panel backing is nearly solid behind the tubes")
				_check(colors.size() > 2 and colors[colors.size() - 1].a == 0.0, "HP panel background still fades at the corners")
		# The resolved rect lands centered on the bottom edge of the viewport.
		var vp := get_viewport().get_visible_rect().size
		var rect = panel.get_global_rect()
		_check(absf((rect.position.x + rect.size.x * 0.5) - vp.x * 0.5) < 2.0, "HP panel renders centered on the bottom edge")
		_check(absf((rect.position.y + rect.size.y) - (vp.y + panel.offset_bottom)) < 2.0, "HP panel bottom matches its padded offset")
		# The whole HP UI grew ~20% longer than the compact 304px version.
		var panel_w = panel.offset_right - panel.offset_left
		_check(panel_w >= 350.0, "HP panel is ~20% longer than the compact version")
		# core_hud auto-fits the panel height to its content, so every row —
		# including the LEG frame bar, the last one — stays INSIDE the panel
		# frame and inside the viewport instead of poking out of both.
		var leg_frame = panel.get_node_or_null("Grid/PartsGrid/RightCell/LegRFrameBar")
		_check(leg_frame != null, "HP panel still builds the leg frame bar")
		if leg_frame:
			var panel_bottom = rect.position.y + rect.size.y
			var leg_bottom = leg_frame.get_global_rect().position.y + leg_frame.get_global_rect().size.y
			_check(leg_bottom <= panel_bottom + 1.0, "leg HP bar stays inside the panel frame")
			_check(panel_bottom <= vp.y, "HP panel bottom stays inside the viewport")
			_check(panel_bottom <= vp.y - 8.0, "HP panel keeps a clear margin off the viewport bottom")

		# The original shape is back: head/body bars span the full container
		# width while the limb bars sit in their half-width grid columns, and
		# every bar fills its cell again instead of pinning to 120px.
		var head_bar = panel.get_node_or_null("Grid/HeadCell/HeadArmorBar")
		var body_bar = panel.get_node_or_null("Grid/BodyCell/BodyArmorBar")
		var arm_bar = panel.get_node_or_null("Grid/PartsGrid/LeftCell/ArmLArmorBar")
		var leg_bar = panel.get_node_or_null("Grid/PartsGrid/LeftCell/LegLArmorBar")
		_check(head_bar != null and head_bar.size_flags_horizontal == Control.SIZE_FILL, "part bars fill their cells again")
		if head_bar and body_bar and arm_bar:
			_check(head_bar.size.x >= 300.0, "head bar spans the full container width")
			_check(absf(head_bar.size.x - body_bar.size.x) < 2.0, "body bar matches the head bar's full width")
			_check(arm_bar.size.x < head_bar.size.x * 0.7, "arm/leg bars stay narrower than the full-width bars")
			_check(arm_bar.size.x >= 140.0, "limb bars grew ~20% longer")
			_check(leg_bar != null and absf(leg_bar.size.x - arm_bar.size.x) < 2.0, "left limb bars share one column width")
		# Heights stay compact (only the length grew).
		if head_bar:
			_check(head_bar.size.y <= 12.0, "bar heights stay compact")

	core.queue_free()
	await get_tree().process_frame


func _verify_squad_panel() -> void:
	var squad = load("res://scripts/ui/squad_hud.gd").new()
	add_child(squad)
	await get_tree().process_frame
	await get_tree().process_frame

	var panel = squad.panel
	_check(panel != null, "squad HUD builds its panel")
	if panel:
		# Anchored to the top-left corner.
		_check(is_equal_approx(panel.anchor_left, 0.0) and is_equal_approx(panel.anchor_top, 0.0), "squad panel anchors to the top-left")
		_check(is_equal_approx(panel.anchor_right, 0.0) and is_equal_approx(panel.anchor_bottom, 0.0), "squad panel is not bottom-anchored")
		# Sits inside the top-left corner (positive offsets from it).
		_check(panel.offset_left >= 0.0 and panel.offset_top >= 0.0, "squad panel sits inside the top-left corner")
		# Resolved rect stays in the top half / left half, clear of the
		# bottom-left hand-weapon panel.
		var vp := get_viewport().get_visible_rect().size
		var rect = panel.get_global_rect()
		_check(rect.position.y + rect.size.y <= vp.y * 0.5, "squad panel stays in the top half of the screen")
		_check(rect.position.x < vp.x * 0.5, "squad panel stays in the left half of the screen")

	squad.queue_free()
	await get_tree().process_frame
