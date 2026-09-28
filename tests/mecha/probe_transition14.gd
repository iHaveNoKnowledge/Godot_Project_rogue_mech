extends Node

# Bisection probe 9: two pristine mechas + enter_combat (suppressed), then board.
func _ready() -> void:
	var d := Driver.new()
	get_tree().root.add_child.call_deferred(d)

class Driver extends Node:
	var _snap := {}
	var _dr := 0
	func _snap_all() -> void:
		_snap["pd"] = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
		_snap["hm"] = (GlobalData.hangar.hangar_mechs as Array).duplicate(true)
		_snap["aid"] = str(GlobalData.hangar.active_hangar_mech_id)
		_snap["wl"] = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	func _land(mech: CharacterBody3D) -> void:
		var f := 0
		while not mech.is_on_floor() and f < 120:
			await get_tree().physics_frame
			f += 1
		await get_tree().physics_frame
		await get_tree().physics_frame
	func _on_dr(_s: String, _a: float, _t: String) -> void:
		_dr += 1
	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		_snap_all()
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
		var m1: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		m1.position = Vector3(0, 10, 0)
		get_tree().current_scene.add_child(m1)
		m1.is_player_driven = false
		await _land(m1)
		var hs1: Node = m1.get_node_or_null("HealthSystem")
		hs1.take_damage_to_part("arm_left", 30.0, "kinetic")
		await get_tree().physics_frame
		var m2: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		m2.position = Vector3(20, 10, 0)
		get_tree().current_scene.add_child(m2)
		m2.is_player_driven = false
		await _land(m2)
		var hs2: Node = m2.get_node_or_null("HealthSystem")
		print("PROBE14: derived armor_hp=", hs2.parts["arm_left"]["armor_hp"])
		for m in get_tree().get_nodes_in_group("mecha"):
			m.queue_free()
		await get_tree().process_frame
		(GlobalData.weapons.part_damage as Dictionary).clear()
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
