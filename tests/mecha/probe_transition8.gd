extends Node

# Bisection probe 8: enter_combat (suppressed) with NO mechas, then enter_board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		GameManager.suppress_scene_change = true
		GameManager.enter_combat("grunt")
		await get_tree().process_frame
		print("PROBE8: state=%s entering board" % str(GameManager.current_state))
		GameManager.suppress_scene_change = false
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE8: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE8: survived")
				get_tree().quit(0)
				return
		print("PROBE8: board never reached")
		get_tree().quit(2)
