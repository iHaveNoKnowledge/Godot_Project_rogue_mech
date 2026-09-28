extends Node

# Bisection probe 9: two pristine mechas + enter_combat (suppressed), then board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		var cam := Camera3D.new()
		get_tree().current_scene.add_child(cam)
		for i in range(2):
			var m: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
			m.position = Vector3(i * 20, 10, 0)
			get_tree().current_scene.add_child(m)
			m.is_player_driven = false
		for i in range(120):
			await get_tree().physics_frame
		var probe_mech: Node = null
		for m in get_tree().get_nodes_in_group("mecha"):
			probe_mech = m
			break
		var phs: Node = probe_mech.get_node_or_null("HealthSystem") if probe_mech else null
		if phs:
			phs.take_damage_to_part("arm_left", 30.0, "kinetic")
			await get_tree().physics_frame
		GameManager.suppress_scene_change = true
		GameManager.enter_combat("grunt")
		await get_tree().process_frame
		GameManager.suppress_scene_change = false
		print("PROBE9: entering board")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE9: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE9: survived")
				get_tree().quit(0)
				return
		print("PROBE9: board never reached")
		get_tree().quit(2)
