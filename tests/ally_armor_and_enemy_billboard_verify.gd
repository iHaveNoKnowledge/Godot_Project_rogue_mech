extends Node3D

## Verification test for Ally Armor Breaking visual sync and Enemy Billboard Dual-Bar status.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("COMBAT_UI_OK: %s" % msg)
	else:
		_fails += 1
		print("COMBAT_UI_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Ally Armor and Enemy Billboard Verification ---")

	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")

	# 1. Test Ally Mech Armor Break Visuals
	var ally = mecha_scene.instantiate()
	ally.name = "AllyMecha"
	add_child(ally)

	await get_tree().physics_frame
	await get_tree().process_frame

	var hs_ally = ally.get_node_or_null("HealthSystem")
	var pmm_ally = ally.get_node_or_null("PartMeshManager")
	if hs_ally:
		hs_ally.is_player = false
	_check(hs_ally != null and pmm_ally != null, "Ally Mecha HealthSystem and PartMeshManager exist")

	# Equip armor and check initial state
	var arm_slot: Dictionary = pmm_ally.slot_meshes.get("arm_left", {})
	var armor_container: Node3D = arm_slot.get("armor")
	var frame_container: Node3D = arm_slot.get("frame")
	_check(armor_container != null and armor_container.visible, "Ally left arm armor is initially visible")

	# Break ally left arm armor (100 damage)
	hs_ally.take_damage_to_part("arm_left", 200.0, "kinetic")
	await get_tree().process_frame

	_check(hs_ally.is_armor_broken("arm_left"), "Ally arm_left armor is broken in HealthSystem")
	_check(not armor_container.visible, "Ally arm_left armor mesh is HIDDEN upon armor break")
	_check(frame_container.visible, "Ally arm_left inner frame mesh is VISIBLE upon armor break")

	# 2. Test Enemy Status Billboard Dual-Layer Bars
	var enemy = mecha_scene.instantiate()
	enemy.name = "EnemyMecha"
	add_child(enemy)

	await get_tree().physics_frame
	await get_tree().process_frame

	var hs_enemy = enemy.get_node_or_null("HealthSystem")
	if hs_enemy:
		hs_enemy.is_player = false
	var billboard_script = load("res://scripts/ui/enemy_status_billboard.gd")
	var billboard = billboard_script.new()
	add_child(billboard)
	billboard.setup_target(enemy)

	await get_tree().process_frame

	var body_block = billboard.part_blocks.get("body")
	_check(body_block != null, "Billboard body part block exists with dual-layer container")
	_check(body_block.has("armor") and body_block.has("frame"), "Billboard body block has armor and frame bars")

	# 1. Break enemy body armor completely (300 damage / 4.0 AC = 75 damage > 60 armor HP)
	hs_enemy.take_damage_to_part("body", 300.0, "kinetic")
	billboard._update_status()
	_check(hs_enemy.is_armor_broken("body"), "Enemy body armor is broken")

	# 2. Damage enemy body frame (20 damage on 40 max_frame = 50% HP -> should turn yellow)
	hs_enemy.take_damage_to_part("body", 20.0, "kinetic")
	billboard._update_status()

	var frame_bar: ColorRect = body_block["frame"]
	_check(frame_bar.color == billboard._color_frame_yellow, "Billboard frame bar turns yellow when frame is at 50% HP")

	# Destroy enemy completely
	hs_enemy.take_damage_to_part("body", 50.0, "kinetic")
	billboard._update_status()
	_check(billboard._is_fading, "Billboard enters fading state when enemy is destroyed")

	print("--- Combat UI Verification Finished: %d passed, %d failed ---" % [_checks - _fails, _fails])
	if _fails == 0:
		print("ALL_COMBAT_UI_TESTS_PASSED")
	get_tree().quit(0 if _fails == 0 else 1)
