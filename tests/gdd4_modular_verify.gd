extends Node

const BoardConfig = preload("res://scripts/board/board_config.gd")
const PatrolSystem = preload("res://scripts/systems/patrol_system.gd")
const BoardSystem = preload("res://scripts/systems/board_system.gd")
const PilotSystem = preload("res://scripts/systems/pilot_system.gd")
const PilotGenerator = preload("res://scripts/systems/pilot_generator.gd")

## Headless verification of GDD v4.0 Master Modular Architecture features:
##   1. Dual-Cost Energy Movement (Road, Mud/Off-road, Roller Dash)
##   2. 4 Fleet Archetypes & Properties (Recon, Armored, Artillery, Hunter-Killer)
##   3. Zone of Control (ZoC) detection
##   4. Artillery Bombardment Range detection
##   5. Board HUD Scene structure

var _fails := 0
var _checks := 0


func _check(cond: bool, name: String) -> void:
	_checks += 1
	if cond:
		print("GDD4_OK: " + name)
	else:
		_fails += 1
		printerr("GDD4_FAIL: " + name)


func _ready() -> void:
	print("--- Running GDD v4.0 Master Modular Verification ---")
	GlobalData.reset_run_data()

	# 1. Dual-Cost Movement & Terrain Energy Costs (GDD §3.1)
	_check(BoardConfig.energy_cost("road", false) == 10.0, "road energy cost is 10")
	_check(BoardConfig.energy_cost("sand", false) == 25.0, "sand energy cost is 25")
	_check(BoardConfig.energy_cost("forest", false) == 25.0, "forest energy cost is 25")
	_check(BoardConfig.energy_cost("road", true) == 5.0, "roller dash mode on road is 5")
	_check(BoardConfig.energy_cost("plain", true) == 35.0, "roller dash off-road penalty is 35")

	GlobalData.board_roller_mode = false
	_check(GlobalData.get_tile_energy_cost("road") == 10.0, "GlobalData get_tile_energy_cost road standard")
	GlobalData.board_roller_mode = true
	_check(GlobalData.get_tile_energy_cost("road") == 5.0, "GlobalData get_tile_energy_cost road roller")

	# 2. 4 Fleet Archetypes (GDD §3.3)
	_check(BoardConfig.FLEET_ARCHETYPES.has("recon"), "has recon fleet archetype")
	_check(BoardConfig.FLEET_ARCHETYPES.has("armored"), "has armored fleet archetype")
	_check(BoardConfig.FLEET_ARCHETYPES.has("artillery"), "has artillery fleet archetype")
	_check(BoardConfig.FLEET_ARCHETYPES.has("hunter_killer"), "has hunter_killer fleet archetype")

	_check(BoardConfig.FLEET_ARCHETYPES["recon"]["mp"] == 4, "recon MP is 4")
	_check(BoardConfig.FLEET_ARCHETYPES["armored"]["mp"] == 1, "armored MP is 1")
	_check(BoardConfig.FLEET_ARCHETYPES["artillery"]["mp"] == 1, "artillery MP is 1")
	_check(BoardConfig.FLEET_ARCHETYPES["artillery"]["bombard_range"] == 2, "artillery bombard range is 2")
	_check(BoardConfig.FLEET_ARCHETYPES["hunter_killer"]["mp"] == 3, "hunter_killer MP is 3")

	# 3. Zone of Control (ZoC) (GDD §3.3)
	GlobalData.board_patrols = [
		{
			"id": 1, "pos": Vector2i(5, 5), "home": Vector2i(5, 5),
			"name": "Armored Iron", "grunts": 2, "aces": 0, "aggro": false,
			"archetype": "armored", "faction": "hostile", "character_id": "", "dir": Vector2i(1, 0),
		}
	]
	_check(PatrolSystem.is_in_zone_of_control(Vector2i(5, 6)), "adjacent tile (5,6) is in Zone of Control")
	_check(PatrolSystem.is_in_zone_of_control(Vector2i(4, 5)), "adjacent tile (4,5) is in Zone of Control")
	_check(not PatrolSystem.is_in_zone_of_control(Vector2i(7, 7)), "far tile (7,7) is not in Zone of Control")

	# 4. Artillery Bombardment (GDD §3.3)
	GlobalData.board_patrols = [
		{
			"id": 2, "pos": Vector2i(10, 10), "home": Vector2i(10, 10),
			"name": "Artillery Battery", "grunts": 1, "aces": 0, "aggro": false,
			"archetype": "artillery", "faction": "hostile", "character_id": "", "dir": Vector2i(0, 1),
		}
	]
	var in_range = PatrolSystem.check_artillery_bombardment(Vector2i(10, 12))
	_check(in_range.size() == 1, "distance 2 is within artillery bombardment range")
	var out_of_range = PatrolSystem.check_artillery_bombardment(Vector2i(10, 13))
	_check(out_of_range.is_empty(), "distance 3 is outside artillery bombardment range")

	# 5. Board HUD Scene verification
	var hud_scene = preload("res://scenes/ui/board_hud.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)
	_check(hud != null, "board_hud instantiated successfully")
	_check(hud.layer == 10, "board_hud layer is 10 (base board layer)")
	_check(hud._energy_bar != null, "energy bar created in board hud")
	_check(hud._convoy_hp_bar != null, "convoy hp bar created in board hud")
	_check(hud._unit_status_panel != null, "unit status panel created in board hud")
	_check(hud._inspector_panel != null, "tile inspector panel created in board hud")
	hud.queue_free()

	# 6. UI Layer Priority & Z-Index hierarchy verification
	var event_ui = preload("res://scenes/ui/event_ui.tscn").instantiate()
	add_child(event_ui)
	_check(event_ui.layer == 100, "EventUI layer is 100 (highest priority modal)")
	event_ui.queue_free()

	var tooltip_ui = preload("res://scenes/ui/board_tooltip_ui.tscn").instantiate()
	add_child(tooltip_ui)
	_check(tooltip_ui.layer == 15, "BoardTooltipUI layer is 15 (below modals)")
	tooltip_ui.queue_free()

	# 7. Pilot Generator & Massive Name Pool verification
	_check(PilotGenerator.FIRST_NAMES.size() >= 150, "First names pool has >= 150 entries (has %d)" % PilotGenerator.FIRST_NAMES.size())
	_check(PilotGenerator.CALLSIGNS.size() >= 100, "Callsigns pool has >= 100 entries (has %d)" % PilotGenerator.CALLSIGNS.size())
	_check(PilotGenerator.LAST_NAMES.size() >= 150, "Last names pool has >= 150 entries (has %d)" % PilotGenerator.LAST_NAMES.size())

	var sample_pilot := PilotGenerator.generate_pilot()
	_check(sample_pilot.has("name") and sample_pilot["name"] != "", "PilotGenerator generated valid full name: %s" % sample_pilot.get("name", ""))
	_check(sample_pilot.has("perk_name") and sample_pilot["perk_name"] != "", "PilotGenerator generated valid perk: %s" % sample_pilot.get("perk_name", ""))
	_check(sample_pilot.has("background") and sample_pilot["background"] != "", "PilotGenerator generated background: %s" % sample_pilot.get("background", ""))

	var replacement := PilotSystem.record_pilot_permadeath(sample_pilot["name"], "Mech Core Overheat Breach")
	_check(GlobalData.fallen_pilots.size() == 1, "Fallen pilots memorial recorded casualty")
	_check(replacement.has("name") and replacement["name"] != sample_pilot["name"], "Replacement pilot generated: %s" % replacement.get("name", ""))

	# 8. Nemesis Rival Pilot & Faction Mobilization verification
	var mock_tile_1 = Node.new()
	mock_tile_1.set_meta("tile_type", "empty")
	mock_tile_1.set_meta("terrain", "plain")
	var mock_tile_2 = Node.new()
	mock_tile_2.set_meta("tile_type", "empty")
	mock_tile_2.set_meta("terrain", "plain")
	GlobalData.board_grid = [{ Vector2i(5, 5): mock_tile_1, Vector2i(6, 6): mock_tile_2 }]
	GlobalData.board_patrols.clear()
	PatrolSystem.spawn_patrols()
	_check(GlobalData.board_patrols.size() > 0, "patrols spawned successfully")
	var patrol_lead = GlobalData.board_patrols[0]
	_check(patrol_lead.has("commander") and patrol_lead["commander"].has("name"), "patrol fleet has assigned named commander: %s" % patrol_lead.get("commander", {}).get("name", ""))

	var initial_bounty: int = int(patrol_lead["commander"].get("bounty", 150))
	var initial_rivalry: int = int(patrol_lead["commander"].get("rivalry_count", 0))

	# Test Escape/Retreat: Rival survives and rivalry escalates
	GlobalData.board_patrol_engagement = int(patrol_lead.get("id"))
	PatrolSystem.resolve_patrol_combat(false) # false = player escaped / retreated
	_check(patrol_lead["commander"]["rivalry_count"] == initial_rivalry + 1, "rivalry count escalated after retreat (now %d)" % patrol_lead["commander"]["rivalry_count"])
	_check(patrol_lead["commander"]["is_nemesis"] == true, "commander is now marked as Nemesis Rival")
	_check(patrol_lead["commander"]["bounty"] > initial_bounty, "bounty increased for nemesis rival (now %d)" % patrol_lead["commander"]["bounty"])
	_check(GlobalData.rival_pilots.size() > 0, "surviving rival recorded in GlobalData.rival_pilots")

	# Test Victory: Rival is eliminated and bounty is collected
	var prev_credits := GlobalData.credits
	GlobalData.board_patrol_engagement = int(patrol_lead.get("id"))
	PatrolSystem.resolve_patrol_combat(true) # true = player victory
	_check(GlobalData.defeated_rivals.size() > 0, "defeated rival recorded in GlobalData.defeated_rivals")
	_check(GlobalData.credits > prev_credits, "bounty reward credited on rival defeat (+%d Cr)" % (GlobalData.credits - prev_credits))

	mock_tile_1.free()
	mock_tile_2.free()

	print("\nVerification Complete: %d checks, %d failures" % [_checks, _fails])
	if _fails > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
