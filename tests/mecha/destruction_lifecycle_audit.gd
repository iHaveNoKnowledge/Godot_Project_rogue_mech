extends Node

## End-to-end destruction lifecycle audit (REAL production chain, async kept):
##   body frame destroy -> is_destroyed + mecha_destroyed (once)
##   -> core breach (1.8 s) -> pilot eject (once) -> combat_ended(false, once)
##   -> hangar/wreckage/fuel GlobalData tail -> fresh-mech derivation.
## Run: godot --headless --path . res://tests/mecha/destruction_lifecycle_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _c_mecha_destroyed := 0
var _c_combat_ended := 0
var _c_combat_payload: Array = []
var _c_eject := 0
var _c_pilot_spawned := 0
var _mech: CharacterBody3D
var _hs: Node
var _snap := {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _on_md() -> void:
	_c_mecha_destroyed += 1


func _on_ce(victory: bool) -> void:
	_c_combat_ended += 1
	_c_combat_payload.append(victory)


func _on_eject() -> void:
	_c_eject += 1


func _on_pilot(_p) -> void:
	_c_pilot_spawned += 1


func _pilots() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("pilot"):
		if is_instance_valid(m):
			n += 1
	return n


func _snap_global() -> void:
	_snap["part_damage"] = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	_snap["hangar_mechs"] = (GlobalData.hangar.hangar_mechs as Array).duplicate(true)
	_snap["active_id"] = str(GlobalData.hangar.active_hangar_mech_id)
	_snap["pilot_hp"] = float(GlobalData.pilot.pilot_hp)
	_snap["mech_less"] = bool(GlobalData.narrative.mech_less)
	_snap["wreck_pos"] = GlobalData.fuel.wreckage_tile_pos
	_snap["wreck_fuel"] = float(GlobalData.fuel.wreckage_fuel_remaining)
	_snap["siphoned"] = float(GlobalData.fuel.siphoned_fuel)


func _restore_global() -> void:
	GlobalData.weapons.part_damage = (_snap["part_damage"] as Dictionary).duplicate(true)
	GlobalData.hangar.hangar_mechs = (_snap["hangar_mechs"] as Array).duplicate(true)
	GlobalData.hangar.active_hangar_mech_id = str(_snap["active_id"])
	GlobalData.pilot.pilot_hp = float(_snap["pilot_hp"])
	GlobalData.narrative.mech_less = bool(_snap["mech_less"])
	GlobalData.fuel.wreckage_tile_pos = _snap["wreck_pos"]
	GlobalData.fuel.wreckage_fuel_remaining = float(_snap["wreck_fuel"])
	GlobalData.fuel.siphoned_fuel = float(_snap["siphoned"])


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("DESTRUCTION_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


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
	_check(_hs != null, "health system present")
	_hs.mecha_destroyed.connect(_on_md)
	EventBus.combat_ended.connect(_on_ce)
	EventBus.eject_initiated.connect(_on_eject)
	EventBus.pilot_spawned.connect(_on_pilot)
	_snap_global()
	var hp0: float = float(GlobalData.pilot.pilot_hp)
	var pilots0 := _pilots()

	# ---- frame destroy -> mecha destroy (once) ----
	_hs.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	_hs.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.parts["body"]["destroyed"] == true, "body frame destroyed")
	_check(_hs.is_destroyed == true, "mecha destroyed flag set")
	_check(_c_mecha_destroyed == 1, "mecha_destroyed emitted exactly once")
	# repeated lethal hits during/after the window: no duplicates
	_hs.take_damage_to_part("body", 500.0, "kinetic")
	_hs.take_damage_to_part("head", 500.0, "kinetic")
	_hs.take_damage_to_part("head", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_c_mecha_destroyed == 1, "no duplicate destruction from repeated lethal hits")
	_check(_mech.is_physics_processing() == false, "destroyed mech physics halted")

	# ---- async tail: breach (1.8 s) + eject + combat end (~2 s) ----
	var t := 0.0
	while t < 7.0 and _c_combat_ended == 0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(_c_combat_ended == 1, "combat_ended emitted exactly once")
	_check(_c_combat_payload == [false], "defeat payload carried")
	await get_tree().create_timer(1.0).timeout
	_check(_c_combat_ended == 1, "no duplicate combat_ended after settle")
	_check(_c_eject >= 1, "ejection initiated")
	_check(_pilots() == pilots0 + 1, "exactly one pilot ejected (had %d, now %d)" % [pilots0, _pilots()])
	var pmm: Node = _mech.get_node_or_null("PartMeshManager")
	_check(pmm != null and bool(pmm.get("is_cockpit_open")) == true, "hatch opened for ejection")
	var hp1: float = float(GlobalData.pilot.pilot_hp)
	_check(hp1 == maxf(hp0 - 35.0, 0.0), "pilot took eject damage (%.1f->%.1f)" % [hp0, hp1])

	# ---- GlobalData tail ----
	_check(GlobalData.narrative.mech_less == true or GlobalData.hangar.hangar_mechs.size() > 0, "hangar state consistent after removal")
	print("hangar mechs=%d active='%s' wreck=%s" % [GlobalData.hangar.hangar_mechs.size(), str(GlobalData.hangar.active_hangar_mech_id), str(GlobalData.fuel.wreckage_tile_pos)])
	_check(is_instance_valid(_mech), "wreck node persists (no premature free)")

	# ---- post-destruction: further damage ignored, no new signals ----
	var ce0 := _c_combat_ended
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_c_combat_ended == ce0, "no new combat end from post-destruction hits")

	# ---- fresh mech derivation from persisted damage ----
	var mech2: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech2)
	await get_tree().process_frame
	var hs2: Node = mech2.get_node_or_null("HealthSystem")
	_check(hs2.parts["body"]["destroyed"] == true, "fresh spawn derives destroyed body from dict")
	mech2.queue_free()
	GlobalData.weapons.part_damage.clear()
	var mech3: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech3)
	await get_tree().process_frame
	var hs3: Node = mech3.get_node_or_null("HealthSystem")
	_check(hs3.is_destroyed == false, "cleared damage -> fresh mech intact (no leak)")
	mech3.queue_free()

	_restore_global()
	_check((GlobalData.weapons.part_damage as Dictionary).is_empty() == (_snap["part_damage"] as Dictionary).is_empty(), "part_damage restored")
	_check(GlobalData.hangar.hangar_mechs.size() == (_snap["hangar_mechs"] as Array).size(), "hangar roster restored")
	_check(is_equal_approx(float(GlobalData.pilot.pilot_hp), float(_snap["pilot_hp"])), "pilot HP restored")
	_mech.queue_free()
	await get_tree().process_frame
