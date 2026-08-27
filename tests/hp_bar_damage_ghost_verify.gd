extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running hp_bar_damage_ghost_verify ---")
	await _verify_damage_ghost_trail()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_damage_ghost_trail() -> void:
	var bar := HPPartBar.new()
	bar.size = Vector2(100, 10)
	add_child(bar)

	# 1. Full HP
	bar.setup(100.0, 100.0, false)
	bar._process(0.1)
	_check(bar.ratio == 1.0, "initial ratio is 1.0")
	_check(bar._damage_ghost == 1.0, "initial damage ghost is 1.0")

	# 2. Take heavy chunk damage (100 -> 60)
	bar.setup(60.0, 100.0, false)
	bar._process(0.016)
	_check(bar.ratio == 0.6, "target ratio drops to 0.6")
	_check(bar._damage_ghost >= 0.99, "damage ghost stays at 1.0 during hold duration")
	_check(bar._ghost_delay_timer > 0.0, "ghost delay timer is active")

	# 3. Simulate hold duration expiration (0.6s)
	bar._process(0.6)
	_check(bar._damage_ghost < 1.0 and bar._damage_ghost > 0.6, "damage ghost starts draining toward current HP")

	# 4. Drain completes
	for i in range(30):
		bar._process(0.1)
	_check(is_equal_approx(bar._damage_ghost, bar.ratio), "damage ghost caught up with current HP")

	# 5. Heal / Repair (60 -> 90)
	bar.setup(90.0, 100.0, false)
	bar._process(0.016)
	_check(bar.ratio == 0.9, "target ratio goes up to 0.9 on heal")
	_check(bar._damage_ghost == 0.9, "damage ghost snaps up instantly without ghost lag on heal")

	bar.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All hp_bar_damage_ghost_verify tests passed.")
		get_tree().quit(0)
	else:
		print("hp_bar_damage_ghost_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
