extends Node

## Headless verification for the merged enemy_health.gd (SIMPLE/FULL/TANK).
## Run: godot --headless --path . res://tests/enemy_health_verify.tscn

var _fails: int = 0
var _checks: int = 0

# Signal flags for the TANK layout check. Member vars are used because GDScript
# lambdas capture locals by value, so local flags would never update.
var _movement_lost: bool = false
var _turret_down: bool = false


func _ready() -> void:
	await _verify_layouts()
	await _verify_tank_scene()
	await _verify_full_scenes()
	print("ENEMY_HEALTH_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	# Let queued_free nodes flush before quitting so no instances leak.
	await get_tree().process_frame
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _make_health(layout) -> Node:
	var script = load("res://scripts/mecha/enemy_health.gd")
	var hs = script.new()
	hs.name = "HealthSystem"
	hs.layout = layout
	add_child(hs)
	# _ready fires synchronously on add_child (parent is in-tree); wait a frame
	# so _init_parts / _find_meshes have definitely run.
	await get_tree().process_frame
	return hs


func _verify_layouts() -> void:
	# SIMPLE: single body part, 100/100 HP
	var simple = await _make_health(0)
	_check(simple.parts.size() == 1, "SIMPLE has 1 part")
	_check(simple.parts.has("body"), "SIMPLE has body")
	_check(simple.parts["body"]["armor_hp"] == 100.0, "SIMPLE body armor 100")
	_check(simple.parts["body"]["frame_hp"] == 100.0, "SIMPLE body frame 100")
	_check(simple.is_player == false, "SIMPLE is_player false")

	# FULL: six mech slots
	var full = await _make_health(1)
	_check(full.parts.size() == 6, "FULL has 6 parts")
	_check(full.parts.has("head") and full.parts.has("body"), "FULL has head+body")
	_check(full.parts.has("arm_left") and full.parts.has("arm_right"), "FULL has arms")
	_check(full.parts.has("leg_left") and full.parts.has("leg_right"), "FULL has legs")
	_check(full.parts["body"]["armor_hp"] == 80.0, "FULL body armor 80")
	_check(full.parts["body"]["frame_hp"] == 60.0, "FULL body frame 60")

	# TANK: hull/turret/treads
	var tank = await _make_health(2)
	_check(tank.parts.size() == 3, "TANK has 3 parts")
	_check(tank.parts.has("hull") and tank.parts.has("turret") and tank.parts.has("treads"), "TANK has hull/turret/treads")
	_check(tank.parts["hull"]["armor_hp"] == 80.0, "TANK hull armor 80")
	_check(tank.parts["hull"]["armor_class"] == 1.2, "TANK hull armor_class 1.2")
	_check(tank.has_signal("mobility_lost") and tank.has_signal("turret_disabled"), "TANK signals exist")

	# take_heal on SIMPLE heals body (heal clamps at max)
	simple.parts["body"]["frame_hp"] = 50.0
	simple.take_heal(10.0)
	_check(simple.parts["body"]["frame_hp"] == 60.0, "SIMPLE take_heal heals body")
	simple.take_heal(999.0)
	_check(simple.parts["body"]["frame_hp"] == 100.0, "SIMPLE take_heal clamps at max")

	# take_heal on FULL heals the most damaged alive part
	full.parts["arm_left"]["frame_hp"] = 5.0
	full.take_heal(10.0)
	_check(full.parts["arm_left"]["frame_hp"] == 15.0, "FULL take_heal heals worst part")

	# TANK never heals (legacy behavior: support units skip tanks)
	tank.parts["hull"]["frame_hp"] = 20.0
	tank.take_heal(10.0)
	_check(tank.parts["hull"]["frame_hp"] == 20.0, "TANK take_heal is a no-op")

	# TANK frame-destroy emits mobility_lost / turret_disabled signals
	var parent = CharacterBody3D.new()
	parent.name = "Parent"
	add_child(parent)
	tank.get_parent().remove_child(tank)
	parent.add_child(tank)
	await get_tree().process_frame
	_movement_lost = false
	_turret_down = false
	tank.mobility_lost.connect(_on_tank_mobility_lost)
	tank.turret_disabled.connect(_on_tank_turret_down)
	tank.parts["treads"]["frame_hp"] = 0.0
	tank._on_frame_destroyed("treads")
	_check(_movement_lost, "TANK treads destroy -> mobility_lost")
	tank.parts["turret"]["frame_hp"] = 0.0
	tank._on_frame_destroyed("turret")
	_check(_turret_down, "TANK turret destroy -> turret_disabled")


func _on_tank_mobility_lost() -> void:
	_movement_lost = true


func _on_tank_turret_down() -> void:
	_turret_down = true


func _verify_tank_scene() -> void:
	var scene = load("res://scenes/mecha/enemy_tank.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var hs = inst.get_node_or_null("HealthSystem")
	_check(hs != null, "tank scene has HealthSystem")
	if hs:
		_check(hs.parts.has("hull") and hs.parts.has("turret") and hs.parts.has("treads"), "tank scene parts = TANK layout")
	inst.queue_free()


func _verify_full_scenes() -> void:
	for scene_path in [
		"res://scenes/mecha/enemy_dummy_full.tscn",
		"res://scenes/mecha/enemy_heavy.tscn",
		"res://scenes/mecha/enemy_ranged.tscn",
		"res://scenes/mecha/enemy_support.tscn",
		"res://scenes/mecha/enemy_boss.tscn",
		"res://scenes/mecha/ally_dummy.tscn",
	]:
		var scene = load(scene_path)
		var inst = scene.instantiate()
		add_child(inst)
		await get_tree().process_frame
		var hs = inst.get_node_or_null("HealthSystem")
		_check(hs != null, "%s has HealthSystem" % scene_path)
		if hs:
			_check(hs.parts.size() == 6, "%s parts = FULL (6)" % scene_path)
		inst.queue_free()
