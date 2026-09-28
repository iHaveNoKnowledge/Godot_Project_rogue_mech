extends Node

# Bisection probe 7: combat music only, then enter_board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		AudioManager.play_combat_music("grunt", 1.5, false, "suburb")
		await get_tree().process_frame
		print("PROBE7: music started, entering board")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE7: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE7: survived")
				get_tree().quit(0)
				return
		print("PROBE7: board never reached")
		get_tree().quit(2)
