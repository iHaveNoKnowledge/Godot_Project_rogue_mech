extends Node

## Regression test: board entry must not leave the Intermission menu stuck.
## Guards against a parse error in intermission_controller.gd silently leaving
## IntermissionUI as a bare CanvasLayer (no buttons, no handlers), which made
## the menu unresponsive and blocked all movement on board entry.
## The driver lives on /root (PROCESS_MODE_ALWAYS) because enter_board() calls
## change_scene_to_file(), which frees this test scene.

func _ready() -> void:
	await get_tree().process_frame
	var driver := Node.new()
	driver.name = "BoardEntryDriver"
	driver.set_script(load("res://tests/board_entry_driver.gd"))
	get_tree().root.add_child(driver)
	driver.run()