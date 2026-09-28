extends Node

# Transition-crash bisection probe (temporary, deleted after diagnosis).
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		GlobalData.weapons.part_damage["arm_left"] = 0.5
		GameManager.transition_to(GameManager.State.COMBAT)
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE: survived")
				get_tree().quit(0)
				return
		print("PROBE: board never reached")
		get_tree().quit(2)
