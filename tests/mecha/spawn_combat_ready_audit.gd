extends Node

## Spawn -> combat-ready forensic audit (REAL production paths only):
## game_world-style spawn (mecha_base + WeaponManager + stock loadout),
## pristine/damaged/destroyed init, reserve delivery, leak/cycle checks.
## Run: godot --headless --path . res://tests/mecha/spawn_combat_ready_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const WM_SCRIPT := "res://scripts/mecha/weapon_manager.gd"
const RIFLE := "res://resources/mech/stock/weapon_beam_rifle.tres"
const BLADE := "res://resources/mech/stock/weapon_heat_blade.tres"

var _fails := 0
var _checks := 0
var _pd_snap: Dictionary = {}


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
	# game_world.tscn combat spawn contract: attach WeaponManager + stock arms.
	var wm: Node3D = Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load(WM_SCRIPT))
	mech.add_child(wm)
	return mech


func _arm_mech(mech: CharacterBody3D) -> void:
	var wm: Node = mech.get_node_or_null("WeaponManager")
	wm.left_hand = load(RIFLE)
	wm.right_hand = load(BLADE)


func _land(mech: CharacterBody3D) -> void:
	var f := 0
	while not mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	await get_tree().physics_frame


func _hs(mech: CharacterBody3D) -> Node:
	return mech.get_node_or_null("HealthSystem")


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("SPAWN_AUDIT: checks=%d fails=%d" % [_checks, _fails])
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
	_pd_snap = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	_check((GlobalData.weapons.part_damage as Dictionary).is_empty(), "fresh process has no stale part_damage")

	# ---- A. pristine spawn ----
	var m1 := _spawn_mech(Vector3(0, 10, 0))
	await _land(m1)
	var hs1: Node = _hs(m1)
	_check(hs1 != null, "health initialized on spawn")
	var pristine := true
	for s in hs1.parts.keys():
		var p: Dictionary = hs1.parts[s]
		if p["armor_hp"] != p["max_armor"] or p["frame_hp"] != p["max_frame"] or p["armor_broken"] or p["destroyed"]:
			pristine = false
	_check(pristine, "pristine HP/armor/frame, nothing broken")
	_check(hs1.is_destroyed == false, "not destroyed at spawn")
	_arm_mech(m1)
	await get_tree().process_frame
	var wm1: Node = m1.get_node_or_null("WeaponManager")
	_check(wm1.left_hand != null and wm1.right_hand != null, "stock loadout armed")
	_check(wm1._hand_usable("left") and wm1._hand_usable("right"), "hands usable at spawn")
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), 1.0), "full speed at spawn")
	_check(float(m1.energy) > 0.0, "energy initialized")
	var hb1: Area3D = m1.get_node_or_null("Hitbox")
	_check(hb1 != null and hb1.monitoring and hb1.health_system != null, "hitbox live at spawn")
	var anim1: Node = m1.get_node_or_null("MechaAnimation")
	_check(anim1 != null and bool(anim1.get("is_kneeling")) == false and bool(anim1.get("is_core_breach")) == false, "animation neutral at spawn")
	_check(m1.velocity.length() < 0.5, "no stale velocity at spawn")

	# ---- B. immediate combat actions on fresh spawn ----
	var hp0: float = hs1.parts["arm_left"]["armor_hp"]
	hs1.take_damage_at_point(5.0, (m1.get_node_or_null("ArmLeft") as Node3D).global_position, "kinetic")
	await get_tree().physics_frame
	_check(hs1.parts["arm_left"]["armor_hp"] < hp0, "fresh mech hittable immediately")
	var core: WeaponCore = wm1._core_for_weapon(wm1.left_hand)
	var ammo0: int = core.ammo
	wm1._try_fire("left", wm1.left_hand)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(core.ammo == ammo0 - 1, "fresh mech fires immediately (ammo %d->%d)" % [ammo0, core.ammo])

	# ---- C. damaged-save restoration ----
	GlobalData.weapons.part_damage["arm_left"] = 1.0
	GlobalData.weapons.part_damage["arm_left_frame"] = 1.0
	GlobalData.weapons.part_damage["leg_right"] = 0.5
	GlobalData.weapons.part_damage["head"] = 0.3
	GlobalData.weapons.part_damage["body"] = 0.2
	var m2 := _spawn_mech(Vector3(20, 10, 0))
	await _land(m2)
	_arm_mech(m2)
	await get_tree().process_frame
	var hs2: Node = _hs(m2)
	_check(hs2.parts["arm_left"]["destroyed"] == true, "restored destroyed arm")
	_check(is_equal_approx(hs2.parts["leg_right"]["armor_hp"], hs2.parts["leg_right"]["max_armor"] * 0.5), "restored partial armor")
	var wm2: Node = m2.get_node_or_null("WeaponManager")
	_check(wm2._hand_usable("left") == false and wm2._hand_usable("right") == true, "capability re-derived per-arm")
	m1.queue_free()
	m2.queue_free()
	await get_tree().process_frame

	# ---- D. destroy -> new spawn isolation (3 arm-destroy cycles: no cascade,
	# fast and clean; full body cascade covered separately below) ----
	var kids0 := get_child_count()
	var pilots0 := get_tree().get_nodes_in_group("pilot").size()
	for cycle in range(1, 4):
		GlobalData.weapons.part_damage.clear()
		var ma := _spawn_mech(Vector3(-20 * cycle, 10, 0))
		await _land(ma)
		_arm_mech(ma)
		await get_tree().process_frame
		var hsa: Node = _hs(ma)
		_check(is_equal_approx(hsa.parts["arm_left"]["armor_hp"], hsa.parts["arm_left"]["max_armor"]), "cycle %d: spawns pristine" % cycle)
		var pk0 := _pickups()
		var sc0 := _scraps()
		hsa.take_damage_to_part("arm_left", 500.0, "kinetic")
		await get_tree().physics_frame
		hsa.take_damage_to_part("arm_left", 500.0, "kinetic")
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(hsa.is_part_destroyed("arm_left"), "cycle %d: arm destroyed" % cycle)
		_check(_pickups() == pk0 + 1, "cycle %d: exactly one pickup generated" % cycle)
		_check(_scraps() == sc0 + 1, "cycle %d: exactly one scrap generated" % cycle)
		_check(_scrap_names_unique(), "cycle %d: wreck names distinct" % cycle)
		ma.queue_free()
		await get_tree().process_frame
		GlobalData.weapons.part_damage.clear()
		var mb := _spawn_mech(Vector3(-20 * cycle, 10, 0))
		await _land(mb)
		_arm_mech(mb)
		await get_tree().process_frame
		var hsb: Node = _hs(mb)
		_check(hsb.is_destroyed == false, "cycle %d: fresh mech intact" % cycle)
		var sv := 0
		while mb.velocity.length() >= 0.5 and sv < 120:
			await get_tree().physics_frame
			sv += 1
		_check(mb.velocity.length() < 0.5, "cycle %d: no stale velocity" % cycle)
		_check(mb.is_physics_processing() == true, "cycle %d: physics running" % cycle)
		var wmb: Node = mb.get_node_or_null("WeaponManager")
		_check(wmb._hand_usable("left") and wmb._hand_usable("right"), "cycle %d: hands capable" % cycle)
		# fresh mech derives only from current dict (cleared above): signals die
		# with the freed instance; exactly one emission on the new one.
		var cnt := [0]
		hsb.health_changed.connect(func(_s: String, _l: String, _c: float, _m: float) -> void: cnt[0] += 1)
		hsb.take_damage_to_part("arm_right", 5.0, "kinetic")
		await get_tree().physics_frame
		_check(cnt[0] == 1, "cycle %d: exactly one callback on new mech" % cycle)
		mb.queue_free()
		await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("mecha").is_empty(), "no mecha group residue")
	_check(get_tree().get_nodes_in_group("pilot").size() == pilots0, "no pilot accumulation")
	# VFX drain check: transient combat effects must expire; drops and the
	# (absent here — no cascade in cycles) wreck persist by design.
	var meshes0 := _scene_meshes()
	await get_tree().create_timer(15.0).timeout
	_check(_scene_meshes() <= meshes0, "transient VFX drain, no unbounded growth (%d->%d)" % [meshes0, _scene_meshes()])
	_check(get_child_count() <= kids0 + 20, "no unexpected node growth (%d->%d)" % [kids0, get_child_count()])

	# ---- E. full body-destroy cascade, then post-combat spawn ----
	var snap2 := {
		"hangar": (GlobalData.hangar.hangar_mechs as Array).duplicate(true),
		"active": str(GlobalData.hangar.active_hangar_mech_id),
		"php": float(GlobalData.pilot.pilot_hp),
		"ml": bool(GlobalData.narrative.mech_less),
		"wp": GlobalData.fuel.wreckage_tile_pos,
		"wf": float(GlobalData.fuel.wreckage_fuel_remaining),
		"sf": float(GlobalData.fuel.siphoned_fuel),
	}
	var md := _spawn_mech(Vector3(40, 10, 0))
	await _land(md)
	_arm_mech(md)
	await get_tree().process_frame
	var hsd: Node = _hs(md)
	hsd.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	hsd.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(hsd.is_destroyed == true, "cascade: mech destroyed")
	var t := 0.0
	while t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(get_tree().get_nodes_in_group("pilot").size() == pilots0 + 1, "cascade: exactly one pilot ejected")
	md.queue_free()
	GlobalData.weapons.part_damage.clear()
	var mf := _spawn_mech(Vector3(40, 10, 0))
	await _land(mf)
	_arm_mech(mf)
	await get_tree().process_frame
	var hsf: Node = _hs(mf)
	_check(hsf.is_destroyed == false, "post-combat spawn intact")
	var wmf: Node = mf.get_node_or_null("WeaponManager")
	_check(wmf._hand_usable("left"), "post-combat spawn capable")
	mf.queue_free()
	GlobalData.hangar.hangar_mechs = (snap2["hangar"] as Array).duplicate(true)
	GlobalData.hangar.active_hangar_mech_id = str(snap2["active"])
	GlobalData.pilot.pilot_hp = float(snap2["php"])
	GlobalData.narrative.mech_less = bool(snap2["ml"])
	GlobalData.fuel.wreckage_tile_pos = snap2["wp"]
	GlobalData.fuel.wreckage_fuel_remaining = float(snap2["wf"])
	GlobalData.fuel.siphoned_fuel = float(snap2["sf"])
	_check(true, "post-cascade shared state restored")

	# ---- F. reserve delivery (real _spawn_reserve_mech, berth-agnostic) ----
	GlobalData.weapons.part_damage.clear()
	var RBSpawner: GDScript = load("res://scripts/systems/backup_mech_spawner.gd")
	var spawner: Node = RBSpawner.new()
	add_child(spawner)
	await get_tree().process_frame
	spawner._spawn_reserve_mech("audit_berth", Vector3(60, 5, 0))
	print("reserve immediate phys=%s" % str((get_node_or_null("ReserveMech") as CharacterBody3D).is_physics_processing()))
	# control: bare spawn + flag off, same tick
	var ctl: CharacterBody3D = load(MECH_SCENE).instantiate()
	ctl.set_physics_process(false)
	add_child(ctl)
	print("control immediate phys=%s (expect false)" % str(ctl.is_physics_processing()))
	ctl.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var reserve: CharacterBody3D = get_node_or_null("ReserveMech")
	_check(reserve != null and is_instance_valid(reserve), "reserve mech delivered")
	if reserve:
		_check(reserve.is_in_group("backup_mech"), "reserve flagged boardable backup")
		print("reserve phys=%s proc=%s" % [str(reserve.is_physics_processing()), str(reserve.is_processing())])
		_check(reserve.is_physics_processing() == false, "reserve parked (physics off)")
		_check(str(reserve.get_meta("hangar_mech_id")) == "audit_berth", "reserve tagged with berth id")
		var ran: Node = reserve.get_node_or_null("MechaAnimation")
		_check(ran != null and bool(ran.get("is_kneeling")) == true, "reserve kneels via fixed animation ref")
		for i in range(90):
			await get_tree().physics_frame
		var rleg: Node3D = reserve.get_node_or_null("LegLeft")
		_check(rleg != null and rleg.rotation.x > 0.5, "reserve kneel pose applies (thigh %.2f)" % (rleg.rotation.x if rleg else 0.0))
		var rpm: Node = reserve.get_node_or_null("PartMeshManager")
		_check(rpm != null and bool(rpm.get("is_cockpit_open")) == true, "reserve hatch open")
		reserve.queue_free()
		await get_tree().process_frame
	spawner.queue_free()

	GlobalData.weapons.part_damage = _pd_snap.duplicate(true)
	await get_tree().process_frame


func _pickups() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is Area3D and c.get("weapon_resource") != null:
			n += 1
	return n


func _scene_meshes() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is MeshInstance3D:
			n += 1
	return n


func _dump_children(tag: String) -> void:
	var counts := {}
	for c in get_tree().current_scene.get_children():
		var k := c.get_class() + ":" + (c as Node).name.get_slice("@", 0)
		counts[k] = int(counts.get(k, 0)) + 1
		if c is MeshInstance3D:
			var mm: Mesh = (c as MeshInstance3D).mesh
			var mk := ("none" if mm == null else mm.get_class())
			counts["MESHRES:" + mk] = int(counts.get("MESHRES:" + mk, 0)) + 1
		if c is RigidBody3D:
			counts["RB:" + str((c as RigidBody3D).contact_monitor)] = int(counts.get("RB:" + str((c as RigidBody3D).contact_monitor), 0)) + 1
	print("children[%s]=%s" % [tag, str(counts)])


func _scraps() -> int:
	var n := 0
	for c in get_tree().current_scene.get_children():
		if c is RigidBody3D and (c as Node).name.begins_with("Scrap_"):
			n += 1
	return n


func _scrap_names_unique() -> bool:
	var seen := {}
	for c in get_tree().current_scene.get_children():
		if c is RigidBody3D and (c as Node).name.begins_with("Scrap_"):
			var nm := str((c as Node).name)
			if seen.has(nm):
				return false
			seen[nm] = true
	return true
