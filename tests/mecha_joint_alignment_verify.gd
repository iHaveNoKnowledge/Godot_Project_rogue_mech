extends Node
## MECHA JOINT ALIGNMENT CONTRACT — architectural invariants, not historical coordinates.
##
## Guards the foundation the Frame Extension audit relies on:
##   joint identity (node names + GlobalData.SLOT_TO_NODE + MechaRig bones),
##   joint hierarchy (slot roots under the mech root, lower joints nested),
##   transform validity (finite, sane local scale),
##   spatial invariants (ordering / symmetry / separation — relative, never
##   hard-coded historical coordinates), and
##   animation compatibility (a base-position offset applied through the plain
##   node API survives live animation frames, proving the rotation-dominant
##   animation path does not overwrite structural placement).
##
## Deliberately Frame-Extension-neutral: no assertion pins a joint's absolute
## base position, so a future armor-driven structural offset
## (Base + Offset = Runtime) will not invalidate this contract.
## Run: godot --headless --path . res://tests/mecha_joint_alignment_verify.tscn

const MECHA_SCENE := "res://scenes/mecha/mecha_base.tscn"

# The authoritative joint vocabulary: scene node paths (GlobalData.SLOT_TO_NODE
# values) plus nested lower-joint paths. No invented JNT_* names.
const SLOT_PATHS: Array[String] = ["Head", "Body", "ArmLeft", "ArmRight", "LegLeft", "LegRight"]
const LOWER_JOINTS := {
	"ArmLeft/ForearmLeft": "ArmLeft",
	"ArmRight/ForearmRight": "ArmRight",
	"LegLeft/ShinLeft": "LegLeft",
	"LegRight/ShinRight": "LegRight",
	"LegLeft/ShinLeft/FootLeft": "LegLeft/ShinLeft",
	"LegRight/ShinRight/FootRight": "LegRight/ShinRight",
}

# Probe offset for the animation-compatibility check. Mirrors the audit's
# wide-armor example magnitude; test-only, creates no production API.
const STRUCTURAL_PROBE := 0.30
const POS_TOL := 0.02
const SYM_TOL := 0.05

var _failures := 0
var _checks := 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + message)
	else:
		_failures += 1
		print("  FAIL: " + message)


func _close(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol


func _finite(v: Vector3) -> bool:
	return not (is_nan(v.x) or is_nan(v.y) or is_nan(v.z) or is_inf(v.x) or is_inf(v.y) or is_inf(v.z))


func _ready() -> void:
	print("--- Running mecha_joint_alignment_verify (contract) ---")
	var mecha_scene: PackedScene = load(MECHA_SCENE)
	_check(mecha_scene != null and mecha_scene.can_instantiate(), "mecha_base.tscn loads as an instantiable scene")
	if mecha_scene == null or not mecha_scene.can_instantiate():
		_finish()
		return
	var mecha: Node = mecha_scene.instantiate()
	add_child(mecha)
	await get_tree().process_frame

	_verify_identity(mecha)
	_verify_hierarchy(mecha)
	_verify_transform_validity(mecha)
	_verify_spatial_invariants(mecha)
	_verify_carry_mount_contract()
	await _verify_animation_preserves_base_offset(mecha)

	mecha.queue_free()
	await get_tree().process_frame
	_finish()


# A. Joint identity: every required joint exists, and the authoritative
# slot vocabulary (GlobalData.SLOT_TO_NODE) resolves to those same nodes.
func _verify_identity(mecha: Node) -> void:
	for path in SLOT_PATHS:
		_check(mecha.get_node_or_null(path) != null, "joint identity: node '%s' exists" % path)
	for path in LOWER_JOINTS.keys():
		_check(mecha.get_node_or_null(path) != null, "joint identity: lower joint '%s' exists" % path)
	var slot_map: Dictionary = GlobalData.SLOT_TO_NODE
	_check(not slot_map.is_empty(), "joint identity: GlobalData.SLOT_TO_NODE vocabulary present")
	for slot in GlobalData.MECHA_SLOTS:
		var node_name := str(slot_map.get(slot, ""))
		_check(node_name != "" and mecha.get_node_or_null(node_name) != null,
			"joint identity: slot '%s' maps to live node '%s'" % [slot, node_name])


# B. Hierarchy: actual current layout — the six slot roots hang directly off
# the mech root (NOT off Body), lower joints nest under their slot parent.
func _verify_hierarchy(mecha: Node) -> void:
	for path in SLOT_PATHS:
		var n: Node = mecha.get_node_or_null(path)
		_check(n != null and n.get_parent() == mecha, "hierarchy: '%s' is a direct child of the mech root" % path)
	for path in LOWER_JOINTS.keys():
		var n: Node = mecha.get_node_or_null(path)
		var parent_path: String = LOWER_JOINTS[path]
		var parent: Node = mecha.get_node_or_null(parent_path)
		_check(n != null and parent != null and n.get_parent() == parent,
			"hierarchy: '%s' nests under '%s'" % [path, parent_path])


# C. Base transforms exist and are valid — finite positions, sane unit scales.
# No absolute coordinate is asserted here.
func _verify_transform_validity(mecha: Node) -> void:
	var paths: Array = SLOT_PATHS.duplicate()
	paths.append_array(LOWER_JOINTS.keys())
	for path in paths:
		var n := mecha.get_node_or_null(path) as Node3D
		if n == null:
			_check(false, "transform validity: '%s' resolves to Node3D" % path)
			continue
		_check(_finite(n.position), "transform validity: '%s' position finite (%s)" % [path, str(n.position)])
		_check(_finite(n.rotation), "transform validity: '%s' rotation finite" % path)
		_check(_close(n.scale.x, 1.0, 0.01) and _close(n.scale.y, 1.0, 0.01) and _close(n.scale.z, 1.0, 0.01),
			"transform validity: '%s' local scale is unit (%s)" % [path, str(n.scale)])


# Spatial invariants: relative placement only — ordering, direction, symmetry,
# separation. All tolerant; none pins a historical coordinate.
func _verify_spatial_invariants(mecha: Node) -> void:
	var head := mecha.get_node_or_null("Head") as Node3D
	var body := mecha.get_node_or_null("Body") as Node3D
	var arm_l := mecha.get_node_or_null("ArmLeft") as Node3D
	var arm_r := mecha.get_node_or_null("ArmRight") as Node3D
	var leg_l := mecha.get_node_or_null("LegLeft") as Node3D
	var leg_r := mecha.get_node_or_null("LegRight") as Node3D
	if head == null or body == null or arm_l == null or arm_r == null or leg_l == null or leg_r == null:
		_check(false, "spatial invariants: slot nodes resolve (skipped, see identity failures)")
		return
	# Left/right direction convention: left joints sit at -X, right at +X.
	_check(arm_l.position.x < 0.0 and arm_r.position.x > 0.0, "spatial: arms respect left(-X)/right(+X) direction")
	_check(leg_l.position.x < 0.0 and leg_r.position.x > 0.0, "spatial: legs respect left(-X)/right(+X) direction")
	# Bilateral symmetry (explicitly required by the mirrored rig).
	_check(_close(arm_l.position.x, -arm_r.position.x, SYM_TOL), "spatial: shoulder mounts symmetric about center")
	_check(_close(arm_l.position.y, arm_r.position.y, SYM_TOL), "spatial: shoulder mounts level with each other")
	_check(_close(leg_l.position.x, -leg_r.position.x, SYM_TOL), "spatial: hip mounts symmetric about center")
	_check(_close(leg_l.position.y, leg_r.position.y, SYM_TOL), "spatial: hip mounts level with each other")
	# Vertical stack: head above shoulders above torso mass above hips.
	_check(head.position.y > arm_l.position.y, "spatial: head rides above the shoulder line")
	_check(arm_l.position.y > body.position.y, "spatial: shoulder line sits above the torso center")
	_check(body.position.y > leg_l.position.y + 0.3, "spatial: torso mass sits clear above the hips")
	# Forward convention (project forward is -Z): head sits forward of torso center.
	_check(head.position.z < body.position.z, "spatial: head forward (-Z) of torso center")
	_check(_close(head.position.x, 0.0, SYM_TOL) and _close(body.position.x, 0.0, SYM_TOL),
		"spatial: head and torso centered on the sagittal plane")
	# Arms outboard of hips; joints genuinely separated (no collapsed rig).
	_check(absf(arm_l.position.x) > absf(leg_l.position.x), "spatial: shoulder mounts outboard of hip mounts")
	_check(absf(arm_l.position.x - arm_r.position.x) > 0.5, "spatial: non-zero shoulder span")
	_check(absf(leg_l.position.x - leg_r.position.x) > 0.3, "spatial: non-zero hip span")
	# Lower joints hang below their parents and stay centered on the limb axis.
	for path in LOWER_JOINTS.keys():
		var n := mecha.get_node_or_null(path) as Node3D
		if n == null:
			_check(false, "spatial: lower joint '%s' resolves (skipped)" % path)
			continue
		_check(n.position.y < -0.1, "spatial: '%s' hangs below its parent joint" % path)
		_check(absf(n.position.x) < SYM_TOL and absf(n.position.z) < SYM_TOL,
			"spatial: '%s' centered on its limb axis" % path)


# Back-carry mount contract (unchanged from the previous revision — still valid).
func _verify_carry_mount_contract() -> void:
	_check(WeaponVisualFactory.BACK_ROT_DEG.x <= -90.0, "Back carry rotation pitches weapon vertically upright (<= -90 deg on X)")
	_check(WeaponVisualFactory.BACK_Z >= 0.60, "Back carry mount is positioned clear behind backpack (Z >= 0.60m)")


# Animation compatibility (§8): a structural-style base offset applied through
# the plain node API must survive live animation frames, and the child limb
# must follow through hierarchy — proving the rotation-dominant animation path
# (MechaAnimation / WalkingSystem / ClipRetarget / ActionAnimator) owns
# articulation, not base placement. Uses only existing runtime behavior.
func _verify_animation_preserves_base_offset(mecha: Node) -> void:
	var arm_l := mecha.get_node_or_null("ArmLeft") as Node3D
	var fore_l := mecha.get_node_or_null("ArmLeft/ForearmLeft") as Node3D
	var arm_r := mecha.get_node_or_null("ArmRight") as Node3D
	if arm_l == null or fore_l == null or arm_r == null:
		_check(false, "animation compatibility: arm joints resolve (skipped)")
		return
	# Let the live animation systems run so caches seed and a posture settles.
	for i in range(10):
		await get_tree().physics_frame
	if not is_instance_valid(arm_l) or not is_instance_valid(fore_l):
		_check(false, "animation compatibility: joints survive live frames")
		return
	var base_x := arm_l.position.x
	var arm_r_x := arm_r.position.x
	var fore_local: Vector3 = fore_l.position
	var fore_world_before: Vector3 = fore_l.global_position
	# Simulate a future structural offset: plain transform write, no new API.
	arm_l.position.x = base_x - STRUCTURAL_PROBE
	for i in range(10):
		await get_tree().physics_frame
	if not is_instance_valid(arm_l) or not is_instance_valid(fore_l) or not is_instance_valid(arm_r):
		_check(false, "animation compatibility: joints survive offset + live frames")
		return
	_check(_close(arm_l.position.x, base_x - STRUCTURAL_PROBE, POS_TOL),
		"animation compatibility: applied base offset on ArmLeft.x survives live animation")
	_check((fore_l.position - fore_local).length() < 0.001,
		"animation compatibility: child ForearmLeft local transform untouched (offset propagates via hierarchy)")
	_check(fore_l.global_position.x - fore_world_before.x < -0.15,
		"animation compatibility: forearm world position follows the widened shoulder")
	_check(_close(arm_r.position.x, arm_r_x, POS_TOL),
		"animation compatibility: offset is per-joint, opposite arm unaffected")
	_check(_finite(arm_l.rotation),
		"animation compatibility: articulation still live on the offset joint (rotation finite)")


func _finish() -> void:
	if _failures == 0:
		print("All mecha_joint_alignment_verify tests passed (checks=%d)." % _checks)
		get_tree().quit(0)
	else:
		print("mecha_joint_alignment_verify failed with %d error(s) of %d checks." % [_failures, _checks])
		get_tree().quit(1)
