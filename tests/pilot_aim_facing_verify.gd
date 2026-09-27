extends Node
## PILOT AIM FACING VERIFY - pilot body follows the camera on RMB aim and snaps
## to the shooting direction when firing (TPS aim contract).
##
## Covers:
##  1. yaw_facing() math faces -Z-forward correctly for 4 cardinal directions.
##  2. Holding fire_right (RMB ADS) turns the body toward the camera yaw.
##  3. Firing snaps the body to the camera shooting direction + spends a round.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)


func _ready() -> void:
	print("--- Running pilot_aim_facing_verify ---")
	_test_yaw_math()
	_test_rmb_aim_turns_body()
	_test_shoot_faces_direction()
	await _test_visor_and_grip()
	print("PILOT_AIM_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _spawn_pilot() -> CharacterBody3D:
	GameManager.current_state = GameManager.State.EJECT
	GlobalData.reset_run_data()
	GlobalData.pilot.pilot_ammo["sidearm"] = 120
	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)
	return pilot


func _spawn_camera() -> Camera3D:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	return cam


func _test_yaw_math() -> void:
	print("Testing yaw_facing math...")
	var pilot_scene = preload("res://scenes/pilot/pilot.tscn")
	var pilot = pilot_scene.instantiate()
	add_child(pilot)
	_check(is_equal_approx(pilot.yaw_facing(Vector3(0, 0, -1)), 0.0), "faces -Z at yaw 0")
	_check(is_equal_approx(pilot.yaw_facing(Vector3(1, 0, 0)), -PI / 2.0), "faces +X at yaw -PI/2")
	_check(absf(angle_difference(pilot.yaw_facing(Vector3(0, 0, 1)), PI)) < 0.001, "faces +Z at yaw PI")
	_check(is_equal_approx(pilot.yaw_facing(Vector3(-1, 0, 0)), PI / 2.0), "faces -X at yaw PI/2")
	pilot.queue_free()


func _test_rmb_aim_turns_body() -> void:
	print("Testing RMB ADS turns body to camera yaw...")
	var pilot := _spawn_pilot()
	var cam := _spawn_camera()
	cam.rotation = Vector3(0, -PI / 2.0, 0) # look toward +X
	pilot.rotation.y = 0.8
	# NOTE: headless has no capturable mouse, so the mouse_mode gate in
	# _physics_process can't be satisfied here; drive the RMB handler directly.
	Input.action_press("fire_right")
	_check(pilot.is_aiming(), "fire_right reads as aiming")
	pilot._update_aim_facing(0.5)
	Input.action_release("fire_right")
	_check(not pilot.is_aiming(), "aim releases with RMB")
	_check(absf(pilot.rotation.y - (-PI / 2.0)) < 0.05, "body turned to camera yaw on RMB (yaw=%.3f)" % pilot.rotation.y)
	pilot.queue_free()
	cam.queue_free()


func _test_shoot_faces_direction() -> void:
	print("Testing firing snaps body to shooting direction...")
	var pilot := _spawn_pilot()
	var cam := _spawn_camera() # default looks -Z
	pilot.rotation.y = 0.8
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var mag_before: int = pilot.get_current_magazine()
	_check(mag_before > 0, "magazine loaded for live-fire check (%d)" % mag_before)
	pilot._try_fire()
	_check(absf(pilot.rotation.y) < 0.05, "body snapped to camera forward on shoot (yaw=%.3f)" % pilot.rotation.y)
	_check(pilot.get_current_magazine() == mag_before - 1, "shot consumed one round")
	pilot.queue_free()
	cam.queue_free()


func _test_visor_and_grip() -> void:
	print("Testing visor marker + pistol seated in palm...")
	var pilot := _spawn_pilot()
	# Let the runtime grip converge (calibrates once the idle clip is live).
	for i in range(60):
		await get_tree().physics_frame
		if pilot.get("_grip_ready"):
			break
	var vis: Node = pilot.get_node_or_null("TacticalHumanVisual")
	var marker: Node = vis.find_child("PilotVisorMarker", true, false) if vis else null
	_check(marker is MeshInstance3D, "visor marker present on kit")
	if marker is MeshInstance3D:
		var mat: Material = (marker as MeshInstance3D).get_surface_override_material(0)
		_check(mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled,
			"visor marker emissive (visible in dark)")
	var skel: Skeleton3D = null
	var pistol: Node3D = null
	if vis:
		for c in vis.get_children():
			if skel == null:
				skel = _find_skeleton(c)
			var f: Node = c.find_child("PistolProp", true, false)
			if f != null:
				pistol = f as Node3D
	_check(skel != null and pistol != null, "skeleton + in-hand pistol present")
	if skel != null and pistol != null:
		var hi: int = skel.find_bone("hand_r")
		var hw: Vector3 = skel.get_bone_global_pose(hi).origin
		var pw: Vector3 = (pistol as Node3D).global_transform.origin
		print("PROBEDBG pistol local=", (pistol as Node3D).transform.origin, " attach=", ((pistol as Node3D).get_parent().name if (pistol as Node3D).get_parent() else "none"))
		_check(hw.distance_to(pw) < 0.15, "pistol seated in palm (gap=%.3fm)" % hw.distance_to(pw))
		_check_grip_orientation(pistol as MeshInstance3D, hw)
	pilot.queue_free()


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


## Grip orientation: darkest surface = polymer grip (must hang below the
## gray metal slide), and the muzzle end must reach forward of the hand.
func _check_grip_orientation(pistol: MeshInstance3D, hand_pos: Vector3) -> void:
	var mesh: ArrayMesh = pistol.mesh
	var grip_c := Vector3.ZERO
	var slide_c := Vector3.ZERO
	var grip_n := 0
	var slide_n := 0
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi_v := Vector3(-1e9, -1e9, -1e9)
	for s in range(mesh.get_surface_count()):
		var m: Material = pistol.get_surface_override_material(s)
		if m == null:
			m = mesh.surface_get_material(s)
		var bright := 1.0
		if m is StandardMaterial3D:
			var c: Color = (m as StandardMaterial3D).albedo_color
			bright = (c.r + c.g + c.b) / 3.0
		var arrays: Array = mesh.surface_get_arrays(s)
		for v in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			var w: Vector3 = pistol.global_transform * v
			lo.x = minf(lo.x, w.x)
			lo.y = minf(lo.y, w.y)
			lo.z = minf(lo.z, w.z)
			hi_v.x = maxf(hi_v.x, w.x)
			hi_v.y = maxf(hi_v.y, w.y)
			hi_v.z = maxf(hi_v.z, w.z)
			if bright < 0.2:
				grip_c += w
				grip_n += 1
			elif bright < 0.3:
				slide_c += w
				slide_n += 1
	if grip_n > 0 and slide_n > 0:
		grip_c /= float(grip_n)
		slide_c /= float(slide_n)
		_check(grip_c.y < slide_c.y - 0.01, "mag below slide (grip_y=%.3f slide_y=%.3f)" % [grip_c.y, slide_c.y])
	else:
		_check(false, "grip/slide surfaces identifiable (grip_n=%d slide_n=%d)" % [grip_n, slide_n])
	_check(lo.z < hand_pos.z - 0.10, "muzzle reaches forward of hand (min_z=%.3f hand=%.3f)" % [lo.z, hand_pos.z])
