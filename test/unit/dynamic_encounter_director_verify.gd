extends Node

## DYNAMIC ENCOUNTER DIRECTOR VERIFICATION
## Validates tactical counter-adaptation, encounter triggers, and rival ace prototype deployment.

var _checks: int = 0
var _fails: int = 0

const DynamicEncounterDirector = preload("res://scripts/systems/dynamic_encounter_director.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("DIRECTOR_OK: " + msg)
	else:
		_fails += 1
		printerr("DIRECTOR_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame
	print("=== STARTING DYNAMIC ENCOUNTER DIRECTOR VERIFICATION ===")

	_test_1_tactical_counter_adaptation_rules()
	_test_2_encounter_trigger_evaluation()
	await _test_3_rival_prototype_spawn_integration()

	print("=== DYNAMIC ENCOUNTER DIRECTOR VERIFICATION FINISHED: Checks=%d, Fails=%d ===" % [_checks, _fails])
	if _fails > 0:
		printerr("TEST FAILED WITH %d ERRORS" % _fails)
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _test_1_tactical_counter_adaptation_rules() -> void:
	print("\n--- Test 1: Tactical Counter Adaptation Rules ---")
	
	# Rule 1: Against Melee -> Counter with SHIELD_RANGED (Archetype 5)
	var proto_anti_melee = DynamicEncounterDirector.generate_counter_prototype("melee")
	_check(proto_anti_melee["archetype"] == 5, "Counter against Melee is Archetype 5 (Shield Ranged)")
	_check("beam" in proto_anti_melee["tech_id"], "Anti-Melee equips beam suppression weaponry")
	_check(proto_anti_melee["tactical_stance"] == "Kite_And_Disrupt", "Anti-Melee stance is Kite_And_Disrupt")
	
	# Rule 2: Against Long Range / Sniper -> Counter with SHIELD_MELEE (Archetype 4)
	var proto_anti_range = DynamicEncounterDirector.generate_counter_prototype("long_range")
	_check(proto_anti_range["archetype"] == 4, "Counter against Long Range is Archetype 4 (Shield Melee)")
	_check(proto_anti_range["speed_mult"] > 1.25, "Anti-Ranged gains bonus closure speed")
	_check(proto_anti_range["tactical_stance"] == "Frontal_Breaker", "Anti-Ranged stance is Frontal_Breaker")
	
	# Rule 3: Against Defense / Heavy Armor -> Counter with HEAVY (Archetype 2)
	var proto_anti_armor = DynamicEncounterDirector.generate_counter_prototype("defense")
	_check(proto_anti_armor["archetype"] == 2, "Counter against Defense is Archetype 2 (Heavy)")
	_check(proto_anti_armor["damage_mult"] > 1.4, "Anti-Armor gains bonus damage multiplier")


func _test_2_encounter_trigger_evaluation() -> void:
	print("\n--- Test 2: Encounter Trigger Evaluation ---")
	RivalProgSys.reset()
	
	_check(not DynamicEncounterDirector.should_trigger_encounter(), "No trigger when no pending prototype or heat")
	
	RivalProgSys.pending_prototype_encounter = true
	_check(DynamicEncounterDirector.should_trigger_encounter(), "Triggers encounter when pending_prototype_encounter is true")
	
	RivalProgSys.pending_prototype_encounter = false


func _test_3_rival_prototype_spawn_integration() -> void:
	print("\n--- Test 3: SpawnManager.spawn_rival_prototype Integration ---")
	var sm = SpawnManager.new()
	add_child(sm)
	await get_tree().process_frame

	RivalProgSys.pending_prototype_encounter = true
	var proto = DynamicEncounterDirector.generate_counter_prototype("long_range")
	proto["name"] = "Rival Test Unit"
	proto["pilot_callsign"] = "Shadow"

	var rival_mech = await sm.spawn_rival_prototype(proto, Vector3.ZERO)
	_check(rival_mech != null, "Rival prototype instantiated successfully")
	if rival_mech:
		_check(rival_mech.is_in_group("rival_ace"), "Rival tagged in rival_ace group")
		_check(rival_mech.is_in_group("boss"), "Rival tagged in boss group")
		_check(rival_mech.get_node_or_null("MechaAIController") != null, "MechaAIController attached to Rival")
		_check(not RivalProgSys.pending_prototype_encounter, "Pending prototype state cleared after spawn")
		rival_mech.queue_free()

	sm.queue_free()
