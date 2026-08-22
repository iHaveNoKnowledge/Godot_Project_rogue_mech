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

	# Simulate 50% damage to body
	hs.apply_damage_to_slot("body", 50.0, "kinetic")
	await get_tree().process_frame

	var slot_data: Dictionary = dmg_vis._slot_overlays.get("body", {})
	var mat: ShaderMaterial = slot_data.get("material")
	_check(mat != null, "ShaderMaterial found for body slot")

	var dmg_val: float = float(mat.get_shader_parameter("damage_amount"))
	_check(dmg_val > 0.0, "Shader parameter 'damage_amount' updated on health loss (current: %.2f)" % dmg_val)

	print("--- Armor Damage Visuals Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_ARMOR_DAMAGE_VISUALS_TESTS_PASSED")
