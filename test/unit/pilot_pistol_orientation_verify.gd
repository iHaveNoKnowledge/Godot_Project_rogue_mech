## PILOT PISTOL ORIENTATION VERIFY — in-hand pistol seats correctly on the kit.
##
## Regression guard for the "muzzle points at the sky" bug: the prop's long
## (barrel) axis is local Y, but the old Blender re-seat assumed local +Z, so
## the gun stood upright in the fist. Checks on the exported GLB kit:
##  1. Exactly ONE pistol node exists and it hangs under the hand_r joint.
##  2. At idle f0 the pistol mesh extends FORWARD of the hand (-Z, Godot
##     forward) and is longer along Z than it is tall along Y (no upright gun).
##  3. Grip mass sits BELOW the bore line (dark grip vertices under the slide).
##  4. Fingers wrap: fingertip bones stay within a fist's reach of hand_r.
## Sampling is synchronous (seek + update, no awaits).

extends Node

const KIT_PATH := "res://scenes/pilot/pilot_pistol_kit.glb"

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("PILOT_PISTOL OK: " + name)
	else:
		_fails += 1
		printerr("PILOT_PISTOL FAIL: " + name)


func _ready() -> void:
	print("--- Running pilot_pistol_orientation_verify ---")
	_check(ResourceLoader.exists(KIT_PATH), "kit file present")
	if not ResourceLoader.exists(KIT_PATH):
		_finish()
		return
	var packed: PackedScene = load(KIT_PATH)
	_check(packed != null and packed.can_instantiate(), "kit instantiates")
	if packed == null or not packed.can_instantiate():
		_finish()
		return
	var inst: Node = packed.instantiate()
	add_child(inst)

	# 1) exactly one pistol node, parented under the hand_r bone chain
	var pistols: Array[Node] = []
	_find_pistols(inst, pistols)
	_check(pistols.size() == 1, "exactly one pistol node (found %d)" % pistols.size())
	if pistols.is_empty():
		_finish()
		return
	var pistol := pistols[0] as Node3D
	var chain_ok := false
	var n: Node = pistol
	while n != null:
		if n is Skeleton3D:
			chain_ok = true
		n = n.get_parent()
	_check(chain_ok, "pistol parented under the skeleton (bone attach)")

	var skel := _find_skeleton(inst)
	var player := _find_player(inst)
	_check(skel != null and player != null, "skeleton + animation player present")
	if skel == null or player == null:
		_finish()
		return

	# 2) seat orientation at idle f0. NOTE: the pistol hangs off a
	# BoneAttachment3D which refreshes on the skeleton's updated signal, so
	# give the tree a couple of frames after seeking before reading its
	# world transform (direct bone reads are valid immediately).
	var hi: int = skel.find_bone("hand_r")
	_check(hi >= 0, "hand_r bone present")
	player.play("pistol_idle_loop")
	player.seek(0.0, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var hw: Vector3 = skel.global_transform * skel.get_bone_global_pose(hi).origin
	var aabb := _world_aabb(pistol)
	var depth := aabb.size.z
	var height := aabb.size.y
	print("  DBG pistol origin %s | hand_r %s | aabb pos=%s size=%s" % [
		pistol.global_transform.origin, hw, aabb.position, aabb.size])
	_check(pistol.global_transform.origin.distance_to(hw) < 0.25,
		"pistol sits at the hand (gap %.3fm)" % pistol.global_transform.origin.distance_to(hw))
	_check(depth > height * 1.2,
		"gun lies along the aim axis, not upright (depth %.3f vs height %.3f)" % [depth, height])
	_check(height < 0.16,
		"gun not standing on the barrel (world-up extent %.3f)" % height)

	# muzzle side: the kit model faces +Z (controller yaw-flips it), so the
	# barrel must reach PAST the hand toward +Z
	_check(aabb.end.z > hw.z + 0.08,
		"muzzle reaches forward of the hand (max_z %.3f vs hand %.3f)" % [aabb.end.z, hw.z])

	# 3) grip mass hangs low: rear-half vertices sit lower than front-half
	# (slide/barrel) vertices — geometric, no material assumptions
	var drop := _grip_drop(pistol)
	_check(drop > 0.01,
		"grip mass hangs below the bore line (rear-below-front %.3fm)" % drop)

	# 4) fingers wrapped: every fingertip within a fist's reach of the palm
	# point (wrist + 5 cm along the hand axis)
	var hy: Vector3 = skel.global_transform * skel.get_bone_global_pose(hi).basis.y
	var palm := hw + hy.normalized() * 0.05
	var wrapped := 0
	var total := 0
	for side in ["r", "l"]:
		for chain in ["thumb", "index", "middle", "ring", "pinky"]:
			var bi := skel.find_bone("%s_03_%s" % [chain, side])
			if bi < 0:
				continue
			total += 1
			var tip: Vector3 = skel.global_transform * skel.get_bone_global_pose(bi).origin
			if tip.distance_to(palm) < 0.18:
				wrapped += 1
	_check(total > 0 and wrapped == total,
		"fingers wrapped around the grip (%d/%d within fist reach)" % [wrapped, total])

	inst.queue_free()
	_finish()


func _find_pistols(n: Node, out: Array[Node]) -> void:
	if n.name.contains("Pistol"):
		out.append(n)
	for c in n.get_children():
		_find_pistols(c, out)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var f := _find_skeleton(c)
		if f != null:
			return f
	return null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null


func _world_aabb(pistol: Node3D) -> AABB:
	var first := true
	var out := AABB()
	for c in pistol.get_children():
		if c is MeshInstance3D:
			var box: AABB = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).get_aabb()
			if first:
				out = box
				first = false
			else:
				out = out.merge(box)
	if first:
		# pistol itself may be the MeshInstance3D
		if pistol is MeshInstance3D:
			out = pistol.global_transform * (pistol as MeshInstance3D).get_aabb()
		else:
			out = AABB(hw_zero(pistol), Vector3.ONE * 0.001)
	return out


func hw_zero(pistol: Node3D) -> Vector3:
	return pistol.global_transform.origin


## Mean height of rear-half vertices minus mean height of front-half
## vertices (world +Y): a correctly seated gun carries its grip mass in the
## rear half, below the slide line, so the rear sits lower than the front.
func _grip_drop(pistol: Node3D) -> float:
	var mesh_mi := _first_mesh(pistol)
	if mesh_mi == null:
		return -1.0
	var mi := mesh_mi as MeshInstance3D
	var mesh: Mesh = mi.mesh
	var aabb: AABB = mi.global_transform * mesh.get_aabb()
	var mid_z := aabb.position.z + aabb.size.z * 0.5
	var rear_y := 0.0
	var rear_n := 0
	var front_y := 0.0
	var front_n := 0
	for s in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(s)
		for v in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var w: Vector3 = mi.global_transform * v
			if w.z > mid_z:
				rear_y += w.y
				rear_n += 1
			else:
				front_y += w.y
				front_n += 1
	if rear_n == 0 or front_n == 0:
		return -1.0
	return (front_y / front_n) - (rear_y / rear_n)


func _first_mesh(n: Node) -> Node:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f := _first_mesh(c)
		if f != null:
			return f
	return null


func _finish() -> void:
	print("PILOT_PISTOL_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	print("ALL_PILOT_PISTOL_TESTS_PASSED" if _fails == 0 else "PILOT_PISTOL_TESTS_FAILED")
	get_tree().quit(0 if _fails == 0 else 1)
