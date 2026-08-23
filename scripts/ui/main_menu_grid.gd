extends Control

# Ultra-minimal tactical grid — 1px hairlines at low alpha, no textures
func _draw() -> void:
	var col := Color(1, 1, 1, 0.04)
	var col2 := Color(1, 1, 1, 0.025)
	var step := 64.0
	var size := get_rect().size
	# Vertical lines
	var x := fmod(0.0, step)
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), col, 1.0)
		x += step
	# Horizontal lines
	var y := fmod(0.0, step)
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0)
		y += step
	# Outer hairline border 1px
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.22, 0.22, 0.22, 0.35), false, 1.0)
	# Corner brackets (tactical)
	var bracket := 14.0
	var bw := 1.0
	var bc := Color(0.45, 0.45, 0.45, 0.45)
	# Top-left
	draw_line(Vector2(0, 0), Vector2(bracket, 0), bc, bw)
	draw_line(Vector2(0, 0), Vector2(0, bracket), bc, bw)
	# Top-right
	draw_line(Vector2(size.x - bracket, 0), Vector2(size.x, 0), bc, bw)
	draw_line(Vector2(size.x, 0), Vector2(size.x, bracket), bc, bw)
	# Bottom-left
	draw_line(Vector2(0, size.y), Vector2(bracket, size.y), bc, bw)
	draw_line(Vector2(0, size.y - bracket), Vector2(0, size.y), bc, bw)
	# Bottom-right
	draw_line(Vector2(size.x - bracket, size.y), Vector2(size.x, size.y), bc, bw)
	draw_line(Vector2(size.x, size.y - bracket), Vector2(size.x, size.y), bc, bw)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
