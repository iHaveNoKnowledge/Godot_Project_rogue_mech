extends Node

## Headless verification of the mech kneel/stand pose:
##   - a mech starts standing (occupied by its pilot)
##   - EventBus.mecha_occupancy_changed(false) (pilot ejected) makes it kneel:
##     thighs fold forward, shins fold back under, torso drops
##   - EventBus.mecha_occupancy_changed(true) (pilot boards) stands it back up
## Run: godot --headless --path . res://tests/mecha_kneel_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_kneel_cycle()
	print("MECHA_KNEEL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


func _wait_physics(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame


func _verify_kneel_cycle() -> void:
	# The mech controller bails out of movement (and gravity) with no camera,
	# so provide one for the test.
	var cam := Camera3D.new()
	add_child(cam)

	# Ground so the mech settles and its standing idle pose is stable.
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 3, 120)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)

	var mech = load("res://scenes/mecha/mecha_base.tscn").instantiate()
	mech.position = Vector3(0, 10, 0)
	add_child(mech)
	# Fall from above so CharacterBody3D.is_on_floor() reports true once landed.
	await _wait_physics(90)

	var anim = mech.get_node_or_null("AnimationSystem")
	_check(anim != null, "mech has an AnimationSystem")
	if anim == null:
		mech.queue_free()
		return

	var leg_left = mech.get_node_or_null("LegLeft")
	var shin_left = mech.get_node_or_null("LegLeft/ShinLeft")
	var body = mech.get_node_or_null("Body")

	_check(mech.is_on_floor(), "mech settles on the ground")
	_check(anim.is_kneeling == false, "occupied mech starts standing (not kneeling)")

	# Pilot out: the empty-cockpit signal drives the kneel pose.
	EventBus.mecha_occupancy_changed.emit(false)
	_check(anim.is_kneeling, "empty signal makes the mech kneel")
	await _wait_physics(40)
	if leg_left and shin_left:
		_check(leg_left.rotation.x > 0.9, "kneel folds the thighs forward")
		_check(shin_left.rotation.x < -1.0, "kneel folds the shins back")
	if body:
		_check(body.position.y < 1.6, "kneel drops the torso toward the ground")

	# Pilot back in: the occupied signal stands the mech up again.
	EventBus.mecha_occupancy_changed.emit(true)
	_check(anim.is_kneeling == false, "occupied signal stands the mech back up")
	await _wait_physics(120)
	if leg_left:
		_check(leg_left.rotation.x < 0.4, "thighs ease back to the standing pose")

	mech.queue_free()
	await get_tree().process_frame
