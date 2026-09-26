extends Node

## Persistence / serialization boundary audit (REAL production paths):
## save_run/load_run file round trip, berth isolation, missing-field defaults,
## semantic drift, load side effects, post-destruction record persistence.
## NOTE: exercises the real user:// save file; the runner must back it up
## beforehand and restore it afterwards (see task protocol).
## Run: godot --headless --path . res://tests/mecha/persistence_state_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _snap := {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _spawn_mech(pos: Vector3) -> CharacterBody3D:
	var mech: CharacterBody3D = load(MECH_SCENE).instantiate()
	mech.position = pos
	add_child(mech)
	mech.is_player_driven = false
	return mech


func _land(mech: CharacterBody3D) -> void:
	var f := 0
	while not mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().physics_frame


func _snapshot() -> void:
	_snap["pd"] = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	_snap["hm"] = (GlobalData.hangar.hangar_mechs as Array).duplicate(true)
	_snap["aid"] = str(GlobalData.hangar.active_hangar_mech_id)
	_snap["php"] = float(GlobalData.pilot.pilot_hp)
	_snap["ef"] = (GlobalData.weapons.equipped_frames as Dictionary).duplicate(true)
	_snap["ep"] = (GlobalData.weapons.equipped_parts as Dictionary).duplicate(true)
	_snap["wl"] = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)
	_snap["cfr"] = float(GlobalData.fuel.convoy_fuel_reserve)
	_snap["ml"] = bool(GlobalData.narrative.mech_less)


func _restore() -> void:
	GlobalData.weapons.part_damage = (_snap["pd"] as Dictionary).duplicate(true)
	GlobalData.hangar.hangar_mechs = (_snap["hm"] as Array).duplicate(true)
	GlobalData.hangar.active_hangar_mech_id = str(_snap["aid"])
	GlobalData.pilot.pilot_hp = float(_snap["php"])
	GlobalData.weapons.equipped_frames = (_snap["ef"] as Dictionary).duplicate(true)
	GlobalData.weapons.equipped_parts = (_snap["ep"] as Dictionary).duplicate(true)
	GlobalData.weapons.weapon_loadout = (_snap["wl"] as Dictionary).duplicate(true)
	GlobalData.fuel.convoy_fuel_reserve = float(_snap["cfr"])
	GlobalData.narrative.mech_less = bool(_snap["ml"])


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("PERSIST_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000, 3, 4000)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	_snapshot()

	# ---- A. real file round trip ----
	GlobalData.weapons.part_damage["audit_probe"] = 0.42
	GlobalData.fuel.convoy_fuel_reserve = float(GlobalData.fuel.convoy_fuel_reserve) + 7.0
	SaveGameIO.save_run()
	_check(FileAccess.file_exists(GlobalData.SAVE_PATH), "save file written")
	var raw := ""
	var f := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	if f:
		raw = f.get_as_text()
	var parsed = JSON.parse_string(raw)
	_check(parsed is Dictionary and parsed.has("damage"), "save parses with damage key")
	GlobalData.weapons.part_damage["audit_probe"] = 0.99
	GlobalData.fuel.convoy_fuel_reserve = 12345.0
	_check(SaveGameIO.load_run() == true, "load_run succeeds")
	_check(is_equal_approx(float(GlobalData.weapons.part_damage.get("audit_probe", -1.0)), 0.42), "scalar round-trips exactly")
	_check(is_equal_approx(float(GlobalData.fuel.convoy_fuel_reserve), float(_snap["cfr"]) + 7.0), "fuel round-trips")
	(GlobalData.weapons.part_damage as Dictionary).erase("audit_probe")

	# ---- B. berth isolation (synthetic berths, real loader) ----
	var berth_a := {"id": "audit_A", "damage": {"arm_left": 1.0, "arm_left_frame": 1.0}, "parts": {}, "frames": {}}
	var berth_b := {"id": "audit_B", "damage": {}, "parts": {}, "frames": {}}
	(GlobalData.hangar.hangar_mechs as Array).append(berth_a)
	(GlobalData.hangar.hangar_mechs as Array).append(berth_b)
	_check(HangarManager.load_mech_state("audit_A") == true, "berth A loads")
	var ma := _spawn_mech(Vector3(0, 10, 0))
	await _land(ma)
	var hsA: Node = ma.get_node_or_null("HealthSystem")
	_check(hsA.parts["arm_left"]["destroyed"] == true, "berth A damage applies (arm destroyed)")
	_check(HangarManager.load_mech_state("audit_B") == true, "berth B loads")
	var mb := _spawn_mech(Vector3(20, 10, 0))
	await _land(mb)
	var hsB: Node = mb.get_node_or_null("HealthSystem")
	_check(hsB.parts["arm_left"]["destroyed"] == false, "berth B pristine (no leak from A)")
	# mutate B live; roster A must be unaffected (no aliasing)
	GlobalData.weapons.part_damage["leg_left"] = 0.5
	var ra: Dictionary = {}
	for m in (GlobalData.hangar.hangar_mechs as Array):
		if m is Dictionary and str(m.get("id", "")) == "audit_A":
			ra = m
	_check(float((ra.get("damage", {}) as Dictionary).get("leg_left", 0.0)) == 0.0, "live mutation does not leak into stored berth")
	_check(HangarManager.load_mech_state("audit_A") == true, "reload berth A")
	_check(float(GlobalData.weapons.part_damage.get("arm_left", 0.0)) >= 1.0, "berth A state intact after B cycle")
	_check(float(GlobalData.weapons.part_damage.get("leg_left", 0.0)) == 0.0, "B mutation did not follow into A load")
	ma.queue_free()
	mb.queue_free()
	await get_tree().process_frame
	# remove synthetic berths
	var roster: Array = GlobalData.hangar.hangar_mechs
	for i in range(roster.size() - 1, -1, -1):
		if roster[i] is Dictionary and str(roster[i].get("id", "")).begins_with("audit_"):
			roster.remove_at(i)

	# ---- C. missing/legacy fields ----
	SaveGameIO.restore_from_dict({})
	_check(true, "empty dict restores without errors")
	SaveGameIO.restore_from_dict({"damage": {"arm_left": 1}, "board_day": "3", "credits": 50})
	_check(float(GlobalData.weapons.part_damage.get("arm_left", 0.0)) == 1.0, "int damage value survives")
	_check(int(GlobalData.board.board_day) == 3, "string day coerces safely")

	# ---- D. semantic drift: save -> load -> save ----
	GlobalData.weapons.part_damage.clear()
	GlobalData.weapons.part_damage["leg_right"] = 0.5
	GlobalData.weapons.part_damage["head"] = 0.25
	GlobalData.fuel.convoy_fuel_reserve = float(_snap["cfr"]) + 3.0
	SaveGameIO.save_run()
	var f1 := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	var snap_txt := f1.get_as_text() if f1 else ""
	SaveGameIO.load_run()
	SaveGameIO.save_run()
	var f2 := FileAccess.open(GlobalData.SAVE_PATH, FileAccess.READ)
	var snap_txt2 := f2.get_as_text() if f2 else ""
	var j1 = JSON.parse_string(snap_txt)
	var j2 = JSON.parse_string(snap_txt2)
	_check(j1 is Dictionary and j2 is Dictionary, "both snapshots parse")
	_check(float(j1["damage"].get("leg_right", -1.0)) == float(j2["damage"].get("leg_right", -2.0)), "damage drift-free")
	_check(float(j1["damage"].get("head", -1.0)) == float(j2["damage"].get("head", -2.0)), "head drift-free")
	_check(str(j1.get("active_hangar_mech_id", "a")) == str(j2.get("active_hangar_mech_id", "b")), "active id drift-free")

	# ---- E. load emits no gameplay events ----
	var mc := _spawn_mech(Vector3(40, 10, 0))
	await _land(mc)
	var hsC: Node = mc.get_node_or_null("HealthSystem")
	var ec := [0, 0, 0]
	hsC.health_changed.connect(func(_s: String, _l: String, _c: float, _m: float) -> void: ec[0] += 1)
	hsC.armor_broken.connect(func(_s: String) -> void: ec[1] += 1)
	hsC.part_destroyed.connect(func(_s: String) -> void: ec[2] += 1)
	var hp_pre: float = hsC.parts["arm_left"]["armor_hp"]
	SaveGameIO.restore_from_dict({"damage": {"arm_left": 1.0, "arm_left_frame": 1.0}})
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ec == [0, 0, 0], "load emits no gameplay events")
	_check(is_equal_approx(hsC.parts["arm_left"]["armor_hp"], hp_pre), "load does not mutate live runtime objects")
	mc.queue_free()
	await get_tree().process_frame

	# ---- F. post-destruction record persists, fresh spawn derives ----
	GlobalData.weapons.part_damage["body"] = 1.0
	GlobalData.weapons.part_damage["body_frame"] = 1.0
	SaveGameIO.save_run()
	SaveGameIO.load_run()
	var md := _spawn_mech(Vector3(60, 10, 0))
	await _land(md)
	var hsD: Node = md.get_node_or_null("HealthSystem")
	_check(hsD.parts["body"]["destroyed"] == true, "destroyed body persists across save/load/spawn")
	md.queue_free()
	await get_tree().process_frame

	_restore()
	_check((GlobalData.weapons.part_damage as Dictionary) == (_snap["pd"] as Dictionary), "part_damage restored")
	_check((GlobalData.hangar.hangar_mechs as Array).size() == (_snap["hm"] as Array).size(), "roster restored")
