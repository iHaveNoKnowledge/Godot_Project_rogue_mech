class_name PatrolSystem
extends RefCounted

# -----------------------------------------------------------------------------
# ENEMY PATROL FLEETS
# Fleets roam the open board grid. They patrol near their home anchor, but the
# moment the player's convoy gets close they turn aggressive and pursue. Each
# day (EventBus.board_day_ended) they move one cell. Stepping onto a patrol
# cell (or letting one step onto you) forces combat.
#
# State lives in GlobalData.board.board_patrols (Array of Dictionaries) so it survives
# scene changes and save/load. Each entry:
#   {id, pos: Vector2i, home: Vector2i, name, grunts, aces, aggro: bool,
#    faction: "hostile" | "unknown", character_id: String}
# -----------------------------------------------------------------------------

const NAMES := ["Ravens", "Vultures", "Jackals", "Hawks", "Coyotes", "Strykers"]
const GRUNT_MIN: int = 1
const GRUNT_MAX: int = 3

# How close a hostile fleet must be to smell the convoy (base). Grows as
# patrol_alert climbs, so lingering near patrols widens their hunt.
const DETECT_BASE := 4
const ALERT_MAX := 4


# Patrol entries carry their heading (and pos/home) as Vector2i at runtime, but
# a save file flattens Vector2i into a String like "(1, 0)" or stores {x, y}
# dicts. normalize_dir() parses every shape back into a real Vector2i so board
# arrow markers always have a heading to face — a fleet whose dir broke used to
# spawn without its arrow after loading a save.
static func normalize_dir(v: Variant) -> Vector2i:
	if v is Vector2i:
		return v
	if v is Vector2:
		var v2: Vector2 = v
		return Vector2i(roundi(v2.x), roundi(v2.y))
	if v is Dictionary:
		return Vector2i(int(v.get("x", 1)), int(v.get("y", 0)))
	if v is String:
		return _parse_dir_string(v)
	return Vector2i(1, 0)


static func _parse_dir_string(raw: String) -> Vector2i:
	var clean := raw.replace("(", "").replace(")", "").replace("Vector2i", "").strip_edges()
	var parts := clean.split(",")
	if parts.size() >= 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(1, 0)


# Repairs a patrol entry (old saves / JSON round-trips) so pos/home/dir are all
# real Vector2i. Mutates the dictionary in place; the board heals every fleet
# whenever it redraws the arrow markers.
static func normalize_patrol(p: Dictionary) -> void:
	p["pos"] = normalize_dir(p.get("pos"))
	p["home"] = normalize_dir(p.get("home"))
	p["dir"] = normalize_dir(p.get("dir"))
	p["fleet_count"] = maxi(int(p.get("fleet_count", 1)), 1)
	if not p.has("merged_fleets") or not p["merged_fleets"] is Array:
		p["merged_fleets"] = []
	if p.has("prev_pos"):
		p["prev_pos"] = normalize_dir(p.get("prev_pos"))
	if not p.has("commander") or not p["commander"] is Dictionary or p["commander"].is_empty():
		var arch_str: String = str(p.get("archetype", "armored"))
		p["commander"] = PilotGenerator.generate_pilot({
			"archetype": BoardConfig.FLEET_ARCHETYPES.get(arch_str, {}).get("mp", 1),
			"level": GlobalData.board.current_sector,
		})


## Merges source fleet into target fleet on the board.
static func merge_fleets(target_id: int, source_id: int) -> bool:
	if target_id == source_id:
		return false
	var target := get_patrol_by_id(target_id)
	var source := get_patrol_by_id(source_id)
	if target.is_empty() or source.is_empty():
		return false

	normalize_patrol(target)
	normalize_patrol(source)
	var add_count: int = int(source.get("fleet_count", 1))
	target["fleet_count"] += add_count
	var sub_fleets: Array = target.get("merged_fleets", [])
	sub_fleets.append(source.duplicate(true))
	target["merged_fleets"] = sub_fleets

	remove_patrol(source_id)
	return true


## Splits 1 sub-fleet from a multi-fleet token (fleet_count > 1) to an adjacent tile.
static func split_fleet(patrol_id: int, target_pos: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var p := get_patrol_by_id(patrol_id)
	if p.is_empty() or int(p.get("fleet_count", 1)) <= 1:
		return {}

	normalize_patrol(p)
	p["fleet_count"] -= 1
	var sub_fleets: Array = p.get("merged_fleets", [])
	var detached_template: Dictionary = {}
	if not sub_fleets.is_empty():
		detached_template = sub_fleets.pop_back()
	p["merged_fleets"] = sub_fleets

	var max_id := 0
	for item in GlobalData.board.board_patrols:
		max_id = maxi(max_id, int(item.get("id", 0)))
	var new_id := max_id + 1

	var cur_pos: Vector2i = p.get("pos")
	var split_pos := target_pos if target_pos != Vector2i(-1, -1) else cur_pos

	var detached_fleet := {
		"id": new_id,
		"pos": split_pos,
		"home": cur_pos,
		"prev_pos": cur_pos,
		"dir": p.get("dir", Vector2i(1, 0)),
		"name": detached_template.get("name", p.get("name", "Vanguard Strike")),
		"grunts": detached_template.get("grunts", p.get("grunts", 2)),
		"aces": detached_template.get("aces", p.get("aces", 0)),
		"aggro": p.get("aggro", true),
		"faction": p.get("faction", "hostile"),
		"archetype": detached_template.get("archetype", p.get("archetype", "recon")),
		"character_id": detached_template.get("character_id", ""),
		"fleet_count": 1,
		"merged_fleets": [],
		"commander": detached_template.get("commander", {}),
	}
	normalize_patrol(detached_fleet)
	GlobalData.board.board_patrols.append(detached_fleet)
	return detached_fleet


static func _merge_coincident_fleets() -> void:
	var pos_map: Dictionary = {} # Vector2i -> Array[Dictionary]
	for p in GlobalData.board.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		var pos: Vector2i = PatrolSystem.normalize_dir(p.get("pos"))
		if not pos_map.has(pos):
			pos_map[pos] = []
		pos_map[pos].append(p)

	for pos in pos_map:
		var list: Array = pos_map[pos]
		if list.size() <= 1:
			continue
		var primary: Dictionary = list[0]
		normalize_patrol(primary)
		for i in range(1, list.size()):
			var sec: Dictionary = list[i]
			normalize_patrol(sec)
			primary["fleet_count"] += int(sec.get("fleet_count", 1))
			primary["merged_fleets"].append(sec.duplicate(true))
			remove_patrol(int(sec.get("id", -1)))


static func _check_tactical_fleet_splits(nodes: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator, player_pos: Vector2i) -> void:
	var snapshot := GlobalData.board.board_patrols.duplicate()
	for p in snapshot:
		if int(p.get("fleet_count", 1)) <= 1:
			continue
		if not p.get("aggro", false):
			continue
		# 40% tactical split chance when pursuing from a distance
		var cur: Vector2i = p.get("pos")
		if _manhattan(cur, player_pos) <= 1 or rng.randf() > 0.4:
			continue

		# Find a free adjacent passable tile to pincer
		var best_tile := Vector2i(-1, -1)
		var best_dist := 999
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cand: Vector2i = cur + offset
			if nodes.has(cand) and not occupied.has(cand) and BoardConfig.is_passable(nodes[cand].get_meta("terrain", "plain")):
				var d := _manhattan(cand, player_pos)
				if d < best_dist:
					best_dist = d
					best_tile = cand

		if best_tile != Vector2i(-1, -1):
			var new_fleet := split_fleet(int(p.get("id", -1)), best_tile)
			if not new_fleet.is_empty():
				occupied[best_tile] = true


static func has_patrols() -> bool:
	return not GlobalData.board.board_patrols.is_empty()


static func get_patrol_at(pos: Vector2i) -> Dictionary:
	for p in GlobalData.board.board_patrols:
		if p.get("pos") == pos:
			return p
	return {}


static func get_patrol_by_id(id: int) -> Dictionary:
	for p in GlobalData.board.board_patrols:
		if int(p.get("id", -1)) == id:
			return p
	return {}


static func remove_patrol(id: int) -> void:
	for i in range(GlobalData.board.board_patrols.size() - 1, -1, -1):
		if int(GlobalData.board.board_patrols[i].get("id", -1)) == id:
			GlobalData.board.board_patrols.remove_at(i)
			return


# Spawns patrol fleets on the freshly generated board. Called by the board
# manager after generation (only when no fleets exist yet for this sector).
static func spawn_patrols() -> void:
	if not GlobalData.board.board_patrols.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board.board_seed + 7919
	var theme := GlobalData.board.board_theme_id
	var count: int
	match theme:
		"urban":
			count = rng.randi_range(3, 4)
		"desert", "forest":
			count = rng.randi_range(2, 3)
		_:
			count = rng.randi_range(2, 4)
	# The patrol_hunt objective demands a fixed number of fleet destructions.
	# Never spawn fewer hostile fleets than the objective requires, or the
	# player can be soft-locked (objective never completes, exit stays sealed).
	var required_hostile := 0
	if BoardConfig.get_objective(theme).get("id", "") == "patrol_hunt":
		required_hostile = int(BoardConfig.get_objective(theme).get("required", 1))
	count = maxi(count, required_hostile)

	var grid_size := BoardConfig.GRID_SIZE
	var nodes: Dictionary = {}
	var grid: Array = GlobalData.board.board_grid
	if not grid.is_empty() and grid[0] is Dictionary:
		nodes = grid[0]

	var candidate: Array = []
	for key in nodes:
		var tile_type: String = nodes[key].get_meta("tile_type", "empty")
		if tile_type in ["start", "exit", "safehouse", "city", "enemy_base"]:
			continue
		if not BoardConfig.is_passable(nodes[key].get_meta("terrain", "plain")):
			continue
		candidate.append(key)
	candidate.shuffle()

	var id := 1
	var archetypes_pool := ["recon", "armored", "artillery"]
	for i in range(mini(count, candidate.size())):
		var home: Vector2i = candidate[i]
		var grunts := rng.randi_range(GRUNT_MIN, GRUNT_MAX)
		var aces := 1 if (rng.randf() < 0.30 and GlobalData.board.current_sector >= 2) else 0

		# Pick Fleet Archetype (GDD §3.3)
		var archetype := ""
		if aces > 0 or (GlobalData.board.wanted_level >= 3 and rng.randf() < 0.4):
			archetype = "hunter_killer"
			aces = 1
		else:
			archetype = archetypes_pool[i % archetypes_pool.size()]

		# Unknown fleets are mercenary convoys that fly a white arrow on the map.
		# They only show up once recruitable pilots exist and never carry aces.
		var faction := "hostile"
		var character_id := ""
		if aces == 0 and rng.randf() < 0.25 and _has_recruitable_pilot():
			faction = "unknown"
			character_id = _pick_recruitable_pilot()

		var commander: Dictionary = PilotGenerator.generate_pilot({
			"archetype": BoardConfig.FLEET_ARCHETYPES.get(archetype, {}).get("mp", 1),
			"level": GlobalData.board.current_sector,
		})
		commander["rivalry_count"] = 0
		commander["escapes"] = 0
		commander["is_nemesis"] = false
		commander["bounty"] = 120 + (GlobalData.board.current_sector * 50) + (100 if aces > 0 else 0)

		GlobalData.board.board_patrols.append({
			"id": id,
			"pos": home,
			"home": home,
			"name": NAMES[rng.randi() % NAMES.size()],
			"grunts": grunts,
			"aces": aces,
			"archetype": archetype,
			"aggro": false,
			"faction": faction,
			"character_id": character_id,
			"dir": Vector2i(1, 0),
			"commander": commander,
		})
		id += 1

	# Always deploy 1 Roaming Sector Supreme Commander (Boss) in the Fog of War
	if not candidate.is_empty():
		var boss_home: Vector2i = candidate[candidate.size() - 1]
		var boss_commander: Dictionary = PilotGenerator.generate_pilot({
			"archetype": 2,
			"level": GlobalData.board.current_sector + 2,
		})
		boss_commander["name"] = "OVERLORD " + NAMES[rng.randi() % NAMES.size()].to_upper()
		boss_commander["bounty"] = 650 + (GlobalData.board.current_sector * 200)
		boss_commander["is_boss"] = true

		GlobalData.board.board_patrols.append({
			"id": id,
			"pos": boss_home,
			"home": boss_home,
			"name": "👑 [BOSS] " + boss_commander["name"],
			"grunts": GRUNT_MAX + 1,
			"aces": 2,
			"archetype": "boss",
			"aggro": false,
			"faction": "hostile",
			"character_id": "",
			"dir": Vector2i(1, 0),
			"commander": boss_commander,
			"is_boss": true,
		})
		id += 1


# True when at least one recruitable pilot can still be met this run (so an
# unknown fleet's talk encounter has someone worth talking to).
static func _has_recruitable_pilot() -> bool:
	for character in RecruitSystem.CHARACTERS:
		if RecruitSystem.is_character_available(str(character.get("id", ""))):
			return true
	return false


# Picks a recruitable pilot for an unknown fleet (biased toward the current run
# theme so the fleet feels like a story beat rather than a random hire).
static func _pick_recruitable_pilot() -> String:
	var weighted_pool: Array[String] = []
	for character in RecruitSystem.CHARACTERS:
		var cid := str(character.get("id", ""))
		if not RecruitSystem.is_character_available(cid):
			continue
		var min_sector: int = int(character.get("min_sector", 1))
		if GlobalData.board.current_sector < min_sector:
			continue
		var w: int = int(character.get("weight", 6))
		var themes: Array = character.get("themes", [])
		if GlobalData.board.board_theme_id in themes:
			w = int(w * 1.5)
		for i in range(w):
			weighted_pool.append(cid)
	if not weighted_pool.is_empty():
		return weighted_pool.pick_random()
	return ""


# Advances every fleet according to its Archetype MP at the end of a day. Returns
# the position of a fleet that just moved onto the player (for an ambush), or (-1,-1).
static func advance_day(player_pos: Vector2i) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board.board_day * 101 + GlobalData.board.board_seed
	var nodes: Dictionary = {}
	var grid: Array = GlobalData.board.board_grid
	if not grid.is_empty() and grid[0] is Dictionary:
		nodes = grid[0]

	var occupied: Dictionary = {}
	for p in GlobalData.board.board_patrols:
		occupied[p.get("pos")] = true

	var detect := DETECT_BASE + clampi(GlobalData.board.patrol_alert, 0, ALERT_MAX)
	var saw_player := false
	var ambush := Vector2i(-1, -1)

	# Tactical fleet splitting: multi-fleet strike groups can split off flanking units
	_check_tactical_fleet_splits(nodes, occupied, rng, player_pos)

	for p in GlobalData.board.board_patrols:
		# Heal entries loaded from older saves before reading their fields.
		normalize_patrol(p)
		var cur: Vector2i = p.get("pos")
		var home: Vector2i = p.get("home")
		var dist := _manhattan(cur, player_pos)
		var archetype: String = str(p.get("archetype", "armored"))
		var fleet_mp: int = int(BoardConfig.FLEET_ARCHETYPES.get(archetype, {}).get("mp", 1))

		# Unknown fleets never chase the player; they wander and can only be
		# encountered when the player steps onto them.
		var is_unknown := str(p.get("faction", "hostile")) == "unknown"

		if not is_unknown and dist <= detect:
			p["aggro"] = true
			# Remember exactly where the convoy was spotted so fleets out of
			# sight still converge on that tile (reactive pursuit).
			GlobalData.board.patrol_last_seen = player_pos
			saw_player = true
		elif p.get("aggro", false) and dist > detect + 3:
			p["aggro"] = false

		# Multi-step movement based on Fleet Archetype MP (Recon = 4, HK = 3, Armored = 1)
		var is_vagrant := str(p.get("character_id", "")) == "vagrant_ace"
		var steps_to_take: int = fleet_mp if p.get("aggro", false) else mini(fleet_mp, 2)
		for step in range(steps_to_take):
			var next := cur
			if is_vagrant:
				# The Leading Shadow: Predicts player trajectory and steps 1 tile ahead on player's heading
				var p_dir: Vector2i = GlobalData.board.player_last_dir if GlobalData.board.player_last_dir != Vector2i.ZERO else Vector2i(1, 0)
				var lead_target := player_pos + p_dir
				if not nodes.has(lead_target) or not BoardConfig.is_passable(nodes[lead_target].get_meta("terrain", "plain")):
					lead_target = player_pos + Vector2i(p_dir.y, p_dir.x)
				next = _step_toward(cur, lead_target, nodes, occupied, rng)
			elif p.get("aggro", false):
				next = _step_toward(cur, player_pos, nodes, occupied, rng)
			elif not is_unknown and GlobalData.board.patrol_last_seen != Vector2i(-1, -1) \
					and rng.randf() < 0.7:
				# A fleet that lost visual still has the convoy's last heading: step
				# toward the trail instead of wandering back to its anchor.
				next = _step_toward(cur, GlobalData.board.patrol_last_seen, nodes, occupied, rng)
			elif rng.randf() < 0.6:
				next = _wander(cur, home, nodes, occupied, rng)

			if next != cur:
				occupied.erase(cur)
				occupied[next] = true
				p["prev_pos"] = cur
				p["pos"] = next
				# Remember the heading so the board's arrow marker can face it.
				p["dir"] = next - cur
				cur = next
				if next == player_pos:
					ambush = next
					break

	# Tactical fleet merging: allied fleets converging on the same tile stack together into 1 token
	_merge_coincident_fleets()

	# Parked Convoy Camouflage & 3-Stage Seizure System
	_process_parked_convoy_seizure(nodes, rng, player_pos)

	# The convoy is a moving target: force escalation climbs while a hostile
	# fleet keeps visual and cools back down once the player relocates.
	if saw_player:
		GlobalData.board.patrol_alert = mini(GlobalData.board.patrol_alert + 1, ALERT_MAX)
	else:
		GlobalData.board.patrol_alert = maxi(GlobalData.board.patrol_alert - 1, 0)
	return ambush


static func _process_parked_convoy_seizure(nodes: Dictionary, rng: RandomNumberGenerator, player_pos: Vector2i) -> void:
	# 1. Check if an enemy patrol stumbled upon the parked Convoy Base Camp while player is deployed elsewhere
	if GlobalData.fuel.convoy_is_deployed and player_pos != GlobalData.fuel.convoy_pos:
		var c_pos: Vector2i = GlobalData.fuel.convoy_pos
		var patrol_at_camp := get_patrol_at(c_pos)
		if not patrol_at_camp.is_empty() and str(patrol_at_camp.get("faction", "hostile")) != "unknown":
			if GlobalData.fuel.seizure_stage == 0:
				var terrain_str: String = "plain"
				if nodes.has(c_pos) and nodes[c_pos].has_meta("terrain"):
					terrain_str = str(nodes[c_pos].get_meta("terrain"))
				var camo_rate := GlobalData.fuel.get_camouflage_rate(terrain_str)
				if rng.randf() < camo_rate:
					GlobalData.board.run_notice = "🌿 PATROL EVADED: Enemy scouts passed by our camouflaged base camp without noticing."
				else:
					GlobalData.fuel.seizure_stage = 1
					GlobalData.fuel.seizure_turns_left = 2
					GlobalData.board.run_notice = "🚨 BASE COMPROMISED: Enemy scouts discovered our parked Base Camp! [Stage 1: Investigation - 2 turns remaining]"

	# 2. Advance 3-Stage Seizure Countdown if compromised
	if GlobalData.fuel.seizure_stage > 0:
		GlobalData.fuel.seizure_turns_left -= 1
		if GlobalData.fuel.seizure_turns_left <= 0:
			if GlobalData.fuel.seizure_stage == 1:
				GlobalData.fuel.seizure_stage = 2
				GlobalData.fuel.seizure_turns_left = 2
				GlobalData.board.run_notice = "⚠️ SALVAGE TEAM ARRIVED: Enemy technicians are breaching our base camp! [Stage 2: Breaching - 2 turns remaining]"
			elif GlobalData.fuel.seizure_stage == 2:
				GlobalData.fuel.seizure_stage = 3
				GlobalData.fuel.seizure_turns_left = 1
				GlobalData.board.run_notice = "🚛 EXTRACTION UNDERWAY: Enemy recovery vehicles are towing our assets! [Stage 3: Extraction - 1 turn remaining]"
			elif GlobalData.fuel.seizure_stage == 3:
				GlobalData.fuel.convoy_fuel = 0.0
				GlobalData.currency.scrap = maxi(GlobalData.currency.scrap - 30, 0)
				GlobalData.fuel.seizure_stage = 0
				GlobalData.fuel.seizure_turns_left = 0
				GlobalData.board.run_notice = "❌ ASSETS LOOTED: The enemy recovery team stripped our base camp and hauled away our fuel and scrap!"


# Checks if any hostile Artillery fleet is within Bombardment Range of player_pos (GDD §3.3)
static func check_artillery_bombardment(player_pos: Vector2i) -> Array[Dictionary]:
	var bombarding_fleets: Array[Dictionary] = []
	for p in GlobalData.board.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		var archetype: String = str(p.get("archetype", ""))
		if archetype != "artillery":
			continue
		var range_limit: int = int(BoardConfig.FLEET_ARCHETYPES.get("artillery", {}).get("bombard_range", 2))
		var dist := _manhattan(p.get("pos", Vector2i(-1, -1)), player_pos)
		if dist > 0 and dist <= range_limit:
			bombarding_fleets.append(p)
	return bombarding_fleets


# Zone of Control (ZoC): true if player_pos is directly adjacent (distance 1) to any hostile fleet.
static func is_in_zone_of_control(target_pos: Vector2i) -> bool:
	for p in GlobalData.board.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		var p_pos: Vector2i = p.get("pos", Vector2i(-1, -1))
		if _manhattan(p_pos, target_pos) == 1:
			return true
	return false


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# The player stepped onto `pos`. Any hostile fleet close enough to see the
# convoy marks it as the last-known position (reactive pursuit keeps converging
# on that tile even after the player moves on).
static func record_spotting(pos: Vector2i) -> void:
	var detect := DETECT_BASE + clampi(GlobalData.board.patrol_alert, 0, ALERT_MAX)
	for p in GlobalData.board.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		if _manhattan(p.get("pos", Vector2i(-1, -1)), pos) <= detect:
			GlobalData.board.patrol_last_seen = pos
			return


# The sector objective's anchor tile: the exit for most maps, or the enemy
# research base when the HQ-strike objective is live. Interception blocks and
# ambushes are evaluated against this goal.
static func _objective_anchor() -> Vector2i:
	var obj := BoardSystem.get_objective()
	if str(obj.get("id", "")) == "hq_strike" and GlobalData.narrative.enemy_base_active:
		return GlobalData.narrative.enemy_base_tile_pos
	var g := BoardConfig.GRID_SIZE
	return Vector2i(g - 1, g - 1)


# Interception block: a hostile fleet sitting between the convoy and the sector
# objective forces the player to either fight it or pay extra MP to slip past.
# Returns the MP surcharge for stepping onto `target` (0 = unblocked).
static func interception_surcharge(player_pos: Vector2i, target: Vector2i) -> int:
	var anchor := _objective_anchor()
	if anchor == Vector2i(-1, -1):
		return 0
	for p in GlobalData.board.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		var patrol_pos: Vector2i = p.get("pos")
		# Only fleets strictly BETWEEN the convoy and the goal count; fleets
		# behind the player or already past the objective don't block the way.
		if _manhattan(patrol_pos, anchor) >= _manhattan(player_pos, anchor):
			continue
		# Stepping from the patrol's cell one tile closer to the goal crosses
		# its firing line — that crossing costs extra movement.
		if _manhattan(target, patrol_pos) == 1 \
				and _manhattan(target, anchor) < _manhattan(patrol_pos, anchor):
			return 1
	return 0


static func _step_toward(cur: Vector2i, target: Vector2i, nodes: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var best := cur
	var best_dist := _manhattan(cur, target)
	var bests: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + d
		if not nodes.has(n):
			continue
		if not BoardConfig.is_passable(nodes[n].get_meta("terrain", "plain")):
			continue
		if occupied.has(n) and n != target:
			continue
		if nodes[n].get_meta("tile_type", "empty") in ["start", "exit", "safehouse", "city", "enemy_base"]:
			continue
		var d2 := _manhattan(n, target)
		if d2 < best_dist:
			best = n
			best_dist = d2
			bests = [n]
		elif d2 == best_dist:
			bests.append(n)
	if bests.is_empty():
		return best
	return bests[rng.randi() % bests.size()]


static func _wander(cur: Vector2i, home: Vector2i, nodes: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var options: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = cur + d
		if not nodes.has(n):
			continue
		if not BoardConfig.is_passable(nodes[n].get_meta("terrain", "plain")):
			continue
		if occupied.has(n):
			continue
		if nodes[n].get_meta("tile_type", "empty") in ["start", "exit", "safehouse", "city", "enemy_base"]:
			continue
		# Bias back toward the anchor so fleets don't drift across the map.
		if _manhattan(n, home) <= _manhattan(cur, home) + 1:
			options.append(n)
	if options.is_empty():
		return cur
	return options[rng.randi() % options.size()]


# The active combat was a patrol encounter; resolve it.
static func resolve_patrol_combat(victory: bool) -> void:
	var id := GlobalData.board.board_patrol_engagement
	if id < 0:
		return
	var p := get_patrol_by_id(id)
	GlobalData.board.board_patrol_engagement = -1

	if p.is_empty():
		return

	var commander: Dictionary = p.get("commander", {})

	if victory:
		remove_patrol(id)
		if not commander.is_empty():
			GlobalData.pilot.defeated_rivals.append(commander)
			var bounty := int(commander.get("bounty", 150))
			GlobalData.currency.credits += bounty
			GlobalData.board.run_notice = "RIVAL ELIMINATED: %s [%s] was defeated in battle!\nBounty Claimed: +%d Credits." % [
				commander.get("name", "Enemy Commander"), str(p.get("archetype", "fleet")).to_upper(), bounty
			]
		else:
			GlobalData.board.run_notice = "Patrol %s wiped out! The route ahead is safer." % p.get("name", "fleet")
		BoardSystem.add_progress(1)
	else:
		# Player retreated / escaped: rival commander survived!
		if not commander.is_empty():
			commander["rivalry_count"] = int(commander.get("rivalry_count", 0)) + 1
			commander["escapes"] = int(commander.get("escapes", 0)) + 1
			commander["is_nemesis"] = true
			commander["bounty"] = int(commander.get("bounty", 150)) + 100
			GlobalData.pilot.rival_pilots.append(commander)
			GlobalData.board.run_notice = "RIVAL SURVIVED: Commander %s remembers this retreat.\nRivalry escalated to Rank %d (Bounty: %d Cr)!" % [
				commander.get("name", "Enemy Commander"), commander["rivalry_count"], commander["bounty"]
			]
