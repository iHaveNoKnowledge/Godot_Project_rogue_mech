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
#   {id, pos: Vector2i, home: Vector2i, name, grunts, aces, aggro: bool}
# -----------------------------------------------------------------------------

const NAMES := ["Ravens", "Vultures", "Jackals", "Hawks", "Coyotes", "Strykers"]
const GRUNT_MIN: int = 1
const GRUNT_MAX: int = 3


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
		GlobalData.board_patrols.append({
			"id": id,
			"pos": home,
			"home": home,
			"name": NAMES[rng.randi() % NAMES.size()],
			"grunts": grunts,
			"aces": aces,
			"aggro": false,
		})
		id += 1


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
		var cur: Vector2i = p.get("pos")
		var home: Vector2i = p.get("home")
		var dist := _manhattan(cur, player_pos)

		if dist <= 4:
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
