class_name ArmorDamageVisuals
extends RefCounted

## ---------------------------------------------------------------------------
## ARMOR DAMAGE VISUALS MANAGER
##
## Manages procedural damage shader overlays for mech body parts.
## Generates unique random noise seeds for each part so crack patterns never
## repeat, and updates damage_amount based on real-time health loss.
## ---------------------------------------------------------------------------

const DAMAGE_SHADER := preload("res://shaders/armor_crack.gdshader")

var health_system: Node = null
var mecha_root: Node3D = null

# slot_name -> { "material": ShaderMaterial, "meshes": Array[MeshInstance3D] }
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

	# 1. Connect to PartMeshManager if present (armor AND inner frame: the
	# frame is exposed once the armor plate breaks, so it needs cracks too)
	var pmm = mecha_root.get_node_or_null("PartMeshManager")
	if pmm and "slot_meshes" in pmm:
		for slot in pmm.slot_meshes:
			var data: Dictionary = pmm.slot_meshes[slot]
			for key in ["armor", "armor_lower", "frame", "frame_lower"]:
				var container: Node3D = data.get(key)
				if container:
					register_slot_container(slot, container)

	# 2. Collect and bind for standard mecha_base.tscn nodes as well
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
				register_slot_container(slot, node)


func _get_or_create_slot_mat(slot: String) -> ShaderMaterial:
	if _slot_overlays.has(slot):
		return _slot_overlays[slot].get("material")
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	var random_seed := Vector3(
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0)
	)
	mat.set_shader_parameter("noise_offset", random_seed)
	mat.set_shader_parameter("damage_amount", 0.0)
	_slot_overlays[slot] = {
		"material": mat,
		"meshes": [] as Array[MeshInstance3D],
	}
	return mat


func register_slot_container(slot: String, container: Node) -> void:
	if container == null or not is_instance_valid(container):
		return
	var mat := _get_or_create_slot_mat(slot)
	var entry: Dictionary = _slot_overlays[slot]
	var mesh_list: Array = entry.get("meshes", [])

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


func update_slot_damage(slot: String, damage_ratio: float) -> void:
	if _slot_overlays.has(slot):
		var mat: ShaderMaterial = _slot_overlays[slot].get("material")
		if mat:
			mat.set_shader_parameter("damage_amount", clampf(damage_ratio, 0.0, 1.0))


func _on_health_changed(slot_name: String, _layer: String, current_hp: float, max_hp: float) -> void:
	if max_hp <= 0.0:
		return
	var damage_ratio := 1.0 - clampf(current_hp / max_hp, 0.0, 1.0)
	update_slot_damage(slot_name, damage_ratio)


## Helper to apply damage overlays to custom models / dynamic meshes
func bind_custom_mesh(slot: String, mesh_node: MeshInstance3D) -> void:
	if mesh_node == null:
		return
	var mat := _get_or_create_slot_mat(slot)
	mesh_node.material_overlay = mat
	var mesh_list: Array = _slot_overlays[slot].get("meshes", [])
	if not mesh_list.has(mesh_node):
		mesh_list.append(mesh_node)
