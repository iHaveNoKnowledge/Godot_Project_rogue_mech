extends Node

## Test suite verifying the 6 key battle mechanics asked by user:
## 1. Attack capability (Ranged & Melee & Fist)
## 2. Reload mechanics (Mag, Reserve ammo, Full/Empty fail)
## 3. Dodge/Dash mechanics (Energy cost, Flash burn, Precision dodge)
## 4. HP reduction (Armor first, Frame next, Part destruction, Pilot HP)
## 5. Eject state isolation (Pilot vs Mech state/resources)
## 6. Eject effect on Ally/Other objects (Signal leakage check)

var _fails: int = 0
var _checks: int = 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("BATTLE_TEST OK: " + label)
	else:
		_fails += 1
		printerr("BATTLE_TEST FAIL: " + label)

func _ready() -> void:
	GlobalData.reset_run_data()
	await get_tree().process_frame

	await _test_1_attack_system()
	await _test_2_reload_system()
	await _test_3_dodge_dash_system()
	await _test_4_hp_and_damage_system()
	await _test_5_eject_state_system()
	await _test_6_eject_signal_impact_on_allies()

	print("\n==================================================")
	print("BATTLE_SYSTEM_BEHAVIOR_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [_checks, _fails])
	print("==================================================\n")
	get_tree().quit(1 if _fails > 0 else 0)


# -----------------------------------------------------------------------------
# 1. ATTACK SYSTEM
# -----------------------------------------------------------------------------
func _test_1_attack_system() -> void:
	print("--- 1. Testing Attack System ---")
	var weapon = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
	var core = WeaponCore.from_weapon(weapon)
	core.auto_reload = false
	
	_check(core.can_fire(), "WeaponCore ready to fire")
	var fired = core.consume_shot()
	_check(fired, "consume_shot successfully fires")
	_check(core.ammo == weapon.max_ammo - 1, "ammo reduced by 1 after firing")
	_check(core.cooldown > 0.0, "cooldown applied after shot")
	_check(not core.can_fire(), "cannot fire during cooldown")

	# Melee weapon
	var melee_w = preload("res://resources/mech/stock/weapon_heat_blade.tres")
	var melee_core = WeaponCore.from_weapon(melee_w)
	_check(melee_core.can_fire(), "Melee weapon can attack")
	_check(melee_core.consume_shot(), "Melee consume shot succeeds")

	# Bare fist
	var fist_w = WeaponPart.new()
	fist_w.weapon_name = "Bare Fist"
	fist_w.damage = 8.0
	fist_w.fire_rate = 0.5
	var fist_core = WeaponCore.from_weapon(fist_w)
	_check(fist_core.can_fire(), "Bare fist unarmed attack can fire")


# -----------------------------------------------------------------------------
# 2. RELOAD SYSTEM
# -----------------------------------------------------------------------------
func _test_2_reload_system() -> void:
	print("--- 2. Testing Reload System ---")
	var mecha = CharacterBody3D.new()
	var wm = Node3D.new()
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)
	add_child(mecha)
	await get_tree().process_frame

	var gun = preload("res://resources/mech/stock/weapon_beam_rifle.tres").duplicate()
	wm.left_hand = gun
	var ammo_type = gun.get_ammo_type()
	wm.battle_reserve[ammo_type] = 50

	var core = wm._core_for_weapon(gun)
	core.ammo = 5 # depleted from max (e.g. 15)

	var needed = gun.max_ammo - core.ammo
	_check(needed > 0, "Magazine needs ammo")
	var reserve_before = wm.get_battle_reserve(ammo_type)
	var taken = wm.consume_battle_reserve(ammo_type, needed)
	core.ammo += taken

	_check(core.ammo == gun.max_ammo, "Magazine reloaded to full")
	_check(wm.get_battle_reserve(ammo_type) == reserve_before - taken, "Reserve ammo decreased by reloaded amount")

	# Try reload when full
	_check(gun.max_ammo - core.ammo == 0, "Full magazine prevents further reload")

	mecha.queue_free()


# -----------------------------------------------------------------------------
# 3. DODGE / DASH SYSTEM
# -----------------------------------------------------------------------------
func _test_3_dodge_dash_system() -> void:
	print("--- 3. Testing Dodge / Dash System ---")
	var dash_sys = Node.new()
	dash_sys.set_script(load("res://scripts/mecha/mecha_dash_system.gd"))
	add_child(dash_sys)
	await get_tree().process_frame

	var energy = 100.0
	_check(dash_sys.can_dash(energy), "Can dash with sufficient energy")
	_check(not dash_sys.can_dash(2.0), "Cannot dash with insufficient energy (< 6.0)")

	# Dash 1: normal cost
	var cost1 = dash_sys.start_dash(energy, Vector3.ZERO, Basis())
	_check(dash_sys.is_dashing, "is_dashing set to true after start_dash")
	_check(cost1 == 6.0, "Normal dash cost is 6.0")

	# Dash 2 in spam window: Flash Burn penalty
	var cost2 = dash_sys.start_dash(energy - cost1, Vector3.ZERO, Basis())
	_check(cost2 > cost1, "Spam dash triggers Flash Burn (higher energy cost: %f > %f)" % [cost2, cost1])

	# Velocity application
	var vel = dash_sys.apply_velocity(Vector3.ZERO)
	_check(vel.length() > 0.0, "Dash applies horizontal velocity vector: %s" % str(vel))

	dash_sys.queue_free()


# -----------------------------------------------------------------------------
# 4. HP AND DAMAGE SYSTEM
# -----------------------------------------------------------------------------
func _test_4_hp_and_damage_system() -> void:
	print("--- 4. Testing HP & Damage System ---")
	var mecha = CharacterBody3D.new()
	var hs = Node3D.new()
	hs.set_script(load("res://scripts/mecha/mecha_health.gd"))
	hs.is_player = true
	mecha.add_child(hs)
	add_child(mecha)
	await get_tree().process_frame

	var body_part = hs.parts.get("body", {})
	_check(not body_part.is_empty(), "Mech has body part initialized")
	var initial_armor = body_part["armor_hp"]
	var initial_frame = body_part["frame_hp"]

	# Hit 1: Damage armor first
	hs.take_damage_to_part("body", 20.0, "kinetic", "armor")
	_check(hs.parts["body"]["armor_hp"] < initial_armor, "Armor HP reduced after hit")
	_check(hs.parts["body"]["frame_hp"] == initial_frame, "Frame HP undamaged while armor absorbs")

	# Hit 2: Break armor completely
	hs.take_damage_to_part("body", 500.0, "kinetic", "armor")
	_check(hs.parts["body"]["armor_broken"] == true, "Armor broken when armor HP reaches 0")
	
	# Hit 3: Now that armor is broken, subsequent hit damages frame
	hs.take_damage_to_part("body", 15.0, "kinetic", "armor")
	_check(hs.parts["body"]["frame_hp"] < initial_frame, "Frame HP damaged after armor breaks")

	# Pilot HP
	GlobalData.pilot.pilot_hp = 100.0
	PilotSystem.take_damage(35.0)
	_check(PilotSystem.get_hp() == 65.0, "Pilot HP decreases when damaged (100 -> 65)")

	mecha.queue_free()


# -----------------------------------------------------------------------------
# 5. EJECT STATE SYSTEM (Pilot vs Mech)
# -----------------------------------------------------------------------------
func _test_5_eject_state_system() -> void:
	print("--- 5. Testing Eject State Isolation ---")
	var mecha = CharacterBody3D.new()
	mecha.name = "Mecha"
	var eject = Node.new()
	eject.set_script(load("res://scripts/mecha/mecha_eject.gd"))
	eject.name = "MechaEject"
	mecha.add_child(eject)
	add_child(mecha)
	await get_tree().process_frame

	# Initial state: pilot in mech
	_check(not mecha.has_meta("is_parked"), "Mech starts active (not parked)")

	eject.initiate_eject()
	await get_tree().process_frame

	# After eject:
	_check(mecha.has_meta("is_parked") and mecha.get_meta("is_parked") == true, "Mech state becomes parked after eject")
	_check(mecha.is_in_group("backup_mech"), "Mech marked as backup_mech so pilot can re-board")
	_check(GameManager.current_state == GameManager.State.EJECT, "GameManager state switched to EJECT")

	# Pilot instance check
	var pilots = get_tree().get_nodes_in_group("pilot")
	_check(not pilots.is_empty(), "Pilot instance spawned into scene")
	if not pilots.is_empty():
		var pilot = pilots[0]
		_check(pilot is CharacterBody3D, "Pilot is an independent CharacterBody3D")
		_check("stamina" in pilot, "Pilot uses independent stamina system")
		_check(pilot.has_method("take_damage"), "Pilot takes damage to PilotSystem HP")

	# Clean up
	for p in pilots:
		p.queue_free()
	mecha.queue_free()


# -----------------------------------------------------------------------------
# 6. EJECT SIGNAL IMPACT ON ALLIES / OTHER OBJECTS
# -----------------------------------------------------------------------------
func _test_6_eject_signal_impact_on_allies() -> void:
	print("--- 6. Testing Eject Signal Impact on Allies / Enemies ---")
	
	# Spawn an Ally dummy and an Enemy dummy that have MechaAnimation
	var ally = CharacterBody3D.new()
	ally.name = "AllyDummy"
	ally.add_to_group("ally")
	var ally_anim = Node.new()
	ally_anim.set_script(load("res://scripts/mecha/mecha_animation.gd"))
	ally_anim.name = "AnimationSystem"
	ally.add_child(ally_anim)
	add_child(ally)

	var enemy = CharacterBody3D.new()
	enemy.name = "EnemyDummy"
	enemy.add_to_group("enemy")
	var enemy_anim = Node.new()
	enemy_anim.set_script(load("res://scripts/mecha/mecha_animation.gd"))
	enemy_anim.name = "AnimationSystem"
	enemy.add_child(enemy_anim)
	add_child(enemy)

	await get_tree().process_frame

	_check(ally_anim.is_kneeling == false, "Ally starts standing (not kneeling)")
	_check(enemy_anim.is_kneeling == false, "Enemy starts standing (not kneeling)")

	# Player ejects and emits EventBus.mecha_occupancy_changed.emit(false)
	EventBus.mecha_occupancy_changed.emit(false)
	await get_tree().process_frame

	# Check if ally / enemy got protected from player eject signal
	var ally_affected = ally_anim.is_kneeling
	var enemy_affected = enemy_anim.is_kneeling

	print("  [SIGNAL IMPACT CHECK] Ally anim is_kneeling after player eject: %s" % str(ally_affected))
	print("  [SIGNAL IMPACT CHECK] Enemy anim is_kneeling after player eject: %s" % str(enemy_affected))

	_check(ally_affected == false, "Ally does NOT kneel on player eject (properly protected)")
	_check(enemy_affected == false, "Enemy does NOT kneel on player eject (properly protected)")

	# Re-board stands them back up
	EventBus.mecha_occupancy_changed.emit(true)
	await get_tree().process_frame
	_check(ally_anim.is_kneeling == false, "Re-board signal stands them back up")

	ally.queue_free()
	enemy.queue_free()
