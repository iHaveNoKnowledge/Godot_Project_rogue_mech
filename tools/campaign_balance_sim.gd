extends Node
## ---------------------------------------------------------------------------
## CAMPAIGN AUTO-BATTLE BALANCE SIMULATOR — Phase C8-D tuning tool.
##
## Not a test. Runs two things and prints a table:
##   1. A parameter grid through `CampaignAutoBattle.simulate` (pure formula,
##      so candidate ratios can be evaluated without touching constants).
##   2. A REAL campaign playthrough: starts the canonical `frontier_skirmish`
##      scenario through `RunStartSystem`, seeds the player garrison, injects
##      a hostile force at the player base node, then advances real campaign
##      turns and reports what the strategic layer actually resolves.
##
## Usage (headless):
##   godot --headless --path . res://tools/campaign_balance_sim.tscn
## ---------------------------------------------------------------------------

const SCENARIO_ID := "frontier_skirmish"
const DEFENDER_STRENGTHS := [10, 12, 15, 20, 25, 32]
const ATTACKER_STRENGTHS := [10, 20, 30, 40]
const RATIO_CANDIDATES := [0.15, 0.2, 0.25]


func _ready() -> void:
	print("=== AUTO-BATTLE BALANCE (production ratio %.2f, max %d rounds) ===" % [
		CampaignAutoBattle.ATTRITION_RATIO, CampaignAutoBattle.MAX_ROUNDS])
	_print_grid()
	_print_ratio_sweep()
	_run_real_playthrough()
	await get_tree().process_frame
	get_tree().quit(0)


func _print_grid() -> void:
	var header := "DEF vs ATT"
	for atk in ATTACKER_STRENGTHS:
		header += " | atk %d" % atk
	print(header)
	for def in DEFENDER_STRENGTHS:
		var row := "def %3d" % def
		for atk in ATTACKER_STRENGTHS:
			var r := CampaignAutoBattle.simulate(def, atk)
			row += " | %s r%d %d/%d" % [
				_short(str(r.get("winner", ""))),
				int(r.get("rounds", 0)),
				int(r.get("defender_remaining", 0)),
				int(r.get("attacker_remaining", 0)),
			]
		print(row)


func _print_ratio_sweep() -> void:
	print("--- ratio sweep: defender 20, attacker 20 / 30 ---")
	for ratio in RATIO_CANDIDATES:
		var row := "ratio %.2f" % ratio
		for atk in [20, 30]:
			var r := CampaignAutoBattle.simulate(20, atk, ratio, 5)
			row += " | vs %d: %s r%d %d/%d" % [
				atk,
				_short(str(r.get("winner", ""))),
				int(r.get("rounds", 0)),
				int(r.get("defender_remaining", 0)),
				int(r.get("attacker_remaining", 0)),
			]
		print(row)


func _run_real_playthrough() -> void:
	print("--- REAL PLAYTHROUGH: %s ---" % SCENARIO_ID)
	GlobalData.reset_run_data()
	var start := RunStartSystem.start_campaign_scenario(SCENARIO_ID)
	print("start ok=%s node=%s" % [
		str(start.get("ok", false)), str(start.get("player_node_id", ""))])
	var player_base := _first_player_base()
	if player_base.is_empty():
		print("no player base in scenario — aborting playthrough")
		return
	var base_id := str(player_base.get("id", ""))
	var node_id := str(player_base.get("node_id", ""))
	print("player base=%s node=%s garrison=%s" % [
		base_id, node_id,
		str(CampaignPlayerForce.get_active_at_node(node_id)),
	])

	# One hostile push at the player's base, strength from the authored zeon force.
	var attacker_strength := 30
	var attacker := CampaignForce.register_force(
		"force_sim_zeon_push", "PATROL", "zeon", node_id, "", 3, attacker_strength)
	print("hostile push registered=%s strength=%d" % [attacker, attacker_strength])

	for turn in range(1, 8):
		var receipt := CampaignTurnExecutive.advance_campaign_turn(
			"balance_sim", {"spy_roll": false, "enemy_base_points": 0.0, "board_tiles": {}})
		var assault: Dictionary = receipt.get("strategic_assault", {})
		print("turn %d | created=%s resolved=%s deferred=%s" % [
			int(receipt.get("turn", turn)),
			str(assault.get("created", [])),
			str(assault.get("auto_resolved", [])),
			str(assault.get("deferred", [])),
		])
	print("after playthrough base_state=%s controller=%s garrison=%s" % [
		CampaignBase.state_to_name(CampaignBase.get_state(base_id)),
		str(CampaignBase.get_base(base_id).get("controller", "")),
		str(CampaignPlayerForce.get_active_at_node(node_id)),
	])


func _first_player_base() -> Dictionary:
	var player_faction := FactionSystem.get_player_faction()
	for base in CampaignBase.get_bases():
		if int(base.get("state", -1)) == CampaignBase.BaseState.DESTROYED:
			continue
		if str(base.get("controller", "")) == player_faction:
			return base
	return {}


func _short(winner: String) -> String:
	match winner:
		"defender":
			return "HOLD"
		"attacker":
			return "LOSE"
		"mutual_destruction":
			return "BOTH"
		"player":
			return "WIN "
		"enemy":
			return "LOSS"
		_:
			return "TIE "
