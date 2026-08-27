extends Node

var _failures: int = 0


func _ready() -> void:
	print("--- Running procedural_lore_and_faction_verify ---")
	await _verify_procedural_lore_and_factions()
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS: %s" % message)
	else:
		_failures += 1
		print("  FAIL: %s" % message)


func _verify_procedural_lore_and_factions() -> void:
	# 1. Initialize lore with Federation role
	var fed_lore = ProceduralLoreSystem.initialize_run_lore(ProceduralLoreSystem.PlayerRole.FEDERATION_SOLDIER)
	_check(fed_lore.get("role", "") == "Federation Vanguard Soldier", "role is Federation Soldier")
	_check(fed_lore.get("origin", "") != "", "generated valid tech origin")
	_check(ProceduralLoreSystem.rival_commander_pilot.size() > 0, "procedural rival commander generated")
	_check(ProceduralLoreSystem.rival_ace_squad.size() == 2, "rival ace squad initialized with 2 pilots")

	var fed_perks = ProceduralLoreSystem.get_role_perks()
	_check(fed_perks.get("federation_standing", 0) > 0, "federation soldier has positive federation standing")

	# 2. Initialize lore with Scavenger role
	var scav_lore = ProceduralLoreSystem.initialize_run_lore(ProceduralLoreSystem.PlayerRole.THIRD_PARTY_SCAVENGER)
	_check(scav_lore.get("role", "") == "Third-Party Scavenger (Neutral Mercenary)", "role is Third-Party Scavenger")
	var scav_perks = ProceduralLoreSystem.get_role_perks()
	_check(scav_perks.get("black_market_discount", 0.0) > 0.0, "scavenger gains black market discount")
	_check(scav_perks.get("scrap_bonus", 1.0) > 1.0, "scavenger gains scrap salvage multiplier")


func _finish() -> void:
	if _failures == 0:
		print("All procedural_lore_and_faction_verify tests passed.")
		get_tree().quit(0)
	else:
		print("procedural_lore_and_faction_verify failed with %d error(s)." % _failures)
		get_tree().quit(1)
