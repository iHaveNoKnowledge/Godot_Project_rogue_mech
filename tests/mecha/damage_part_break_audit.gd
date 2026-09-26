extends Node

## Deterministic damage -> part-break integration audit. Drives ONLY the real
## production path (hitbox entry, take_damage_at_point/to_part, signals,
## visuals, penalties, persistence keys) on a live mecha_base instance.
## Run: godot --headless --path . res://tests/mecha/damage_part_break_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _sig := {"health_changed": 0, "armor_broken": 0, "part_destroyed": 0, "mecha_destroyed": 0}
var _bus_hits := 0
var _mech: CharacterBody3D
var _hs: Node
var _pd_snap: Dictionary = {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("DAMAGE_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _on_hc(_s: String, _l: String, _c: float, _m: float) -> void:
	_sig["health_changed"] += 1


func _on_ab(_s: String) -> void:
	_sig["armor_broken"] += 1


func _on_pd(_s: String) -> void:
	_sig["part_destroyed"] += 1


func _on_md() -> void:
	_sig["mecha_destroyed"] += 1


func _on_bus(_slot: String, _amount: float, _type: String) -> void:
	_bus_hits += 1


func _hp(slot: String) -> Array:
	var p: Dictionary = _hs.parts[slot]
	return [p["armor_hp"], p["frame_hp"], p["armor_broken"], p["destroyed"]]


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)

	_mech = load(MECH_SCENE).instantiate()
	_mech.position = Vector3(0, 10, 0)
	add_child(_mech)
	_mech.is_player_driven = false
	var f := 0
	while not _mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	_hs = _mech.get_node_or_null("HealthSystem")
	_check(_hs != null, "HealthSystem present with 6-slot parts")
	_check(_hs.parts.keys().size() == 6, "six damageable slots")
	_hs.health_changed.connect(_on_hc)
	_hs.armor_broken.connect(_on_ab)
	_hs.part_destroyed.connect(_on_pd)
	_hs.mecha_destroyed.connect(_on_md)
	EventBus.damage_received.connect(_on_bus)
	_pd_snap = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)

	# ---- 1. routing: hit positions resolve to the right slot ----
	var arm_pos: Vector3 = (_mech.get_node_or_null("ArmLeft") as Node3D).global_position
	var head_pos: Vector3 = (_mech.get_node_or_null("Head") as Node3D).global_position
	var leg_pos: Vector3 = (_mech.get_node_or_null("LegLeft") as Node3D).global_position
	_check(_hs._resolve_hit(arm_pos)["slot"] == "arm_left", "hit at arm resolves arm_left")
	_check(_hs._resolve_hit(head_pos)["slot"] == "head", "hit at head resolves head")
	_check(_hs._resolve_hit(leg_pos)["slot"] == "leg_left", "hit at leg resolves leg_left")

	# ---- 2. layering: armor absorbs first, frame untouched ----
	var before := _hp("arm_left")
	_hs.take_damage_at_point(5.0, arm_pos, "kinetic")
	await get_tree().physics_frame
	var after := _hp("arm_left")
	_check(after[0] < before[0], "armor absorbs first hit")
	_check(is_equal_approx(after[1], before[1]), "frame untouched while armor intact")
	_check(_hp("head")[0] == _hs.parts["head"]["max_armor"], "other slots untouched by localized hit")

	# ---- 3. single-hit linearity (durability wear legitimately raises the
	# second identical hit; a double-apply would double ONE call instead) ----
	var h0: float = _hs.parts["leg_right"]["armor_hp"]
	_hs.take_damage_to_part("leg_right", 10.0, "kinetic")
	var h1: float = _hs.parts["leg_right"]["armor_hp"]
	_hs.take_damage_to_part("leg_right", 10.0, "kinetic")
	var h2: float = _hs.parts["leg_right"]["armor_hp"]
	var d1: float = h0 - h1
	var d2: float = h1 - h2
	_check(d1 > 0.0 and d2 > 0.0 and d2 < 2.0 * d1, "identical hits apply once each (%.3f, %.3f)" % [d1, d2])

	# ---- 4. hitbox entry applies exactly once ----
	var hc0: int = _sig["health_changed"]
	var proj := CharacterBody3D.new()
	proj.add_to_group("projectile")
	var dmg_script := GDScript.new()
	dmg_script.source_code = "extends CharacterBody3D\nfunc get_damage() -> float:\n\treturn 7.0\n"
	dmg_script.reload()
	proj.set_script(dmg_script)
	_check(proj.has_method("get_damage"), "fake projectile exposes damage API")
	add_child(proj)
	proj.global_position = arm_pos
	var hb: Area3D = _mech.get_node_or_null("Hitbox")
	_check(hb != null, "whole-body Hitbox present")
	var arm_before: float = _hs.parts["arm_left"]["armor_hp"]
	hb._on_body_entered(proj)
	await get_tree().physics_frame
	var arm_after: float = _hs.parts["arm_left"]["armor_hp"]
	_check(_sig["health_changed"] == hc0 + 1, "hitbox entry emits exactly one health change")
	_check(arm_before - arm_after > 0.0 and arm_before - arm_after < 30.0, "hitbox hit applies single-hit damage (%.3f)" % (arm_before - arm_after))
	if is_instance_valid(proj):
		proj.queue_free()

	# ---- 5. break transitions: armor -> frame -> destroyed, signals once each ----
	_sig["armor_broken"] = 0
	_sig["part_destroyed"] = 0
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.parts["arm_left"]["armor_broken"] == true, "arm_left armor breaks")
	_check(_sig["armor_broken"] == 1, "armor_broken emitted exactly once")
	var am: Node3D = _mech.get_node_or_null("ArmLeft/ArmorMesh")
	var fm: Node3D = _mech.get_node_or_null("ArmLeft/FrameMesh")
	_check(am != null and am.visible == false, "broken armor hidden (frame shown)")
	_check(fm != null and fm.visible == true, "inner frame exposed on break")
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.parts["arm_left"]["destroyed"] == true, "arm_left frame destroyed")
	_check(_sig["part_destroyed"] == 1, "part_destroyed emitted exactly once")
	_check(fm.visible == false, "destroyed part hidden entirely")
	# post-break hits ignored
	var hp_hold: float = _hs.parts["arm_left"]["frame_hp"]
	_hs.take_damage_to_part("arm_left", 100.0, "kinetic")
	_check(is_equal_approx(_hs.parts["arm_left"]["frame_hp"], hp_hold), "post-break hits ignored")

	# ---- 6. hitbox skips destroyed parts ----
	var r: Dictionary = _hs._resolve_hit(arm_pos)
	_check(r["slot"] != "arm_left", "destroyed arm skipped by hit resolution (got %s)" % str(r["slot"]))

	# ---- 7. capability: arm break disables hand; leg break slows mech ----
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	_mech.add_child(wm)
	await get_tree().process_frame
	_check(wm._hand_usable("left") == false, "broken arm disables hand weapon")
	_check(wm._hand_usable("right") == true, "intact arm still usable")
	var spd_before: float = PartPenaltySystem.total_board_speed_multiplier()
	_hs.take_damage_to_part("leg_left", 500.0, "kinetic")
	_hs.take_damage_to_part("leg_left", 500.0, "kinetic")
	await get_tree().physics_frame
	var spd_after: float = PartPenaltySystem.total_board_speed_multiplier()
	print("speed mult before=%.3f after leg break=%.3f" % [spd_before, spd_after])
	_check(spd_after <= spd_before, "leg break does not speed up mech")
	_check(_hs.is_part_destroyed("leg_left"), "leg_left destroyed")

	# ---- 8. persistence keys ----
	var pd: Dictionary = GlobalData.weapons.part_damage
	_check(float(pd.get("arm_left", -1.0)) >= 1.0, "destroyed armor persisted (arm_left=1.0)")
	_check(float(pd.get("arm_left_frame", -1.0)) >= 1.0, "destroyed frame persisted (arm_left_frame=1.0)")
	# save -> fresh mech restore cycle
	var mech2: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech2)
	await get_tree().process_frame
	var hs2: Node = mech2.get_node_or_null("HealthSystem")
	var restored: float = hs2.parts["arm_left"]["armor_hp"]
	_check(restored <= 0.001, "fresh mech restores destroyed armor as broken (hp=%.2f)" % restored)
	mech2.queue_free()
	await get_tree().process_frame

	# ---- 9. body armor break (no mech-destroy cascade) ----
	_hs.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.parts["body"]["armor_broken"] == true, "body armor breaks")
	_check(_hs.is_destroyed == false, "armor break alone does not destroy mech")

	# ---- 10. explosive AoE: primary + splash through the same pipeline ----
	# (65% primary / 35% splash split; head need not fully break from one hit)
	var pre := {}
	for s in _hs.parts.keys():
		pre[s] = float(_hs.parts[s]["armor_hp"]) + float(_hs.parts[s]["frame_hp"])
	_hs.take_damage_at_point(60.0, head_pos, "explosive")
	await get_tree().physics_frame
	var post := {}
	for s in _hs.parts.keys():
		post[s] = float(_hs.parts[s]["armor_hp"]) + float(_hs.parts[s]["frame_hp"])
	var dhead: float = pre["head"] - post["head"]
	var dmax := 0.0
	for s in pre.keys():
		dmax = maxf(dmax, float(pre[s]) - float(post[s]))
	_check(dhead > 0.0 and is_equal_approx(dhead, dmax), "explosive primary hits head hardest (%.2f)" % dhead)
	var dsplash: float = (float(pre["body"]) - float(post["body"])) + float(pre["arm_left"]) - float(post["arm_left"])
	_check(dsplash > 0.0, "explosive splashes adjacent parts (%.2f)" % dsplash)
	_check(_bus_hits > 0, "damage events reach the bus (%d)" % _bus_hits)

	GlobalData.weapons.part_damage = _pd_snap.duplicate(true)
	_mech.queue_free()
	await get_tree().process_frame
