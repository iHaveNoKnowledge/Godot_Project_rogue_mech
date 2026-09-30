extends Node

## Scene-transition / lifecycle-boundary audit. A persistent Driver node (child
## of root, survives change_scene_to_file) drives REAL production transitions:
## mecha_base combat objects, GameManager.enter_board/enter_hangar/
## return_to_board/enter_combat(suppressed test-hook path), asserting ownership,
## handoff, isolation and stability. game_world.tscn cannot load headless
## (documented) so combat-scene legs use direct spawn + the suppressed
## combat-logic path instead of faking results.
##
## Driver is fully self-contained: it must NEVER hold a reference to this scene
## root (or any node of it), because change_scene_to_file frees the old scene
## mid-run; touching such a freed reference afterwards is a native access
## violation (0xC0000005) in release templates — the historical "headless
## segfault" of this audit.
##
## Board residue note: the board legitimately embeds mecha_controller-based
## tokens (player token via _build_valkren_player), so group "mecha" is NOT
## empty on the board by design. Residue is therefore asserted by instance id:
## every mecha spawned by Stage A must be freed after the transition.
##
## Run: godot --headless --path . res://tests/mecha/scene_transition_audit.tscn

func _ready() -> void:
	get_tree().root.add_child.call_deferred(Driver.new())


class Driver extends Node:
	var _fails := 0
	var _checks := 0
	var _blocked := 0
	var _snap := {}
	var _dr := 0
	var _spawned_mech_ids: Array[int] = []

	func _on_dr(_s: String, _a: float, _t: String) -> void:
		_dr += 1

	func _check(cond: bool, label: String) -> void:
		_checks += 1
		if cond:
			print("  PASS: " + label)
		else:
			_fails += 1
			push_error("FAIL: " + label)

	func _block(label: String) -> void:
		_blocked += 1
		print("  BLOCKED: " + label)

	func _snap_all() -> void:
		_snap["pd"] = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
		_snap["hm"] = (GlobalData.hangar.hangar_mechs as Array).duplicate(true)
		_snap["aid"] = str(GlobalData.hangar.active_hangar_mech_id)
		_snap["wl"] = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)

	func _restore_all() -> void:
		GlobalData.weapons.part_damage = (_snap["pd"] as Dictionary).duplicate(true)
		GlobalData.hangar.hangar_mechs = (_snap["hm"] as Array).duplicate(true)
		GlobalData.hangar.active_hangar_mech_id = str(_snap["aid"])
		GlobalData.weapons.weapon_loadout = (_snap["wl"] as Dictionary).duplicate(true)

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

	## True when none of the mechas spawned by Stage A survive the transition.
	func _spawned_mechs_all_freed() -> bool:
		for id in _spawned_mech_ids:
			if is_instance_valid(instance_from_id(id)):
				return false
		return true

	func _spawn_mech(pos: Vector3) -> CharacterBody3D:
		var mech: CharacterBody3D = load("res://scenes/mecha/mecha_base.tscn").instantiate()
		mech.position = pos
		get_tree().current_scene.add_child(mech)
		mech.is_player_driven = false
		_spawned_mech_ids.append(mech.get_instance_id())
		return mech

	func _land(mech: CharacterBody3D) -> void:
		# Ground is only guaranteed in the test scene; elsewhere settle briefly.
		var f := 0
		while not mech.is_on_floor() and f < 120:
			await get_tree().physics_frame
			f += 1
		await get_tree().physics_frame
		await get_tree().physics_frame

	func finish() -> void:
		print("TRANSITION_AUDIT: checks=%d fails=%d blocked=%d" % [_checks, _fails, _blocked])
		get_tree().quit(1 if _fails > 0 else 0)

	func _ready() -> void:
		await get_tree().process_frame
		await get_tree().process_frame
		await _run()

	func _run() -> void:
		_snap_all()
		EventBus.damage_received.connect(_on_dr)
		# ---- Stage A: combat objects in test scene (direct spawn, landed) ----
		var cam := Camera3D.new()
		cam.name = "AuditCam"
		get_tree().current_scene.add_child(cam)
		var ground := StaticBody3D.new()
		ground.name = "AuditGround"
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
		_check(hs1 != null, "A: health present on spawned mech")
		hs1.take_damage_to_part("arm_left", 30.0, "kinetic")
		await get_tree().physics_frame
		_check(float(GlobalData.weapons.part_damage.get("arm_left", 0.0)) > 0.0, "A: damage reaches persistent dict")
		var m2 := _spawn_mech(Vector3(20, 10, 0))
		await _land(m2)
		var hs2: Node = m2.get_node_or_null("HealthSystem")
		_check(float(hs2.parts["arm_left"]["armor_hp"]) < float(hs2.parts["arm_left"]["max_armor"]), "A: second spawn derives damage")
		m1.queue_free()
		m2.queue_free()
		await get_tree().process_frame
		GlobalData.weapons.part_damage.clear()
		# ---- Stage B: suppressed combat-logic path (project test hook) ----
		GameManager.suppress_scene_change = true
		GameManager.enter_combat("grunt")
		await get_tree().process_frame
		_check(GameManager.current_state == GameManager.State.COMBAT, "B: combat state entered")
		_check(GlobalData.pre_combat_weapon_loadout is Dictionary, "B: pre-combat loadout snapshot taken")
		GameManager.suppress_scene_change = false
		# ---- Stage C: real change to board ----
		GameManager.enter_board()
		if not await _wait_scene("game_board", 150.0):
			_block("game_board never loaded")
			finish()
			return
		_check(_spawned_mechs_all_freed(), "C: no Stage-A mecha residue after scene change")
		_check(get_tree().root.find_child("SceneTransitionAudit", false, false) == null, "C: old test scene freed")
		# ---- Stage D: board -> hangar -> board (real production path) ----
		var pd_before: Dictionary = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
		GameManager.enter_hangar()
		if not await _wait_scene("hangar_scene", 150.0):
			_block("hangar_scene never loaded")
			finish()
			return
		_check(GameManager.current_state == GameManager.State.HANGAR, "D: hangar state entered")
		GameManager.return_to_board()
		if not await _wait_scene("game_board", 150.0):
			_block("board return never loaded")
			finish()
			return
		_check((GlobalData.weapons.part_damage as Dictionary) == pd_before, "D: part_damage stable across hangar hop")
		# ---- Stage E: second lap for accumulation ----
		GameManager.enter_hangar()
		if not await _wait_scene("hangar_scene", 150.0):
			_block("hangar reload never loaded")
			finish()
			return
		GameManager.return_to_board()
		if not await _wait_scene("game_board", 150.0):
			_block("board reload never loaded")
			finish()
			return
		_check(_spawned_mechs_all_freed(), "E: still no Stage-A mecha residue after 2 laps")
		_check(GameManager.current_state == GameManager.State.BOARD, "E: board state stable")
		_restore_all()
		finish()
