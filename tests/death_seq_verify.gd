extends Node

## Regression test: a destroyed enemy mech must stay ALIVE long enough for the
## core-breach safety sequence (1.8s warning + flash) and detonation to play.
## Previously the enemy's own free-tween fired at 0.5s, cutting the sequence
## short — the machine vanished with NO explosion. The dummy now waits
## health_system.DESTROYED_NODE_LIFETIME (CORE_BREACH_DELAY + 1.0 ≈ 2.8s).

var _checks := 0
var _fails := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("DEATH OK: " + name)
	else:
		_fails += 1
		printerr("DEATH FAIL: " + name)


func _ready() -> void:
	var scene := load("res://scenes/mecha/enemy_dummy.tscn") as PackedScene
	_check(scene != null, "enemy scene loads")
	var enemy = scene.instantiate()
	add_child(enemy)
	await get_tree().process_frame
	var hs = enemy.get_node_or_null("HealthSystem")
	_check(hs != null, "enemy has a health system child")
	if hs == null:
		get_tree().quit(1)
		return
	_check(hs.get("CORE_BREACH_DELAY") == 1.8, "core-breach delay is 1.8s")
	_check(hs.get("DESTROYED_NODE_LIFETIME") > 1.8, "destroyed node lifetime covers the full sequence")
	_check(hs.get("DESTROYED_NODE_LIFETIME") <= 3.5, "destroyed node lifetime is not absurdly long")

	# Destroy through the REAL damage path (frame HP to 0), then measure how
	# long the enemy node stays alive after the destruction signal.
	var start := Time.get_ticks_msec()
	var freed_at := -1
	var parts = hs.get("parts")
	if parts is Dictionary and not parts.is_empty():
		for slot in parts:
			hs.take_damage_to_part(slot, 99999.0)
	_check(hs.get("is_destroyed"), "enemy is destroyed after full damage")

	for i in range(60):
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(enemy):
			freed_at = Time.get_ticks_msec() - start
			break
	if freed_at < 0:
		freed_at = Time.get_ticks_msec() - start

	# The node must survive at least through the 1.8s warning window (it is
	# freed only after detonation at DESTROYED_NODE_LIFETIME ≈ 2.8s).
	_check(freed_at >= 1800, "enemy survives >= 1.8s for the death sequence (got %.0fms)" % freed_at)

	print("DEATH_SEQ_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
