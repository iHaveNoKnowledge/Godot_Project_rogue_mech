extends Node3D

## Verification test for Beehave Behavior Tree and Pilot Personality Traits.
## Tests trait parsing, blackboard configuration, leaf condition logic,
## and dynamic action execution across all 4 personality profiles.

var _checks: int = 0
var _fails: int = 0


func _check(condition: bool, msg: String) -> void:
	_checks += 1
	if condition:
		print("BEEHAVE_OK: %s" % msg)
	else:
		_fails += 1
		print("BEEHAVE_FAIL: %s" % msg)


func _ready() -> void:
	print("--- Starting Beehave Behavior Tree & Pilot Traits Verification ---")
	_test_trait_parsing()
	_test_tree_factory_and_blackboard()
	_test_health_condition_by_trait()
	_test_melee_condition_by_trait()
	_test_scavenge_condition_and_action()
	_test_targeting_action_by_trait()
	_test_end_to_end_ally_and_enemy()

	print("BEEHAVE_AI_TRAITS_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_trait_parsing() -> void:
	_check(AiPilotTraits.get_personality_type("Reckless Daredevil") == AiPilotTraits.PersonalityType.AGGRESSIVE, "Reckless maps to AGGRESSIVE")
	_check(AiPilotTraits.get_personality_type("Hot-headed") == AiPilotTraits.PersonalityType.AGGRESSIVE, "Hot-headed maps to AGGRESSIVE")
	_check(AiPilotTraits.get_personality_type("Cold & Calculating") == AiPilotTraits.PersonalityType.CAUTIOUS, "Cold & Calculating maps to CAUTIOUS")
	_check(AiPilotTraits.get_personality_type("Cynical") == AiPilotTraits.PersonalityType.CAUTIOUS, "Cynical maps to CAUTIOUS")
	_check(AiPilotTraits.get_personality_type("Scavenger") == AiPilotTraits.PersonalityType.SCAVENGER, "Scavenger maps to SCAVENGER")
	_check(AiPilotTraits.get_personality_type("Quiet Professional") == AiPilotTraits.PersonalityType.TACTICAL, "Quiet Professional maps to TACTICAL")
	_check(AiPilotTraits.get_personality_type("Vigilant") == AiPilotTraits.PersonalityType.TACTICAL, "Vigilant maps to TACTICAL")


func _test_tree_factory_and_blackboard() -> void:
	var dummy := CharacterBody3D.new()
	add_child(dummy)
	
	var tree := MechaBehaviorTreeFactory.create_tree(dummy, "Reckless Daredevil")
	dummy.add_child(tree)
	
	_check(tree != null, "MechaBehaviorTreeFactory returned a valid tree")
	_check(tree.blackboard != null, "Tree has an active Blackboard")
	
	var profile: Dictionary = tree.blackboard.get_value("personality_profile", {})
	_check(profile.get("name") == "Aggressive", "Profile name is Aggressive")
	_check(profile.get("flee_hp_threshold") == 0.10, "Aggressive flee threshold is 0.10 (10%)")
	_check(profile.get("prefer_melee") == true, "Aggressive prefers melee")
	
	dummy.queue_free()


func _test_health_condition_by_trait() -> void:
	var ally := CharacterBody3D.new()
	add_child(ally)
	var hs := Node3D.new()
	hs.name = "HealthSystem"
	hs.set_script(preload("res://scripts/mecha/enemy_health.gd"))
	ally.add_child(hs)
	hs.parts = {"body": {"armor_hp": 0.0, "frame_hp": 35.0, "max_armor": 0.0, "max_frame": 100.0, "destroyed": false}}
	hs._calculate_totals()
	ally.set("health_system", hs)
	
	var cond := IsHealthLowCondition.new()
	
	# Test Cautious trait (threshold 0.45): 35% HP < 45% -> should trigger flee (SUCCESS)
	var bb_cautious := Blackboard.new()
	bb_cautious.set_value("personality_profile", AiPilotTraits.get_personality_profile("Cautious"))
	var res_cautious := cond.tick(ally, bb_cautious)
	_check(res_cautious == BeehaveNode.SUCCESS, "Cautious pilot at 35% HP triggers flee (SUCCESS)")
	
	# Test Aggressive trait (threshold 0.10): 35% HP > 10% -> should NOT flee (FAILURE)
	var bb_aggro := Blackboard.new()
	bb_aggro.set_value("personality_profile", AiPilotTraits.get_personality_profile("Aggressive"))
	var res_aggro := cond.tick(ally, bb_aggro)
	_check(res_aggro == BeehaveNode.FAILURE, "Aggressive pilot at 35% HP does NOT flee (FAILURE)")
	
	# Lower HP to 8%: Aggressive should now flee
	hs.parts["body"]["frame_hp"] = 8.0
	hs._calculate_totals()
	var res_aggro_low := cond.tick(ally, bb_aggro)
	_check(res_aggro_low == BeehaveNode.SUCCESS, "Aggressive pilot at 8% HP triggers flee (SUCCESS)")
	
	ally.queue_free()


func _test_melee_condition_by_trait() -> void:
	var actor := CharacterBody3D.new()
	actor.position = Vector3(0, 0, 0)
	add_child(actor)
	
	var enemy := CharacterBody3D.new()
	enemy.position = Vector3(0, 0, 12.0) # 12 meters away
	add_child(enemy)
	
	var cond := ShouldUseMeleeCondition.new()
	
	# Aggressive pilot: at 12m, prefers melee -> SUCCESS
	var bb_aggro := Blackboard.new()
	bb_aggro.set_value("personality_profile", AiPilotTraits.get_personality_profile("Aggressive"))
	bb_aggro.set_value("combat_target", enemy)
	var res_aggro := cond.tick(actor, bb_aggro)
	_check(res_aggro == BeehaveNode.SUCCESS, "Aggressive pilot at 12m charges melee (SUCCESS)")
	
	# Cautious pilot: at 12m, avoids melee -> FAILURE
	var bb_cautious := Blackboard.new()
	bb_cautious.set_value("personality_profile", AiPilotTraits.get_personality_profile("Cautious"))
	bb_cautious.set_value("combat_target", enemy)
	var res_cautious := cond.tick(actor, bb_cautious)
	_check(res_cautious == BeehaveNode.FAILURE, "Cautious pilot at 12m avoids melee (FAILURE)")
	
	# Move enemy into point-blank range (4m): Cautious pilot uses emergency blade
	enemy.position = Vector3(0, 0, 4.0)
	var res_cautious_close := cond.tick(actor, bb_cautious)
	_check(res_cautious_close == BeehaveNode.SUCCESS, "Cautious pilot at 4m uses blade (SUCCESS)")
	
	actor.queue_free()
	enemy.queue_free()


func _test_scavenge_condition_and_action() -> void:
	var actor := CharacterBody3D.new()
	actor.position = Vector3(0, 0, 0)
	actor.set("move_speed", 5.0)
	add_child(actor)
	
	var pickup := Node3D.new()
	pickup.name = "GroundAmmo"
	pickup.add_to_group("ammo_pickup")
	pickup.position = Vector3(10, 0, 0)
	add_child(pickup)
	
	var cond := HasScavengeTargetCondition.new()
	
	# Test Scavenger trait: detects nearby pickup -> SUCCESS
	var bb_scav := Blackboard.new()
	bb_scav.set_value("personality_profile", AiPilotTraits.get_personality_profile("Scavenger"))
	var res_scav: int = cond.tick(actor, bb_scav)
	_check(res_scav == BeehaveNode.SUCCESS, "Scavenger pilot detects nearby pickup (SUCCESS)")
	_check(bb_scav.get_value("scavenge_target") == pickup, "Scavenge target set in Blackboard")
	
	# Test CollectPickupAction: moves toward pickup
	var act := CollectPickupAction.new()
	var act_res: int = act.tick(actor, bb_scav)
	_check(act_res == BeehaveNode.RUNNING, "CollectPickupAction runs while moving toward pickup")
	_check(actor.velocity.x > 0.0, "Actor velocity points toward pickup on X axis")
	
	# Move actor directly onto pickup: collects and finishes
	actor.position = Vector3(9.5, 0, 0)
	var act_finish: int = act.tick(actor, bb_scav)
	_check(act_finish == BeehaveNode.SUCCESS, "CollectPickupAction succeeds when reaching pickup")
	_check(not bb_scav.has_value("scavenge_target"), "Scavenge target erased after pickup")
	
	actor.queue_free()
	if is_instance_valid(pickup):
		pickup.queue_free()


func _test_targeting_action_by_trait() -> void:
	var ally := CharacterBody3D.new()
	ally.add_to_group("ally")
	ally.position = Vector3(0, 0, 0)
	add_child(ally)
	
	# Create two enemies: enemy1 near full HP, enemy2 low HP
	var e1 := CharacterBody3D.new()
	e1.name = "EnemyFullHP"
	e1.add_to_group("enemy")
	e1.position = Vector3(5, 0, 0)
	add_child(e1)
	var hs1 := Node3D.new()
	hs1.name = "HealthSystem"
	hs1.set_script(preload("res://scripts/mecha/enemy_health.gd"))
	e1.add_child(hs1)
	hs1.parts = {"body": {"armor_hp": 0.0, "frame_hp": 100.0, "max_armor": 0.0, "max_frame": 100.0, "destroyed": false}}
	hs1._calculate_totals()
	
	var e2 := CharacterBody3D.new()
	e2.name = "EnemyLowHP"
	e2.add_to_group("enemy")
	e2.position = Vector3(8, 0, 0)
	add_child(e2)
	var hs2 := Node3D.new()
	hs2.name = "HealthSystem"
	hs2.set_script(preload("res://scripts/mecha/enemy_health.gd"))
	e2.add_child(hs2)
	hs2.parts = {"body": {"armor_hp": 0.0, "frame_hp": 10.0, "max_armor": 0.0, "max_frame": 100.0, "destroyed": false}}
	hs2._calculate_totals()
	
	var act := FindTargetAction.new()
	
	# Aggressive pilot (priority "lowest_hp") should lock onto e2
	var bb_aggro := Blackboard.new()
	bb_aggro.set_value("personality_profile", AiPilotTraits.get_personality_profile("Aggressive"))
	act.tick(ally, bb_aggro)
	_check(bb_aggro.get_value("combat_target") == e2, "Aggressive pilot targets lowest HP enemy (EnemyLowHP)")
	
	ally.queue_free()
	e1.queue_free()
	e2.queue_free()


func _test_end_to_end_ally_and_enemy() -> void:
	var ally_scene: PackedScene = load("res://scenes/mecha/ally_dummy.tscn")
	var ally = ally_scene.instantiate()
	add_child(ally)
	ally.setup_beehave_tree("Cold & Calculating")
	
	_check(ally.beehave_tree != null, "Ally successfully attached BeehaveTree")
	_check(ally.pilot_trait == "Cold & Calculating", "Ally pilot trait set to Cold & Calculating")
	
	var profile: Dictionary = ally.beehave_tree.blackboard.get_value("personality_profile", {})
	_check(profile.get("name") == "Cautious", "Cautious profile active on squadmate")
	
	ally.queue_free()
