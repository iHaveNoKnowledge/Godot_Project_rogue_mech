extends Node3D

## Headless verification that enemy spawns don't stack on each other or inside
## cover objects:
##   1. is_pos_blocked_by_covers() flags positions inside cover footprints
##      (including rotated covers), with a margin.
##   2. _get_spawn_position() hands out a distinct ring marker per spawn until
##      all markers are used, then still returns a valid fallback.
##   3. A marker covered by an obstacle is never picked.
## Run: godot --headless --path . res://tests/spawn_spacing_verify.tscn

const SPAWN_SCRIPT := preload("res://scripts/systems/spawn_manager.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SPACING_OK: " + name)
	else:
		_fails += 1
		print("SPACING_FAIL: " + name)


func _add_cover(pos: Vector3, size: Vector3, rot_y: float = 0.0, in_group: bool = false) -> StaticBody3D:
	var cover := StaticBody3D.new()
	cover.position = pos
	cover.rotation.y = rot_y
	if in_group:
		cover.add_to_group("cover")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, size.y * 0.5, 0)
	cover.add_child(col)
	add_child(cover)
	return cover


func _key(pos: Vector3) -> Vector3:
	return Vector3(snappedf(pos.x, 0.01), 0, snappedf(pos.z, 0.01))


func _ready() -> void:
	await get_tree().process_frame

	# --- cover blocking (pure AABB math, no physics needed) ---
	var cover := _add_cover(Vector3(0, 0, 0), Vector3(6, 2.2, 1.2))
	await get_tree().process_frame

	_check(SPAWN_SCRIPT.is_pos_blocked_by_covers(Vector3(0, 0, 0), [cover]), "position inside cover is blocked")
	_check(SPAWN_SCRIPT.is_pos_blocked_by_covers(Vector3(2.5, 0, 0.4), [cover]), "position at cover edge is blocked (margin)")
	_check(not SPAWN_SCRIPT.is_pos_blocked_by_covers(Vector3(10, 0, 0), [cover]), "position far from cover is clear")

	var rotated := _add_cover(Vector3(20, 0, 20), Vector3(6, 2.2, 1.2), deg_to_rad(90))
	await get_tree().process_frame
	_check(SPAWN_SCRIPT.is_pos_blocked_by_covers(Vector3(20.3, 0, 20), [rotated]), "rotated cover blocks its footprint")

	# --- spawn point dedup: 12 distinct markers, then a fallback ---
	var mgr := SPAWN_SCRIPT.new()
	add_child(mgr)

	var used: Dictionary = {}
	var duplicates := 0
	for i in range(13):
		var p := mgr._get_spawn_position()
		var k := _key(p)
		if used.has(k):
			duplicates += 1
		else:
			used[k] = true
	_check(used.size() == 12, "13 spawns use 12 distinct markers (got %d)" % used.size())
	_check(duplicates == 1, "13th spawn falls back to a reused marker (got %d)" % duplicates)

	# --- a marker sitting on cover is never picked ---
	var mgr2 := SPAWN_SCRIPT.new()
	add_child(mgr2)
	var blocked_key := _key(mgr2.spawn_points[0].global_position)
	_add_cover(mgr2.spawn_points[0].global_position + Vector3(0, 1.1, 0), Vector3(6, 2.2, 1.2), 0.0, true)
	await get_tree().process_frame

	var picked: Dictionary = {}
	for i in range(13):
		var p := mgr2._get_spawn_position()
		picked[_key(p)] = true
	_check(not picked.has(blocked_key), "marker covered by an obstacle is skipped")
	_check(picked.size() == 11, "covered marker still leaves the other 11 markers usable (got %d)" % picked.size())

	print("SPAWN_SPACING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
