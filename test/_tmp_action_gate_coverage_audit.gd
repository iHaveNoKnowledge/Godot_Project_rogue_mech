extends Node3D
## TEMPORARY gate-coverage audit (DELETE AFTER VERIFICATION).
## Covers what unit suites cannot: salvo gate ORDER (deny before reserve/
## ammo/projectile mutation), hold-path wiring alive + eject-holdover close,
## all through production entry points. Read-only reuse of live objects.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GATECOV OK: " + name)
	else:
		_fails += 1
		printerr("GATECOV FAIL: " + name)


func _fill(wm: Node, weapon: WeaponPart, n: int) -> void:
	var core = wm._core_for_weapon(weapon)
	if core != null and "ammo" in core:
		core.ammo = n
	if core != null and "cooldown" in core:
		core.cooldown = 0.0
	if core != null and "heat" in core:
		core.heat = 0.0


func _ammo(wm: Node, weapon: WeaponPart) -> int:
	var core = wm._core_for_weapon(weapon)
	if core != null and "ammo" in core:
		return int(core.ammo)
	return -1


func _ready() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.0)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)

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
	for i in range(90):
		await get_tree().physics_frame
		if mecha.is_on_floor():
			break
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null:
		wm = Node3D.new()
		wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
		wm.name = "WeaponManager"
		mecha.add_child(wm)
		await get_tree().process_frame
	_check(wm != null, "WeaponManager present")
	var hs = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "HealthSystem present")

	var rifle := load("res://resources/mech/stock/weapon_beam_rifle.tres") as WeaponPart
	var pod := load("res://resources/mech/stock/weapon_missile.tres") as WeaponPart
	_check(rifle != null and pod != null, "stock rifle/pod load")
	wm.right_hand = rifle
	wm.shoulder_left = pod

	# Hold path alive: _hold_fire drives the same gate and fires.
	_fill(wm, rifle, 10)
	var a0 := _ammo(wm, rifle)
	wm._hold_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0 - 1, "alive hold-path FIRE executes (ammo %d→%d)" % [a0, _ammo(wm, rifle)])
	for i in range(30):
		await get_tree().physics_frame

	# Salvo alive with empty lock set: gate allows, loop fires nothing, no crash.
	_fill(wm, pod, 5)
	var p0 := _ammo(wm, pod)
	wm._fire_missile_salvo("shoulder_left", pod, {})
	_check(_ammo(wm, pod) == p0, "alive salvo with empty targets fires nothing, no crash")

	# Salvo destroyed: gate denies BEFORE reserve/ammo/projectile mutation.
	hs.set("is_destroyed", true)
	await get_tree().physics_frame
	_fill(wm, pod, 5)
	p0 = _ammo(wm, pod)
	wm._fire_missile_salvo("shoulder_left", pod, {})
	_check(_ammo(wm, pod) == p0, "destroyed salvo denied with zero mutation")
	# Hold path destroyed: same verdict through the hold entry.
	_fill(wm, rifle, 10)
	a0 = _ammo(wm, rifle)
	wm._hold_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0, "destroyed hold-path denied with zero mutation")
	hs.set("is_destroyed", false)
	await get_tree().physics_frame

	# Hold-eject edge: EJECT + parked meta denies the held trigger at dispatch
	# (the holdover the input boundary alone cannot close).
	var prev_state = GameManager.current_state
	GameManager.current_state = GameManager.State.EJECT
	mecha.set_meta("is_parked", true)
	mecha.set_meta("is_unoccupied", true)
	await get_tree().physics_frame
	_fill(wm, rifle, 10)
	a0 = _ammo(wm, rifle)
	wm._hold_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0, "eject holdover denied at dispatch (ammo unchanged)")
	mecha.remove_meta("is_parked")
	mecha.remove_meta("is_unoccupied")
	GameManager.current_state = prev_state
	await get_tree().physics_frame
	_check(GameManager.current_state == prev_state and not mecha.has_meta("is_parked"), "eject state restored")

	print("GATECOV: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GATECOV_FAILED")
		get_tree().quit(1)
	else:
		print("GATECOV_PASSED")
		get_tree().quit(0)
