extends Node3D

## Verification test for Durability Degradation, Scrap Metal Shader, and Cloth Wrap System.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DURABILITY_OK: %s" % msg)
	else:
		_fails += 1
		print("DURABILITY_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Durability Degradation & Scrap Materials Verification ---")

	# 1. Test Shader Resources
	var scrap_shader: Shader = preload("res://shaders/scrap_metal.gdshader")
	_check(scrap_shader != null, "scrap_metal.gdshader loaded successfully")

	var cloth_shader: Shader = preload("res://shaders/cloth_wrap.gdshader")
	_check(cloth_shader != null, "cloth_wrap.gdshader loaded successfully")

	# 2. Test ArmorSystem Durability Degradation
	var test_inst := {
		"uid": "test_plate_01",
		"name": "Heavy Test Plate",
		"durability": 1.0,
		"equipped": true,
		"slot": "body",
	}
	GlobalData.weapons.armor_inventory.append(test_inst)
	GlobalData.weapons.equipped_parts["body"] = test_inst

	# Degrade 15% on armor break
	var d1 = ArmorSystem.degrade_equipped_armor("body", 0.15)
	_check(absf(d1 - 0.85) < 0.001, "Armor break degrades durability by 15%% (1.0 -> %.2f)" % d1)

	# Degrade 10% on emergency scrap patch
	var d2 = ArmorSystem.degrade_equipped_armor("body", 0.10)
	_check(absf(d2 - 0.75) < 0.001, "Emergency patch degrades durability by 10%% (0.85 -> %.2f)" % d2)

	# Excessive wear clamps to 0.0 and triggers permadeath shattering
	var d_floor = ArmorSystem.degrade_equipped_armor("body", 0.90)
	_check(absf(d_floor - 0.0) < 0.001, "Durability clamps to 0.0 on fatal degradation (was %.2f)" % d_floor)
	_check(GlobalData.weapons.equipped_parts.get("body", {}).is_empty(), "Armor shatters and is unequipped at 0.0 durability")
	var in_inv := false
	for item in GlobalData.weapons.armor_inventory:
		if item is Dictionary and item.get("uid", "") == "test_plate_01":
			in_inv = true
			break
	_check(not in_inv, "Shattered armor is permanently removed from inventory")

	# 3. Test Scrap Primitive & Cloth Wrap Mesh Generation
	var pmm_script = preload("res://scripts/mecha/part_mesh_manager.gd")
	var pmm = pmm_script.new()
	add_child(pmm)

	var scrap_mesh = pmm._build_scrap_primitive_mesh("box")
	_check(scrap_mesh is BoxMesh, "Scrap primitive 'box' built as BoxMesh")

	var cloth_mesh = pmm._build_scrap_primitive_mesh("wrap")
	_check(cloth_mesh is TorusMesh, "Cloth wrap primitive 'wrap' built as TorusMesh")

	print("--- Durability & Material Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_DURABILITY_DEGRADATION_TESTS_PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)
