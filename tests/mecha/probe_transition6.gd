extends Node

# Bisection probe 6: damage + probes, NO enter_combat call, then enter_board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	var _dr := 0
	func _on_dr(_s: String, _a: float, _t: String) -> void:
		_dr += 1
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		EventBus.damage_received.connect(_on_dr)
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
		var m1 := _spawn_mech(Vector3(0, 10, 0))
		await _land(m1)
		var hs1: Node = m1.get_node_or_null("HealthSystem")
		hs1.take_damage_to_part("arm_left", 30.0, "kinetic")
		await get_tree().physics_frame
		var m2 := _spawn_mech(Vector3(20, 10, 0))
		await _land(m2)
		print("PROBE6: entering board (no enter_combat first)")
		GameManager.enter_board()
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			var cs := get_tree().current_scene
			if cs and "game_board" in str(cs.scene_file_path):
				print("PROBE6: board reached, waiting settle")
				for i in range(120):
					await get_tree().process_frame
				print("PROBE6: survived")
				get_tree().quit(0)
				return
		print("PROBE6: board never reached")
		get_tree().quit(2)

	func _spawn_mech(pos: Vector3) -> CharacterBody3D:
		var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		mech.position = pos
		get_tree().current_scene.add_child(mech)
		mech.is_player_driven = false
		return mech

	func _land(mech: CharacterBody3D) -> void:
		var f := 0
		while not mech.is_on_floor() and f < 120:
			await get_tree().physics_frame
			f += 1
		await get_tree().physics_frame
		await get_tree().physics_frame
