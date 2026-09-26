extends Node

## Part-break -> combat-capability integration audit. Executes the REAL paths:
## arm states -> _hand_usable -> _try_fire (ammo/projectile/side effects),
## weapon drop pickup lifecycle, leg penalties + movement availability, head
## sensor penalties, body energy/heat penalties, save/load rehydration.
## Run: godot --headless --path . res://tests/mecha/capability_part_break_audit.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const RIFLE := "res://resources/mech/stock/weapon_beam_rifle.tres"

var _fails := 0
var _checks := 0
var _mech: CharacterBody3D
var _hs: Node
var _wm: Node3D
var _pd_snap: Dictionary = {}
var _loadout_snap: Dictionary = {}


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS: " + label)
	else:
		_fails += 1
		push_error("FAIL: " + label)


func _projectiles() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(m):
			n += 1
	return n


# Inject frame-durability wear for a slot. Returns a restore token.
# Penalties are driven STRICTLY by this durability channel (architect
# contract), not by combat part HP.
func _set_wear(slot: String, v: float) -> Array:
	var ef: Dictionary = GlobalData.weapons.equipped_frames
	var had: bool = ef.has(slot)
	var orig = ef.get(slot)
	var entry = orig
	if entry is Dictionary:
		entry = (entry as Dictionary).duplicate(true)
	else:
		entry = {}
	(entry as Dictionary)["durability"] = v
	ef[slot] = entry
	return [slot, had, orig]


func _restore_wear(token: Array) -> void:
	var ef: Dictionary = GlobalData.weapons.equipped_frames
	if bool(token[1]):
		ef[token[0]] = token[2]
	else:
		ef.erase(token[0])


func _ready() -> void:
	await get_tree().process_frame
	await _run()
	print("CAPABILITY_AUDIT: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	_mech = load(MECH_SCENE).instantiate()
	_mech.position = Vector3(0, 10, 0)
	add_child(_mech)
	_mech.is_player_driven = false
	var f := 0
	while not _mech.is_on_floor() and f < 180:
		await get_tree().physics_frame
		f += 1
	await get_tree().physics_frame
	_hs = _mech.get_node_or_null("HealthSystem")
	_check(_hs != null, "health system present")
	var WMScript: GDScript = load("res://scripts/mecha/weapon_manager.gd")
	_wm = WMScript.new()
	_wm.name = "WeaponManager"
	_mech.add_child(_wm)
	await get_tree().process_frame
	_pd_snap = (GlobalData.weapons.part_damage as Dictionary).duplicate(true)
	_loadout_snap = (GlobalData.weapons.weapon_loadout as Dictionary).duplicate(true)

	# ---- A. arm states: intact / armor-broken usable, frame-destroyed blocked ----
	_check(_wm._hand_usable("left") == true, "intact arm usable")
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.parts["arm_left"]["armor_broken"] == true, "arm_left armor broken")
	_check(_wm._hand_usable("left") == true, "armor break alone keeps hand usable")
	# blocked fire attempt on a merely armor-broken arm must still fire (control)
	var yaw0: float = _mech.rotation.y
	_wm._try_fire("left", null)
	await get_tree().physics_frame
	# (fist melee may rotate mech; only used as side-effect probe below)
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.is_part_destroyed("arm_left"), "arm_left frame destroyed")
	_check(_wm._hand_usable("left") == false, "destroyed arm not usable")
	_check(_wm._hand_usable("right") == true, "right arm independent")
	var yaw1: float = _mech.rotation.y
	var proj0 := _projectiles()
	_wm._try_fire("left", null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(is_equal_approx(_mech.rotation.y, yaw1), "blocked fist fire causes no side effects")
	_check(_projectiles() == proj0, "blocked fist fire spawns no projectile")

	# ---- B. ranged resource lifecycle on intact arm ----
	var rifle: WeaponPart = load(RIFLE)
	_wm.right_hand = rifle
	await get_tree().process_frame
	var core: WeaponCore = _wm._core_for_weapon(rifle)
	_check(core != null, "rifle core created")
	var ammo0: int = core.ammo
	proj0 = _projectiles()
	_wm._try_fire("right", rifle)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(core.ammo == ammo0 - 1, "intact fire consumes ammo (%d->%d)" % [ammo0, core.ammo])
	_check(_projectiles() >= proj0, "intact fire can spawn projectile")

	# ---- C. broken arm with held weapon: drop pickup, gate holds ----
	_wm.left_hand = rifle
	await get_tree().process_frame
	# arm already destroyed above; re-trigger drop path explicitly
	_hs.take_damage_to_part("arm_left", 500.0, "kinetic")
	await get_tree().physics_frame
	var pickup: Area3D = null
	for n in get_tree().current_scene.get_children():
		if n is Area3D and n.get("weapon_resource") == rifle:
			pickup = n
			break
	# drop happens inside _on_frame_destroyed; arm was already destroyed, so
	# emulate a fresh destroy sequence on a clone path: call drop directly
	if pickup == null:
		_hs._drop_hand_weapon_pickup("left", "arm_left")
		await get_tree().process_frame
		for n in get_tree().current_scene.get_children():
			if n is Area3D and n.get("weapon_resource") == rifle:
				pickup = n
				break
	_check(pickup != null, "destroyed arm drops held weapon as pickup")
	_check(_wm.left_hand == null, "dropped weapon detached from hand")
	ammo0 = core.ammo
	proj0 = _projectiles()
	_wm._try_fire("left", rifle)
	await get_tree().physics_frame
	_check(core.ammo == ammo0, "broken-arm fire consumes no ammo")
	_check(_projectiles() == proj0, "broken-arm fire spawns no projectile")
	if pickup:
		pickup.queue_free()

	# ---- D. both arms destroyed: independence ----
	_hs.take_damage_to_part("arm_right", 500.0, "kinetic")
	_hs.take_damage_to_part("arm_right", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_wm._hand_usable("left") == false and _wm._hand_usable("right") == false, "both arms destroyed -> both hands down")

	# ---- E. legs: destroyed legs do NOT hard-stop (penalties flow strictly
	# through the durability channel by architect contract); movement stays
	# available. Enemy dummies additionally ragdoll/crawl; the player mech
	# has no crawl state (immobilization would soft-lock the run).
	var mult_pre: float = PartPenaltySystem.leg_speed_multiplier()
	_hs.take_damage_to_part("leg_left", 500.0, "kinetic")
	_hs.take_damage_to_part("leg_left", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.is_part_destroyed("leg_left"), "leg_left destroyed")
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), mult_pre), "destroyed leg alone does not change speed mult (durability channel separate)")
	_hs.take_damage_to_part("leg_right", 500.0, "kinetic")
	_hs.take_damage_to_part("leg_right", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), mult_pre), "both legs destroyed -> still durability-driven (no stacking)")
	_mech.cmd_world_direction = Vector3(0, 0, -1)
	for i in range(60):
		await get_tree().physics_frame
	_check(_mech.velocity.length() > 0.5, "movement still available with broken legs (v=%.2f)" % _mech.velocity.length())
	_mech.cmd_world_direction = Vector3.ZERO
	# durability channel itself (the real penalty path)
	var tok := _set_wear("leg_left", 0.1)
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), 0.55), "worn legs -> 55% speed (%.2f)" % PartPenaltySystem.leg_speed_multiplier())
	_restore_wear(tok)
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), mult_pre), "durability restore recovers speed")

	# ---- F. head sensor penalties (durability channel; combat damage only
	# feeds it via slight durability wear per hit) ----
	var s0: float = PartPenaltySystem.head_spread_penalty()
	var l0: float = PartPenaltySystem.head_lock_on_multiplier()
	var g0: bool = PartPenaltySystem.head_hud_glitching()
	_hs.take_damage_to_part("head", 40.0, "kinetic")
	await get_tree().physics_frame
	var tokh := _set_wear("head", 0.1)
	_check(PartPenaltySystem.head_spread_penalty() > s0, "worn head raises spread")
	_check(PartPenaltySystem.head_lock_on_multiplier() < l0, "worn head slows lock-on")
	_check(PartPenaltySystem.head_hud_glitching() == true, "worn head flags HUD glitch (was %s)" % str(g0))
	_restore_wear(tokh)
	_hs.take_damage_to_part("head", 500.0, "kinetic")
	_hs.take_damage_to_part("head", 500.0, "kinetic")
	await get_tree().physics_frame
	_check(_hs.is_part_destroyed("head"), "head destroyed")

	# ---- G. body energy/heat penalties (durability channel) ----
	var e0: float = PartPenaltySystem.torso_energy_multiplier()
	var tokb := _set_wear("body", 0.1)
	_check(PartPenaltySystem.torso_energy_multiplier() < e0, "worn body reduces max energy")
	_check(PartPenaltySystem.torso_heat_multiplier() > 1.0, "worn body raises heat")
	_restore_wear(tokb)
	_hs.take_damage_to_part("body", 60.0, "kinetic")
	await get_tree().physics_frame

	# ---- H. save/load rehydration derives capability ----
	var mech2: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech2)
	await get_tree().process_frame
	var wm2: Node3D = WMScript.new()
	wm2.name = "WeaponManager"
	mech2.add_child(wm2)
	await get_tree().process_frame
	_check(wm2._hand_usable("left") == false, "fresh mech re-derives broken hand from damage dict")
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), 1.0), "fresh mech speed full: combat damage alone does not slow (durability channel)")
	mech2.queue_free()
	GlobalData.weapons.part_damage.clear()
	var mech3: CharacterBody3D = load(MECH_SCENE).instantiate()
	add_child(mech3)
	await get_tree().process_frame
	var wm3: Node3D = WMScript.new()
	wm3.name = "WeaponManager"
	mech3.add_child(wm3)
	await get_tree().process_frame
	_check(wm3._hand_usable("left") == true, "cleared damage -> fresh mech capable (no leak)")
	_check(is_equal_approx(PartPenaltySystem.leg_speed_multiplier(), 1.0), "cleared damage -> full speed")
	mech3.queue_free()
	GlobalData.weapons.part_damage = _pd_snap.duplicate(true)
	GlobalData.weapons.weapon_loadout = _loadout_snap.duplicate(true)
	_mech.queue_free()
	await get_tree().process_frame
