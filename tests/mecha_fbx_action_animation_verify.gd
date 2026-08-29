extends Node

const MechaActionAnimator = preload("res://scripts/mecha/mecha_action_animator.gd")

var _fails: int = 0
var _checks: int = 0

func _check(condition: bool, name: String) -> void:
	_checks += 1
	if condition:
		print("  PASS: " + name)
	else:
		_fails += 1
		printerr("  FAIL: " + name)

func _ready() -> void:
	print("--- Running mecha_fbx_action_animation_verify ---")
	_test_library_loading()
	_test_melee_combo_progression()
	_test_shooting_animations()
	_test_shoulder_and_status_actions()
	_test_joint_rotation_application()

	print("MECHA_FBX_ACTION_ANIMATION_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_library_loading() -> void:
	print("Testing FBX Animation Library loading and caching...")
	var animator = MechaActionAnimator.new()
	add_child(animator)
	
	_check(MechaActionAnimator._cached_anim_library.size() >= 30, "Cached at least 30 animations from FBX (found %d)" % MechaActionAnimator._cached_anim_library.size())
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Attack1_R"), "Has Mech_Attack1_R")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Attack2_R"), "Has Mech_Attack2_R")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Attack3_R"), "Has Mech_Attack3_R")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Attack1_L"), "Has Mech_Attack1_L")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Shoot_R"), "Has Mech_Shoot_R")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Shoot2_R"), "Has Mech_Shoot2_R")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_ShoulderShoot1"), "Has Mech_ShoulderShoot1")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_GetHit"), "Has Mech_GetHit")
	_check(MechaActionAnimator._cached_anim_library.has("Mech_Die"), "Has Mech_Die")
	
	animator.queue_free()


func _test_melee_combo_progression() -> void:
	print("Testing Melee Combo step sequencing...")
	var animator = MechaActionAnimator.new()
	add_child(animator)
	
	animator.play_melee("right", 1)
	_check(animator.current_anim_name == "Mech_Attack1_R", "Step 1 Right triggers Mech_Attack1_R")
	_check(animator.is_active, "Animator is active")
	
	animator.play_melee("right", 2)
	_check(animator.current_anim_name == "Mech_Attack2_R", "Step 2 Right triggers Mech_Attack2_R")
	
	animator.play_melee("right", 3)
	_check(animator.current_anim_name == "Mech_Attack3_R", "Step 3 Right triggers Mech_Attack3_R")
	
	animator.play_melee("left", 1)
	_check(animator.current_anim_name == "Mech_Attack1_L", "Step 1 Left triggers Mech_Attack1_L")
	
	animator.queue_free()


func _test_shooting_animations() -> void:
	print("Testing Ranged Shooting animations...")
	var animator = MechaActionAnimator.new()
	add_child(animator)
	
	animator.play_shoot("right", false)
	_check(animator.current_anim_name == "Mech_Shoot_R", "Light shoot right triggers Mech_Shoot_R")
	
	animator.play_shoot("right", true)
	_check(animator.current_anim_name == "Mech_Shoot2_R", "Heavy shoot right triggers Mech_Shoot2_R")
	
	animator.play_shoot("left", false)
	_check(animator.current_anim_name == "Mech_Shoot_L", "Light shoot left triggers Mech_Shoot_L")
	
	animator.play_shoot("left", true)
	_check(animator.current_anim_name == "Mech_Shoot2_L", "Heavy shoot left triggers Mech_Shoot2_L")
	
	animator.queue_free()


func _test_shoulder_and_status_actions() -> void:
	print("Testing Shoulder Shoot, GetHit, and Die status animations...")
	var animator = MechaActionAnimator.new()
	add_child(animator)
	
	animator.play_shoulder_shoot(1)
	_check(animator.current_anim_name == "Mech_ShoulderShoot1", "Shoulder shoot 1 triggers Mech_ShoulderShoot1")
	
	animator.play_shoulder_shoot(2)
	_check(animator.current_anim_name == "Mech_ShoulderShoot2", "Shoulder shoot 2 triggers Mech_ShoulderShoot2")
	
	animator.play_get_hit()
	_check(animator.current_anim_name == "Mech_GetHit", "GetHit triggers Mech_GetHit")
	
	animator.play_die()
	_check(animator.current_anim_name == "Mech_Die", "Die triggers Mech_Die")
	
	animator.queue_free()


func _test_joint_rotation_application() -> void:
	print("Testing real-time joint rotation application and crossfading...")
	var animator = MechaActionAnimator.new()
	add_child(animator)
	
	# Create dummy joints
	var body = Node3D.new()
	var arm_r = Node3D.new()
	var forearm_r = Node3D.new()
	var arm_l = Node3D.new()
	var head = Node3D.new()
	
	var joints = {
		"body": body,
		"arm_right": arm_r,
		"forearm_right": forearm_r,
		"arm_left": arm_l,
		"head": head
	}
	
	# Play attack 1 right
	animator.play_melee("right", 1)
	
	# Advance by 0.3s (mid-attack)
	animator.update(0.3)
	_check(animator.blend_weight > 0.5, "Blend weight faded in (blend_weight=%.2f)" % animator.blend_weight)
	
	animator.apply_to_joints(joints, 1.0)
	
	_check(absf(arm_r.rotation.x) > 0.01 or absf(arm_r.rotation.z) > 0.01, "Arm Right rotation was updated by keyframe (rot=%s)" % str(arm_r.rotation))
	_check(absf(body.rotation.y) > 0.01 or absf(body.rotation.x) > 0.01, "Body rotation was updated by keyframe (rot=%s)" % str(body.rotation))
	
	animator.queue_free()
	body.queue_free()
	arm_r.queue_free()
	forearm_r.queue_free()
	arm_l.queue_free()
	head.queue_free()
