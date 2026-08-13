extends Node

## Headless verification of the combat HUD layout:
##   - the HP panel (core_hud.tscn) anchors to the bottom-center of the screen,
##     stays padded off the bottom edge, renders with a semi-transparent faded
##     background, and keeps its part bars compact.
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
	# Two frames: one for _ready to build the hit flash, one for the container
	# layout pass that resolves anchors into the final panel rect.
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
		# Semi-transparent background with faded edges: the panel stylebox is a
		# texture stylebox drawing a radial GradientTexture2D whose start color
		# is not fully opaque (edges fade toward alpha 0).
		var style = panel.get_theme_stylebox("panel")
		_check(style is StyleBoxTexture, "HP panel background uses a texture stylebox")
		if style is StyleBoxTexture:
			var tex = style.texture
			_check(tex is GradientTexture2D, "HP panel background uses a gradient texture")
			if tex is GradientTexture2D and tex.gradient != null:
				var colors: PackedColorArray = tex.gradient.colors
				_check(colors.size() > 0 and colors[0].a < 1.0, "HP panel background is semi-transparent with faded edges")
		# The resolved rect lands centered on the bottom edge of the viewport.
		var vp := get_viewport().get_visible_rect().size
		var rect := panel.get_global_rect()
		_check(absf((rect.position.x + rect.size.x * 0.5) - vp.x * 0.5) < 2.0, "HP panel renders centered on the bottom edge")
		_check(absf((rect.position.y + rect.size.y) - (vp.y + panel.offset_bottom)) < 2.0, "HP panel bottom matches its padded offset")
		# Part bars stay compact (regression against the old 210px-wide bars).
		var head_bar = panel.get_node_or_null("Grid/HeadCell/HeadArmorBar")
		_check(head_bar != null and head_bar.custom_minimum_size.x <= 150.0, "HP part bars stay compact")
		_check(head_bar == null or head_bar.size.x <= 150.0, "HP part bars render at their compact width (no stretching)")

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
		var rect := panel.get_global_rect()
		_check(rect.position.y + rect.size.y <= vp.y * 0.5, "squad panel stays in the top half of the screen")
		_check(rect.position.x < vp.x * 0.5, "squad panel stays in the left half of the screen")

	squad.queue_free()
	await get_tree().process_frame
