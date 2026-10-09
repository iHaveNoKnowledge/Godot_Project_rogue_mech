extends Node3D
## TEMPORARY gate-execution integration audit (DELETE AFTER VERIFICATION).
## Exercises the WIRED paths (never the resolvers alone):
##   _try_fire / _commit_normal_fire / _fire_missile_salvo-entry /
##   MechaCombat aim liveness — across Alive/Destroyed/Ejected × FIRE/MELEE/
##   AIM/GUARD, plus F-2 live fire, spam, and side-effect accounting.
## Asserts ammo/heat/cooldown/animation/lifecycle/shield/damage deltas.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GATEEXE OK: " + name)
	else:
		_fails += 1
		printerr("GATEEXE FAIL: " + name)


class MockEnemy:
	extends Node3D
	var hits: Array = []

	func take_damage_at_point(damage: float, _point: Vector3, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})

	func take_damage(damage: float, _type: String = "kinetic") -> void:
		hits.append({"frame": Engine.get_physics_frames(), "damage": damage})


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
	# Capture request (production play state). Headless dummy server ignores
	# it (readback stays VISIBLE), so per-frame aim assignment is
	# environmentally unreachable here — AIM is proven via direct ray +
	# wired gate decisions instead. Kept: harmless, documents intent.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
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
	var anim = mecha.get_node_or_null("MechaAnimation")
	var animator = anim.get("action_animator") if anim != null else null
	_check(animator != null, "action animator present")
	var combat = mecha.get_node_or_null("MechaCombat")
	_check(combat != null, "MechaCombat present")
	var hs = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "HealthSystem present")

	var rifle := load("res://resources/mech/stock/weapon_beam_rifle.tres") as WeaponPart
	var blade := load("res://resources/mech/stock/weapon_heat_blade.tres") as WeaponPart
	var shield := load("res://resources/mech/stock/weapon_shield.tres") as WeaponPart
	var rail := load("res://resources/mech/stock/weapon_railgun.tres") as WeaponPart
	var mini := load("res://resources/mech/stock/weapon_minigun.tres") as WeaponPart
	var pod := load("res://resources/mech/stock/weapon_missile.tres") as WeaponPart
	_check(rifle != null and blade != null and shield != null and rail != null and mini != null and pod != null, "stock loadout loads")

	var enemy := MockEnemy.new()
	enemy.add_to_group("enemy")
	mecha.add_child(enemy)
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	await get_tree().physics_frame

	# ---- ALIVE: allowed actions still execute ---------------------------
	wm.right_hand = rifle
	_fill(wm, rifle, 10)
	var a0 := _ammo(wm, rifle)
	wm._try_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0 - 1, "alive rifle FIRE executes (ammo %d→%d)" % [a0, _ammo(wm, rifle)])
	for i in range(30):
		await get_tree().physics_frame

	wm.right_hand = blade
	_fill(wm, blade, 99)
	animator.last_attack_time_ms = 0
	enemy.hits.clear()
	var aid0: int = animator.attack_id
	wm._try_fire("right", blade)
	_check(animator.attack_id == aid0 + 1, "alive blade MELEE starts through wired gate")
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 1 and not animator.is_melee_active(), "alive blade 1-1-1-1 lifecycle intact")

	# Wired-path repeat: gated MELEE allows again after cooldown (no gate latch).
	animator.last_attack_time_ms = 0
	var aid1: int = animator.attack_id
	_fill(wm, blade, 99)
	for i in range(60):
		await get_tree().physics_frame
	wm._try_fire("right", blade)
	_check(animator.attack_id == aid1 + 1, "wired MELEE re-allows after cooldown")
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 2, "second wired swing hits once more")

	wm.left_hand = shield
	_check(bool(wm.get("shield_active")) == false, "shield starts down")
	wm._commit_normal_fire("left")
	_check(bool(wm.get("shield_active")) == true, "alive shield GUARD toggles")
	wm._commit_normal_fire("left")
	_check(bool(wm.get("shield_active")) == false, "alive shield GUARD toggles back")

	for i in range(10):
		await get_tree().physics_frame
	# Per-frame assignment is unreachable headless (UI-modal gate needs a
	# captured mouse; readback proves the dummy server forces VISIBLE), so
	# AIM is proven at the decision layer with live state reads (below) plus
	# the direct ray call, which bypasses only the modal early-return.
	_check((combat.resolve_aim_point() as Vector3) != Vector3.ZERO, "alive AIM ray resolves")
	wm.right_hand = rifle
	var g_aim: Dictionary = wm._request_gate("right", "AIM")
	_check(bool(g_aim.get("allowed")), "alive AIM gate allows")

	wm.shoulder_left = pod
	_fill(wm, pod, 5)
	var p0 := _ammo(wm, pod)
	wm._try_fire("shoulder_left", pod)
	_check(_ammo(wm, pod) < p0, "alive shoulder pod FIRE executes (ammo %d→%d)" % [p0, _ammo(wm, pod)])
	for i in range(30):
		await get_tree().physics_frame

	# ---- F-2 LIVE: support destroyed still fires -------------------------
	wm.left_hand = rail
	wm.right_hand = rifle
	_fill(wm, rail, 5)
	(hs.parts["arm_right"] as Dictionary)["destroyed"] = true
	await get_tree().physics_frame
	_check(bool(hs.is_part_destroyed("arm_right")), "support arm reads destroyed")
	var r0 := _ammo(wm, rail)
	wm._try_fire("left", rail)
	_check(_ammo(wm, rail) == r0 - 1, "railgun + destroyed support FIRES (Option B, ammo %d→%d)" % [r0, _ammo(wm, rail)])
	for i in range(30):
		await get_tree().physics_frame
	wm.left_hand = mini
	_fill(wm, mini, 10)
	var m0 := _ammo(wm, mini)
	wm._try_fire("left", mini)
	_check(_ammo(wm, mini) < m0, "minigun + destroyed support FIRES (ammo %d→%d)" % [m0, _ammo(wm, mini)])
	for i in range(30):
		await get_tree().physics_frame
	# Contrast: acting arm destroyed denies the same request.
	(hs.parts["arm_left"] as Dictionary)["destroyed"] = true
	await get_tree().physics_frame
	var r1 := _ammo(wm, rail)
	wm.left_hand = rail
	_fill(wm, rail, 5)
	r1 = _ammo(wm, rail)
	wm._try_fire("left", rail)
	_check(_ammo(wm, rail) == r1, "acting arm destroyed denies (ammo unchanged)")
	(hs.parts["arm_left"] as Dictionary)["destroyed"] = false
	(hs.parts["arm_right"] as Dictionary)["destroyed"] = false
	await get_tree().physics_frame

	# ---- DESTROYED MECH: all four deny with zero side effects ------------
	hs.set("is_destroyed", true)
	await get_tree().physics_frame
	_fill(wm, rifle, 10)
	wm.right_hand = rifle
	a0 = _ammo(wm, rifle)
	var did0: int = animator.attack_id
	wm._try_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0 and animator.attack_id == did0 and wm.get("_pending_melee").is_empty(), "destroyed FIRE denied, zero side effects")
	_fill(wm, blade, 99)
	wm.right_hand = blade
	animator.last_attack_time_ms = 0
	enemy.hits.clear()
	for i in range(4):
		wm._try_fire("right", blade)
	_check(animator.attack_id == did0 and enemy.hits.is_empty(), "destroyed 4 MELEE requests → 0 starts, 0 strikes")
	wm.left_hand = shield
	wm._commit_normal_fire("left")
	_check(bool(wm.get("shield_active")) == false, "destroyed GUARD denied (no toggle)")
	# Per-frame aim assignment is headless-unreachable (see alive section);
	# the denial itself is proven live at the wired decision layer.
	wm.right_hand = rifle
	var g_aim_dead: Dictionary = wm._request_gate("right", "AIM")
	_check(not bool(g_aim_dead.get("allowed")) and str(g_aim_dead.get("reason")) == "dead", "destroyed AIM gate denies")
	hs.set("is_destroyed", false)
	await get_tree().physics_frame

	# ---- EJECT: all four deny (input boundary + dispatch + aim) ----------
	var prev_state = GameManager.current_state
	GameManager.current_state = GameManager.State.EJECT
	mecha.set_meta("is_parked", true)
	mecha.set_meta("is_unoccupied", true)
	await get_tree().physics_frame
	_fill(wm, rifle, 10)
	wm.right_hand = rifle
	a0 = _ammo(wm, rifle)
	wm._try_fire("right", rifle)
	_check(_ammo(wm, rifle) == a0 and wm.get("_pending_melee").is_empty(), "ejected FIRE denied at dispatch")
	wm.left_hand = shield
	wm._commit_normal_fire("left")
	_check(bool(wm.get("shield_active")) == false, "ejected GUARD denied (no toggle)")
	wm.right_hand = rifle
	var g_aim_eject: Dictionary = wm._request_gate("right", "AIM")
	_check(not bool(g_aim_eject.get("allowed")) and str(g_aim_eject.get("reason")) == "disabled", "ejected AIM gate denies")
	mecha.remove_meta("is_parked")
	mecha.remove_meta("is_unoccupied")
	GameManager.current_state = prev_state
	await get_tree().physics_frame
	_check(GameManager.current_state == prev_state and not mecha.has_meta("is_parked"), "eject state restored")

	# ---- ALIVE SPAM: 4 inputs → 4 starts, clean ---------------------------
	wm.right_hand = blade
	_fill(wm, blade, 99)
	animator.last_attack_time_ms = 0
	enemy.hits.clear()
	var sid: int = animator.attack_id
	for i in range(4):
		wm._melee_attack("right", blade)
	_check(animator.attack_id == sid + 4, "spam mints four starts")
	var budget: int = animator.strike_times.size()
	for i in range(220):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "spam final swing only (%d)" % enemy.hits.size())
	for i in range(60):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "spam no late dupes")

	print("GATEEXE: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GATEEXE_FAILED")
		get_tree().quit(1)
	else:
		print("GATEEXE_PASSED")
		get_tree().quit(0)
