extends Node

## Architecture migration audit: the legacy "AnimationSystem" node was renamed
## to "MechaAnimation" and no longer exists. Proves every active runtime path
## resolves the current owner (no behavior depends on the obsolete name).
## Run: godot --headless --path . res://tests/mecha/architecture_migration_reference_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"

var _fails := 0
var _checks := 0


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
	print("MIGRATION_AUDIT: checks=%d fails=%d" % [_checks, _fails])
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

	# ---- node contract: current owner exists, obsolete name resolves null ----
	var mech: CharacterBody3D = load(MECH_SCENE).instantiate()
	mech.position = Vector3(0, 10, 0)
	add_child(mech)
	mech.is_player_driven = false
	await get_tree().process_frame
	_check(mech.get_node_or_null("MechaAnimation") != null, "current animation owner exists")
	_check(mech.get_node_or_null("AnimationSystem") == null, "obsolete node name resolves null (fully removed)")
	for n in ["PartMeshManager", "HealthSystem", "Hitbox", "FootIKSystem", "MechaCombat", "MechaEject", "WeaponMount", "LegLeft", "ArmLeft", "Body", "Head"]:
		_check(mech.get_node_or_null(n) != null, "contract node present: " + n)

	# ---- landing impact reaches the current owner ----
	var anim: Node = mech.get_node_or_null("MechaAnimation")
	_check(anim.has_method("play_landing_impact"), "landing-impact method exists on current owner")
	var peak := 0.0
	var f := 0
	while f < 240:
		await get_tree().physics_frame
		f += 1
		if mech.is_on_floor():
			peak = maxf(peak, float(anim.get("landing_impact")))
			if peak > 0.3 and f > 30:
				break
	_check(peak > 0.3, "landing impact drives current animation owner (peak=%.2f)" % peak)

	# ---- fire path requirement present (action_animator on current owner) ----
	_check(anim.get("action_animator") != null, "fire path animator present on current owner")

	# ---- reserve path resolves current owner ----
	var RBSpawner: GDScript = load("res://scripts/systems/backup_mech_spawner.gd")
	var spawner: Node = RBSpawner.new()
	add_child(spawner)
	await get_tree().process_frame
	spawner._spawn_reserve_mech("audit_berth", Vector3(60, 5, 0))
	await get_tree().physics_frame
	var reserve: Node = get_node_or_null("ReserveMech")
	_check(reserve != null, "reserve delivered")
	if reserve:
		_check(reserve.get_node_or_null("MechaAnimation") != null, "reserve carries current animation owner")
		_check(reserve.get_node_or_null("AnimationSystem") == null, "reserve has no obsolete node")
		reserve.queue_free()
	spawner.queue_free()
	mech.queue_free()
	await get_tree().process_frame
