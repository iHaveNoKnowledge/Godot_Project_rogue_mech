class_name HPPartBar
extends Control

## Single skewed health bar (CSS skewX(-30deg) style). Dark track + configurable
## fill gradient + Damage Ghost / Red Lag Bar (showing recent chunk damage).
## Armor bars use silver/gray, frame bars use green - each part shows two of
## these stacked (armor on top, frame below).

const TRACK_COLOR := Color("#333333")
const DESTROY_COLOR := Color(0.12, 0.12, 0.12, 1)

const SKEW_DEGREES := -30.0

# Shared fill palettes matching battle HUD & intermission:
const ARMOR_FILL_A := Color(0.77, 0.76, 0.75)
const ARMOR_FILL_B := Color(0.60, 0.60, 0.60)

const FRAME_FILL_A := Color(0.376, 0.82, 0.43)
const FRAME_FILL_B := Color(0.537, 1.0, 0.53)

const SHIELD_FILL_A := Color(0.2, 0.7, 1.0)
const SHIELD_FILL_B := Color(0.1, 0.5, 0.85)

const DURABILITY_FILL_A := Color(0.2, 0.85, 1.0)
const DURABILITY_FILL_B := Color(0.0, 0.55, 0.85)

const DURABILITY_WARN_A := Color(1.0, 0.75, 0.2)
const DURABILITY_WARN_B := Color(0.9, 0.45, 0.1)

const DURABILITY_CRIT_A := Color(1.0, 0.3, 0.25)
const DURABILITY_CRIT_B := Color(0.8, 0.1, 0.1)

# Damage ghost / Red catch-up lag bar:
const DAMAGE_FILL_A := Color(0.96, 0.22, 0.18)
const DAMAGE_FILL_B := Color(0.72, 0.08, 0.08)

const GHOST_HOLD_DURATION: float = 0.55
const GHOST_DRAIN_RATE: float = 0.45

@export var fill_color_a: Color = Color("#c4c3c0")
@export var fill_color_b: Color = Color("#9a9a9a")

var ratio: float = 1.0
var destroyed: bool = false

var _display: float = 1.0
var _damage_ghost: float = 1.0
var _ghost_delay_timer: float = 0.0
var _wants_redraw: bool = true


func _ready() -> void:
	_display = ratio
	_damage_ghost = ratio


func setup(current_hp: float, max_hp: float, is_destroyed: bool) -> void:
	var new_ratio := clampf(current_hp / maxf(max_hp, 1.0), 0.0, 1.0) if max_hp > 0.0 else 0.0
	if new_ratio < ratio - 0.001:
		# Took damage: hold the ghost bar at the previous higher HP mark
		_damage_ghost = maxf(_damage_ghost, _display)
		_ghost_delay_timer = GHOST_HOLD_DURATION
	elif new_ratio > ratio + 0.001:
		# Healed or repaired: instantly snap ghost up
		_damage_ghost = new_ratio
	ratio = new_ratio
	destroyed = is_destroyed
	_wants_redraw = true


func _process(delta: float) -> void:
	var smooth := 1.0 - exp(-18.0 * delta)
	_display = lerpf(_display, ratio, smooth)

	# Damage ghost catch-up logic
	if _ghost_delay_timer > 0.0:
		_ghost_delay_timer -= delta
	else:
		if _damage_ghost > _display:
			_damage_ghost = move_toward(_damage_ghost, _display, delta * GHOST_DRAIN_RATE)
		else:
			_damage_ghost = _display

	if _wants_redraw or absf(_display - ratio) > 0.0005 or absf(_damage_ghost - _display) > 0.0005:
		queue_redraw()
		_wants_redraw = false


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var skew := tan(deg_to_rad(SKEW_DEGREES)) * h

	# 1. Dark Background Track
	_draw_skew(w, h, skew, TRACK_COLOR, TRACK_COLOR)

	if destroyed:
		_draw_skew(w * _display, h, skew, DESTROY_COLOR, DESTROY_COLOR)
		return

	# 2. Damage Ghost / Red Lag Bar (reveals recent chunk damage taken)
	if _damage_ghost > _display + 0.002:
		_draw_skew(w * _damage_ghost, h, skew, DAMAGE_FILL_A, DAMAGE_FILL_B)

	# 3. Main HP Bar (drawn on top of the red ghost bar)
	if _display > 0.001:
		_draw_skew(w * _display, h, skew, fill_color_a, fill_color_b)


func _draw_skew(fill_w: float, h: float, skew: float, color_left: Color, color_right: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(fill_w, 0.0),
		Vector2(fill_w + skew, h),
		Vector2(skew, h),
	])
	var colors := PackedColorArray([color_left, color_right, color_right, color_left])
	draw_polygon(pts, colors)


## Helper to build a complete slanted HP / Durability bar row (Label + HPPartBar + Value label)
## used in Battle, Intermission, and Hangar views.
static func create_row(
	label_text: String,
	current: float,
	max_value: float,
	is_frame: bool = false,
	is_shield: bool = false,
	bar_width: float = 180.0,
	bar_height: float = 8.0,
	font_size: int = 11,
	is_durability: bool = false
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	if label_text != "":
		var name := Label.new()
		name.text = label_text
		name.custom_minimum_size = Vector2(56, 0)
		name.add_theme_font_size_override("font_size", font_size)
		name.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		row.add_child(name)

	var bar: HPPartBar = HPPartBar.new()
	bar.custom_minimum_size = Vector2(bar_width, bar_height)
	if bar_width <= 0:
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cur_ratio := (current / max_value) if max_value > 0.0 else 0.0
	if is_durability:
		if cur_ratio <= 0.35:
			bar.fill_color_a = DURABILITY_CRIT_A
			bar.fill_color_b = DURABILITY_CRIT_B
		elif cur_ratio <= 0.70:
			bar.fill_color_a = DURABILITY_WARN_A
			bar.fill_color_b = DURABILITY_WARN_B
		else:
			bar.fill_color_a = DURABILITY_FILL_A
			bar.fill_color_b = DURABILITY_FILL_B
	elif is_frame:
		bar.fill_color_a = FRAME_FILL_A
		bar.fill_color_b = FRAME_FILL_B
	elif is_shield:
		bar.fill_color_a = SHIELD_FILL_A
		bar.fill_color_b = SHIELD_FILL_B
	else:
		bar.fill_color_a = ARMOR_FILL_A
		bar.fill_color_b = ARMOR_FILL_B

	bar.setup(current, max_value, current <= 0.001 and max_value > 0.0)
	row.add_child(bar)

	var value := Label.new()
	value.name = "ValueLabel"
	if is_durability:
		value.text = "%.0f%%" % [cur_ratio * 100.0]
	else:
		value.text = "%d / %d" % [int(round(current)), int(round(max_value))]
	value.add_theme_font_size_override("font_size", font_size)
	value.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	row.add_child(value)

	return row
