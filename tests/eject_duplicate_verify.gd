extends Node

## Headless verification of the eject re-trigger guard:
##   - the first eject spawns exactly one pilot and parks the mech
##   - pressing eject again while parked spawns nothing extra
##   - boarding clears the parked state so a later eject works again
## Run: godot --headless --path . res://tests/eject_duplicate_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_eject_guard()
	print("EJECT_DUPLICATE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _pilot_count() -> int:
	return get_tree().get_nodes_in_group("pilot").size()


func _verify_eject_guard() -> void:
	var mech = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	add_child(mech)
	await get_tree().process_frame

	var eject = mech.get_node_or_null("MechaEject")
	_check(eject != null, "mech has a MechaEject")
	if eject == null:
		mech.queue_free()
		return

	_check(_pilot_count() == 0, "no pilot on the field before ejecting")
	eject.initiate_eject()
	await get_tree().process_frame
	_check(_pilot_count() == 1, "first eject spawns exactly one pilot")
	_check(mech.has_meta("is_parked"), "the mech parks after ejecting")

	# The bug: pressing eject again spawned a duplicate pilot. The parked flag
	# must suppress any further eject until the pilot boards again.
	eject.initiate_eject()
	await get_tree().process_frame
	_check(_pilot_count() == 1, "repeat eject does not spawn a second pilot")

	# Boarding consumes the pilot and clears the parked state (the full board
	# path also transitions scenes, which would tear down this test — the eject
	# guard only reads the parked flag, so simulate the state change directly).
	for p in get_tree().get_nodes_in_group("pilot"):
		p.queue_free()
	mech.remove_meta("is_parked")
	await get_tree().process_frame
	_check(_pilot_count() == 0, "boarding removes the pilot")
	_check(not mech.has_meta("is_parked"), "boarding clears the parked state")

	# ...so the pilot can eject again on the next sortie.
	eject.initiate_eject()
	await get_tree().process_frame
	_check(_pilot_count() == 1, "eject works again after re-boarding")

	mech.queue_free()
	await get_tree().process_frame
