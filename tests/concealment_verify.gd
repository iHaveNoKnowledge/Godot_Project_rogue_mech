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

	# Clear the section-1 cover/barrier so their footprints don't pollute the
	# crest test (the crest enemy stands at the origin, where the trunk was).
	cover.queue_free()
	barrier.queue_free()
	await get_tree().physics_frame

	await _verify_crest_concealment()

	print("CONCEALMENT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# HILL-CREST CONCEALMENT — an enemy on the far side of a terrain crest is
# hidden from the camera's line of sight; once the camera clears the crest the
# enemy is visible again. Uses a real Camera3D + layer-2 terrain hill.
func _verify_crest_concealment() -> void:
	# Flat terrain pad (layer 2) so the down-probe finds ground under the enemy.
	var pad := StaticBody3D.new()
	pad.collision_layer = 2
	var pad_col := CollisionShape3D.new()
	var pad_shape := BoxShape3D.new()
	pad_shape.size = Vector3(200, 1.0, 200)
	pad_col.shape = pad_shape
	pad.add_child(pad_col)
	pad.position = Vector3(0, -0.5, 0)  # top surface at y=0
	add_child(pad)

	# A hill crest between the camera and the enemy: 4m tall box centered at
	# (0, 2.0, -12), top at y=4, spanning z in [-15, -9].
	var hill := StaticBody3D.new()
	hill.collision_layer = 2
	var hill_col := CollisionShape3D.new()
	var hill_shape := BoxShape3D.new()
	hill_shape.size = Vector3(40, 4.0, 6.0)
	hill_col.shape = hill_shape
	hill.add_child(hill_col)
	hill.position = Vector3(0, 2.0, -12)
	add_child(hill)

	# Camera looking from the south (behind the hill) at the enemy at origin.
	var cam := Camera3D.new()
	cam.name = "TestCam"
	cam.current = true
	cam.position = Vector3(0, 5.0, -30)
	add_child(cam)

	# Let the physics server register the pad + hill before raycasting.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var concealment := preload("res://scripts/arena/concealment_system.gd").new()
	add_child(concealment)
	concealment._refresh_concealment_bodies()

	# Enemy at the origin, behind the hill from the camera's viewpoint.
	var enemy := _make_enemy(Vector3(0, 0.25, 0))
	add_child(enemy)
	concealment._update_all()
	_check(enemy.get("concealed") == true, "enemy behind a hill crest is concealed from the camera")

	# The same enemy on the NEAR side of the hill (between hill and camera, at
	# z=-18) is not crest-hidden — the hill sits behind it.
	enemy.position = Vector3(0, 0.25, -18)
	concealment._update_all()
	_check(enemy.get("concealed") == false, "enemy on the near side of the hill is visible")

	# Camera climbs well above the crest -> the far-side enemy becomes visible.
	enemy.position = Vector3(0, 0.25, 0)
	cam.position = Vector3(0, 14.0, -30)
	concealment._update_all()
	_check(enemy.get("concealed") == false, "enemy visible once the camera clears the crest")

	# Trees still conceal via the footprint system even with a camera present:
	# reuse the tree trunk from the earlier section by spawning a fresh one.
	var spawner_script = preload("res://scripts/arena/obstacle_spawner.gd")
	var spawner := spawner_script.new()
	add_child(spawner)
	var trunk := spawner._create_cover({
		"pos": Vector3(30, 0, 0),
		"type": 6,
		"rot": 0.0,
	})
	add_child(trunk)
	concealment._refresh_concealment_bodies()
	enemy.position = Vector3(30, 0.25, 0)
	concealment._update_all()
	_check(enemy.get("concealed") == true, "tree trunk still conceals via footprint with camera present")

	# Clean up: remove the camera so no other test section is affected.
	cam.queue_free()
	enemy.queue_free()
	hill.queue_free()
	pad.queue_free()
	trunk.queue_free()
	await get_tree().physics_frame