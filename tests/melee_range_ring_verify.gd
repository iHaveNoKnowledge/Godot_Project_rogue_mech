extends Node

## Verifies the crosshair melee-reach ring:
##   - the reach shown matches the loadout: a held melee weapon's range, the
##     bare-fist reach (3.0) when a hand is empty, nothing for a fully ranged
##     loadout,
##   - the arc geometry: MELEE_ARC_STEPS+1 world points all sitting at the
##     weapon's radius around the mech on the mech's ground plane, forming a
##     front-facing 180° semicircle along the aim direction (no rear coverage).
## Run: godot --headless --path . res://tests/melee_range_ring_verify.tscn

var _fails := 0
var _checks := 0

var _crosshair: Node = null
var _wm: Node = null
var _mecha: CharacterBody3D = null

var _pile: WeaponPart = preload("res://resources/mech/stock/weapon_pile_bunker.tres")
var _rifle: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
var _shotgun: WeaponPart = preload("res://resources/mech/stock/weapon_combat_shotgun.tres")


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("RING OK: " + name)
	else:
		_fails += 1
		print("RING FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	_build_scene()
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Empty hands -> bare-fist reach.
	_check(_crosshair._get_melee_range() == 4.5, "empty hands show the bare-fist reach (4.5)")

	# 2. Held melee weapon -> its own range.
	_wm.left_hand = _pile
	await get_tree().process_frame
	_check(_crosshair._get_melee_range() == 6.0, "held pile bunker shows its 6m reach")

	# 3. Ranged weapon + empty hand -> fist reach from the empty hand.
	_wm.left_hand = _rifle
	_wm.right_hand = null
	await get_tree().process_frame
	_check(_crosshair._get_melee_range() == 4.5, "ranged weapon + empty hand shows the fist reach")

	# 4. Both hands ranged -> no ring.
	_wm.right_hand = _shotgun
	await get_tree().process_frame
	_check(_crosshair._get_melee_range() == 0.0, "fully ranged loadout shows no ring")

	# 5. Arc geometry: pile (6.0) on the left, aim straight ahead (-Z).
	_wm.left_hand = _pile
	_wm.right_hand = null
	var mecha_pos := Vector3(0, 1.5, 0)
	var aim := Vector3(0, 0, -1)
	var points: PackedVector3Array = _crosshair._compute_melee_arc_world_points(mecha_pos, aim, 6.0)
	_check(points.size() == 25, "arc uses %d segments + closure point (%d points)" % [24, points.size()])
	var all_on_radius := true
	var all_in_front := true
	var all_on_plane := true
	for p in points:
		var flat := Vector2(p.x - mecha_pos.x, p.z - mecha_pos.z)
		if absf(flat.length() - 6.0) > 0.05:
			all_on_radius = false
		if p.z > 0.05:
			all_in_front = false
		if absf(p.y - mecha_pos.y) > 0.001:
			all_on_plane = false
	_check(all_on_radius, "every arc point sits at the weapon's radius from the mech")
	_check(all_in_front, "arc only covers the front 180° (no rear coverage)")
	_check(all_on_plane, "arc lies flat on the mech's ground plane")
	_check(points[0].distance_to(Vector3(6.0, 1.5, 0.0)) < 0.05, "arc starts on the right (+90°)")
	_check(points[24].distance_to(Vector3(-6.0, 1.5, 0.0)) < 0.05, "arc ends on the left (-90°)")
	_check(points[12].distance_to(Vector3(0.0, 1.5, -6.0)) < 0.05, "arc apex points straight ahead")

	print("RING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _build_scene() -> void:
	_mecha = CharacterBody3D.new()
	_mecha.name = "Mecha"
	_mecha.position = Vector3(0, 1.5, 0)
	add_child(_mecha)

	_wm = Node3D.new()
	_wm.name = "WeaponManager"
	_wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	_mecha.add_child(_wm)
	_wm.left_hand = null
	_wm.right_hand = null

	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 3.0, 6.0)
	cam.look_at(Vector3(0, 1.5, -3.0))
	add_child(cam)

	var crosshair_scene: PackedScene = preload("res://scenes/ui/crosshair.tscn")
	_crosshair = crosshair_scene.instantiate()
	add_child(_crosshair)
