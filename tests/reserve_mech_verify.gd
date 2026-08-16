extends Node

## Verifies the reserve-mech call system:
##   1. BackupMechSpawner.call_reserve_mech() picks a clear drop point at the
##      arena edge (outside the combat core, clear of solid obstacles), spawns
##      a beacon, announces "RESERVE MECH INBOUND", and delivers after the 30s
##      delay as a boardable parked mech.
##   2. CombatTabMenu free-mech filtering: only mechs that are not active and
##      not already fielded in this battle are offered; empty roster -> empty
##      free-mech list.
## Run: godot --headless --path . res://tests/reserve_mech_verify.tscn

const BackupMechSpawnerScript := preload("res://scripts/systems/backup_mech_spawner.gd")
const CombatTabMenuScript := preload("res://scripts/ui/combat_tab_menu.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RESERVE OK: " + name)
	else:
		_fails += 1
		printerr("RESERVE FAIL: " + name)


func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame
	await _verify_spawner()
	await _verify_tab_menu_filtering()
	print("RESERVE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _verify_spawner() -> void:
	var spawner := BackupMechSpawnerScript.new()
	spawner.name = "BackupMechSpawner"
	add_child(spawner)
	await get_tree().process_frame

	# Empty / unknown mech id is rejected.
	_check(not spawner.call_reserve_mech(""), "empty mech id is rejected")
	_check(not spawner.call_reserve_mech("ghost_id"), "unknown mech id is rejected")

	# A known roster id is accepted and starts the delivery clock.
	var mech := GlobalData.build_hangar_mech("Reserve Test")
	var mech_id := str(mech.get("id", ""))
	_check(spawner.call_reserve_mech(mech_id), "call reserve mech accepts a roster id")

	# Beacon exists at the drop point.
	var markers := get_tree().get_nodes_in_group("")  # group-less; scan children
	var beacon: Node3D = null
	for child in spawner.get_parent().get_children():
		if child.name == "ReserveDropMarker":
			beacon = child
			break
	_check(beacon != null, "drop beacon spawns at the landing zone")
	if beacon:
		_check(beacon.position.y >= 0.0, "beacon sits above the ground")
		# Drop point sits outside the combat core but inside the 240m arena.
		var dist := Vector2(beacon.position.x, beacon.position.z).length()
		_check(dist > 60.0 and dist < 120.0, "drop point is at the arena edge ring (%.0fm)" % dist)

	# Same mech cannot be called twice while pending.
	_check(not spawner.call_reserve_mech(mech_id), "duplicate pending call is rejected")

	# Fast-forward the delivery timer and confirm the mech lands boardable.
	# Delivery runs in _physics_process, so wait on physics frames (not just
	# process frames) to let the timer tick down deterministically.
	spawner._pending[mech_id]["timer"] = 0.0
	for i in range(8):
		await get_tree().physics_frame
	await get_tree().process_frame
	var delivered: Node = null
	for child in spawner.get_parent().get_children():
		if child.name == "ReserveMech":
			delivered = child
			break
	_check(delivered != null, "reserve mech is delivered after the delay")
	if delivered:
		_check(delivered.is_in_group("backup_mech"), "delivered mech is boardable (backup_mech group)")
		_check(str(delivered.get_meta("hangar_mech_id", "")) == mech_id, "delivered mech carries the called berth id")
		var anim = delivered.get_node_or_null("AnimationSystem")
		_check(anim != null, "delivered mech keeps its animation node")
	_check(beacon == null or not is_instance_valid(beacon), "beacon is cleared after delivery")
	_check(spawner._pending.is_empty(), "pending delivery map is empty after delivery")


func _verify_tab_menu_filtering() -> void:
	# Build the menu and check _collect_free_mechs() logic directly.
	var menu := CombatTabMenuScript.new()
	add_child(menu)
	await get_tree().process_frame

	GlobalData.reset_run_data()
	GlobalData.ensure_hangar_roster()
	# Grow the fleet so the convoy has enough berths for multiple spares.
	GlobalData.fleet_roster.append({
		"template_id": "grunt_1", "name": "Grunt 1", "hp": 100.0, "max_hp": 100.0,
		"destroyed": false, "fielded": false,
	})
	GlobalData.fleet_roster.append({
		"template_id": "grunt_2", "name": "Grunt 2", "hp": 100.0, "max_hp": 100.0,
		"destroyed": false, "fielded": false,
	})
	# Roster now has only the active mech -> nothing free.
	var free := menu._collect_free_mechs()
	_check(free.is_empty(), "no free mechs when only the active mech exists")

	# Build a second, non-active mech -> it becomes free.
	var mech := GlobalData.build_hangar_mech("Spare Mech")
	var mech_id := str(mech.get("id", ""))
	free = menu._collect_free_mechs()
	_check(free.size() == 1, "a spare (non-active) mech is free")
	if free.size() == 1:
		_check(str(free[0].get("mech_id", "")) == mech_id, "free list offers the spare mech id")

	# A second spare is also offered.
	var mech2 := GlobalData.build_hangar_mech("Spare Mech 2")
	_check(not mech2.is_empty(), "second spare mech builds (fleet berths available)")
	free = menu._collect_free_mechs()
	_check(free.size() == 2, "two spare mechs are both free")

	menu.queue_free()
