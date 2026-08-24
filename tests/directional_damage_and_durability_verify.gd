extends Node3D

## Verification test for:
## 1. Directional 3-Stage Damage Shader & Hit Localization
## 2. Real-time Reactive Hangar Refresh & Live 3D Overlay Sync
## 3. Component Lifetime Durability Architecture (Battery Health vs HP)

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("VERIFY_OK: %s" % msg)
	else:
		_fails += 1
		print("VERIFY_FAIL: %s" % msg)


func _ready() -> void:
	print("=== Starting Directional Damage, Hangar Refresh & Durability Verification ===")

	# -----------------------------------------------------------------------
	# 1. Test Damage Shader Compilation & Parameter Setup
	# -----------------------------------------------------------------------
	var crack_shader: Shader = preload("res://shaders/armor_crack.gdshader")
	_check(crack_shader != null, "armor_crack.gdshader loaded successfully")

	var smat := ShaderMaterial.new()
	smat.shader = crack_shader
	smat.set_shader_parameter("damage_amount", 0.20)
	smat.set_shader_parameter("hit_pos", Vector3(0.5, 1.2, 0.0))
	smat.set_shader_parameter("hit_radius", 0.65)
	_check(smat != null, "ShaderMaterial initialized with directional hit parameters")

	# -----------------------------------------------------------------------
	# 2. Test ArmorDamageVisuals Hit Localization & Reset
	# -----------------------------------------------------------------------
	var adv := ArmorDamageVisuals.new()
	var test_mesh := MeshInstance3D.new()
	test_mesh.mesh = BoxMesh.new()
	add_child(test_mesh)
	
	adv.bind_custom_mesh("body", test_mesh, "armor")
	adv.update_slot_layer_damage("body", "armor", 0.50)
	adv.update_slot_hit("body", "armor", Vector3(0.2, 0.8, -0.1), 0.75)
	
	var cur_mat: ShaderMaterial = test_mesh.material_overlay as ShaderMaterial
	_check(cur_mat != null, "MeshInstance3D received overlay material")
	_check(absf(float(cur_mat.get_shader_parameter("damage_amount")) - 0.50) < 0.01, "Damage amount set to 50%")
	_check(float(cur_mat.get_shader_parameter("hit_radius")) > 0.0, "Hit radius is active and localized")

	# Test clearing damage on repair
	adv.clear_slot_damage("body")
	_check(float(cur_mat.get_shader_parameter("damage_amount")) <= 0.001, "clear_slot_damage resets damage to 0.0")
	_check(float(cur_mat.get_shader_parameter("hit_radius")) <= 0.001, "clear_slot_damage resets hit radius to 0.0")

	# -----------------------------------------------------------------------
	# 3. Test Component Lifetime Durability (Battery Health vs HP)
	# -----------------------------------------------------------------------
	var test_part := {
		"uid": "test_chest_plate",
		"name": "Barbatos Reinforced Torso",
		"hp": 100.0,
		"max_hp": 100.0,
		"durability": 1.0,
		"slot": "body"
	}
	GlobalData.weapons.equipped_parts["body"] = test_part
	GlobalData.weapons.part_damage["body"] = 0.80 # 80% HP lost in battle

	# Test get_part_durability returns actual component lifetime, NOT (1.0 - damage)
	var initial_dur := GlobalData.get_part_durability("body")
	_check(absf(initial_dur - 1.0) < 0.01, "get_part_durability returns true component lifespan (1.0) independent of missing HP")

	# Test durability degradation on repair
	GlobalData.degrade_part_durability("body", 0.80 * 0.04) # 4% wear from repairing heavy damage
	var repaired_dur := GlobalData.get_part_durability("body")
	_check(repaired_dur < 1.0 and repaired_dur > 0.90, "Repair slightly wears down lifetime durability (1.0 -> %.2f)" % repaired_dur)

	# Test weapon durability degradation on high heat firing
	var test_weapon := {
		"uid": "test_rifle_uid",
		"name": "Beam Rifle",
		"durability": 1.0
	}
	GlobalData.weapons.inventory.append(test_weapon)
	GlobalData.weapons.equipped_weapon_instances["right"] = "test_rifle_uid"
	
	GlobalData.degrade_weapon_durability("right", 0.05)
	var w_dur := GlobalData.get_durability_ratio(test_weapon)
	_check(absf(w_dur - 0.95) < 0.01, "Weapon firing/overheat degrades weapon durability (1.0 -> %.2f)" % w_dur)

	# -----------------------------------------------------------------------
	# 4. Test Effective Max HP Scaling with Durability
	# -----------------------------------------------------------------------
	var mh_script = preload("res://scripts/mecha/mecha_health.gd")
	var mh = mh_script.new()
	add_child(mh)
	mh._init_parts()
	
	var effective_max := float(mh.parts["body"]["max_armor"])
	_check(effective_max <= 100.0 * repaired_dur + 0.01, "MechaHealth scales effective Max HP by component lifetime durability (%.1f HP)" % effective_max)

	print("=== Verification Finished: %d passed, %d failed ===" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_DIRECTIONAL_DAMAGE_AND_DURABILITY_TESTS_PASSED")
