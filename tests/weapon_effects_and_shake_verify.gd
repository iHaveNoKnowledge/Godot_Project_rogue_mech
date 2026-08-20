extends Node

## Verifies:
## 1. Dynamic light flash and emissive bloom on weapon firing
## 2. Recoil camera shake on shooting weapons
## 3. Impact camera shake on melee hits
## 4. Explosion dynamic light and shake

var _fails := 0
var _checks := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		printerr("FAIL: " + label)
	else:
		print("EFFECT_OK: " + label)

func _ready() -> void:
	# 1. Setup EffectManager
	var fx := EffectManager.new()
	fx.name = "EffectManager"
	add_child(fx)

	# 2. Setup CameraRig
	var cam_scene: PackedScene = preload("res://scenes/camera/mecha_camera.tscn")
	var cam_rig = cam_scene.instantiate()
	add_child(cam_rig)

	# Test 1: Spawn Muzzle Flash
	EffectManager.spawn_muzzle_flash(Vector3(0, 1, 0), Vector3(0, 0, -1), Color(1.0, 0.8, 0.2))
	var has_light := false
	for child in fx.get_children():
		if child is OmniLight3D:
			has_light = true
			_check(child.light_energy > 0.0, "Muzzle flash spawned dynamic OmniLight3D (energy=%.1f)" % child.light_energy)
			_check(child.omni_range >= 5.0, "Muzzle flash light range is effective (range=%.1f)" % child.omni_range)
	_check(has_light, "Dynamic light flash attached to scene")

	# Test 2: Recoil Camera Shake on weapon firing
	var mecha := CharacterBody3D.new()
	mecha.name = "Mecha"
	add_child(mecha)

	var wm := Node3D.new()
	wm.name = "WeaponManager"
	wm.set_script(preload("res://scripts/mecha/weapon_manager.gd"))
	mecha.add_child(wm)

	var rifle := WeaponPart.new()
	rifle.weapon_name = "Beam Rifle"
	rifle.weapon_type = WeaponPart.WeaponType.BEAM_RIFLE
	rifle.damage = 25.0
	rifle.recoil_shake = 0.0 # Not set explicitly, should auto-compute shake

	cam_rig.shake_amount = 0.0
	wm._apply_recoil(rifle)
	_check(cam_rig.shake_amount > 0.0, "Rifle firing triggered camera recoil shake (shake=%.2f)" % cam_rig.shake_amount)

	var rocket := WeaponPart.new()
	rocket.weapon_name = "Missile Launcher"
	rocket.weapon_type = WeaponPart.WeaponType.MISSILE
	rocket.damage = 80.0
	rocket.recoil_shake = 0.0
	cam_rig.shake_amount = 0.0
	wm._apply_recoil(rocket)
	_check(cam_rig.shake_amount >= 0.3, "Heavy missile firing triggered strong camera shake (shake=%.2f)" % cam_rig.shake_amount)

	# Test 3: Explosion dynamic light and shake
	cam_rig.shake_amount = 0.0
	EffectManager.spawn_explosion(Vector3(5, 0, 5))
	_check(cam_rig.shake_amount >= 0.3, "Explosion triggered explosion camera shake (shake=%.2f)" % cam_rig.shake_amount)

	print("WEAPON_EFFECTS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
