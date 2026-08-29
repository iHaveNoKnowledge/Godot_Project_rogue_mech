extends CanvasLayer

## Full-screen "DEPLOYING" overlay shown the instant a battle scene loads.
##
## The player mech spawns a few meters up and drops onto the ground; without this
## overlay that drop-in is visible as a janky mid-air spawn. The overlay covers
## the whole drop with an opaque loading screen and mutes all battle audio until
## the mech has touched down. It then fades out, revealing the mech already
## standing on the ground with the battle music playing.

const MIN_HOLD_TIME := 1.1
const FADE_TIME := 0.6
const MAX_WAIT_TIME := 4.0

var _overlay: ColorRect
var _elapsed: float = 0.0
var _landed: bool = false
var _done: bool = false


func _ready() -> void:
	layer = 100
	_build_overlay()
	if AudioManager:
		AudioManager.set_combat_muted(true)


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "LoadingOverlay"
	_overlay.color = Color(0.02, 0.03, 0.06, 1.0)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	_overlay.add_child(vbox)

	var title := Label.new()
	title.text = "DEPLOYING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0, 1.0))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Drop pod inbound — hold position."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72, 1.0))
	vbox.add_child(hint)

	var bar := ColorRect.new()
	bar.color = Color(0.3, 0.55, 0.9, 1.0)
	bar.custom_minimum_size = Vector2(240, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(bar)

	# Subtle progress shimmer: the bar empties out as the mech closes with the ground.
	var tween := create_tween().set_loops()
	tween.tween_property(bar, "custom_minimum_size", Vector2(40, 4), MIN_HOLD_TIME)


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if not _landed:
		var mecha: Node3D = GameManager.get_player_mecha()
		if mecha == null and get_parent() is Node:
			mecha = get_parent().get_node_or_null("Mecha")
		if mecha is CharacterBody3D and (mecha as CharacterBody3D).is_on_floor():
			_landed = true
	if _landed and _elapsed >= MIN_HOLD_TIME or _elapsed >= MAX_WAIT_TIME:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	var overlay_id := _overlay.get_instance_id() if _overlay else 0
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, FADE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func():
		if AudioManager and is_instance_valid(AudioManager):
			AudioManager.set_combat_muted(false)
		var ov = instance_from_id(overlay_id) if overlay_id != 0 else null
		# Self may already be freed if scene changed - guard
		if is_instance_valid(self):
			queue_free()
		elif is_instance_valid(ov):
			ov.queue_free()
	)
