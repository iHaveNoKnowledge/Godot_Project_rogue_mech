extends Node
## LIMB PROPORTION + ANKLE VERIFY (Wanzer rebalance pass)
##
## The torso/body is the FIXED reference and must NOT be resized. Limbs are
## scaled UP in width/depth/volume (never length) to match it, and the foot is
## a separate movable part on its own ankle pivot (THIGH > KNEE > SHIN >
## ANKLE > FOOT).
##
## Covers:
##  1. Torso dimensions unchanged (chest plate + Body pivot).
##  2. Arm/leg thickness increased, lengths unchanged, L/R symmetrical.
##  3. Joints (shoulder/hip/knee/ankle) have believable mechanical volume.
##  4. FootLeft/FootRight ankle pivots exist, are symmetrical, and own the
##     foot meshes (shin containers hold no foot meshes).
##  5. Weapons still mount under the Forearm nodes.

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("LIMB OK: " + name)
	else:
		_fails += 1
		printerr("LIMB FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads")
	_make_ground()
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")

	# Build every slot procedurally (null scenes -> procedural builders).
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var part := ArmorPart.new()
		part.slot_id = slot
		pmm.initialize_slot(slot, part, false)
	await get_tree().process_frame

	_test_torso_untouched(mecha, pmm)
	_test_arms(mecha, pmm)
	_test_legs(mecha, pmm)
	_test_ankle_foot(mecha, pmm)
	_test_weapon_mount(mecha)

	print("LIMB_PROPORTION_ANKLE_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("LIMB_PROPORTION_ANKLE_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_LIMB_PROPORTION_ANKLE_TESTS_PASSED")
		get_tree().quit(0)


# --- helpers ---------------------------------------------------------------

# Static floor so the CharacterBody settles instead of free-falling (a falling
# mech reads as "moving" to the gait system and never takes the idle stance).
func _make_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var col := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	plane.plane = Plane(Vector3.UP, 0.14)
	col.shape = plane
	ground.add_child(col)
	add_child(ground)

func _boxes_in(container: Node) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			out.append(child)
	return out


func _find_box(container: Node, y_size: float) -> MeshInstance3D:
	for mi in _boxes_in(container):
		var s: Vector3 = (mi.mesh as BoxMesh).size
		if absf(s.y - y_size) < 0.001:
			return mi
	return null


func _find_sphere(container: Node) -> MeshInstance3D:
	if container == null:
		return null
	for child in container.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh:
			return child
	return null


func _find_cyl(container: Node, height: float) -> MeshInstance3D:
	if container == null:
		return null
	for child in container.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is CylinderMesh:
			var c := (child as MeshInstance3D).mesh as CylinderMesh
			if absf(c.height - height) < 0.001:
				return child
	return null


func _mesh_sizes(container: Node) -> Array:
	var out: Array = []
	if container == null:
		return out
	for child in container.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			out.append((child as MeshInstance3D).mesh)
	return out


# --- 1. torso is the fixed reference ----------------------------------------

func _test_torso_untouched(mecha: Node3D, pmm: Node) -> void:
	var body = mecha.get_node_or_null("Body")
	# The idle combat stance eases the hips down ~0.02 (crouch compensation),
	# so allow that envelope while pinning X/Z and the rest height.
	_check(body != null and absf(body.position.x) < 0.001 and absf(body.position.z) < 0.001 and body.position.y <= 3.024 and body.position.y >= 2.97, "Body pivot unchanged (x/z 0, y in idle envelope, got %s)" % str(body.position) if body != null else "Body pivot unchanged")
	var entry: Dictionary = pmm.slot_meshes.get("body", {})
	var armor: Node3D = entry.get("armor")
	_check(armor != null, "body armor container exists")
	# Chest plate: PrismMesh 0.95 x 0.65 x 0.48 (must NOT change).
	var chest_ok := false
	if armor != null:
		for root in [armor] + _all_descendants(armor):
			if root is MeshInstance3D and (root as MeshInstance3D).mesh is PrismMesh:
				var s: Vector3 = ((root as MeshInstance3D).mesh as PrismMesh).size
				if s.is_equal_approx(Vector3(0.95, 0.65, 0.48)):
					chest_ok = true
	_check(chest_ok, "chest plate dimensions unchanged (0.95, 0.65, 0.48)")


func _all_descendants(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_descendants(c))
	return out


# --- 2. arms: thicker, same length, symmetrical ------------------------------

func _test_arms(_mecha: Node3D, pmm: Node) -> void:
	var sizes := {}
	for slot in ["arm_left", "arm_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var upper: MeshInstance3D = _find_box(entry.get("frame"), 0.40)
		var fore: MeshInstance3D = _find_box(entry.get("frame_lower"), 0.45)
		_check(upper != null, slot + " upper-arm frame exists (length 0.40 kept)")
		_check(fore != null, slot + " forearm frame exists (length 0.45 kept)")
		if upper != null:
			var s: Vector3 = (upper.mesh as BoxMesh).size
			_check(s.x >= 0.28 and s.z >= 0.28, slot + " upper arm thickened (x/z >= 0.28, got %s)" % str(s))
			sizes[slot + "_upper"] = s
		if fore != null:
			var s2: Vector3 = (fore.mesh as BoxMesh).size
			_check(s2.x >= 0.30 and s2.z >= 0.30, slot + " forearm thickened (x/z >= 0.30, got %s)" % str(s2))
			sizes[slot + "_fore"] = s2
		# Shoulder joint volume.
		var shoulder := _find_sphere(entry.get("frame"))
		_check(shoulder != null and (shoulder.mesh as SphereMesh).radius >= 0.21, slot + " shoulder joint radius >= 0.21")
		# Elbow disc volume.
		var elbow := _find_cyl(entry.get("frame_lower"), 0.18)
		_check(elbow != null and ((elbow.mesh as CylinderMesh).top_radius) >= 0.15, slot + " elbow disc radius >= 0.15")
		# Armor follows the frame.
		var guard: MeshInstance3D = _find_box(entry.get("armor_lower"), 0.46)
		_check(guard != null and (guard.mesh as BoxMesh).size.x >= 0.40, slot + " forearm guard armor thickened (x >= 0.40)")
		_check(entry.get("frame_foot") == null and entry.get("armor_foot") == null, slot + " has no foot containers")
	if sizes.has("arm_left_upper") and sizes.has("arm_right_upper"):
		_check((sizes["arm_left_upper"] as Vector3).is_equal_approx(sizes["arm_right_upper"]), "upper arms symmetrical L/R")
	if sizes.has("arm_left_fore") and sizes.has("arm_right_fore"):
		_check((sizes["arm_left_fore"] as Vector3).is_equal_approx(sizes["arm_right_fore"]), "forearms symmetrical L/R")


# --- 3. legs: load-bearing mass, same length, symmetrical --------------------

func _test_legs(_mecha: Node3D, pmm: Node) -> void:
	var sizes := {}
	for slot in ["leg_left", "leg_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var thigh: MeshInstance3D = _find_box(entry.get("frame"), 0.44)
		var shin: MeshInstance3D = _find_box(entry.get("frame_lower"), 0.44)
		_check(thigh != null, slot + " thigh frame exists (length 0.44 kept)")
		_check(shin != null, slot + " shin frame exists (length 0.44 kept)")
		if thigh != null:
			var s: Vector3 = (thigh.mesh as BoxMesh).size
			_check(s.x >= 0.34 and s.z >= 0.34, slot + " thigh thickened (x/z >= 0.34, got %s)" % str(s))
			sizes[slot + "_thigh"] = s
		if shin != null:
			var s2: Vector3 = (shin.mesh as BoxMesh).size
			_check(s2.x >= 0.34 and s2.z >= 0.34, slot + " shin thickened (x/z >= 0.34, got %s)" % str(s2))
			sizes[slot + "_shin"] = s2
		var hip := _find_sphere(entry.get("frame"))
		_check(hip != null and (hip.mesh as SphereMesh).radius >= 0.22, slot + " hip joint radius >= 0.22")
		var knee := _find_cyl(entry.get("frame_lower"), 0.20)
		_check(knee != null and ((knee.mesh as CylinderMesh).top_radius) >= 0.17, slot + " knee disc radius >= 0.17")
		var thigh_armor: MeshInstance3D = _find_box(entry.get("armor"), 0.44)
		_check(thigh_armor != null and (thigh_armor.mesh as BoxMesh).size.x >= 0.46, slot + " thigh armor thickened (x >= 0.46)")
		var shin_armor: MeshInstance3D = _find_box(entry.get("armor_lower"), 0.48)
		_check(shin_armor != null and (shin_armor.mesh as BoxMesh).size.x >= 0.46, slot + " shin armor thickened (x >= 0.46)")
	if sizes.has("leg_left_thigh") and sizes.has("leg_right_thigh"):
		_check((sizes["leg_left_thigh"] as Vector3).is_equal_approx(sizes["leg_right_thigh"]), "thighs symmetrical L/R")
	if sizes.has("leg_left_shin") and sizes.has("leg_right_shin"):
		_check((sizes["leg_left_shin"] as Vector3).is_equal_approx(sizes["leg_right_shin"]), "shins symmetrical L/R")


# --- 4. ankle joint + separate foot part -------------------------------------

func _test_ankle_foot(mecha: Node3D, pmm: Node) -> void:
	var foot_l = mecha.get_node_or_null("LegLeft/ShinLeft/FootLeft")
	var foot_r = mecha.get_node_or_null("LegRight/ShinRight/FootRight")
	_check(foot_l != null, "FootLeft ankle pivot exists under ShinLeft")
	_check(foot_r != null, "FootRight ankle pivot exists under ShinRight")
	if foot_l != null and foot_r != null:
		_check(absf(foot_l.position.x + foot_r.position.x) < 0.001 and absf(foot_l.position.y - foot_r.position.y) < 0.001, "ankle pivots symmetrical L/R")
		# Ankle pivots hang below the shin origin at the old ankle height.
		_check(foot_l.position.y < -0.5 and foot_l.position.x == 0.0, "ankle pivot sits at lower-leg bottom (got %s)" % str(foot_l.position))
	for slot in ["leg_left", "leg_right"]:
		var entry: Dictionary = pmm.slot_meshes.get(slot, {})
		var frame_foot: Node3D = entry.get("frame_foot")
		var armor_foot: Node3D = entry.get("armor_foot")
		_check(frame_foot != null, slot + " has foot frame container")
		_check(armor_foot != null, slot + " has foot armor container")
		if frame_foot != null:
			_check(frame_foot.get_node_or_null("AnkleJoint") != null, slot + " ankle joint mesh exists in foot container")
			var ankle: Node3D = frame_foot.get_node_or_null("AnkleJoint")
			if ankle is MeshInstance3D:
				var c := (ankle as MeshInstance3D).mesh as CylinderMesh
				_check(c != null and c.top_radius >= 0.13, slot + " ankle has mechanical volume (r >= 0.13)")
			_check(frame_foot.get_node_or_null("FootBlock") != null, slot + " foot block lives in the FOOT container")
			var block: Node3D = frame_foot.get_node_or_null("FootBlock")
			if block is MeshInstance3D:
				var s: Vector3 = ((block as MeshInstance3D).mesh as BoxMesh).size
				_check(s.x >= 0.34 and s.z >= 0.48, slot + " foot enlarged to support the mech (got %s)" % str(s))
		if armor_foot != null:
			_check(armor_foot.get_node_or_null("FootCap") != null, slot + " foot armor cap lives in the FOOT container")
		# The shin containers must NOT hold foot meshes anymore.
		var shin_holds_foot := false
		for c in [entry.get("frame_lower"), entry.get("armor_lower")]:
			if c == null:
				continue
			for child in (c as Node3D).get_children():
				if child.name in ["FootBlock", "FootCap", "FootHeel", "FootRoller", "FootClaw", "FootSkid", "FootSkidGuard", "FootToe", "AnkleJoint"]:
					shin_holds_foot = true
		_check(not shin_holds_foot, slot + " shin containers hold no foot meshes (clean split)")
	# Foot world placement preserved: foot block sits at the old ground height.
	if foot_l != null:
		var entry_l: Dictionary = pmm.slot_meshes.get("leg_left", {})
		var ff: Node3D = entry_l.get("frame_foot")
		if ff != null:
			var block_l: Node3D = ff.get_node_or_null("FootBlock")
			if block_l != null:
				var world_y: float = (block_l as Node3D).global_position.y
				var shin = mecha.get_node_or_null("LegLeft/ShinLeft")
				_check(world_y < shin.global_position.y, "foot block sits below the shin pivot (world y %.3f)" % world_y)


# --- 5. weapons still attach to the forearms ---------------------------------

func _test_weapon_mount(mecha: Node3D) -> void:
	for side in ["Left", "Right"]:
		var forearm = mecha.get_node_or_null("Arm" + side + "/Forearm" + side)
		_check(forearm != null, "Forearm" + side + " node exists for weapon mounting")
	var wpath := "res://resources/mech/stock/weapon_machine_gun.tres"
	if not ResourceLoader.exists(wpath):
		_check(false, "stock machine gun resource exists for mount check")
		return
	var weapon: WeaponPart = load(wpath)
	var mount = WeaponVisualFactory.mount_hand(mecha, "right", weapon, "WeaponVisual_test_right")
	_check(mount != null and mount.get_parent() != null and str(mount.get_parent().name) == "ForearmRight", "weapon mounts under ForearmRight (hand)")
	_check(mount.get_child_count() > 0, "mounted weapon has visible model children")
	mount.queue_free()
