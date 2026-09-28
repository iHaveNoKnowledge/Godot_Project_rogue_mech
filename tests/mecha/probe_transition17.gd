extends Node

# Bisection probe 17: probe14's exact statements + full-audit structure.

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)

func _ready() -> void:
	var d := Driver.new()
	d._audit = self
	get_tree().root.add_child.call_deferred(d)

func check(c: bool, l: String) -> void:
	_check(c, l)

func finish() -> void:
	print("P17: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

class Driver extends Node:
	var _audit = null
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

	func _cur_file() -> String:
		var cs := get_tree().current_scene
		return str(cs.scene_file_path) if cs and cs.scene_file_path != "" else "?"

	func _wait_scene(fragment: String, timeout_s: float) -> bool:
		var t := 0.0
		while t < timeout_s:
			await get_tree().process_frame
			t += get_process_delta_time()
			if fragment in _cur_file():
				for i in range(5):
					await get_tree().process_frame
				return true
		return false

	func _spawn_mech(pos: Vector3) -> CharacterBody3D:
		var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		mech.position = pos
		get_tree().current_scene.add_child(mech)
		mech.is_player_driven = false
		return mech

	func _restore_all() -> void:
		GlobalData.weapons.part_damage = (_snap["pd"] as Dictionary).duplicate(true)
		GlobalData.hangar.hangar_mechs = (_snap["hm"] as Array).duplicate(true)
		GlobalData.hangar.active_hangar_mech_id = str(_snap["aid"])
		GlobalData.weapons.weapon_loadout = (_snap["wl"] as Dictionary).duplicate(true)
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
		print("P17: entering board")
		GameManager.enter_board()
		if not await _wait_scene("game_board", 150.0):
			print("P17: board never loaded")
			get_tree().quit(2)
			return
		_audit.check(get_tree().get_nodes_in_group("mecha").is_empty(), "C: no mecha residue")
		var pd_before: Dictionary = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
		GameManager.enter_hangar()
		if not await _wait_scene("hangar_scene", 150.0):
			print("P17: hangar never loaded")
			get_tree().quit(2)
			return
		GameManager.return_to_board()
		if not await _wait_scene("game_board", 150.0):
			print("P17: board return never loaded")
			get_tree().quit(2)
			return
		_audit.check((GlobalData.weapons.part_damage as Dictionary) == pd_before, "D: part_damage stable")
		_restore_all()
		_audit.finish()
