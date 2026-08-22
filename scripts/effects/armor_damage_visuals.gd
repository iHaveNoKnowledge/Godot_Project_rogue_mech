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

	# Collect and bind for standard slots
	var slot_node_map := {
		"head": ["Head", "Head/HeadMesh", "Head/Visor"],
		"body": ["Body", "Body/BodyMesh", "Body/ChestPlate", "Body/Backpack"],
		"arm_left": ["ArmLeft", "ArmLeft/ShoulderLeft", "ArmLeft/UpperArmLeft", "ArmLeft/ForearmLeft", "ArmLeft/ForearmLeft/ArmLeftMesh"],
		"arm_right": ["ArmRight", "ArmRight/ShoulderRight", "ArmRight/UpperArmRight", "ArmRight/ForearmRight", "ArmRight/ForearmRight/ArmRightMesh"],
		"leg_left": ["LegLeft", "LegLeft/ThighLeft", "LegLeft/ShinLeft", "LegLeft/ShinLeft/LegLeftMesh", "LegLeft/ShinLeft/KneeLeft", "LegLeft/ShinLeft/FootLeft"],
		"leg_right": ["LegRight", "LegRight/ThighRight", "LegRight/ShinRight", "LegRight/ShinRight/LegRightMesh", "LegRight/ShinRight/KneeRight", "LegRight/ShinRight/FootRight"],
	}

	for slot in slot_node_map:
		var meshes: Array[MeshInstance3D] = []
		for path in slot_node_map[slot]:
			var node = mecha_root.get_node_or_null(path)
			if node is MeshInstance3D:
				meshes.append(node)
			elif node is Node3D:
				for child in node.get_children():
					if child is MeshInstance3D and not meshes.has(child):
						meshes.append(child)

		if not meshes.is_empty():
			_register_slot_meshes(slot, meshes)


func _register_slot_meshes(slot: String, meshes: Array[MeshInstance3D]) -> void:
	# Create a dedicated ShaderMaterial instance with a randomized noise seed
	var mat := ShaderMaterial.new()
	mat.shader = DAMAGE_SHADER
	var random_seed := Vector3(
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0)
	)
	mat.set_shader_parameter("noise_offset", random_seed)
	mat.set_shader_parameter("damage_amount", 0.0)

	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = mat

	_slot_overlays[slot] = {
		"material": mat,
		"meshes": meshes,
	}


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
	if not _slot_overlays.has(slot):
		_register_slot_meshes(slot, [mesh_node])
	else:
		var mat: ShaderMaterial = _slot_overlays[slot].get("material")
		mesh_node.material_overlay = mat
		var mesh_list: Array = _slot_overlays[slot].get("meshes", [])
		if not mesh_list.has(mesh_node):
			mesh_list.append(mesh_node)
