class_name BackpackVisualFactory
extends RefCounted

## ---------------------------------------------------------------------------
## BACKPACK VISUAL FACTORY — derived visual representation of first-class
## Backpack equipment (cargo / booster / combat).
##
## CONTRACT (hardpoint ownership audit):
##   - Loadout.equipped_backpack (BackpackSystem) is the SOLE authority.
##   - This factory is DERIVED-ONLY: it reads the equipped dict and builds
##     primitive meshes under the stable Body/Backpack socket. It never writes
##     loadout, frame, chassis, weight, damage, or save state, and it creates
##     zero collision objects.
##   - Procedural primitives follow the established project precedent
##     (WeaponVisualFactory weapon models, DropTankVisuals canisters,
##     PartMeshManager inner frames): deterministic per-definition geometry,
##     not placeholder art. Each backpack type maps to exactly one silhouette.
##   - Idempotent: repeated mounts reuse one mount node and replace its model,
##     so equip/replace/unequip/load/spawn cycles can never pile up visuals.
## ---------------------------------------------------------------------------

const MOUNT_NODE_NAME := "BackpackVisual"

# Fallback root offset when Body/Backpack is absent (non-MechaBase scenes never
# carry backpack equipment, so this path only keeps the call total).
const FALLBACK_POS := Vector3(0.0, 1.85, 0.65)


## Mounts (or clears) the backpack visual on a mecha. `bp` is the equipped
## backpack dict ({} = unequipped → empty mount, zero visuals). Returns the
## mount node. Safe to call on every visual refresh seam.
static func mount_backpack(mecha: Node3D, bp: Dictionary, node_name: String = MOUNT_NODE_NAME) -> Node3D:
	if mecha == null:
		return null
	var socket := mecha.get_node_or_null("Body/Backpack") as Node3D
	var parent: Node3D = socket if socket != null else mecha
	var mount := parent.get_node_or_null(node_name) as Node3D
	if mount == null or not mount.is_inside_tree() or mount.is_queued_for_deletion():
		if mount != null and mount.is_inside_tree():
			parent.remove_child(mount)
		mount = Node3D.new()
		mount.name = node_name
		parent.add_child(mount)
	if socket == null:
		mount.position = FALLBACK_POS
	else:
		mount.position = Vector3.ZERO
	mount.rotation = Vector3.ZERO
	for child in mount.get_children():
		child.queue_free()
	if bp.is_empty():
		return mount
	mount.add_child(build(bp))
	return mount


## Builds the deterministic per-type model for a backpack definition.
## Unknown/missing types fall back to a generic container in the def color —
## the call never fails and never substitutes another backpack's identity.
static func build(bp: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "BackpackModel"
	var btype := str(bp.get("type", "cargo")).to_lower()
	var color := _resolve_color(bp)
	match btype:
		"booster":
			_build_booster(root, color)
		"combat":
			_build_combat(root, color)
		_:
			_build_cargo(root, color)
	return root


## Reads the definition color in every shape it can arrive in: live Color
## instances, post-save "(r, g, b, a)" strings (JSON flattens Colors; the save
## schema intentionally stores them raw, cf. armor color healing), and
## {r,g,b,a} dicts. Never fails; falls back to neutral steel gray.
static func _resolve_color(bp: Dictionary) -> Color:
	var raw = bp.get("color", null)
	if raw is Color:
		return raw
	if raw is Dictionary:
		return Color(float(raw.get("r", 0.5)), float(raw.get("g", 0.5)), float(raw.get("b", 0.55)), float(raw.get("a", 1.0)))
	if raw is String:
		var clean := str(raw).replace("(", "").replace(")", "").replace("Color", "").strip_edges()
		var parts := clean.split(",")
		if parts.size() >= 3:
			var alpha := 1.0
			if parts.size() >= 4:
				alpha = float(parts[3])
			return Color(float(parts[0]), float(parts[1]), float(parts[2]), alpha)
	return Color(0.5, 0.5, 0.55)


## Cargo Backpack: container box + lid stripe (hauls pack capacity).
static func _build_cargo(root: Node3D, color: Color) -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.70, 0.35)
	body.mesh = box
	body.material_override = _mat(color, 0.5, 0.55)
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lid_box := BoxMesh.new()
	lid_box.size = Vector3(0.57, 0.10, 0.37)
	lid.mesh = lid_box
	lid.position = Vector3(0.0, 0.32, 0.0)
	lid.material_override = _mat(color.darkened(0.35), 0.7, 0.35)
	root.add_child(lid)


## Booster Pack: twin thruster cylinders + dark caps (dash/roller drive).
static func _build_booster(root: Node3D, color: Color) -> void:
	for x in [-0.22, 0.22]:
		var tube := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.13
		cyl.bottom_radius = 0.15
		cyl.height = 0.80
		tube.mesh = cyl
		tube.position = Vector3(x, 0.0, 0.0)
		tube.material_override = _mat(color, 0.6, 0.4)
		root.add_child(tube)
		var cap := MeshInstance3D.new()
		var cap_cyl := CylinderMesh.new()
		cap_cyl.top_radius = 0.15
		cap_cyl.bottom_radius = 0.10
		cap_cyl.height = 0.12
		cap.mesh = cap_cyl
		cap.position = Vector3(x, -0.46, 0.0)
		cap.material_override = _mat(Color(0.15, 0.15, 0.17), 0.8, 0.3)
		root.add_child(cap)


## Combat Pack: armor plate + darker inset (mounted protection + cooling).
static func _build_combat(root: Node3D, color: Color) -> void:
	var plate := MeshInstance3D.new()
	var plate_box := BoxMesh.new()
	plate_box.size = Vector3(0.60, 0.75, 0.18)
	plate.mesh = plate_box
	plate.material_override = _mat(color, 0.7, 0.35)
	root.add_child(plate)
	var inset := MeshInstance3D.new()
	var inset_box := BoxMesh.new()
	inset_box.size = Vector3(0.44, 0.55, 0.06)
	inset.mesh = inset_box
	inset.position = Vector3(0.0, 0.0, 0.10)
	inset.material_override = _mat(color.darkened(0.45), 0.8, 0.3)
	root.add_child(inset)


static func _mat(albedo: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.metallic = metallic
	mat.roughness = roughness
	return mat
