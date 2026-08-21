extends Node3D

## Mounts modules in local space under one of the six Mecha body sections.
# Re-export GlobalData.MECHA_SLOTS for local convenience.
const BODY_SLOTS: Array[String] = GlobalData.MECHA_SLOTS
var mounted_nodes: Dictionary = {}

func _ready() -> void:
	call_deferred("rebuild_from_global_data")

func rebuild_from_global_data() -> void:
	for node in mounted_nodes.values():
		if is_instance_valid(node): node.queue_free()
	mounted_nodes.clear()
	for attachment in GlobalData.weapons.attachments: mount_attachment(attachment)

func mount_attachment(data: Dictionary) -> Node3D:
	var slot := str(data.get("slot", ""))
	if slot not in BODY_SLOTS: return null
	var parent := _get_slot_node(slot)
	if parent == null: return null
	var node := Node3D.new()
	node.name = "Attachment_%s" % str(data.get("id", "module"))
	parent.add_child(node)
	node.position = _vector_from_data(data.get("position", Vector3.ZERO))
	node.rotation = _vector_from_data(data.get("rotation", Vector3.ZERO))
	node.scale = _vector_from_data(data.get("scale", Vector3.ONE))
	node.set_meta("attachment_id", str(data.get("id", "")))
	node.set_meta("attachment_slot", slot)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _vector_from_data(data.get("size", Vector3(0.35, 0.35, 0.35)))
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = data.get("color", Color(0.2, 0.7, 1.0))
	material.metallic = 0.75
	material.roughness = 0.25
	mesh.material_override = material
	node.add_child(mesh)
	mounted_nodes[str(data.get("id", "module"))] = node
	return node

func update_attachment_transform(attachment_id: String, position: Vector3, rotation: Vector3 = Vector3.ZERO) -> bool:
	for data in GlobalData.weapons.attachments:
		if str(data.get("id", "")) == attachment_id:
			data["position"] = position
			data["rotation"] = rotation
			var node = mounted_nodes.get(attachment_id)
			if node and is_instance_valid(node):
				node.position = position
				node.rotation = rotation
			return true
	return false

func get_attachment_capacity(slot: String) -> float:
	var info := LoadoutSystem.get_chassis_stats()
	var capacities: Dictionary = info.get("attachment_capacity", {})
	return float(capacities.get(slot, 0.0))

func get_slot_attachment_weight(slot: String, excluding_id: String = "") -> float:
	var result := 0.0
	for data in GlobalData.weapons.attachments:
		if data.get("slot", "") == slot and data.get("id", "") != excluding_id:
			result += float(data.get("weight", 0.0))
	return result

func can_mount(data: Dictionary) -> bool:
	var slot := str(data.get("slot", ""))
	if slot not in BODY_SLOTS: return false
	return get_slot_attachment_weight(slot, str(data.get("id", ""))) + float(data.get("weight", 0.0)) <= get_attachment_capacity(slot)

func _get_slot_node(slot: String) -> Node3D:
	var node_name: String = GlobalData.SLOT_TO_NODE.get(slot, "")
	if node_name == "":
		return null
	return get_parent().get_node_or_null(node_name)

func _vector_from_data(value) -> Vector3:
	if value is Vector3: return value
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
