extends Node

# Bisection probe 4: damage a live mech, then enter_board (no combat state).
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		var cam := Camera3D.new()
		get_tree().current_scene.add_child(cam)
		var ground := StaticBody3D.new()
		ground.collision_layer = 2
		ground.position = Vector3(0, -1.5, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4000, 3, 4000)
		shape.shape = box
		ground.add_child(shape)
		get_tree().current_scene.add_child(ground)
		var m: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		m.position = Vector3(0, 10, 0)
		get_tree().current_scene.add_child(m)
		m.is_player_driven = false
		var f := 0
		while not m.is_on_floor() and f < 120:
			await get_tree().physics_frame
			f += 1
		var hs: Node = m.get_node_or_null("HealthSystem")
		hs.take_damage_to_part("arm_left", 30.0, "kinetic")
		await get_tree().physics_frame
		print("PROBE4: damaged, entering board")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE4: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE4: survived")
				get_tree().quit(0)
				return
		print("PROBE4: board never reached")
		get_tree().quit(2)
