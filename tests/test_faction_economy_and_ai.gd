extends SceneTree

const FactionEconomySystem = preload("res://scripts/systems/faction_economy_system.gd")
const MechaAIController = preload("res://scripts/mecha/ai/mecha_ai_controller.gd")
const EnemyAttackTemplates = preload("res://scripts/mecha/ai/enemy_attack_templates.gd")
const BoardConfig = preload("res://scripts/board/board_config.gd")

func _init() -> void:
	print("====================================================")
	print("TEST: Faction Economy, Tactical AI & Board Systems")
	print("====================================================")

	var all_passed := true

	# 1. Test BoardConfig terrain passability
	print("\n[TEST 1] BoardConfig Terrain Passability...")
	var rock_passable := BoardConfig.is_passable("rock")
	var rock_cost := BoardConfig.move_cost("rock")
	var urban_passable := BoardConfig.is_passable("urban")
	var water_passable := BoardConfig.is_passable("water")
	if rock_passable and rock_cost == 3 and urban_passable and not water_passable:
		print("  PASS: Rock (cost=3) and Urban are passable; deep water remains impassable.")
	else:
		print("  FAIL: Rock passable=%s cost=%d urban=%s water=%s" % [rock_passable, rock_cost, urban_passable, water_passable])
		all_passed = false

	# 2. Test FactionEconomySystem
	print("\n[TEST 2] FactionEconomySystem...")
	var eco := FactionEconomySystem.get_economy("federation")
	if eco.is_empty():
		print("  FAIL: Economy initialization failed.")
		all_passed = false
	else:
		print("  PASS: Federation economy active with funds=%d parts=%d stock=%d" % [eco["funds"], eco["parts"], eco["hangar_stock"]])

	var pilot := FactionEconomySystem.pilot_generate("federation", 1)
	if not pilot.is_empty() and pilot.get("faction") == "federation":
		print("  PASS: Generated pilot: %s (callsign: %s)" % [pilot.get("name", ""), pilot.get("callsign", "")])
	else:
		print("  FAIL: Pilot generation failed.")
		all_passed = false

	var unit := FactionEconomySystem.produce_unit("federation", "grunt")
	if not unit.is_empty() and unit.has("pilot"):
		print("  PASS: Assembled unit successfully paired with pilot.")
	else:
		print("  FAIL: Unit assembly failed.")
		all_passed = false

	# Test supply line severed
	FactionEconomySystem.sever_supply_line("federation", 3000, 200)
	var starved := FactionEconomySystem.is_faction_starved("federation")
	if starved:
		print("  PASS: Federation entered starved/depleted state after supply line was severed.")
	else:
		print("  FAIL: Federation did not enter starved state.")
		all_passed = false

	# Test Checkpoint Outposts
	var cp_pos := Vector2i(4, 7)
	FactionEconomySystem.register_checkpoint(cp_pos, "federation", 3)
	var cp := FactionEconomySystem.get_checkpoint_at(cp_pos)
	if not cp.is_empty() and cp.get("strength") == 3:
		print("  PASS: Checkpoint outpost registered at %s." % str(cp_pos))
	else:
		print("  FAIL: Checkpoint registration failed.")
		all_passed = false
	FactionEconomySystem.remove_checkpoint_at(cp_pos)

	# 3. Test MechaAIController Postures and Energy
	print("\n[TEST 3] MechaAIController Postures & Mobility...")
	var dummy_actor := CharacterBody3D.new()
	var ai := MechaAIController.new()
	ai.actor = dummy_actor
	dummy_actor.add_child(ai)
	root.add_child(dummy_actor)

	# Test energy regeneration
	ai.ai_energy = 50.0
	ai.update_ai_decisions(1.0)
	if ai.ai_energy > 50.0:
		print("  PASS: AI energy recharged when walking/idle (energy=%.1f)." % ai.ai_energy)
	else:
		print("  FAIL: AI energy did not recharge.")
		all_passed = false

	# Test Starved Gak Posture
	ai.is_starved = true
	var dec_gak := ai.update_ai_decisions(0.1)
	if ai.posture == "gak":
		print("  PASS: AI correctly switched to 'gak' (conservative) posture when starved.")
	else:
		print("  FAIL: AI posture is %s (expected 'gak')." % ai.posture)
		all_passed = false

	# 4. Test EnemyAttackTemplates walk vs roller speeds
	print("\n[TEST 4] EnemyAttackTemplates speed parity...")
	var rusher_stats := EnemyAttackTemplates.get_stats(EnemyAttackTemplates.Archetype.RUSHER)
	if rusher_stats.get("move_speed", 0.0) < 10.0 and rusher_stats.get("roller_speed", 0.0) >= 14.0:
		print("  PASS: Walk speed (%.1f m/s) properly separated from roller speed (%.1f m/s)." % [rusher_stats["move_speed"], rusher_stats["roller_speed"]])
	else:
		print("  FAIL: Speed separation invalid: %s" % str(rusher_stats))
		all_passed = false

	print("\n====================================================")
	if all_passed:
		print("ALL UNIT TESTS PASSED SUCCESSFULLY!")
	else:
		print("SOME TESTS FAILED.")
	print("====================================================")
	quit(0 if all_passed else 1)
