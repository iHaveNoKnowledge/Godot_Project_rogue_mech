extends Node

## Global event/signal topology audit: ownership, exactly-once, duplicate
## connections, stale listeners, async ownership, ordering, reentrancy.
## Uses REAL production paths on live mecha_base instances (no mocks).
## Run: godot --headless --path . res://tests/mecha/event_topology_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0
var _seen_hp := -1.0
var _seen_broken := false
var _seen_destroyed := false
var _bus_hits := 0
var _reenter_guard := false
var _reenter_count := 0


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
	print("EVENT_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


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


func _on_hc(slot: String, _layer: String, _c: float, _m: float, hs: Node) -> void:
	if slot == "arm_left":
		_seen_hp = float(hs.parts["arm_left"]["armor_hp"])


func _on_ab(slot: String, hs: Node) -> void:
	if slot == "arm_left":
		_seen_broken = bool(hs.parts["arm_left"]["armor_broken"])


func _on_pd(slot: String, hs: Node) -> void:
	if slot == "arm_left":
		_seen_destroyed = bool(hs.parts["arm_left"]["destroyed"])


func _on_bus(_slot: String, _amount: float, _type: String) -> void:
	_bus_hits += 1


func _on_reenter(_s: String, _l: String, _c: float, _m: float, hs: Node) -> void:
	_reenter_count += 1
	if _reenter_guard:
		return
	_reenter_guard = true
	hs.take_damage_to_part("arm_right", 5.0, "kinetic")


func _nodups(sig: Signal, label: String) -> void:
	var seen := {}
	var dup := false
	for c in sig.get_connections():
		var k := str(c["callable"])
		if seen.has(k):
			dup = true
		seen[k] = true
	_check(not dup, "no duplicate connections: " + label)


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
	var pd_snap: Dictionary = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	var hg_snap: Array = (GlobalData.hangar.hangar_mechs as Array).duplicate(true)
	var act_snap: String = str(GlobalData.hangar.active_hangar_mech_id)
	var php_snap: float = float(GlobalData.pilot.pilot_hp)
	var ml_snap: bool = bool(GlobalData.narrative.mech_less)
	var wp_snap = GlobalData.fuel.wreckage_tile_pos
	var wf_snap: float = float(GlobalData.fuel.wreckage_fuel_remaining)

	var m1 := _spawn_mech(Vector3(0, 10, 0))
	await _land(m1)
	var hs1: Node = m1.get_node_or_null("HealthSystem")
	_check(hs1 != null, "health system present")

	# ---- ordering: subscribers observe post-mutation state ----
	hs1.health_changed.connect(_on_hc.bind(hs1))
	hs1.armor_broken.connect(_on_ab.bind(hs1))
	hs1.part_destroyed.connect(_on_pd.bind(hs1))
	EventBus.damage_received.connect(_on_bus)
	_nodups(hs1.health_changed, "health_changed")
	_nodups(hs1.armor_broken, "armor_broken")
	_nodups(hs1.part_destroyed, "part_destroyed")
	hs1.take_damage_to_part("arm_left", 5.0, "kinetic")
	await get_tree().physics_frame
	_check(is_equal_approx(_seen_hp, float(hs1.parts["arm_left"]["armor_hp"])), "health callback sees mutated HP")
	_check(_bus_hits == 1, "one bus event per application")
	hs1.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_seen_broken == true, "break callback sees broken flag")
	hs1.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_seen_destroyed == true, "destroy callback sees destroyed flag")
	_check(_bus_hits == 3, "three applications -> three bus events")

	# ---- reentrancy: damage inside a damage callback terminates ----
	hs1.health_changed.connect(_on_reenter.bind(hs1))
	_reenter_guard = false
	_reenter_count = 0
	hs1.take_damage_to_part("arm_right", 5.0, "kinetic")
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_reenter_count == 2, "reentrant damage terminates (count=%d)" % _reenter_count)

	# ---- multi-cycle: per-cycle exact counts, no accumulation ----
	for cycle in range(1, 4):
		GlobalData.weapons.part_damage.clear()
		print("cyc%d dict=%s" % [cycle, str(GlobalData.weapons.part_damage)])
		var ma := _spawn_mech(Vector3(-30 * cycle, 10, 0))
		await _land(ma)
		var hsa: Node = ma.get_node_or_null("HealthSystem")
		var ab := [0]
		var pd := [0]
		hsa.armor_broken.connect(func(_s: String) -> void: ab[0] += 1)
		hsa.part_destroyed.connect(func(_s: String) -> void: pd[0] += 1)
		hsa.take_damage_to_part("arm_left", 500.0, "kinetic")
		await get_tree().physics_frame
		hsa.take_damage_to_part("arm_left", 500.0, "kinetic")
		await get_tree().physics_frame
		_check(ab[0] == 1 and pd[0] == 1, "cycle %d: exactly one break + one destroy" % cycle)
		ma.queue_free()
		await get_tree().process_frame
	# 3 prior applications + 2 reentrant + 3 cycles x 2 = 11 bus events exactly
	_check(_bus_hits == 11, "bus event total exact across cycles (%d)" % _bus_hits)

	# ---- stale listener: freed mech cannot observe new mech ----
	GlobalData.weapons.part_damage.clear()
	var mA := _spawn_mech(Vector3(50, 10, 0))
	await _land(mA)
	var hsA: Node = mA.get_node_or_null("HealthSystem")
	var cntA := [0]
	hsA.health_changed.connect(func(_s: String, _l: String, _c: float, _m: float) -> void: cntA[0] += 1)
	hsA.take_damage_to_part("arm_left", 5.0, "kinetic")
	await get_tree().physics_frame
	mA.queue_free()
	await get_tree().process_frame
	var mB := _spawn_mech(Vector3(60, 10, 0))
	await _land(mB)
	var hsB: Node = mB.get_node_or_null("HealthSystem")
	var cntB := [0]
	hsB.health_changed.connect(func(_s: String, _l: String, _c: float, _m: float) -> void: cntB[0] += 1)
	hsB.take_damage_to_part("arm_left", 5.0, "kinetic")
	await get_tree().physics_frame
	_check(cntA[0] == 1 and cntB[0] == 1, "freed mech silent, new mech exact (A=%d B=%d)" % [cntA[0], cntB[0]])
	_check(_bus_hits == 13, "bus total exact after stale swap (%d)" % _bus_hits)
	mB.queue_free()
	await get_tree().process_frame

	# ---- async ownership: destroy cascade beside a live mech ----
	GlobalData.weapons.part_damage.clear()
	var mC := _spawn_mech(Vector3(80, 10, 0))
	await _land(mC)
	var hsC: Node = mC.get_node_or_null("HealthSystem")
	var mD := _spawn_mech(Vector3(90, 10, 0))
	await _land(mD)
	var hsD: Node = mD.get_node_or_null("HealthSystem")
	var d_arm0: float = hsD.parts["arm_left"]["armor_hp"]
	hsC.take_damage_to_part("body", 500.0, "kinetic")
	await get_tree().physics_frame
	hsC.take_damage_to_part("body", 500.0, "kinetic")
	var t := 0.0
	while t < 6.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	_check(hsD.parts["arm_left"]["armor_hp"] == d_arm0, "destroy tail never touches live mech")
	_check(hsD.is_destroyed == false, "live mech survives neighbor cascade")
	_check(_bus_hits == 15, "bus total exact after cascade (%d)" % _bus_hits)
	mC.queue_free()
	mD.queue_free()
	await get_tree().process_frame

	GlobalData.weapons.part_damage = pd_snap.duplicate(true)
	GlobalData.hangar.hangar_mechs = hg_snap.duplicate(true)
	GlobalData.hangar.active_hangar_mech_id = act_snap
	GlobalData.pilot.pilot_hp = php_snap
	GlobalData.narrative.mech_less = ml_snap
	GlobalData.fuel.wreckage_tile_pos = wp_snap
	GlobalData.fuel.wreckage_fuel_remaining = wf_snap
	await get_tree().process_frame
