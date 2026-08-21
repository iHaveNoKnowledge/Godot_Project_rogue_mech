class_name MechaBehaviorTreeFactory
extends RefCounted

## Factory that builds modular Beehave Behavior Trees tailored to pilot traits.
## Assembles the decision hierarchy with full Blackboard integration.

static func create_tree(actor: Node, trait_name: String = "Balanced") -> BeehaveTree:
	var tree := BeehaveTree.new()
	tree.name = "MechaBeehaveTree"
	tree.actor_node_path = NodePath("..")
	
	# Configure Blackboard
	var bb := Blackboard.new()
	bb.name = "Blackboard"
	var profile: Dictionary = AiPilotTraits.get_personality_profile(trait_name)
	bb.set_value("personality_profile", profile)
	bb.set_value("pilot_trait", trait_name)
	tree.blackboard = bb
	
	# Root Selector
	var root_selector := SelectorComposite.new()
	root_selector.name = "RootSelector"
	tree.add_child(root_selector)
	
	# Branch 1: Survival / Flee to Cover
	var survival_seq := SequenceComposite.new()
	survival_seq.name = "SurvivalSequence"
	root_selector.add_child(survival_seq)
	
	var health_cond := IsHealthLowCondition.new()
	health_cond.name = "IsHealthLow"
	survival_seq.add_child(health_cond)
	
	var cover_act := SeekCoverAction.new()
	cover_act.name = "SeekCover"
	survival_seq.add_child(cover_act)
	
	# Branch 2: Scavenge Ammo & Scrap
	var scavenge_seq := SequenceComposite.new()
	scavenge_seq.name = "ScavengeSequence"
	root_selector.add_child(scavenge_seq)
	
	var scavenge_cond := HasScavengeTargetCondition.new()
	scavenge_cond.name = "HasScavengeTarget"
	scavenge_seq.add_child(scavenge_cond)
	
	var pickup_act := CollectPickupAction.new()
	pickup_act.name = "CollectPickup"
	scavenge_seq.add_child(pickup_act)
	
	# Branch 3: Combat Engagement
	var combat_seq := SequenceComposite.new()
	combat_seq.name = "CombatSequence"
	root_selector.add_child(combat_seq)
	
	# Target acquisition selector (use existing valid target, or find new one)
	var target_selector := SelectorComposite.new()
	target_selector.name = "TargetSelector"
	combat_seq.add_child(target_selector)
	
	var target_cond := HasTargetCondition.new()
	target_cond.name = "HasTarget"
	target_selector.add_child(target_cond)
	
	var find_target_act := FindTargetAction.new()
	find_target_act.name = "FindTarget"
	target_selector.add_child(find_target_act)
	
	# Attack mode selector (melee charge vs ranged kiting)
	var attack_selector := SelectorComposite.new()
	attack_selector.name = "AttackModeSelector"
	combat_seq.add_child(attack_selector)
	
	# Melee sub-branch
	var melee_seq := SequenceComposite.new()
	melee_seq.name = "MeleeSequence"
	attack_selector.add_child(melee_seq)
	
	var melee_cond := ShouldUseMeleeCondition.new()
	melee_cond.name = "ShouldUseMelee"
	melee_seq.add_child(melee_cond)
	
	var melee_act := ChargeMeleeAction.new()
	melee_act.name = "ChargeMelee"
	melee_seq.add_child(melee_act)
	
	# Ranged default
	var ranged_act := EngageRangedAction.new()
	ranged_act.name = "EngageRanged"
	attack_selector.add_child(ranged_act)
	
	return tree
