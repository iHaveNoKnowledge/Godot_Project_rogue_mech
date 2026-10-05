extends Node
## ARM DESTRUCTION WEAPON DROP VERIFY
##
## Verifies:
## 1. Arm frame destruction triggers canonical weapon drop.
## 2. Weapon is unequipped from WeaponManager (hand set to null).
## 3. Weapon visual mesh is cleared from forearm mount (no stale floating weapon).
## 4. WeaponPickup is spawned in the world with the original weapon resource.
## 5. GlobalData loadout is synchronized.
## 6. Opposite hand remains intact and equipped.
## 7. No stale weapon ownership or duplicated weapons occur.

const MechaHealthScript = preload("res://scripts/mecha/mecha_health.gd")

var _fails := 0
var _checks := 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[WEAPON_DROP PASS] " + msg)
	else:
		_fails += 1
		printerr("[WEAPON_DROP FAIL] " + msg)


func _ready() -> void:
	print("=== RUNNING ARM DESTRUCTION WEAPON DROP VERIFY ===")
	_test_arm_destruction_weapon_drop()
	
	print("\n--- RESULTS: %d checks, %d failures ---" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_arm_destruction_weapon_drop() -> void:
	GlobalData.weapons.reset()
	
	# Instantiate Mecha Base
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha: Node3D = mecha_scene.instantiate()
	add_child(mecha)
	
	var wm = mecha.get_node_or_null("WeaponManager")
	var hs: MechaHealthBase = mecha.get_node_or_null("MechaHealth")
	
	_check(wm != null, "WeaponManager exists on Mecha")
	_check(hs != null, "MechaHealth exists on Mecha")
	
	# Equip two distinct weapons
	var rifle_res: WeaponPart = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	var blade_res: WeaponPart = load("res://resources/mech/stock/weapon_heat_blade.tres")
	
	wm.left_hand = rifle_res
	wm.right_hand = blade_res
	wm._update_weapon_visuals()
	wm.sync_loadout_to_global()
	
	_check(wm.left_hand == rifle_res, "Left hand equipped with Beam Rifle")
	_check(wm.right_hand == blade_res, "Right hand equipped with Heat Blade")
	
	var right_mount = mecha.get_node_or_null("ArmRight/ForearmRight/WeaponMesh_right")
	_check(right_mount != null and right_mount.get_child_count() > 0, "Right weapon mesh is mounted with visual children")
	
	var initial_pickup_count := get_tree().get_nodes_in_group("weapon_pickup").size()
	
	# Destroy right arm frame
	print("\n-- Inflicting lethal frame destruction to arm_right --")
	hs.parts["arm_right"]["armor_hp"] = 0.0
	hs.parts["arm_right"]["armor_broken"] = true
	hs.take_damage_to_part("arm_right", 500.0, "pierce")
	
	_check(hs.parts["arm_right"]["destroyed"] == true, "Right arm frame is destroyed")
	_check(wm.right_hand == null, "Right hand weapon unequipped from WeaponManager (right_hand == null)")
	_check(wm.left_hand == rifle_res, "Left hand weapon remains intact and equipped")
	
	# Check visual mount cleared
	var right_mount_after = mecha.get_node_or_null("ArmRight/ForearmRight/WeaponMesh_right")
	_check(right_mount_after == null or right_mount_after.get_child_count() == 0, "Right weapon mount visual children cleared (no floating weapon)")
	
	# Check loadout sync in GlobalData
	_check(GlobalData.weapons.weapon_loadout.get("right", "") == "", "GlobalData loadout right slot is cleared")
	_check(GlobalData.weapons.weapon_loadout.get("left", "") != "", "GlobalData loadout left slot still holds left weapon")
	
	# Check WeaponPickup created in scene
	var pickups = get_tree().get_nodes_in_group("weapon_pickup")
	_check(pickups.size() == initial_pickup_count + 1, "Exactly one new WeaponPickup spawned in world")
	
	var spawned_pickup = pickups.back()
	if spawned_pickup:
		_check(spawned_pickup.get("weapon_resource") == blade_res, "Spawned pickup holds the dropped Heat Blade resource")
	
	# Now destroy left arm frame
	print("\n-- Inflicting lethal frame destruction to arm_left --")
	hs.parts["arm_left"]["armor_hp"] = 0.0
	hs.parts["arm_left"]["armor_broken"] = true
	hs.take_damage_to_part("arm_left", 500.0, "pierce")
	
	_check(hs.parts["arm_left"]["destroyed"] == true, "Left arm frame is destroyed")
	_check(wm.left_hand == null, "Left hand weapon unequipped from WeaponManager")
	_check(GlobalData.weapons.weapon_loadout.get("left", "") == "", "GlobalData loadout left slot is cleared")
	
	var pickups_final = get_tree().get_nodes_in_group("weapon_pickup")
	_check(pickups_final.size() == initial_pickup_count + 2, "Second WeaponPickup spawned for left hand weapon")
	
	mecha.queue_free()
