extends Node

func _ready() -> void:
	print("--- BEGIN ENEMY MELEE ANIMATION VERIFY TEST ---")
	test_mecha_action_animator_enemy_melee()
	test_state_attack_melee_trigger()
	print("--- ALL TESTS PASSED SUCCESSFULLY! ---")
	get_tree().quit(0)


func assert_true(cond: bool, msg: String) -> void:
	if not cond:
		push_error("ASSERTION FAILED: " + msg)
		print("FAILED: " + msg)
		get_tree().quit(1)
	else:
		print("PASS: " + msg)


func test_mecha_action_animator_enemy_melee() -> void:
	var animator := MechaActionAnimator.new()
	add_child(animator)

	var ok := animator.play_enemy_melee("right", 0.6)
	assert_true(ok, "play_enemy_melee successfully found and played Mech_Attack1_R from Mech_00_Anim.fbx")
	assert_true(animator.is_active, "Animator is active")
	assert_true(animator.is_custom_pacing, "is_custom_pacing is true for windup & strike acceleration")
	assert_true(animator.windup_speed < animator.strike_speed, "Windup speed (%.2f) is slower than strike speed (%.2f)" % [animator.windup_speed, animator.strike_speed])

	# Advance during windup phase
	animator.update(0.1)
	assert_true(animator.blend_weight > 0.0, "Animator blend_weight fades in during windup")

	# Advance into strike phase
	var initial_time := animator.anim_time
	animator.update(0.3)
	assert_true(animator.anim_time > initial_time, "Animation time advanced forward")

	animator.queue_free()


func test_state_attack_melee_trigger() -> void:
	var enemy_script = load("res://scripts/mecha/enemy_dummy.gd")
	var enemy: CharacterBody3D = CharacterBody3D.new()
	enemy.set_script(enemy_script)
	enemy.archetype = 4 # Shield Melee
	add_child(enemy)

	enemy._build_catalog_body()
	enemy._setup_leg_animation()
	enemy._setup_state_machine()

	var target_node := Node3D.new()
	target_node.position = Vector3(0, 0, 3)
	add_child(target_node)
	enemy.target = target_node

	var state_attack = enemy.state_machine.get_node_or_null("StateAttack")
	assert_true(state_attack != null, "StateAttack exists on enemy")

	state_attack.enemy = enemy
	state_attack.state_machine = enemy.state_machine
	state_attack.enter()

	# Simulate telegraph entering window
	state_attack.attack_timer = 0.4
	state_attack.physics_process(0.05)

	var anim_node = enemy.get_node_or_null("MechaAnimation")
	assert_true(anim_node != null, "MechaAnimation node exists on enemy")
	assert_true(anim_node.action_animator != null, "action_animator exists in MechaAnimation")
	assert_true(anim_node.action_animator.is_active, "action_animator is active and playing enemy melee animation")

	enemy.queue_free()
	target_node.queue_free()
