extends Node

# Bisection probe 2: two live mechas, then EXPLICIT free before enter_board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		var cam := Camera3D.new()
		get_tree().current_scene.add_child(cam)
		var ms: Array = []
		for i in range(2):
			var m: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
			m.position = Vector3(i * 20, 10, 0)
			get_tree().current_scene.add_child(m)
			m.is_player_driven = false
			ms.append(m)
		for i in range(120):
			await get_tree().physics_frame
		for m in ms:
			m.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("PROBE2: mechas freed, entering board")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE2: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE2: survived")
				get_tree().quit(0)
				return
		print("PROBE2: board never reached")
		get_tree().quit(2)
