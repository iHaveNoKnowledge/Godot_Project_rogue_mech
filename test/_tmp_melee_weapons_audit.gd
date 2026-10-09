extends Node3D
## TEMPORARY per-weapon live melee audit (DELETE AFTER VERIFICATION).
## Drives the REAL dispatch (wm._melee_attack) on a live mecha_base + MockEnemy
## for each stock melee weapon. Does NOT touch production code.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("WPNMELEE OK: " + name)
	else:
		_fails += 1
		printerr("WPNMELEE FAIL: " + name)


class MockEnemy:
	extends Node3D
	var hits: Array = []

	func take_damage_at_point(damage: float, _point: Vector3, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})

	func take_damage(damage: float, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})


func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.0)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)


func _settle(mecha: CharacterBody3D) -> void:
	for i in range(90):
		await get_tree().physics_frame
		if mecha.is_on_floor():
			break


func _ready() -> void:
	_make_ground()
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base loads")
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	add_child(mecha)
	var cam := Camera3D.new()
	cam.position = mecha.global_position + Vector3(0, 6.0, 10.0)
	add_child(cam)
	cam.look_at(mecha.global_position + Vector3(0, 1.0, -20.0))
	cam.make_current()
	await get_tree().physics_frame
	await _settle(mecha)
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		wm = Node3D.new()
		wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
		wm.name = "WeaponManager"
		mecha.add_child(wm)
		await get_tree().process_frame
	_check(wm != null, "WeaponManager present")
	var anim = mecha.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator") if anim != null else null
	_check(animator != null, "action animator present (compile repair live)")

	var enemy := MockEnemy.new()
	enemy.add_to_group("enemy")
	mecha.add_child(enemy)

	var weapons := [
		"res://resources/mech/stock/weapon_heat_blade.tres",
		"res://resources/mech/stock/weapon_combat_knife.tres",
		"res://resources/mech/stock/weapon_mace.tres",
		"res://resources/mech/stock/weapon_pile_bunker.tres",
	]
	for path in weapons:
		var w := load(path) as WeaponPart
		_check(w != null, "%s loads" % path.get_file())
		if w == null:
			continue
		await _one_weapon(mecha, wm, animator, enemy, w)
	# Spam / double-animation probe on the representative AF weapon + legacy pile.
	for path in [weapons[0], weapons[3]]:
		var w := load(path) as WeaponPart
		await _spam_probe(mecha, wm, animator, enemy, w)

	print("WPNMELEE: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("WPNMELEE_FAILED")
		get_tree().quit(1)
	else:
		print("WPNMELEE_PASSED")
		get_tree().quit(0)


func _one_weapon(mecha: CharacterBody3D, wm: Node, animator: Node, enemy: MockEnemy, w: WeaponPart) -> void:
	var tag: String = w.weapon_name
	enemy.hits.clear()
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	await get_tree().physics_frame
	animator.last_attack_time_ms = 0
	var start_frame := Engine.get_physics_frames()
	var id_before: int = animator.attack_id
	wm._melee_attack("right", w)
	_check(enemy.hits.is_empty(), "[%s] no same-frame damage on input" % tag)
	_check(animator.attack_id == id_before + 1, "[%s] one input mints exactly one attack (no double-start)" % tag)
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 1, "[%s] exactly 1 hit per swing (got %d)" % [tag, enemy.hits.size()])
	if enemy.hits.size() == 1:
		_check(int(enemy.hits[0]["frame"]) > start_frame + 3, "[%s] hit lands after swing start at strike (f+%d)" % [tag, int(enemy.hits[0]["frame"]) - start_frame])
		_check(float(enemy.hits[0]["damage"]) > 0.0, "[%s] hit carries damage (%.1f)" % [tag, float(enemy.hits[0]["damage"])])
	_check(not animator.is_melee_active(), "[%s] attack completes and releases" % tag)
	# Second swing: exactly one more hit, new attack id (no duplication).
	animator.last_attack_time_ms = 0
	var id2: int = animator.attack_id
	wm._melee_attack("right", w)
	_check(animator.attack_id == id2 + 1, "[%s] second input mints exactly one more attack" % tag)
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 2, "[%s] two swings = two hits, no duplication (got %d)" % [tag, enemy.hits.size()])


func _spam_probe(mecha: CharacterBody3D, wm: Node, animator: Node, enemy: MockEnemy, w: WeaponPart) -> void:
	var tag: String = w.weapon_name
	enemy.hits.clear()
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	animator.last_attack_time_ms = 0
	var id_before: int = animator.attack_id
	for i in range(4):
		wm._melee_attack("right", w)
	_check(animator.attack_id == id_before + 4, "[%s spam] four inputs mint four starts, no double-fire per input" % tag)
	var budget: int = animator.strike_times.size()
	for i in range(220):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "[%s spam] only final swing strikes (%d, no phantoms)" % [tag, enemy.hits.size()])
	for i in range(60):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "[%s spam] no late duplicate hits after completion" % tag)
