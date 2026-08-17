class_name PatrolSystem
extends RefCounted

# -----------------------------------------------------------------------------
# ENEMY PATROL FLEETS
# Fleets roam the open board grid. They patrol near their home anchor, but the
# moment the player's convoy gets close they turn aggressive and pursue. Each
# day (EventBus.board_day_ended) they move one cell. Stepping onto a patrol
# cell (or letting one step onto you) forces combat.
#
# State lives in GlobalData.board_patrols (Array of Dictionaries) so it survives
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
	if p.get("pos") is Dictionary or p.get("pos") is String:
		p["pos"] = normalize_dir(p.get("pos"))
	if p.get("home") is Dictionary or p.get("home") is String:
		p["home"] = normalize_dir(p.get("home"))
	p["dir"] = normalize_dir(p.get("dir"))


static func has_patrols() -> bool:
	return not GlobalData.board_patrols.is_empty()


static func get_patrol_at(pos: Vector2i) -> Dictionary:
	for p in GlobalData.board_patrols:
		if p.get("pos") == pos:
			return p
	return {}


static func get_patrol_by_id(id: int) -> Dictionary:
	for p in GlobalData.board_patrols:
		if int(p.get("id", -1)) == id:
			return p
	return {}


static func remove_patrol(id: int) -> void:
	for i in range(GlobalData.board_patrols.size() - 1, -1, -1):
		if int(GlobalData.board_patrols[i].get("id", -1)) == id:
			GlobalData.board_patrols.remove_at(i)
			return


# Spawns patrol fleets on the freshly generated board. Called by the board
# manager after generation (only when no fleets exist yet for this sector).
static func spawn_patrols() -> void:
	if not GlobalData.board_patrols.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board_seed + 7919
	var theme := GlobalData.board_theme_id
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
	var grid: Array = GlobalData.board_grid
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
	for i in range(mini(count, candidate.size())):
		var home: Vector2i = candidate[i]
		var grunts := rng.randi_range(GRUNT_MIN, GRUNT_MAX)
		var aces := 1 if (rng.randf() < 0.30 and GlobalData.current_sector >= 2) else 0
		# Unknown fleets are mercenary convoys that fly a white arrow on the map.
		# They only show up once recruitable pilots exist and never carry aces.
		var faction := "hostile"
		var character_id := ""
		if aces == 0 and rng.randf() < 0.25 and _has_recruitable_pilot():
			faction = "unknown"
			character_id = _pick_recruitable_pilot()
		GlobalData.board_patrols.append({
			"id": id,
			"pos": home,
			"home": home,
			"name": NAMES[rng.randi() % NAMES.size()],
			"grunts": grunts,
			"aces": aces,
			"aggro": false,
			"faction": faction,
			"character_id": character_id,
			"dir": Vector2i(1, 0),
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
	var themed: Array = []
	var others: Array = []
	for character in RecruitSystem.CHARACTERS:
		var cid := str(character.get("id", ""))
		if not RecruitSystem.is_character_available(cid):
			continue
		if str(character.get("theme", "")) == GlobalData.theme_id:
			themed.append(cid)
		else:
			others.append(cid)
	if not themed.is_empty():
		return themed[randi() % themed.size()]
	if not others.is_empty():
		return others[randi() % others.size()]
	return ""


# Advances every fleet one cell at the end of a day. Returns the position of a
# fleet that just moved onto the player (for an ambush), or (-1,-1).
static func advance_day(player_pos: Vector2i) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = GlobalData.board_day * 101 + GlobalData.board_seed
	var nodes: Dictionary = {}
	var grid: Array = GlobalData.board_grid
	if not grid.is_empty() and grid[0] is Dictionary:
		nodes = grid[0]

	var occupied: Dictionary = {}
	for p in GlobalData.board_patrols:
		occupied[p.get("pos")] = true

	var detect := DETECT_BASE + clampi(GlobalData.patrol_alert, 0, ALERT_MAX)
	var saw_player := false
	var ambush := Vector2i(-1, -1)
	for p in GlobalData.board_patrols:
		# Heal entries loaded from older saves before reading their fields.
		normalize_patrol(p)
		var cur: Vector2i = p.get("pos")
		var home: Vector2i = p.get("home")
		var dist := _manhattan(cur, player_pos)
		# Unknown fleets never chase the player; they wander and can only be
		# encountered when the player steps onto them.
		var is_unknown := str(p.get("faction", "hostile")) == "unknown"

		if not is_unknown and dist <= detect:
			p["aggro"] = true
			# Remember exactly where the convoy was spotted so fleets out of
			# sight still converge on that tile (reactive pursuit).
			GlobalData.patrol_last_seen = player_pos
			saw_player = true
		elif p.get("aggro", false) and dist > detect + 3:
			p["aggro"] = false

		var next := cur
		if p.get("aggro", false):
			next = _step_toward(cur, player_pos, nodes, occupied, rng)
		elif not is_unknown and GlobalData.patrol_last_seen != Vector2i(-1, -1) \
				and rng.randf() < 0.7:
			# A fleet that lost visual still has the convoy's last heading: step
			# toward the trail instead of wandering back to its anchor.
			next = _step_toward(cur, GlobalData.patrol_last_seen, nodes, occupied, rng)
		elif rng.randf() < 0.6:
			next = _wander(cur, home, nodes, occupied, rng)
		if next != cur:
			occupied.erase(cur)
			occupied[next] = true
			p["pos"] = next
			# Remember the heading so the board's arrow marker can face it.
			p["dir"] = next - cur
			if next == player_pos:
				ambush = next

	# The convoy is a moving target: force escalation climbs while a hostile
	# fleet keeps visual and cools back down once the player relocates.
	if saw_player:
		GlobalData.patrol_alert = mini(GlobalData.patrol_alert + 1, ALERT_MAX)
	else:
		GlobalData.patrol_alert = maxi(GlobalData.patrol_alert - 1, 0)
	return ambush


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


# The player stepped onto `pos`. Any hostile fleet close enough to see the
# convoy marks it as the last-known position (reactive pursuit keeps converging
# on that tile even after the player moves on).
static func record_spotting(pos: Vector2i) -> void:
	var detect := DETECT_BASE + clampi(GlobalData.patrol_alert, 0, ALERT_MAX)
	for p in GlobalData.board_patrols:
		if str(p.get("faction", "hostile")) == "unknown":
			continue
		if _manhattan(p.get("pos", Vector2i(-1, -1)), pos) <= detect:
			GlobalData.patrol_last_seen = pos
			return


# The sector objective's anchor tile: the exit for most maps, or the enemy
# research base when the HQ-strike objective is live. Interception blocks and
# ambushes are evaluated against this goal.
static func _objective_anchor() -> Vector2i:
	var obj := BoardSystem.get_objective()
	if str(obj.get("id", "")) == "hq_strike" and GlobalData.enemy_base_active:
		return GlobalData.enemy_base_tile_pos
	var g := BoardConfig.GRID_SIZE
	return Vector2i(g - 1, g - 1)


# Interception block: a hostile fleet sitting between the convoy and the sector
# objective forces the player to either fight it or pay extra MP to slip past.
# Returns the MP surcharge for stepping onto `target` (0 = unblocked).
static func interception_surcharge(player_pos: Vector2i, target: Vector2i) -> int:
	var anchor := _objective_anchor()
	if anchor == Vector2i(-1, -1):
		return 0
	for p in GlobalData.board_patrols:
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
	var id := GlobalData.board_patrol_engagement
	if id < 0:
		return
	GlobalData.board_patrol_engagement = -1
	if victory:
		var p := get_patrol_by_id(id)
		if p.is_empty():
			return
		remove_patrol(id)
		GlobalData.run_notice = "Patrol %s wiped out! The route ahead is safer." % p.get("name", "fleet")
		BoardSystem.add_progress(1)
