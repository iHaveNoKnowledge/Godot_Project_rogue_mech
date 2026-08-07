extends Control

## Skewed health bar (mockup style): dark track, green gradient fill, skewed
## by -30deg like CSS skewX(). Each bar holds an outer armor layer on top of a
## dimmer frame layer. When the armor breaks the green drains and the frame
## layer shows underneath.

const TRACK_COLOR := Color("#333333")
const FRAME_COLOR := Color("#5c7a5f")
const DESTROY_COLOR := Color(0.12, 0.12, 0.12, 1)
const ARMOR_COLOR_A := Color("#60D16D")
const ARMOR_COLOR_B := Color("#89FF87")

const SKEW_DEGREES := -30.0

var armor_ratio: float = 1.0
var frame_ratio: float = 1.0
var destroyed: bool = false

var _display_armor: float = 1.0
var _display_frame: float = 1.0
var _wants_redraw: bool = true


func _ready() -> void:
	_display_armor = armor_ratio
	_display_frame = frame_ratio


func setup(armor_hp: float, max_armor: float, frame_hp: float, max_frame: float, is_destroyed: bool) -> void:
	var new_armor := clampf(armor_hp / maxf(max_armor, 1.0), 0.0, 1.0) if max_armor > 0.0 else 0.0
	var new_frame := clampf(frame_hp / maxf(max_frame, 1.0), 0.0, 1.0) if max_frame > 0.0 else 0.0
	armor_ratio = new_armor
	frame_ratio = new_frame
	destroyed = is_destroyed
	_wants_redraw = true


func _process(delta: float) -> void:
	var smooth := 1.0 - exp(-12.0 * delta)
	_display_armor = lerpf(_display_armor, armor_ratio, smooth)
	_display_frame = lerpf(_display_frame, frame_ratio, smooth)
	if _wants_redraw or absf(_display_armor - armor_ratio) > 0.0005 or absf(_display_frame - frame_ratio) > 0.0005:
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
		_draw_skew(w * _display_frame, h, skew, DESTROY_COLOR, DESTROY_COLOR)
		return

	if _display_frame > 0.001:
		_draw_skew(w * _display_frame, h, skew, FRAME_COLOR, FRAME_COLOR)

	if _display_armor > 0.001:
		_draw_skew(w * _display_armor, h, skew, ARMOR_COLOR_A, ARMOR_COLOR_B)


func _draw_skew(fill_w: float, h: float, skew: float, color_left: Color, color_right: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(fill_w, 0.0),
		Vector2(fill_w + skew, h),
		Vector2(skew, h),
	])
	var colors := PackedColorArray([color_left, color_right, color_right, color_left])
	draw_polygon(pts, colors)
