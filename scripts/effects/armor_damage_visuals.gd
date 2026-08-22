class_name ArmorDamageVisuals
extends RefCounted

## ---------------------------------------------------------------------------
## ARMOR DAMAGE VISUALS MANAGER
##
## Manages procedural damage shader overlays for mech body parts.
## ARMOR and FRAME get INDEPENDENT crack materials per slot:
##   - the armor plate cracks up as its own HP drops,
##   - the inner frame stays pristine until its armor breaks and the frame
##     itself starts taking hits.
## Each material generates a unique random noise seed so crack patterns never
## repeat, and damage_amount tracks real-time health loss of that layer.
## ---------------------------------------------------------------------------

const DAMAGE_SHADER := preload("res://shaders/armor_crack.gdshader")

const LAYER_ARMOR := "armor"
const LAYER_FRAME := "frame"

var health_system: Node = null
var mecha_root: Node3D = null

# slot_name -> {
#   "armor": ShaderMaterial, "frame": ShaderMaterial,
#   "armor_meshes": Array[MeshInstance3D], "frame_meshes": Array[MeshInstance3D],
# }
var _slot_overlays: Dictionary = {}


func _init(hs: Node = null) -> void:
	if hs:
		attach_to_health_system(hs)


func attach_to_health_system(hs: Node) -> void:
	health_system = hs
	mecha_root = hs.get_parent() as Node3D

	if hs.has_signal("health_changed"):
		if not hs.health_changed.is_connected(_on_health_changed):
			hs.health_changed.connect(_on_health_changed)

	_setup_mesh_overlays()


func _setup_mesh_overlays() -> void:
	if mecha_root == null:
		return

	# 1. Connect to PartMeshManager if present. Armor containers bind to the
	# armor crack material, inner-frame containers to the frame one. Slots are
	# usually rebuilt LATER by PartMeshManager.initialize_slot(), which calls
	# register_slot_container() itself — this pass only catches containers
	# that already exist right now.
	var pmm = mecha_root.get_node_or_null("PartMeshManager")
	if pmm and "slot_meshes" in pmm:
		for slot in pmm.slot_meshes:
			var data: Dictionary = pmm.slot_meshes[slot]
			for key in ["armor", "armor_lower"]:
				var container: Node3D = data.get(key)
				if container:
					register_slot_container(slot, container, LAYER_ARMOR)
			for key in ["frame", "frame_lower"]:
				var container: Node3D = data.get(key)
				if container:
					register_slot_container(slot, container, LAYER_FRAME)
		return

	# 2. Fallback for mechs WITHOUT a PartMeshManager (primitive-built dummies):
	# bind each standard section subtree to the slot's armor material.
	var slot_node_map := {
		"head": ["Head"],
		"body": ["Body"],
		"arm_left": ["ArmLeft"],
		"arm_right": ["ArmRight"],
		"leg_left": ["LegLeft"],
		"leg_right": ["LegRight"],
	}

	for slot in slot_node_map:
		for path in slot_node_map[slot]:
			var node = mecha_root.get_node_or_null(path)
			if node:
				register_slot_container(slot, node, LAYER_ARMOR)


func _get_or_create_layer_entry(slot: String) -> Dictionary:
	if not _slot_overlays.has(slot):
		_slot_overlays[slot] = {
			LAYER_ARMOR: null,
			LAYER_FRAME: null,
			"armor_meshes": [] as Array[MeshInstance3D],
			"frame_meshes": [] as Array[MeshInstance3D],
		}
	return _slot_overlays[slot]


func _get_or_create_slot_mat(slot: String, layer: String) -> ShaderMaterial:
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	if entry.get(layer) != null:
		return entry[layer]

	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	# Unique random seed per slot AND layer so armor/frame crack patterns
	# never repeat or line up with each other.
	var random_seed := Vector3(
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0)
	)
	mat.set_shader_parameter("noise_offset", random_seed)
	mat.set_shader_parameter("damage_amount", 0.0)
	entry[layer] = mat
	return mat


## Binds every MeshInstance3D under `container` to the slot's crack material
## for the given surface layer ("armor" plates or "frame" skeleton).
func register_slot_container(slot: String, container: Node, layer: String = LAYER_ARMOR) -> void:
	if container == null or not is_instance_valid(container):
		return
	layer = LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR

	var mat := _get_or_create_slot_mat(slot, layer)
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	var mesh_list: Array = entry[layer + "_meshes"]

	var meshes: Array[MeshInstance3D] = []
	_gather_meshes_recursive(container, meshes)
	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = mat
			if not mesh_list.has(mesh):
				mesh_list.append(mesh)


func _gather_meshes_recursive(node: Node, out_meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		if not out_meshes.has(node):
			out_meshes.append(node)
	for child in node.get_children():
		_gather_meshes_recursive(child, out_meshes)


## Legacy single-layer setter — updates the slot's ARMOR plate damage.
func update_slot_damage(slot: String, damage_ratio: float) -> void:
	update_slot_layer_damage(slot, LAYER_ARMOR, damage_ratio)


## Sets the crack intensity of one surface layer (0.0 = pristine, 1.0 = wrecked).
func update_slot_layer_damage(slot: String, layer: String, damage_ratio: float) -> void:
	layer = LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR
	if _slot_overlays.has(slot):
		var mat = _slot_overlays[slot].get(layer)
		if mat != null:
			mat.set_shader_parameter("damage_amount", clampf(damage_ratio, 0.0, 1.0))


func _on_health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	var damage_ratio := 1.0 - clampf(current_hp / max_hp, 0.0, 1.0)
	# Route by surface layer: armor HP drives the plate's cracks, frame HP the
	# skeleton's — so the frame only scars up AFTER the armor has broken.
	update_slot_layer_damage(slot_name, layer, damage_ratio)


## Helper to apply damage overlays to custom models / dynamic meshes
func bind_custom_mesh(slot: String, mesh_node: MeshInstance3D, layer: String = LAYER_ARMOR) -> void:
	if mesh_node == null:
		return
	var mat := _get_or_create_slot_mat(slot, LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR)
	mesh_node.material_overlay = mat
	var entry: Dictionary = _get_or_create_layer_entry(slot)
	var mesh_list: Array = entry[(LAYER_FRAME if str(layer).to_lower() == LAYER_FRAME else LAYER_ARMOR) + "_meshes"]
	if not mesh_list.has(mesh_node):
		mesh_list.append(mesh_node)
