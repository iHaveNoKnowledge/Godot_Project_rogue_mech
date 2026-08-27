extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running durability_wear_material_verify ---")
	await _verify_armor_durability_wear()
	await _verify_weapon_durability_wear()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_armor_durability_wear() -> void:
	var mecha := Node3D.new()
	add_child(mecha)

	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = BoxMesh.new()
	mecha.add_child(mesh_node)

	var hs := Node.new()
	hs.name = "HealthSystem"
	mecha.add_child(hs)

	var adv := ArmorDamageVisuals.new(hs)
	adv.register_slot_container("body", mesh_node, "armor")

	# 1. Full Durability (1.0) -> wear = 0.0
	adv.update_slot_durability("body", "armor", 1.0)
	var mat = mesh_node.material_overlay as ShaderMaterial
	_check(mat != null, "material overlay created on mesh")
	_check(mat != null and is_equal_approx(float(mat.get_shader_parameter("wear_amount")), 0.0), "pristine 1.0 durability has 0.0 wear amount")

	# 2. Battle-worn Durability (0.35) -> wear = 0.65 (torch welds, rust, field repairs)
	adv.update_slot_durability("body", "armor", 0.35)
	_check(mat != null and is_equal_approx(float(mat.get_shader_parameter("wear_amount")), 0.65), "0.35 durability scales wear_amount to 0.65")

	mecha.queue_free()
	await get_tree().process_frame


func _verify_weapon_durability_wear() -> void:
	var mount := Node3D.new()
	var gun_mesh := MeshInstance3D.new()
	gun_mesh.mesh = CylinderMesh.new()
	mount.add_child(gun_mesh)
	add_child(mount)

	# Apply durability wear for a weapon at 50% durability
	WeaponVisualFactory.apply_durability_wear_to_node(mount, 0.5)

	var overlay = gun_mesh.material_overlay as ShaderMaterial
	_check(overlay != null, "weapon mesh receives durability wear shader overlay")
	_check(overlay != null and is_equal_approx(float(overlay.get_shader_parameter("wear_amount")), 0.5), "weapon at 50% durability has 0.5 wear amount")

	mount.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _failures == 0:
		print("All durability_wear_material_verify tests passed.")
		get_tree().quit(0)
	else:
		print("durability_wear_material_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
