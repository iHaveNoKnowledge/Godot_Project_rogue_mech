extends Node3D

## Verifies:
##   1. Every procedural weapon model carries a per-model "Muzzle" barrel-tip
##      marker at a DIFFERENT local position per weapon type
##   2. Custom mesh_scene models get a generic fallback Muzzle, and models that
##      author their own Muzzle node keep it untouched
##   3. WeaponManager resolves fire/jam effect positions from the mounted
##      model's real Muzzle world pos instead of the legacy hip offset
##   4. MechaCombat exposes current_aim_point for the animation system
##   5. Firing a ranged weapon raises the gun arm to point at the aim point,
##      and the arm relaxes back to the guard pose when firing stops

var _checks: int = 0
var _fails: int = 0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("AIM_MUZZLE_OK: %s" % msg)
	else:
		_fails += 1
		print("AIM_MUZZLE_FAIL: %s" % msg)


func _make_weapon(wname: String, wtype: int) -> WeaponPart:
	var w := WeaponPart.new()
	w.weapon_name = wname
	w.weapon_type = wtype as WeaponPart.WeaponType
	return w


func _ready() -> void:
	print("--- Starting Aim Pose & Muzzle Marker Verification ---")

	# --- 1. Per-model barrel-tip markers ---
	var beam_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Beam Rifle", WeaponPart.WeaponType.BEAM_RIFLE)))
	var mg_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Machine Gun", WeaponPart.WeaponType.MACHINE_GUN)))
	var shotgun_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Shotgun", WeaponPart.WeaponType.SHOTGUN)))
	var missile_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Missile Launcher", WeaponPart.WeaponType.MISSILE)))
	var pile_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Pile Bunker", WeaponPart.WeaponType.MELEE)))
	var blade_m := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(_make_weapon("Heat Blade", WeaponPart.WeaponType.MELEE)))

	for entry in [["Beam Rifle", beam_m], ["Machine Gun", mg_m], ["Shotgun", shotgun_m],
			["Missile Launcher", missile_m], ["Pile Bunker", pile_m], ["Heat Blade", blade_m]]:
		_check(entry[1] != null, "%s model carries a Muzzle marker" % entry[0])

	_check(beam_m != null and absf(beam_m.position.z + 1.56) < 0.01,
		"Beam Rifle muzzle at its long barrel tip (z=%.2f)" % (beam_m.position.z if beam_m else 0.0))
	_check(mg_m != null and absf(mg_m.position.z + 1.12) < 0.01,
		"Machine Gun muzzle at its shorter barrel (z=%.2f)" % (mg_m.position.z if mg_m else 0.0))
	if beam_m != null and mg_m != null:
		_check(absf(beam_m.position.z - mg_m.position.z) > 0.2,
			"Different rifle models have different muzzle positions")
	_check(shotgun_m != null and absf(shotgun_m.position.z + 1.02) < 0.01, "Shotgun muzzle at barrel tip")
	_check(missile_m != null and absf(missile_m.position.z + 0.79) < 0.01, "Missile pod muzzle at launch face")
	_check(pile_m != null and absf(pile_m.position.z + 1.72) < 0.01, "Pile bunker muzzle on the spike tip")
	_check(blade_m != null and absf(blade_m.position.z + 1.42) < 0.01, "Heat blade muzzle at the point")

	# --- 2. Custom mesh_scene handling ---
	var plain_packed := PackedScene.new()
	var plain_root := Node3D.new()
	plain_root.name = "CustomGun"
	plain_packed.pack(plain_root)
	var custom_w := _make_weapon("Custom Rifle", WeaponPart.WeaponType.BEAM_RIFLE)
	custom_w.mesh_scene = plain_packed
	var custom_muz := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(custom_w))
	_check(custom_muz != null and absf(custom_muz.position.z + 1.3) < 0.01,
		"Custom mesh_scene model gets the generic fallback Muzzle")

	var authored_packed := PackedScene.new()
	var authored_root := Node3D.new()
	authored_root.name = "AuthoredGun"
	var authored_tip := Node3D.new()
	authored_tip.name = "Muzzle"
	authored_tip.position = Vector3(0.2, 0.05, -2.4)
	authored_root.add_child(authored_tip)
	authored_tip.owner = authored_root  # pack() only serializes owned nodes
	authored_packed.pack(authored_root)
	var authored_w := _make_weapon("Authored Rifle", WeaponPart.WeaponType.MACHINE_GUN)
	authored_w.mesh_scene = authored_packed
	var authored_found := WeaponVisualFactory.find_muzzle_node(WeaponVisualFactory.build(authored_w))
	_check(authored_found != null and authored_found.name == "Muzzle" \
			and absf(authored_found.position.z + 2.4) < 0.01,
		"An authored Muzzle node is preserved, not duplicated")

	# --- 3-5. Live mech wiring ---
	GlobalData.weapons.weapon_loadout["left"] = ""
	GlobalData.weapons.weapon_loadout["right"] = ""
	var mecha_scene: PackedScene = load("res://scenes/mecha/mecha_base.tscn")
	var mecha = mecha_scene.instantiate()
	add_child(mecha)

	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)

	await get_tree().process_frame
	await get_tree().physics_frame

	# No weapon visual mounted yet -> INF sentinel (caller falls back to hip offset).
	_check(wm._get_muzzle_world_pos("right") == Vector3.INF,
		"Muzzle lookup returns INF sentinel when nothing is mounted")

	var beam_res: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres").duplicate()
	wm.right_hand = beam_res
	WeaponVisualFactory.mount_hand(mecha, "right", beam_res, "WeaponMesh_right")
	await get_tree().process_frame

	var muz_pos: Vector3 = wm._get_muzzle_world_pos("right")
	_check(muz_pos != Vector3.INF, "Mounted beam rifle exposes a world-space muzzle position")
	if muz_pos != Vector3.INF:
		var marker := WeaponVisualFactory.find_muzzle_node(mecha.get_node_or_null("ArmRight/ForearmRight/WeaponMesh_right"))
		_check(marker != null and muz_pos.distance_to(marker.global_position) < 0.001,
			"Muzzle world pos matches the mounted marker exactly")
		var legacy: Vector3 = mecha.global_position + mecha.global_transform.basis * Vector3(0.65, 1.4, -1.1)
		_check(muz_pos.distance_to(legacy) > 0.3,
			"Fire origin moved off the legacy hip offset onto the barrel tip")

	var combat = mecha.get_node_or_null("MechaCombat")
	_check(combat != null and "current_aim_point" in combat, "MechaCombat exposes current_aim_point")
	await get_tree().physics_frame
	_check(combat.current_aim_point != Vector3.ZERO or combat.lock_on_target != null,
		"Aim point refreshed during physics frames")

	# --- Aim pose: gun arm raises to point while firing, relaxes after ---
	var anim = mecha.get_node_or_null("AnimationSystem")
	_check(anim != null and anim.has_method("_update_aim_arms"), "AnimationSystem has the aiming pose pass")

	wm.left_hand = beam_res.duplicate()  # ranged weapon in LEFT hand
	# Real hold path: action_press keeps Input reporting held, and seeding the
	# flag mimics the _input() press handler (parse_input_event is unreliable
	# headless); _physics_process then keeps the flag alive while held.
	Input.action_press("fire_left")
	wm.fire_left_holding = true
	for i in range(40):
		await get_tree().physics_frame
	var raised_deg := rad_to_deg(anim.arm_left.rotation.x)
	_check(raised_deg > 40.0, "Gun arm raises toward the aim point while firing (%.1f deg)" % raised_deg)

	Input.action_release("fire_left")
	wm.fire_left_holding = false
	for i in range(40):
		await get_tree().physics_frame
	var relaxed_deg := rad_to_deg(anim.arm_left.rotation.x)
	_check(relaxed_deg < 35.0, "Gun arm relaxes back to guard when firing stops (%.1f deg)" % relaxed_deg)

	print("--- Aim Pose & Muzzle Verification Finished: checks=%d fails=%d ---" % [_checks, _fails])
	if _fails == 0:
		print("ALL_AIM_MUZZLE_TESTS_PASSED")
	get_tree().quit(1 if _fails > 0 else 0)
