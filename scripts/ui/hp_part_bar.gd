extends Control

## Single skewed health bar (CSS skewX(-30deg) style). Dark track + configurable
## fill gradient. Armor bars use silver/gray, frame bars use green — each part
## shows two of these stacked (armor on top, frame below).

const TRACK_COLOR := Color("#333333")
const DESTROY_COLOR := Color(0.12, 0.12, 0.12, 1)

const SKEW_DEGREES := -30.0

@export var fill_color_a: Color = Color("#c4c3c0")
@export var fill_color_b: Color = Color("#9a9a9a")

var ratio: float = 1.0
var destroyed: bool = false

var _display: float = 1.0
var _wants_redraw: bool = true


func _ready() -> void:
	_display = ratio


func setup(current_hp: float, max_hp: float, is_destroyed: bool) -> void:
	ratio = clampf(current_hp / maxf(max_hp, 1.0), 0.0, 1.0) if max_hp > 0.0 else 0.0
	destroyed = is_destroyed
	_wants_redraw = true


func _process(delta: float) -> void:
	var smooth := 1.0 - exp(-12.0 * delta)
	_display = lerpf(_display, ratio, smooth)
	if _wants_redraw or absf(_display - ratio) > 0.0005:
		queue_redraw()
		_wants_redraw = false


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var skew := tan(deg_to_rad(SKEW_DEGREES)) * h

	_draw_skew(w, h, skew, TRACK_COLOR, TRACK_COLOR)

	if destroyed:
		_draw_skew(w * _display, h, skew, DESTROY_COLOR, DESTROY_COLOR)
		return

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
