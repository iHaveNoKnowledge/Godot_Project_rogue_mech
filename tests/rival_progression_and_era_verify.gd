extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running rival_progression_and_era_verify ---")
	await _verify_rival_progression()
	await _verify_era_progression()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_rival_progression() -> void:
	RivalProgressionSystem.reset()
	_check(RivalProgressionSystem.scout_tier == 1, "rival scout tier starts at 1")

	# Check Fog of War masking
	var fow = RivalProgressionSystem.get_fog_of_war_tech_tree()
	_check(fow["laboratory"]["revealed"] == false, "laboratory tech tree is hidden under Fog of War")
	_check(fow["laboratory"]["tier"] == -1, "masked tier returns -1")

	# Reveal intel
	RivalProgressionSystem.reveal_intel("laboratory")
	fow = RivalProgressionSystem.get_fog_of_war_tech_tree()
	_check(fow["laboratory"]["revealed"] == true, "laboratory intel revealed after scanning")

	# Advance turns behind the scenes
	var results = RivalProgressionSystem.advance_rival_turn(10)
	_check(results["scout_farmed"] > 0, "rival farmed scrap & resources across turns")
	_check(RivalProgressionSystem.scout_tier >= 2 or RivalProgressionSystem.lab_tier >= 2, "rival tech branches progress over turns")


func _verify_era_progression() -> void:
	EraProgressionSystem.reset()
	_check(EraProgressionSystem.current_phase == EraProgressionSystem.EraPhase.PHASE_1_TACTICAL, "starts in Phase 1 Tactical Era")
	
	var mods_p1 = EraProgressionSystem.get_era_modifiers()
	_check(mods_p1["ballistic_damage_mult"] > 1.0, "Phase 1 emphasizes ballistic damage")
	_check(mods_p1["cover_defense_bonus"] > 0.3, "Phase 1 has strong cover mechanics")

	# Advance to Phase 2 (Energy Era)
	var res_p2 = EraProgressionSystem.advance_war_turn(15)
	_check(EraProgressionSystem.current_phase == EraProgressionSystem.EraPhase.PHASE_2_ENERGY, "advances to Phase 2 Energy Era at Turn 16")
	var mods_p2 = EraProgressionSystem.get_era_modifiers()
	_check(mods_p2["energy_damage_mult"] > 1.2, "Phase 2 boosts energy / beam damage")
	_check(mods_p2["unlocked_burst_mode"] == true, "Phase 2 unlocks burst mode thrusters")

	# Advance to Phase 3 (Singularity Era)
	var res_p3 = EraProgressionSystem.advance_war_turn(15)
	_check(EraProgressionSystem.current_phase == EraProgressionSystem.EraPhase.PHASE_3_SINGULARITY, "advances to Phase 3 Singularity Era at Turn 31+")
	var mods_p3 = EraProgressionSystem.get_era_modifiers()
	_check(mods_p3["omni_barrier_active"] == true, "Phase 3 activates omni barriers")


func _finish() -> void:
	if _failures == 0:
		print("All rival_progression_and_era_verify tests passed.")
		get_tree().quit(0)
	else:
		print("rival_progression_and_era_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
