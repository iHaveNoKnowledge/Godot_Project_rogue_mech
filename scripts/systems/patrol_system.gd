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

		if not is_unknown and dist <= 4:
			p["aggro"] = true
		elif p.get("aggro", false) and dist > 7:
			p["aggro"] = false

		var next := cur
		if p.get("aggro", false):
			next = _step_toward(cur, player_pos, nodes, occupied, rng)
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
	return ambush


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


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
