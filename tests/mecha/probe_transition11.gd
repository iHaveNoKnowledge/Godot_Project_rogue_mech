extends Node

# Bisection probe 11: combat music soak ~60s, then enter_board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		AudioManager.play_combat_music("grunt", 1.5, false, "suburb")
		EventBus.combat_intensity_changed.emit(1.0)
		for i in range(3600):
			await get_tree().process_frame
		print("PROBE11: entering board after music soak")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE11: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE11: survived")
				get_tree().quit(0)
				return
		print("PROBE11: board never reached")
		get_tree().quit(2)
