extends Node3D

## Verification test for Dual-Segment Articulated Mesh Support & Smart Auto-Split.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DUAL_SEG_OK: %s" % msg)
	else:
		_fails += 1
		print("DUAL_SEG_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Dual-Segment Articulated Mesh Verification ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists on Mecha")

	# 1. Test ArmorPart with explicit mesh_scene + mesh_scene_lower
	var upper_packed := PackedScene.new()
	var upper_node := MeshInstance3D.new()
	upper_node.name = "CustomUpperMesh"
	upper_packed.pack(upper_node)

	var lower_packed := PackedScene.new()
	var lower_node := MeshInstance3D.new()
	lower_node.name = "CustomLowerMesh"
	lower_packed.pack(lower_node)

	var part := ArmorPart.new()
	part.part_name = "Articulated Arm"
	part.slot_id = "arm_left"
	part.mesh_scene = upper_packed
	part.mesh_scene_lower = lower_packed

	pmm.initialize_slot("arm_left", part, false, false)

	var left_arm_meshes = pmm.slot_meshes.get("arm_left", {})
	var armor_upper: Node3D = left_arm_meshes.get("armor")
	var armor_lower: Node3D = left_arm_meshes.get("armor_lower")

	_check(armor_upper != null and armor_upper.get_node_or_null("CustomUpperMesh") != null, "Upper custom mesh attached to Upper Arm")
	_check(armor_lower != null and armor_lower.get_node_or_null("CustomLowerMesh") != null, "Lower custom mesh attached to Forearm")

	# 2. Test Smart Auto-Split on a single scene containing Upper and Lower sub-nodes
	var combined_root := Node3D.new()
	var sub_upper := MeshInstance3D.new()
	sub_upper.name = "Upper"
	combined_root.add_child(sub_upper)
	sub_upper.owner = combined_root

	var sub_lower := MeshInstance3D.new()
	sub_lower.name = "Forearm_Armor"
	combined_root.add_child(sub_lower)
	sub_lower.owner = combined_root

	var combined_packed := PackedScene.new()
	combined_packed.pack(combined_root)

	var split_part := ArmorPart.new()
	split_part.part_name = "Auto Split Arm"
	split_part.slot_id = "arm_right"
	split_part.mesh_scene = combined_packed

	pmm.initialize_slot("arm_right", split_part, false, false)

	var right_arm_meshes = pmm.slot_meshes.get("arm_right", {})
	var r_armor_upper: Node3D = right_arm_meshes.get("armor")
	var r_armor_lower: Node3D = right_arm_meshes.get("armor_lower")

	_check(r_armor_upper != null and r_armor_upper.get_child_count() > 0, "Upper segment attached to Upper Arm container")
	_check(r_armor_lower != null and r_armor_lower.get_node_or_null("Forearm_Armor") != null, "Smart Auto-Split detected 'Forearm_Armor' and reparented to Forearm joint")

	print("--- Dual-Segment Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_DUAL_SEGMENT_MESH_TESTS_PASSED")
