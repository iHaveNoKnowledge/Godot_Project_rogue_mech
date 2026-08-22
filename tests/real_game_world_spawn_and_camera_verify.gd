extends Node3D

## Automated Verification of Live Combat World Spawning, Camera SpringArm, and Terrain Clearance (No Sinking / Submerging).

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("COMBAT_SPAWN_OK: %s" % msg)
	else:
		_fails += 1
		print("COMBAT_SPAWN_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Real GameWorld Spawn & Camera Clearance Verification ---")

	# Set board context to a real battle
	GlobalData.board.board_theme_id = "desert"
	GlobalData.board.current_tile = Vector2i(3, 3)

	# 1. Instantiate the actual GameWorld scene
	var world_scene = preload("res://scenes/game_world.tscn")
	var world = world_scene.instantiate()
	add_child(world)

	var mecha: CharacterBody3D = world.get_node_or_null("Mecha")
	_check(mecha != null, "Found Mecha CharacterBody3D in GameWorld")

	var arena_gen = world.get_node_or_null("ArenaGenerator")
	_check(arena_gen != null, "Found ArenaGenerator in GameWorld")

	var camera_rig = world.get_node_or_null("MechaCamera")
	_check(camera_rig != null, "Found MechaCamera in GameWorld")

	# Simulate physics ticks for drop and landing
	for step in range(30):
		await get_tree().physics_frame

	# 2. Test Ground Collision and Player Altitude
	var ground_y: float = arena_gen._get_terrain_height(mecha.global_position.x, mecha.global_position.z)
	var player_feet_y: float = mecha.global_position.y

	_check(player_feet_y >= ground_y - 0.15, "Player mech is standing ON the terrain surface (feet=%.2f, ground=%.2f, diff=%.2f)" % [player_feet_y, ground_y, player_feet_y - ground_y])
	_check(player_feet_y <= ground_y + 1.5, "Player mech is not floating in the sky (feet=%.2f, ground=%.2f)" % [player_feet_y, ground_y])

	# 3. Test Camera SpringArm3D is NOT compressed by player body
	var spring_arm: SpringArm3D = camera_rig.get_node_or_null("CameraPivot/CameraOffset/SpringArm3D")
	_check(spring_arm != null, "Found SpringArm3D in CameraRig")
	_check(spring_arm.collision_mask == 2, "SpringArm3D collision mask is 2 (Environment only, ignores player layer 1)")

	var cam: Camera3D = spring_arm.get_node_or_null("Camera3D")
	_check(cam != null, "Found Camera3D")
	var cam_dist := cam.global_position.distance_to(mecha.global_position)
	_check(cam_dist > 5.0, "Camera maintains full 3rd-person standoff distance (dist=%.2fm, not collapsed into ground)" % cam_dist)

	# 4. Test Foot IK System Raycasts
	var foot_ik: MechaFootIK = mecha.get_node_or_null("FootIKSystem")
	_check(foot_ik != null, "Found FootIKSystem on Mecha")
	_check(foot_ik.ray_left.collision_mask == 2 and foot_ik.ray_right.collision_mask == 2, "Foot IK rays correctly target layer 2 (Environment)")

	print("--- Real GameWorld Spawn & Camera Clearance Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_GAME_WORLD_SPAWN_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
