extends Node

## Integration test that plays the REAL game flow headless: the board scene
## loads, the token walks, an event popup closes without reloading the board or
## restarting the intermission BGM, then a real battle boots with the extended
## escape zones, screen-top RETREAT banner, energy HUD and enemy energy AI.
##
## The driver lives on /root (PROCESS_MODE_ALWAYS) because enter_board() /
## enter_combat() call change_scene_to_file(), which frees this test scene.
## Run: godot --headless --path . res://tests/game_flow_verify.tscn


func _ready() -> void:
	# Wait a frame first: this test scene's _ready runs while the root is still
	# setting up children, so add_child on /root would fail here. After one
	# frame the tree is settled and the driver (which survives the scene swaps)
	# can be attached.
	await get_tree().process_frame
	var driver := Node.new()
	driver.name = "GameFlowDriver"
	driver.set_script(load("res://tests/game_flow_driver.gd"))
	get_tree().root.add_child(driver)
	driver.run()
