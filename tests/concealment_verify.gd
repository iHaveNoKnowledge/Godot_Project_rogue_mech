extends Node

## Verifies the battle concealment system:
##   1. Tall cover (tree trunk) is tagged into the concealment group.
##   2. An enemy standing inside that cover footprint is hidden.
##   3. The same enemy outside the cover footprint is visible again.
##   4. The enemy health billboard hides with the mech.
## Run: godot --headless --path . res://tests/concealment_verify.tscn

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CONCEAL_OK: " + name)
	else:
		_fails += 1
		printerr("CONCEAL_FAIL: " + name)


# Minimal stand-in enemy that mirrors the enemy_dummy API the concealment system
# calls (group, health_system.is_destroyed, set_concealed, concealed flag).
func _make_enemy(pos: Vector3) -> CharacterBody3D:
	var enemy := CharacterBody3D.new()
	enemy.set_script(preload("res://tests/fake_enemy.gd"))
	enemy.position = pos
	var hs := Node.new()
	hs.name = "HealthSystem"
	hs.set("is_destroyed", false)
	enemy.add_child(hs)
	enemy.health_system = hs
	var billboard := Control.new()
	billboard.name = "EnemyStatus"
	billboard.set_script(preload("res://scripts/ui/enemy_status_billboard.gd"))
	enemy.add_child(billboard)
	return enemy


func _ready() -> void:
	# Build a cover object like the obstacle spawner does (tree trunk type 6).
	var spawner_script = preload("res://scripts/arena/obstacle_spawner.gd")
	var spawner := spawner_script.new()
	add_child(spawner)
	var cover := spawner._create_cover({
		"pos": Vector3(0, 0, 0),
		"type": 6,
		"rot": 0.0,
	})
	add_child(cover)
	_check(cover.is_in_group("cover"), "tree trunk is a cover object")
	_check(cover.is_in_group("concealment"), "tree trunk is concealment (hides mechs)")

	var concealment := preload("res://scripts/arena/concealment_system.gd").new()
	add_child(concealment)
	concealment._refresh_concealment_bodies()
	_check(concealment.concealment_bodies.size() >= 1, "concealment bodies collected (%d)" % concealment.concealment_bodies.size())

	# Enemy standing inside the trunk footprint -> concealed.
	var enemy := _make_enemy(Vector3(0, 0, 0))
	add_child(enemy)
	concealment._update_all()
	_check(enemy.get("concealed") == true, "enemy inside tree trunk is concealed")

	var status = enemy.get_node_or_null("EnemyStatus")
	_check(status != null and status.get("concealed") == true, "enemy health billboard is concealed too")

	# Move the enemy far from the trunk -> revealed.
	enemy.position = Vector3(40, 0, 40)
	concealment._update_all()
	_check(enemy.get("concealed") == false, "enemy outside cover is visible again")

	# A low barrier (type 0) is NOT concealment — mechs are visible over it.
	var barrier := spawner._create_cover({
		"pos": Vector3(0, 0, 30),
		"type": 0,
		"rot": 0.0,
	})
	add_child(barrier)
	_check(not barrier.is_in_group("concealment"), "low barrier is not concealment")

	print("CONCEALMENT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)