extends Node3D
## TEMPORARY capability runtime audit (DELETE AFTER VERIFICATION).
## Live path: stock Weapon → Frame/Handling → get_capability → existing
## action request. Proves the check is consulted WITHOUT changing execution:
## melee lifecycle stays 1 input → 1 start → 1 strike → 1 hit → 1 complete,
## and queries alone mint zero lifecycle events (spam-safe).

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("CAPRUN OK: " + name)
	else:
		_fails += 1
		printerr("CAPRUN FAIL: " + name)


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

	var rifle := load("res://resources/mech/stock/weapon_beam_rifle.tres") as WeaponPart
	var blade := load("res://resources/mech/stock/weapon_heat_blade.tres") as WeaponPart
	var rail := load("res://resources/mech/stock/weapon_railgun.tres") as WeaponPart
	_check(rifle != null and blade != null and rail != null, "stock rifle/blade/railgun load")

	# Capability agrees with the live loadout: rifle fires+aims, blade melees.
	wm.right_hand = rifle
	var c_fire: Dictionary = wm.get_capability("right", "FIRE")
	_check(bool(c_fire.get("allowed")) and str(c_fire.get("grip_mode")) == "ONE_HAND", "live rifle FIRE allowed ONE_HAND")
	_check(bool(wm.get_capability("right", "AIM").get("allowed")), "live rifle AIM allowed")
	_check(str(wm.get_capability("right", "MELEE").get("reason")) == "action_unsupported", "live rifle MELEE rejected")
	wm.right_hand = blade
	_check(bool(wm.get_capability("right", "MELEE").get("allowed")), "live blade MELEE allowed")
	_check(str(wm.get_capability("right", "FIRE").get("reason")) == "action_unsupported", "live blade FIRE rejected")
	wm.left_hand = rail
	var c_rail: Dictionary = wm.get_capability("left", "FIRE")
	_check(bool(c_rail.get("allowed")) and str(c_rail.get("grip_mode")) in ["TWO_HAND", "BRACED"], "live railgun FIRE allowed two-hand family (grip=%s)" % str(c_rail.get("grip_mode")))

	# Queries mint no lifecycle: attack_id frozen, no pending melee.
	var id0: int = animator.attack_id
	for i in range(20):
		wm.get_capability("right", "MELEE")
		wm.get_capability("right", "FIRE")
		wm.get_capability("left", "FIRE")
	_check(animator.attack_id == id0 and wm.get("_pending_melee").is_empty(), "20 live queries mint zero lifecycle events")

	# Execute through the pre-checked path: 1 input → 1 start → 1 strike → 1 hit → 1 complete.
	var enemy := MockEnemy.new()
	enemy.add_to_group("enemy")
	mecha.add_child(enemy)
	enemy.global_position = mecha.global_position + Vector3(0, 0, -2.5)
	await get_tree().physics_frame
	animator.last_attack_time_ms = 0
	enemy.hits.clear()
	var pre: Dictionary = wm.get_capability("right", "MELEE")
	_check(bool(pre.get("allowed")), "pre-check gates the swing (allowed)")
	var start_frame := Engine.get_physics_frames()
	wm._melee_attack("right", blade)
	_check(enemy.hits.is_empty(), "no same-frame damage")
	for i in range(150):
		await get_tree().physics_frame
	_check(enemy.hits.size() == 1, "exactly 1 hit per swing (got %d)" % enemy.hits.size())
	if enemy.hits.size() == 1:
		_check(int(enemy.hits[0]["frame"]) > start_frame + 3, "hit at strike (f+%d)" % (int(enemy.hits[0]["frame"]) - start_frame))
	_check(not animator.is_melee_active(), "attack completes")

	# Spam: 4 inputs → 4 starts, final swing only, no phantoms or late dupes.
	enemy.hits.clear()
	animator.last_attack_time_ms = 0
	var sid: int = animator.attack_id
	for i in range(4):
		wm._melee_attack("right", blade)
	_check(animator.attack_id == sid + 4, "four inputs mint four starts")
	var budget: int = animator.strike_times.size()
	for i in range(220):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "only final swing strikes (%d)" % enemy.hits.size())
	for i in range(60):
		await get_tree().physics_frame
	_check(enemy.hits.size() == budget, "no late duplicate hits")

	# F-1 GUARD live: stock shield guards from the hand; queries never raise it.
	var shield := load("res://resources/mech/stock/weapon_shield.tres") as WeaponPart
	_check(shield != null, "stock shield loads")
	wm.left_hand = shield
	wm.right_hand = rifle
	var c_guard: Dictionary = wm.get_capability("left", "GUARD")
	_check(bool(c_guard.get("allowed")) and str(c_guard.get("grip_mode")) == "ONE_HAND", "live shield GUARD allowed ONE_HAND")
	_check(str(wm.get_capability("right", "GUARD").get("reason")) == "action_unsupported", "live rifle GUARD rejected")
	_check(bool(wm.get("shield_active")) == false, "shield starts down")
	for i in range(20):
		wm.get_capability("left", "GUARD")
	_check(bool(wm.get("shield_active")) == false and wm.get("_pending_melee").is_empty(), "20 GUARD queries never raise the shield nor start melee")

	# F-2 live (Option B): destroy the support arm; railgun stays permitted
	# and enforcement still holsters — execution and capability agree.
	wm.left_hand = rail
	wm.right_hand = rifle
	var hs = mecha.get_node_or_null("HealthSystem")
	var parts_ok: bool = hs != null and hs.get("parts") != null \
		and (hs.get("parts") as Dictionary).has("arm_right") \
		and ((hs.get("parts") as Dictionary)["arm_right"] as Dictionary).has("destroyed")
	_check(parts_ok, "live HealthSystem exposes arm_right destroyed flag")
	((hs.get("parts") as Dictionary)["arm_right"] as Dictionary)["destroyed"] = true
	await get_tree().physics_frame
	_check(bool(hs.is_part_destroyed("arm_right")), "support arm reads destroyed live")
	var c_rail_dead: Dictionary = wm.get_capability("left", "FIRE")
	_check(bool(c_rail_dead.get("allowed")) and str(c_rail_dead.get("grip_mode")) in ["TWO_HAND", "BRACED"], "railgun + destroyed support still allowed (Option B, grip=%s)" % str(c_rail_dead.get("grip_mode")))
	var carry_before: int = wm.carry.size()
	wm._enforce_two_hand_grip()
	_check(wm.get("right_hand") == null and wm.carry.size() == carry_before + 1, "enforcement still holsters with destroyed support (execution agrees)")
	# Contrast: destroying the ACTING arm rejects the same query.
	((hs.get("parts") as Dictionary)["arm_left"] as Dictionary)["destroyed"] = true
	await get_tree().physics_frame
	_check(str(wm.get_capability("left", "FIRE").get("reason")) == "handling_restriction", "destroyed acting arm rejects (handling_restriction)")

	print("CAPRUN: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("CAPRUN_FAILED")
		get_tree().quit(1)
	else:
		print("CAPRUN_PASSED")
		get_tree().quit(0)
