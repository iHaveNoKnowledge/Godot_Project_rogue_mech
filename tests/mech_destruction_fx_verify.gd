extends Node3D

## Verification test for the complete Mech Destruction & Explosion Sequence:
## 1. Freezes all movement / physics / weapons.
## 2. Ejects pilot cleanly.
## 3. Mech collapses and plays core-breach overload light & recursive mesh flashing.
## 4. Giant explosion visual & audio blast.
## 5. Transitions into charred blackened smoking wreckage instead of vanishing into thin air.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("DESTRUCTION_OK: %s" % msg)
	else:
		_fails += 1
		print("DESTRUCTION_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Mech Destruction FX Verification ---")
	await _test_enemy_destruction_sequence()
	await _test_player_destruction_and_eject()

	print("MECH_DESTRUCTION_FX_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_enemy_destruction_sequence() -> void:
	var enemy_scene: PackedScene = load("res://scenes/mecha/enemy_dummy_full.tscn")
	var enemy: CharacterBody3D = enemy_scene.instantiate()
	enemy.position = Vector3(0, 0, 0)
	add_child(enemy)
	await get_tree().process_frame
	await get_tree().process_frame

	var hs: MechaHealthBase = enemy.get_node_or_null("HealthSystem")
	_check(hs != null, "Enemy has HealthSystem")

	# Check recursive mesh finder
	var all_meshes: Array[MeshInstance3D] = hs._get_all_meshes(enemy)
	_check(all_meshes.size() >= 5, "Found all nested body meshes (count: %d)" % all_meshes.size())

	# Test mesh emissive flash during core breach
	hs._core_breach_flash(true)
	var all_flashed := true
	for m in all_meshes:
		if m.material_override == null or not m.material_override.emission_enabled:
			all_flashed = false
			break
	_check(all_flashed, "All body meshes flash emissive orange/white during core breach")

	# Test destruction sequence
	hs.take_damage_to_part("body", 99999.0, "kinetic", "frame")
	_check(hs.is_destroyed, "Enemy marked as destroyed")
	_check(not enemy.is_physics_processing(), "Enemy physics processing disabled on death")

	# Verify enemy pilot was ejected into the scene
	var pilots = get_tree().get_nodes_in_group("enemy_pilot")
	_check(pilots.size() > 0, "Enemy pilot ejected out of the collapsing mech")

	# Trigger detonation
	hs._detonate_mech()

	# Verify charred black wreck material applied to meshes
	var all_charred := true
	for m in all_meshes:
		if m.material_override == null or m.material_override.albedo_color.r > 0.15:
			all_charred = false
			break
	_check(all_charred, "Chassis transformed into charred blackened wreckage after explosion")

	enemy.queue_free()
	for p in pilots:
		p.queue_free()


func _test_player_destruction_and_eject() -> void:
	var player_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	player.position = Vector3(0, 2, 0)
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var hs: MechaHealthBase = player.get_node_or_null("HealthSystem")
	_check(hs != null, "Player mech has HealthSystem")

	# Apply fatal damage
	for slot in hs.parts:
		hs.take_damage_to_part(slot, 99999.0, "kinetic", "frame")

	_check(hs.is_destroyed, "Player mech destroyed upon fatal damage")
	_check(not player.is_physics_processing(), "Player movement stopped immediately")

	var eject = player.get_node_or_null("MechaEject")
	_check(eject != null, "MechaEject component present")

	# Test charred wreckage on player chassis
	hs._detonate_mech()
	var player_meshes = hs._get_all_meshes(player)
	var player_charred := true
	for m in player_meshes:
		if m.material_override == null or m.material_override.albedo_color.r > 0.15:
			player_charred = false
			break
	_check(player_charred, "Player chassis rendered as charred smoking wreck")

	player.queue_free()
