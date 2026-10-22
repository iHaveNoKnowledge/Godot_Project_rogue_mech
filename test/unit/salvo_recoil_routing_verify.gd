extends Node
## SALVO RECOIL ROUTING VERIFY (Gate R2-E, test-only).
##
## Pins the committed `_fire_missile_salvo` recoil branch
## (weapon_manager.gd) through the live call chain — not the animator in
## isolation:
##  1. Shoulder slot + missile -> main-channel shoulder barrage clip.
##  2. Hand slot + missile weapon -> main-channel shoulder barrage clip.
##  3. Hand slot + ordinary rifle -> per-hand shoot recoil channel, and the
##     main channel does NOT take a shoulder clip.
## Each case builds a fresh full-mech fixture (no cross-case state), fires a
## single-target salvo (no inter-missile await), asserts the shot actually
## launched first, then asserts routing. Firing + routing both fail loudly
## if preconditions (ammo, cooldown, target) are unmet — a routing assert can
## never pass on a salvo that never fired.
## Run: godot --headless --path . res://test/unit/salvo_recoil_routing_verify.tscn

const MECH_SCENE := "res://scenes/mecha/mecha_base.tscn"
const MISSILE_PATH := "res://resources/mech/stock/weapon_heavy_missile.tres"
const RIFLE_PATH := "res://resources/mech/stock/weapon_beam_rifle.tres"
const MechaActionAnimator = preload("res://scripts/mecha/mecha_action_animator.gd")

const REQUIRED_RECOIL_CLIPS := [
	"Mech_ShoulderShoot1",
	"Mech_ShoulderShoot2",
	"Mech_Shoot_R",
	"Mech_Shoot_L",
]

var _fails := 0
var _checks := 0
var _injected_clips: Array[String] = []


func _ensure_test_recoil_animations() -> void:
	# In environments where download/Mech_00/Char_Anim/Mech_00_Anim.fbx is
	# excluded (e.g. clean checkouts / CI), MechaActionAnimator._cached_anim_library
	# lacks shoulder barrage and shoot recoil clips. Seed minimal test Animation
	# resources so production routing can be exercised and observed without
	# requiring licensed raw FBX downloads.
	for clip_name in REQUIRED_RECOIL_CLIPS:
		if not MechaActionAnimator._cached_anim_library.has(clip_name):
			var dummy := Animation.new()
			dummy.length = 1.0
			MechaActionAnimator._cached_anim_library[clip_name] = dummy
			_injected_clips.append(clip_name)


func _cleanup_test_recoil_animations() -> void:
	for clip_name in _injected_clips:
		MechaActionAnimator._cached_anim_library.erase(clip_name)
	_injected_clips.clear()


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("SALVO-ROUTING OK: " + name)
	else:
		_fails += 1
		printerr("SALVO-ROUTING FAIL: " + name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_ensure_test_recoil_animations()
	await _test_shoulder_salvo_routing()
	await _test_hand_missile_routing()
	await _test_hand_rifle_fallback()
	_cleanup_test_recoil_animations()
	print("SALVO_RECOIL_ROUTING_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		printerr("SALVO_RECOIL_ROUTING_VERIFY_FAILED")
		get_tree().quit(1)
	else:
		print("ALL_SALVO_ROUTING_TESTS_PASSED")
		get_tree().quit(0)


func _spawn_rig() -> Array:
	var mecha: CharacterBody3D = (load(MECH_SCENE) as PackedScene).instantiate()
	mecha.position = Vector3(0, 1.5, 0)
	add_child(mecha)
	var wm: Node3D = load("res://scripts/mecha/weapon_manager.gd").new()
	wm.name = "WeaponManager"
	mecha.add_child(wm)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	await get_tree().process_frame
	await get_tree().process_frame
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.position = Vector3(0, -1.5, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 3, 200)
	shape.shape = box
	ground.add_child(shape)
	add_child(ground)
	var target := Node3D.new()
	target.position = Vector3(0, 1.5, -20.0)
	add_child(target)
	await get_tree().process_frame
	return [mecha, wm, cam, target]


func _animator(wm: Node3D):
	var mecha: Node3D = wm.get_parent() as Node3D
	var anim = mecha.get_node_or_null("MechaAnimation")
	if anim != null and anim.get("action_animator") != null:
		return anim.get("action_animator")
	return null


func _mount_for_slot(wm: Node3D, slot: String, weapon: WeaponPart) -> void:
	# Mount real visuals through the production mount path so muzzle lookup
	# resolves exactly as in gameplay (bare mounts yield INF muzzles).
	var mecha: Node3D = wm.get_parent() as Node3D
	if slot.begins_with("shoulder"):
		var side := "left" if slot == "shoulder_left" else "right"
		wm._update_shoulder_weapon_visual(mecha, side, weapon)
	else:
		wm._update_hand_weapon_visual(mecha, slot, weapon)


func _fire_salvo_once(wm: Node3D, slot: String, weapon: WeaponPart, target: Node3D) -> bool:
	_mount_for_slot(wm, slot, weapon)
	await get_tree().process_frame
	await get_tree().process_frame
	var core = wm._core_for_weapon(weapon)
	if core == null:
		return false
	core.ammo = core.max_ammo
	core.cooldown = 0.0
	var before := get_tree().get_nodes_in_group("projectile").size()
	wm._fire_missile_salvo(slot, weapon, {target: 1})
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().get_nodes_in_group("projectile").size() > before


func _test_shoulder_salvo_routing() -> void:
	var rig := await _spawn_rig()
	var wm: Node3D = rig[1]
	var target: Node3D = rig[3]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.shoulder_right = missile
	_check(missile.weapon_type == WeaponPart.WeaponType.MISSILE, "shoulder case uses a MISSILE-typed weapon")
	_check(wm.shoulder_right == missile, "shoulder slot holds the salvo instance")
	_check(await _fire_salvo_once(wm, "shoulder_right", missile, target), "shoulder salvo launches")
	var animator = _animator(wm)
	_check(animator != null, "shoulder case has an animator")
	if animator != null:
		_check(str(animator.current_anim_name).begins_with("Mech_ShoulderShoot"), "shoulder salvo takes the main-channel barrage clip (got %s)" % str(animator.current_anim_name))
	_check(_shoot_channels_idle(animator), "shoulder salvo leaves shoot-recoil channels idle")
	(rig[0] as Node).queue_free()


func _test_hand_missile_routing() -> void:
	var rig := await _spawn_rig()
	var wm: Node3D = rig[1]
	var target: Node3D = rig[3]
	var missile: WeaponPart = load(MISSILE_PATH)
	wm.right_hand = missile
	_check(wm.right_hand == missile, "hand slot holds the salvo instance")
	_check(await _fire_salvo_once(wm, "right", missile, target), "hand missile salvo launches")
	var animator = _animator(wm)
	_check(animator != null, "hand-missile case has an animator")
	if animator != null:
		_check(str(animator.current_anim_name).begins_with("Mech_ShoulderShoot"), "hand missile takes the main-channel barrage clip (got %s)" % str(animator.current_anim_name))
	_check(_shoot_channels_idle(animator), "hand missile leaves shoot-recoil channels idle")
	(rig[0] as Node).queue_free()


func _test_hand_rifle_fallback() -> void:
	var rig := await _spawn_rig()
	var wm: Node3D = rig[1]
	var target: Node3D = rig[3]
	var rifle: WeaponPart = load(RIFLE_PATH)
	wm.right_hand = rifle
	_check(rifle.weapon_type != WeaponPart.WeaponType.MISSILE, "rifle case uses a non-missile weapon")
	_check(wm.right_hand == rifle, "hand slot holds the salvo instance")
	_check(await _fire_salvo_once(wm, "right", rifle, target), "rifle salvo launches")
	var animator = _animator(wm)
	_check(animator != null, "rifle case has an animator")
	if animator != null:
		var right_name := str(animator.shoot_channel_right.anim_name)
		_check(right_name.begins_with("Mech_Shoot"), "rifle salvo takes the per-hand recoil channel (got %s)" % right_name)
		_check(not str(animator.current_anim_name).begins_with("Mech_ShoulderShoot"), "rifle salvo does not take the shoulder clip")
	_check(animator == null or str(animator.shoot_channel_left.anim_name) == "", "rifle salvo leaves the off-hand channel idle")
	(rig[0] as Node).queue_free()


func _shoot_channels_idle(animator) -> bool:
	if animator == null:
		return false
	return str(animator.shoot_channel_left.anim_name) == "" and str(animator.shoot_channel_right.anim_name) == ""
