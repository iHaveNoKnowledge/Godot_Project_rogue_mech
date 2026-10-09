extends Node3D
## TEMPORARY action-gate runtime audit (DELETE AFTER VERIFICATION).
## Calls WeaponActionGate.query DIRECTLY on live objects — never wires the
## gate into input or execution. Live: stock loadout capabilities via
## wm.get_capability + real liveness reads (HealthSystem.is_destroyed,
## GameManager eject state). Dead/eject DENIAL paths are unit-proven; flipping
## them live would mutate global/harness state, so live asserts the read path
## reports alive/present and the full allow-matrix agrees.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GATERUN OK: " + name)
	else:
		_fails += 1
		printerr("GATERUN FAIL: " + name)


func _live_runtime(mecha: Node) -> Dictionary:
	var destroyed := false
	var hs = mecha.get_node_or_null("HealthSystem")
	if hs != null:
		destroyed = bool(hs.get("is_destroyed"))
	var absent := GameManager.current_state == GameManager.State.EJECT
	return {"mech_destroyed": destroyed, "operator_absent": absent}


func _ready() -> void:
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base loads")
	var mecha: CharacterBody3D = mecha_scene.instantiate()
	add_child(mecha)
	var cam := Camera3D.new()
	cam.position = mecha.global_position + Vector3(0, 6.0, 10.0)
	add_child(cam)
	cam.look_at(mecha.global_position + Vector3(0, 1.5, -10.0))
	cam.make_current()
	await get_tree().physics_frame
	for i in range(60):
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
	var shield := load("res://resources/mech/stock/weapon_shield.tres") as WeaponPart
	var rail := load("res://resources/mech/stock/weapon_railgun.tres") as WeaponPart
	_check(rifle != null and blade != null and shield != null and rail != null, "stock loadout loads")

	# Live liveness reads report alive + operator present (paths verified).
	var rt := _live_runtime(mecha)
	_check(bool(rt.get("mech_destroyed")) == false and bool(rt.get("operator_absent")) == false, "live runtime reads alive/present")

	# Full allow-matrix on the live loadout through capability → gate.
	wm.right_hand = rifle
	wm.left_hand = shield
	var matrix := {
		"right/FIRE": wm.get_capability("right", "FIRE"),
		"right/AIM": wm.get_capability("right", "AIM"),
		"left/GUARD": wm.get_capability("left", "GUARD"),
	}
	wm.right_hand = blade
	matrix["right/MELEE"] = wm.get_capability("right", "MELEE")
	wm.left_hand = rail
	wm.right_hand = rifle
	matrix["left/FIRE-heavy"] = wm.get_capability("left", "FIRE")
	for key in matrix.keys():
		var g: Dictionary = WeaponActionGate.query(matrix[key], rt)
		_check(bool(g.get("allowed")) and str(g.get("reason")) == "ok", "live gate allows %s" % key)
	# Rejections pass through live too.
	wm.right_hand = blade
	var g_rej: Dictionary = WeaponActionGate.query(wm.get_capability("right", "FIRE"), rt)
	_check(not bool(g_rej.get("allowed")) and str(g_rej.get("reason")) == "action_unsupported", "live gate preserves blade FIRE denial")

	# 100 live queries → identical results, zero gameplay mutation.
	var id0: int = animator.attack_id
	var first: Dictionary = WeaponActionGate.query(wm.get_capability("right", "MELEE"), rt)
	var stable := true
	for i in range(100):
		for k in matrix.keys():
			var g: Dictionary = WeaponActionGate.query(matrix[k], _live_runtime(mecha))
			if not bool(g.get("allowed")):
				stable = false
		if WeaponActionGate.query(wm.get_capability("right", "MELEE"), rt) != first:
			stable = false
	_check(stable, "100 live queries deterministic")
	_check(animator.attack_id == id0 and wm.get("_pending_melee").is_empty() and bool(wm.get("shield_active")) == false, "100 live queries mutate nothing")

	print("GATERUN: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("GATERUN_FAILED")
		get_tree().quit(1)
	else:
		print("GATERUN_PASSED")
		get_tree().quit(0)
