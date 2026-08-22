extends Node3D

## Verification test for Live Procedural Armor Damage Shader Overlays.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DAMAGE_VIS_OK: %s" % msg)
	else:
		_fails += 1
		print("DAMAGE_VIS_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Live Armor Damage Visuals Verification ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var hs = mecha.get_node_or_null("HealthSystem")
	_check(hs != null, "HealthSystem exists on Mecha")

	var dmg_vis = hs.damage_visuals
	_check(dmg_vis != null, "ArmorDamageVisuals instantiated on HealthSystem")

	var pmm = mecha.get_node_or_null("PartMeshManager")
	_check(pmm != null, "PartMeshManager exists")

	# Check that body armor has material_overlay attached
	var body_entry: Dictionary = pmm.slot_meshes.get("body", {})
	var body_armor: Node3D = body_entry.get("armor")
	_check(body_armor != null, "Body armor container exists")

	var found_overlay := false
	for child in body_armor.get_children():
		if child is MeshInstance3D and child.material_overlay != null:
			found_overlay = true
			break
	_check(found_overlay, "Body armor MeshInstance3D has material_overlay assigned")

	# Inner FRAME meshes carry the crack overlay too (the skeleton is exposed
	# once the armor plate breaks, so it needs the same damage material)
	var body_frame: Node3D = body_entry.get("frame")
	var frame_found := false
	if body_frame != null:
		for child in body_frame.get_children():
			if child is MeshInstance3D and child.material_overlay != null:
				frame_found = true
				break
	_check(frame_found, "Body inner-frame MeshInstance3D has material_overlay assigned")

	# Simulate 50% damage to body (armor takes the hit first)
	hs.take_damage_to_part("body", 50.0, "kinetic")
	await get_tree().process_frame

	var slot_data: Dictionary = dmg_vis._slot_overlays.get("body", {})
	var armor_mat: ShaderMaterial = slot_data.get("armor")
	_check(armor_mat != null, "Armor crack ShaderMaterial found for body slot")

	var dmg_val: float = float(armor_mat.get_shader_parameter("damage_amount"))
	_check(dmg_val > 0.0, "Armor crack 'damage_amount' updated on health loss (current: %.2f)" % dmg_val)

	# Frame layer separation: the skeleton must stay pristine while its
	# armor plate still holds, and only scar up when the frame itself is hit.
	var frame_mat: ShaderMaterial = slot_data.get("frame")
	_check(frame_mat != null and frame_mat != armor_mat, "Body frame has its own independent crack material")
	if frame_mat:
		var f_val: float = float(frame_mat.get_shader_parameter("damage_amount"))
		_check(f_val == 0.0, "Frame stays clean while its armor plate still holds (current: %.2f)" % f_val)

	dmg_vis.update_slot_layer_damage("body", "frame", 0.5)
	await get_tree().process_frame
	var f_val2: float = float(frame_mat.get_shader_parameter("damage_amount"))
	_check(absf(f_val2 - 0.5) < 0.01, "Frame cracks appear once the frame itself takes damage (%.2f)" % f_val2)

	print("--- Armor Damage Visuals Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_ARMOR_DAMAGE_VISUALS_TESTS_PASSED")
