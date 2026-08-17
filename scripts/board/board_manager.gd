extends Node3D

## Open-grid board controller. Replaces the old layered node graph with a free-
## movement grid: the player steps cell-by-cell (WASD or click), each cell costs
## movement points from a per-day pool. Patrol fleets roam the grid, objectives
## gate the exit, and terrains slow or block movement.

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: Node3D = $PlayerToken

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var current_pos: Vector2i = Vector2i.ZERO
var nodes_dict: Dictionary = {}
var _tooltip: Node
var _reveal_log: Dictionary = {}
var _patrol_marker_container: Node3D = null
# Last movement heading, used to rotate the player's arrow token. Defaults to
# east so the token faces into the board on spawn.
var _last_dir: Vector2i = Vector2i(1, 0)


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tooltip = get_node_or_null("BoardTooltipUI")
	var generator = get_node_or_null("BoardGenerator")
	if generator:
		var data = generator.generate_board()
		nodes_dict = data["nodes"]

		tile_container.add_child(generator.build_ground())
		for key in nodes_dict:
			tile_container.add_child(nodes_dict[key])

	current_pos = GlobalData.current_tile
	if not nodes_dict.has(current_pos):
		current_pos = Vector2i(0, 0)
		GlobalData.current_tile = current_pos

	# Objective + patrols for this sector (fresh on new sector, restored on
	# reload after combat).
	if GlobalData.board_objective_id == "":
		_setup_objective()
	GlobalData.board_patrol_engagement = -1
	PatrolSystem.spawn_patrols()

	_reveal_around(current_pos)
	_refresh_patrol_markers()
	_update_token_position()
	_highlight_adjacent()

	# Revert any stale enemy_base tile, then surface pending events (same flow as
	# the old graph board).
	_clear_enemy_base_tile()
	# An ACTIVE enemy research base keeps its tile + 3D model across board
	# reloads (returning from a battle must not erase it).
	_restore_enemy_base_tile()
	_refresh_enemy_base_model()

	if GlobalData.consume_pending_escalation_event():
		EventBus.event_triggered.emit(_build_tech_copy_event())

	if GlobalData.consume_pending_enemy_base_destroyed():
		EventBus.event_triggered.emit(_build_enemy_base_destroyed_event())
		if BoardSystem.get_objective().get("id", "") == "hq_strike":
			BoardSystem.complete()

	if GlobalData.run_notice != "":
		var notice := GlobalData.run_notice
		GlobalData.run_notice = ""
		EventBus.event_triggered.emit({
			"name": "CONVOY REPORT",
			"effect": "none",
			"amount": 0,
			"desc": notice,
		})

	if GlobalData.board_day == 1 and GlobalData.board_mp >= GlobalData.board_mp_max and not GlobalData.board_objective_intro_consumed:
		GlobalData.board_objective_intro_consumed = true
		EventBus.event_triggered.emit(_build_objective_event())


func _setup_objective() -> void:
	var obj := BoardSystem.get_objective()
	GlobalData.board_objective_id = str(obj.get("id", ""))
	GlobalData.board_objective_progress = 0
	GlobalData.board_objective_required = int(obj.get("required", 1))


func _build_objective_event() -> Dictionary:
	return {
		"name": "SECTOR OBJECTIVE — %s" % BoardSystem.get_objective().get("name", "?"),
		"effect": "none",
		"amount": 0,
		"desc": BoardSystem.objective_desc(),
	}


# ---------------------------------------------------------------------------
# MOVEMENT (free grid stepping)
# ---------------------------------------------------------------------------

# Legacy API kept for click-driven tiles + intermission. Steps the token to an
# adjacent walkable cell if enough MP remains.
func move_to_tile(target: Vector2i) -> bool:
	if get_tree().paused or _intermission_open():
		return false
	if not _try_step(target):
		print("Cannot move there! (must be an adjacent walkable cell with enough MP)")
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	# The token moves by CLICKING a reachable tile (board_tile._on_input_event);
	# WASD/Q/E now belong to the camera (pan + rotate). Only board-wide keys
	# (end day) are handled here.
	if get_tree().paused or not visible or _intermission_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("pause"):
			return
		if event.keycode == KEY_END or event.keycode == KEY_ENTER:
			_end_day()


func _try_step(target: Vector2i) -> bool:
	if not nodes_dict.has(target):
		return false
	if target == current_pos:
		return false
	var tile = nodes_dict[target]
	if not BoardConfig.is_passable(str(tile.get_meta("terrain", "plain"))):
		return false
	if not _is_adjacent(current_pos, target):
		return false
	var cost := BoardConfig.move_cost(str(tile.get_meta("terrain", "plain")))
	# A hostile fleet between the convoy and the sector objective blocks the
	# route: crossing its firing line costs extra MP (fight it, or pay to slip
	# past and reroute around it).
	cost += PatrolSystem.interception_surcharge(current_pos, target)
	if GlobalData.board_mp < cost:
		# The player cannot move at all: whatever ambush aftermath was blocking the
		# intermission menu (blocked_intermission) must not soft-lock them. Clear it
		# so ESC can open the menu and they can End the Day.
		GlobalData.blocked_intermission = false
		EventBus.event_triggered.emit({
			"name": "NO MOVEMENT LEFT",
			"effect": "none",
			"amount": 0,
			"desc": "You've run out of movement for today. End the day (End key) to push on.",
		})
		return false

	GlobalData.board_mp = maxi(GlobalData.board_mp - cost, 0)
	_last_dir = target - current_pos
	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()
	var revealed := _reveal_around(target)
	if revealed > 0:
		_refresh_patrol_markers()

	# If any hostile fleet can see the convoy on this tile, remember exactly where
	# it was — fleets that lose sight keep converging on that last position.
	PatrolSystem.record_spotting(current_pos)

	GlobalData.blocked_intermission = false

	# Objective progress triggers.
	_check_survey_objective(revealed)
	if str(tile.get_meta("terrain", "plain")) == "bridge" and BoardSystem.get_objective().get("id", "") == "cross_river":
		BoardSystem.complete()
		_announce_objective_done()

	# Stepping onto a patrol fleet forces a fight (checked before the tile's own
	# effect so a patrol on a combat tile doesn't double-trigger). Unknown fleets
	# (white arrows) are mercenary convoys: they offer a talk encounter instead.
	var patrol := PatrolSystem.get_patrol_at(target)
	var engaged_patrol := false
	if not patrol.is_empty() and GameManager.current_state == GameManager.State.BOARD:
		engaged_patrol = true
		GlobalData.board_patrol_engagement = int(patrol.get("id", -1))

	EventBus.tile_entered.emit(target, tile)
	if not engaged_patrol:
		# A chokepoint (bridge / one-wide passage) is ambush ground: hostile
		# forces spring a pincer on the convoy there. Once it fires the combat
		# spawns enemies in two opposing arcs instead of a ring.
		if _roll_chokepoint_ambush(tile):
			GlobalData.ambush_pincer = true
			GlobalData.blocked_intermission = true
			_request_combat("grunt")
			return true
		_process_tile_effect(str(tile.get_meta("tile_type", "empty")))
	elif GameManager.current_state == GameManager.State.BOARD:
		if str(patrol.get("faction", "hostile")) == "unknown" and _has_available_recruit(str(patrol.get("character_id", ""))):
			_trigger_patrol_talk_event(patrol)
			return true
		# Pilot-only convoys can't fight on foot: the encounter becomes a
		# recovery event (same behavior the old combat tiles had).
		if GlobalData.mech_less:
			GlobalData.board_patrol_engagement = -1
			_trigger_recovery_event()
			return true
		_request_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
		return true

	# A tile effect may have already entered combat (change_scene_to_file frees
	# this scene immediately) or opened a pause overlay (safehouse/city shop).
	# Never run the end-of-day flow on a scene that is no longer in the tree —
	# its event popup would crash on get_tree() == null.
	if GlobalData.board_mp <= 0 and get_tree() != null and not get_tree().paused \
			and GameManager.current_state == GameManager.State.BOARD:
		_end_day()
	return true


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	for d: Vector2i in DIRS:
		if a + d == b:
			return true
	return false


func _intermission_open() -> bool:
	var ui := get_node_or_null("IntermissionUI")
	return ui != null and ui.visible


# Repaints the dynamic board state after an event popup closes WITHOUT reloading
# the scene (see event_ui._resume_from_popup). Event effects like patrol_recruit
# remove fleets or move tokens, so the arrow markers and walkable highlights
# must be redrawn in place instead of waiting for a scene reload.
func refresh_after_event() -> void:
	_apply_pending_tile_clear()
	_refresh_patrol_markers()
	_highlight_adjacent()
	_update_token_position()


func _end_day() -> void:
	# Safety net: combat was entered this frame (the board scene is already out
	# of the tree), so the end-of-day emit would hit an orphaned EventUI.
	if get_tree() == null or GameManager.current_state != GameManager.State.BOARD:
		return
	GlobalData.board_day += 1
	GlobalData.board_mp = GlobalData.board_mp_max

	# Once-per-day systems.
	process_turn_mobilization()
	accumulate_stalker_chance()

	var spy_event := GlobalData.roll_spy_event()
	if not spy_event.is_empty():
		EventBus.event_triggered.emit(spy_event)

	if GlobalData.consume_enemy_base_spawn_request():
		_place_enemy_base_node()
		EventBus.event_triggered.emit(_build_enemy_base_spawn_event())

	if GlobalData.tick_enemy_base_progress(1.0):
		EventBus.event_triggered.emit(_build_enemy_base_completed_event())
	# The base's research moved forward today — upgrade its model from a
	# temporary camp to a rooted tower once it has dug in (>= half done).
	_refresh_enemy_base_model()

	EventBus.board_day_ended.emit()

	# Patrols move after the day's systems resolve.
	var ambush := PatrolSystem.advance_day(current_pos)
	if ambush != Vector2i(-1, -1) and GameManager.current_state == GameManager.State.BOARD:
		var patrol := PatrolSystem.get_patrol_at(ambush)
		if not patrol.is_empty():
			GlobalData.board_patrol_engagement = int(patrol.get("id", -1))
			if str(patrol.get("faction", "hostile")) == "unknown" and _has_available_recruit(str(patrol.get("character_id", ""))):
				_trigger_patrol_talk_event(patrol)
				return
			# Pilot-only convoys can't fight on foot: the ambush becomes a
			# recovery event instead of a battle.
			if GlobalData.mech_less:
				GlobalData.board_patrol_engagement = -1
				_trigger_recovery_event()
				return
			_request_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
			return

	_update_token_position()
	_refresh_patrol_markers()
	_highlight_adjacent()
	EventBus.event_triggered.emit({
		"name": "DAY %d" % GlobalData.board_day,
		"effect": "none",
		"amount": 0,
		"desc": "Supplies refreshed — %d MP. %s" % [GlobalData.board_mp_max, BoardSystem.progress_text()],
	})


func _check_survey_objective(newly: int) -> void:
	if BoardSystem.get_objective().get("id", "") != "survey":
		return
	if newly <= 0:
		return
	var before := GlobalData.board_objective_progress
	BoardSystem.add_progress(newly)
	if not BoardSystem.is_objective_complete() and GlobalData.board_objective_progress > before:
		EventBus.event_triggered.emit({
			"name": "Terrain Mapped",
			"effect": "none",
			"amount": 0,
			"desc": "%s" % BoardSystem.progress_text(),
		})


func _announce_objective_done() -> void:
	EventBus.event_triggered.emit({
		"name": "OBJECTIVE COMPLETE",
		"effect": "none",
		"amount": 0,
		"desc": "%s complete! The extraction route to the exit is now open." % BoardSystem.get_objective().get("name", "Objective"),
	})


# ---------------------------------------------------------------------------
# REVEAL / FOG OF WAR
# ---------------------------------------------------------------------------

func _reveal_around(center: Vector2i) -> int:
	var newly := 0
	for k in _tiles_in_radius(center, 1):
		var tile = nodes_dict.get(k)
		if tile == null or tile.is_revealed:
			continue
		if _reveal_log.has(k):
			continue
		tile.reveal()
		_reveal_log[k] = true
		newly += 1
	return newly


func _tiles_in_radius(center: Vector2i, radius: int) -> Array:
	var result: Array = []
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var k := Vector2i(x, y)
			if nodes_dict.has(k):
				result.append(k)
	return result


# ---------------------------------------------------------------------------
# TOKEN / HIGHLIGHTS
# ---------------------------------------------------------------------------

func _highlight_adjacent() -> void:
	if not nodes_dict.has(current_pos):
		return
	for d: Vector2i in DIRS:
		var target_key := current_pos + d
		if not nodes_dict.has(target_key):
			continue
		var tile = nodes_dict[target_key]
		if not BoardConfig.is_passable(str(tile.get_meta("terrain", "plain"))):
			continue
		if GlobalData.board_mp >= BoardConfig.move_cost(str(tile.get_meta("terrain", "plain"))):
			tile.highlight(true)


func _clear_highlights() -> void:
	for key in nodes_dict:
		nodes_dict[key].highlight(false)


func _update_token_position() -> void:
	if nodes_dict.has(current_pos):
		var tile = nodes_dict[current_pos]
		player_token.global_position = tile.global_position + Vector3(0, 0.9, 0)
		# Point the arrow at the last heading (east = (1,0), south = (0,1), ...).
		player_token.face_heading(_last_dir)


# ---------------------------------------------------------------------------
# PATROL FLEET MARKERS (arrow models on the board, one per fleet)
# ---------------------------------------------------------------------------

# Spawns one 3D arrow marker on every patrol fleet's tile so fleets read as
# real units on the map (red = grunts, double red = aces, white = unknown).
func _refresh_patrol_markers() -> void:
	if _patrol_marker_container == null:
		_patrol_marker_container = Node3D.new()
		_patrol_marker_container.name = "PatrolMarkers"
		add_child(_patrol_marker_container)
	for child in _patrol_marker_container.get_children():
		child.queue_free()
	for p in GlobalData.board_patrols:
		# Old saves can carry pos/dir as JSON-flattened Strings — heal the
		# entry so every fleet reliably draws its arrow marker.
		PatrolSystem.normalize_patrol(p)
		var pos: Vector2i = p.get("pos")
		if not nodes_dict.has(pos):
			continue
		var marker := Node3D.new()
		marker.set_script(preload("res://scripts/board/patrol_marker.gd"))
		_patrol_marker_container.add_child(marker)
		marker.global_position = nodes_dict[pos].global_position + Vector3(0, 1.0, 0)
		marker.setup(p)
	_add_boss_marker()


# The exit tile holds the sector boss: a large purple arrow that marks the
# extraction point so its location is obvious at a glance.
func _add_boss_marker() -> void:
	for key in nodes_dict:
		if str(nodes_dict[key].get_meta("tile_type", "empty")) != "exit":
			continue
		var marker := Node3D.new()
		marker.set_script(preload("res://scripts/board/board_arrow.gd"))
		marker.setup(BoardArrow.BOSS_PURPLE, false, 1.7, true)
		_patrol_marker_container.add_child(marker)
		marker.global_position = nodes_dict[key].global_position + Vector3(0, 1.1, 0)
		return


# True when `character_id` is a recruitable pilot who hasn't been met yet.
func _has_available_recruit(character_id: String) -> bool:
	if character_id == "":
		return false
	return RecruitSystem.is_character_available(character_id)


# Unknown fleets (white arrows) offer a choice: talk the pilot into joining the
# convoy, or open fire and take the fleet down.
func _trigger_patrol_talk_event(patrol: Dictionary) -> void:
	var character_id := str(patrol.get("character_id", ""))
	var character := RecruitSystem.get_character(character_id)
	var name := str(patrol.get("name", "Unknown Fleet"))
	var greeting := str(character.get("desc", "State your business."))
	var desc := "An unidentified fleet hails you on open comms. \"%s\" They keep their weapons trained but hold their fire." % greeting
	var choices: Array = []
	if not character.is_empty():
		choices.append({
			"label": str(character.get("friendly_label", "Recruit")),
			"desc": str(character.get("friendly_desc", "Talk them into joining the convoy.")),
			"effect": "patrol_recruit",
			"amount": 0,
			"params": {"character_id": character_id},
		})
	choices.append({
		"label": "Fight",
		"desc": "Open fire and take the fleet down by force.",
		"effect": "force_combat",
		"amount": 0,
		"params": {"combat_type": "grunt"},
	})
	EventBus.event_triggered.emit({
		"name": "UNKNOWN FLEET — %s" % name.to_upper(),
		"effect": "choice",
		"amount": 0,
		"desc": desc,
		"params": {"choices": choices},
	})


# ---------------------------------------------------------------------------
# HOVER TOOLTIP (patrol fleet reconnaissance on hover)
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if get_tree().paused or _tooltip == null:
		if _tooltip and _tooltip.has_method("show_tile"):
			_tooltip.show_tile("", Vector2(-1, -1), {})
		return
	var tile := _hovered_tile()
	if tile == null:
		if _tooltip.has_method("show_tile"):
			_tooltip.show_tile("", Vector2(-1, -1), {})
		return
	var pos := tile.get_meta("grid_pos", Vector2i(-1, -1)) as Vector2i
	var terrain := str(tile.get_meta("terrain", "plain"))
	var tt: String = tile.get_meta("tile_type", "empty")
	var patrol := PatrolSystem.get_patrol_at(pos)
	var text := "%s (%d, %d)\nTerrain: %s — cost %d MP" % [
		str(tt.to_upper()), pos.x, pos.y, terrain.capitalize(),
		BoardConfig.move_cost(terrain)
	]
	if not BoardConfig.is_passable(terrain):
		text += "\nIMPassable!"
	if PatrolSystem.interception_surcharge(current_pos, pos) > 0:
		text += "\n[INTERCEPTION — +1 MP to cross]"
	if GlobalData.patrol_alert > 0:
		text += "\n[HUNT ALERT %d]" % GlobalData.patrol_alert
	if not patrol.is_empty():
		var is_unknown := str(patrol.get("faction", "hostile")) == "unknown"
		text += "\nPATROL: %s — %d grunt(s)" % [patrol.get("name", "fleet"), int(patrol.get("grunts", 1))]
		if int(patrol.get("aces", 0)) > 0:
			text += " + %d ACE" % int(patrol.get("aces", 0))
		if is_unknown:
			text += "\nUNKNOWN — unaligned fleet (white arrow)."
		text += "\n[hover reach = contact]"
	if _tooltip.has_method("show_tile"):
		_tooltip.show_tile(text, _mouse_screen_pos(), {})


func _hovered_tile() -> Node:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mouse)
	var to := from + camera.project_ray_normal(mouse) * 400.0
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 16
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return null
	return hit.get("collider")


func _mouse_screen_pos() -> Vector2:
	return get_viewport().get_mouse_position()


# ---------------------------------------------------------------------------
# LEGACY enemy_base helpers (kept for the research-node lifecycle)
# ---------------------------------------------------------------------------

func _clear_enemy_base_tile() -> void:
	var reset_pos := GlobalData.consume_enemy_base_tile_reset()
	if reset_pos == Vector2i(-1, -1):
		return
	if not nodes_dict.has(reset_pos):
		return
	var tile = nodes_dict[reset_pos]
	if tile.has_method("clear_enemy_base_model"):
		tile.clear_enemy_base_model()
	# New boards never roll "combat" tiles (battles come from patrol arrows), so
	# the former research node reverts to ordinary ground.
	tile.set_meta("tile_type", "empty")
	if tile.has_method("_update_visual"):
		tile._update_visual()


func process_turn_mobilization() -> void:
	if GlobalData.heat < 3:
		return
	var grunt_recruit = int(GlobalData.enemy_forces["grunt_max"] * randf_range(0.10, 0.20))
	GlobalData.enemy_forces["grunt_current"] = clampi(
		GlobalData.enemy_forces["grunt_current"] + grunt_recruit,
		0, GlobalData.enemy_forces["grunt_max"]
	)
	if randf() < 0.30:
		GlobalData.enemy_forces["ace_current"] = clampi(
			GlobalData.enemy_forces["ace_current"] + 1,
			0, GlobalData.enemy_forces["ace_max"]
		)


func accumulate_stalker_chance() -> void:
	if not GlobalData.stalking_aces.is_empty():
		GlobalData.stalking_chance = minf(GlobalData.stalking_chance + 0.20, 1.0)


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			# Legacy — new boards never roll combat tiles (battles come from
			# hostile patrol arrows); kept only as a safety net.
			if GlobalData.mech_less:
				_trigger_recovery_event()
			elif GlobalData.ceasefire_turns > 0:
				GlobalData.ceasefire_turns -= 1
				_trigger_ceasefire_skip()
			elif not GlobalData.stalking_aces.is_empty() and randf() < GlobalData.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				_request_combat("grunt")
		"enemy_base":
			if GlobalData.mech_less:
				_trigger_recovery_event()
				return
			if GlobalData.enemy_base_active and GlobalData.enemy_base_tile_pos == current_pos:
				_request_combat("enemy_base")
			else:
				_request_combat("grunt")
		"event":
			_trigger_random_event()
		"safehouse":
			HeatWantedSystem.modify_heat(-4)
			var safehouse = get_node_or_null("SafehouseUI")
			if safehouse:
				safehouse.visible = true
				get_tree().paused = true
		"city":
			var city = get_node_or_null("CityShopUI")
			if city:
				city.visible = true
				get_tree().paused = true
		"data_node":
			_trigger_data_node_event()
		"dead_end":
			_trigger_dead_end_event()
		"bait":
			# A decoy cache: it looks like loot but springs a pincer ambush.
			# Sprung traps are recorded so the decoy stays cleared on reload.
			_trigger_bait_trap()
		"start":
			print("Entering Hangar Practice Ground.")
		"exit":
			_trigger_exit_event()
		_:
			pass


# A "bait" tile reads as an abandoned supply cache but is a decoy: stepping on
# it springs a hostile pincer ambush (same no-menu aftermath as a patrol fight).
func _trigger_bait_trap() -> void:
	if current_pos in GlobalData.consumed_bait:
		return
	GlobalData.consumed_bait.append(current_pos)
	if GlobalData.mech_less:
		_trigger_recovery_event()
		return
	if GlobalData.ceasefire_turns > 0:
		GlobalData.ceasefire_turns -= 1
		_trigger_ceasefire_skip()
		return
	GlobalData.ambush_pincer = true
	GlobalData.blocked_intermission = true
	EventBus.event_triggered.emit({
		"name": "BAIT CACHE — TRAP",
		"effect": "none",
		"amount": 0,
		"desc": "The supply cache was a decoy! Hostile forces close in from all sides.",
	})
	_request_combat("grunt")


# True when the tile is ambush ground: a bridge crossing or a one-wide passage
# (at most two walkable neighbors). The convoy has nowhere to maneuver there.
func _is_chokepoint_tile(tile: Node) -> bool:
	if tile == null:
		return false
	var terrain := str(tile.get_meta("terrain", "plain"))
	if terrain == "bridge":
		return true
	var pos: Vector2i = tile.get_meta("grid_pos", Vector2i(-1, -1))
	var walkable := 0
	for d: Vector2i in DIRS:
		var n: Vector2i = pos + d
		if nodes_dict.has(n) and BoardConfig.is_passable(str(nodes_dict[n].get_meta("terrain", "plain"))):
			walkable += 1
	return walkable <= 2


# Weighted chokepoint ambush roll. The convoy is more likely to be jumped the
# higher the local alert and wanted level are (the enemy is actively hunting).
# On-foot convoys and ceasefire grace always hold.
func _roll_chokepoint_ambush(tile: Node) -> bool:
	if not _is_chokepoint_tile(tile):
		return false
	if GlobalData.mech_less:
		return false
	if GlobalData.ceasefire_turns > 0:
		return false
	var ttype := str(tile.get_meta("tile_type", "empty"))
	if ttype in ["start", "exit", "safehouse", "city", "enemy_base", "bait"]:
		return false
	var chance := 0.14 + float(GlobalData.patrol_alert) * 0.04 \
			+ minf(GlobalData.wanted_level, 5) * 0.03
	return randf() < chance


# Routes a board-initiated combat through the DEPLOY SQUAD screen when the
# convoy has parked mechs with seated pilots to choose from; solo convoys and
# surprise ambushes skip straight into the battle.
func _request_combat(combat_type: String) -> void:
	# Tell the arena generator what terrain this battle happens on: a forest
	# board fought on a ROAD tile gets the road-through-forest arena.
	var tile = nodes_dict.get(current_pos)
	GlobalData.combat_tile_terrain = str(tile.get_meta("terrain", "plain")) if tile != null else "plain"
	var deploy := get_node_or_null("DeployTeamUI")
	if deploy and deploy.has_method("has_ally_candidates") and deploy.has_method("open_deploy") \
			and deploy.has_ally_candidates():
		deploy.open_deploy(combat_type)
		return
	GameManager.enter_combat(combat_type)


func _trigger_ceasefire_skip() -> void:
	var event = {
		"name": "Ceasefire Holds",
		"effect": "none",
		"amount": 0,
		"desc": "The front is quiet. %d day(s) of ceasefire remain." % GlobalData.ceasefire_turns,
	}
	EventBus.event_triggered.emit(event)


func _trigger_data_node_event() -> void:
	GlobalData.gain_data_cores(2)
	var event = {
		"name": "Data Terminal Extraction",
		"effect": "data_cores",
		"amount": 2,
		"desc": "Extracted blueprint data core! +2 Data Cores.",
	}
	EventBus.event_triggered.emit(event)


func _trigger_dead_end_event() -> void:
	# A dead end is a walkable cell whose way forward is choked with rubble.
	# The player can either pay MP to demolish the obstacle (the work takes
	# the rest of the day) or turn back and find another route.
	var cost := _dead_end_clear_cost()
	var choices: Array = []
	if GlobalData.board_mp >= cost:
		choices.append({
			"label": "Clear the path (%d MP)" % cost,
			"desc": "Spend %d MP demolishing the rubble. The work takes the rest of the day." % cost,
			"effect": "dead_end_clear",
			"amount": cost,
			"params": {"pos": {"x": current_pos.x, "y": current_pos.y}},
		})
	choices.append({
		"label": "Turn back",
		"desc": "Leave the blockage and look for another route.",
		"effect": "none",
		"amount": 0,
	})
	var desc := "The way forward is choked with rubble and impassable terrain."
	if choices.size() == 1:
		desc += " You do not have enough movement left today to clear it (%d MP required)." % cost
	EventBus.event_triggered.emit({
		"name": "BLOCKED PATH",
		"effect": "choice",
		"amount": 0,
		"desc": desc,
		"params": {"choices": choices},
	})


# Demolishing a dead end's rubble costs roughly half a day of movement.
func _dead_end_clear_cost() -> int:
	return maxi(2, int(ceil(float(GlobalData.board_mp_max) * 0.5)))


# The player chose to demolish a dead end's rubble (see refresh_after_event).
# The tile becomes ordinary ground, blocked rock neighbors open up so a real
# path exists past it, and the work consumes the rest of the day.
func _apply_pending_tile_clear() -> void:
	if GlobalData.pending_tile_clear == Vector2i(-1, -1):
		return
	var pos: Vector2i = GlobalData.pending_tile_clear
	GlobalData.pending_tile_clear = Vector2i(-1, -1)
	if not nodes_dict.has(pos):
		return
	var tile = nodes_dict[pos]
	if str(tile.get_meta("tile_type", "empty")) != "dead_end":
		return
	tile.set_meta("tile_type", "empty")
	if tile.has_method("_update_visual"):
		tile._update_visual()
	# Open the rubble cells around the clearing so the dead end stops being one.
	for n in _tiles_in_radius(pos, 1):
		var neighbor = nodes_dict.get(n)
		if neighbor == null:
			continue
		if str(neighbor.get_meta("terrain", "plain")) == "rock":
			neighbor.set_meta("terrain", "plain")
			if neighbor.has_method("_update_visual"):
				neighbor._update_visual()
	_end_day()


func _trigger_exit_event() -> void:
	if not BoardSystem.is_objective_complete():
		EventBus.event_triggered.emit({
			"name": "ROUTE BLOCKED",
			"effect": "none",
			"amount": 0,
			"desc": "The extraction zone is sealed. Complete the sector objective first: %s" % BoardSystem.progress_text(),
		})
		return
	if GlobalData.mech_less:
		var event = {
			"name": "The Wanderer",
			"effect": "wanderer_join",
			"amount": 0,
			"desc": "On foot, the extraction zone is a death sentence. A lone wanderer pulls up beside your convoy and hands you the keys to a spare chassis.",
			"params": {"recovery": true},
		}
		EventBus.event_triggered.emit(event)
		GlobalData.apply_event_effect(event)
		GameManager.enter_combat("boss")
		return
	print("Entering Extraction Zone / Final Boss Battle!")
	GameManager.enter_combat("boss")


func _trigger_recovery_event() -> void:
	var event := GlobalData.get_weighted_recovery_event()
	if event.is_empty():
		_trigger_default_event()
		return
	EventBus.event_triggered.emit(event)
	GlobalData.apply_event_effect(event)


func _trigger_stalker_surprise_ambush() -> void:
	var active_stalker = GlobalData.stalking_aces[0]
	GlobalData.stalking_chance = 0.0
	var safehouse_ui = get_node_or_null("SafehouseUI")
	if safehouse_ui:
		safehouse_ui.status_label.text = "SIREN WARNING! Stalking Ace: " + active_stalker + " Ambushed!"
	GameManager.enter_combat("ace")


func _trigger_random_event() -> void:
	var pool := GlobalData.get_theme_event_pool()
	if pool.is_empty():
		_trigger_default_event()
		return
	if GlobalData.mech_less:
		pool = pool.filter(func(event):
			return str(event.get("effect", "")) != "force_combat")
	pool = pool.filter(func(event):
		return RecruitSystem.is_event_available(event))
	if pool.is_empty():
		_trigger_default_event()
		return
	var total := 0
	for event in pool:
		var weight := int(event.get("weight", 1))
		var themes = event.get("themes", [])
		if themes is Array and not themes.is_empty():
			weight = int(weight * 1.5)
		total += maxi(1, weight)
	var roll := randi() % total
	var chosen: Dictionary = pool[0]
	for event in pool:
		var weight := int(event.get("weight", 1))
		var themes = event.get("themes", [])
		if themes is Array and not themes.is_empty():
			weight = int(weight * 1.5)
		roll -= maxi(1, weight)
		if roll < 0:
			chosen = event
			break
	EventBus.event_triggered.emit(chosen)
	if GlobalData.apply_event_effect(chosen):
		GameManager.enter_combat(str(chosen.get("params", {}).get("combat_type", "grunt")))


func _trigger_default_event() -> void:
	var event = {
		"name": "Abandoned Cache",
		"effect": "credits",
		"amount": 50,
		"desc": "Found abandoned cache! +50 credits",
	}
	EventBus.event_triggered.emit(event)
	GlobalData.apply_event_effect(event)


func _build_tech_copy_event() -> Dictionary:
	var tier := GlobalData.enemy_tech_tier
	return {
		"name": "ENEMY TECH COPY",
		"effect": "none",
		"amount": 0,
		"desc": "Your last victory was so clean the enemy copied your combat data! New enemy standard: Tier %d. Expect tougher foes." % tier,
	}


# Places the enemy research node on an unsettled (non-special) walkable tile
# several cells ahead of the player so it becomes a real hunt.
func _place_enemy_base_node() -> void:
	var current_layer := current_pos.x
	var target_layers: Array[int] = [current_layer + 2, current_layer + 3, current_layer + 4]
	var target_layer: int = target_layers[randi() % target_layers.size()]

	var candidates: Array = []
	var fallback: Array = []
	for key in nodes_dict:
		var tile_type: String = nodes_dict[key].get_meta("tile_type", "empty")
		if tile_type in ["start", "exit", "safehouse", "city", "enemy_base"]:
			continue
		if not BoardConfig.is_passable(str(nodes_dict[key].get_meta("terrain", "plain"))):
			continue
		if key.x == target_layer:
			candidates.append(key)
		elif key.x > current_layer:
			fallback.append(key)
	if candidates.is_empty():
		candidates = fallback
	if candidates.is_empty():
		for key in nodes_dict:
			if key != current_pos and nodes_dict[key].get_meta("tile_type", "empty") not in ["start", "exit", "safehouse", "city"]:
				if BoardConfig.is_passable(str(nodes_dict[key].get_meta("terrain", "plain"))):
					candidates.append(key)
	if candidates.is_empty():
		candidates = [current_pos]

	var target_key: Vector2i = candidates[randi() % candidates.size()]
	var tile = nodes_dict[target_key]
	tile.set_meta("tile_type", "enemy_base")
	GlobalData.enemy_base_tile_pos = target_key
	tile.reveal()
	if tile.has_method("_update_visual"):
		tile._update_visual()
	# A freshly planted base starts as a temporary camp.
	_refresh_enemy_base_model()


func _build_enemy_base_spawn_event() -> Dictionary:
	return {
		"name": "ENEMY RESEARCH BASE",
		"effect": "none",
		"amount": 0,
		"desc": "A stolen-data research base has been detected on the map (burning red tile). Reach it and destroy it before the enemy finishes a counter-unit!",
	}


func _build_enemy_base_completed_event() -> Dictionary:
	match GlobalData.enemy_copy_outcome:
		"grunt_mk2":
			return {
				"name": "ENEMY GRUNT MKII DEPLOYED",
				"effect": "none",
				"amount": 0,
				"desc": "The enemy research base completed! Their grunts have been refit into a stronger MKII standard. Expect tougher infantry.",
			}
		"special_ace":
			return {
				"name": "SPECIAL ACE FIELDED",
				"effect": "none",
				"amount": 0,
				"desc": "The enemy research base completed! A special ace unit matching your mech class has been deployed to hunt you.",
			}
		_:
			return {
				"name": "GUNDAM COPY FIELDED",
				"effect": "none",
				"amount": 0,
				"desc": "The enemy research base completed! They have produced a copy of your gundam-class mech. It fights with your own tech.",
			}


func _build_enemy_base_destroyed_event() -> Dictionary:
	return {
		"name": "ENEMY RESEARCH BASE DESTROYED",
		"effect": "none",
		"amount": 0,
		"desc": "You destroyed the enemy research base! The enemy only salvaged a partial grunt upgrade instead of a full counter-unit.",
	}


func get_tile_type(pos: Vector2i) -> String:
	if nodes_dict.has(pos):
		return nodes_dict[pos].get_meta("tile_type", "empty")
	return "empty"


# Marks the active enemy base's tile back onto the freshly regenerated board
# (returning from a battle rebuilds the grid; the base must survive the trip).
func _restore_enemy_base_tile() -> void:
	if not GlobalData.enemy_base_active:
		return
	var pos := GlobalData.enemy_base_tile_pos
	if pos == Vector2i(-1, -1) or not nodes_dict.has(pos):
		return
	var tile = nodes_dict[pos]
	tile.set_meta("tile_type", "enemy_base")
	tile.reveal()
	if tile.has_method("_update_visual"):
		tile._update_visual()


# Keeps the enemy base's 3D model in sync with how far its research has
# progressed: a freshly planted base is a temporary camp (tent), one that has
# rooted in (>= half its research done) becomes a tall fortified building.
func _refresh_enemy_base_model() -> void:
	if not GlobalData.enemy_base_active:
		return
	var pos := GlobalData.enemy_base_tile_pos
	if pos == Vector2i(-1, -1) or not nodes_dict.has(pos):
		return
	var ratio := 0.0
	if GlobalData.enemy_base_required > 0.0:
		ratio = GlobalData.enemy_base_progress / GlobalData.enemy_base_required
	var kind := "rooted" if ratio >= 0.5 else "camp"
	var tile = nodes_dict[pos]
	if tile.has_method("set_enemy_base_model"):
		tile.set_enemy_base_model(kind)