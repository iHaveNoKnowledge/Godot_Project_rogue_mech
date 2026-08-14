extends Node3D

## Open-grid board controller. Replaces the old layered node graph with a free-
## movement grid: the player steps cell-by-cell (WASD or click), each cell costs
## movement points from a per-day pool. Patrol fleets roam the grid, objectives
## gate the exit, and terrains slow or block movement.

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
# WASD moves the token (camera pans with the arrow keys). Physical-key checks so
# the two never fight over the same input.
const DIR_KEYS := {
	KEY_D: Vector2i(1, 0),
	KEY_A: Vector2i(-1, 0),
	KEY_S: Vector2i(0, 1),
	KEY_W: Vector2i(0, -1),
}

var current_pos: Vector2i = Vector2i.ZERO
var nodes_dict: Dictionary = {}
var _tooltip: Node
var _reveal_log: Dictionary = {}


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
	_update_token_position()
	_highlight_adjacent()

	# Revert any stale enemy_base tile, then surface pending events (same flow as
	# the old graph board).
	_clear_enemy_base_tile()

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

	if GlobalData.board_day == 1 and GlobalData.board_mp >= GlobalData.board_mp_max:
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
	if get_tree().paused or not visible or _intermission_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		for keycode in DIR_KEYS:
			if event.is_keycode_pressed(keycode):
				var dir: Vector2i = DIR_KEYS[keycode]
				_try_step(current_pos + dir)
				return
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
	if GlobalData.board_mp < cost:
		EventBus.event_triggered.emit({
			"name": "NO MOVEMENT LEFT",
			"effect": "none",
			"amount": 0,
			"desc": "You've run out of movement for today. End the day (End key) to push on.",
		})
		return false

	GlobalData.board_mp = maxi(GlobalData.board_mp - cost, 0)
	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()
	var revealed := _reveal_around(target)

	GlobalData.blocked_intermission = false

	# Objective progress triggers.
	_check_survey_objective(revealed)
	if str(tile.get_meta("terrain", "plain")) == "bridge" and BoardSystem.get_objective().get("id", "") == "cross_river":
		BoardSystem.complete()
		_announce_objective_done()

	# Stepping onto a patrol fleet forces a fight (checked before the tile's own
	# effect so a patrol on a combat tile doesn't double-trigger).
	var patrol := PatrolSystem.get_patrol_at(target)
	var engaged_patrol := false
	if not patrol.is_empty() and GameManager.current_state == GameManager.State.BOARD:
		engaged_patrol = true
		GlobalData.board_patrol_engagement = int(patrol.get("id", -1))

	EventBus.tile_entered.emit(target, tile)
	if not engaged_patrol:
		_process_tile_effect(str(tile.get_meta("tile_type", "empty")))
	elif GameManager.current_state == GameManager.State.BOARD:
		GameManager.enter_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
		return true

	if GlobalData.board_mp <= 0:
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


func _end_day() -> void:
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

	EventBus.board_day_ended.emit()

	# Patrols move after the day's systems resolve.
	var ambush := PatrolSystem.advance_day(current_pos)
	if ambush != Vector2i(-1, -1) and GameManager.current_state == GameManager.State.BOARD:
		var patrol := PatrolSystem.get_patrol_at(ambush)
		if not patrol.is_empty():
			GlobalData.board_patrol_engagement = int(patrol.get("id", -1))
			GameManager.enter_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
			return

	_update_token_position()
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
	if not patrol.is_empty():
		text += "\nPATROL: %s — %d grunt(s)" % [patrol.get("name", "fleet"), int(patrol.get("grunts", 1))]
		if int(patrol.get("aces", 0)) > 0:
			text += " + %d ACE" % int(patrol.get("aces", 0))
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
	tile.set_meta("tile_type", "combat")
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
			if GlobalData.mech_less:
				_trigger_recovery_event()
			elif GlobalData.ceasefire_turns > 0:
				GlobalData.ceasefire_turns -= 1
				_trigger_ceasefire_skip()
			elif not GlobalData.stalking_aces.is_empty() and randf() < GlobalData.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				GameManager.enter_combat("grunt")
		"enemy_base":
			if GlobalData.mech_less:
				_trigger_recovery_event()
				return
			if GlobalData.enemy_base_active and GlobalData.enemy_base_tile_pos == current_pos:
				GameManager.enter_combat("enemy_base")
			else:
				GameManager.enter_combat("grunt")
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
		"start":
			print("Entering Hangar Practice Ground.")
		"exit":
			_trigger_exit_event()
		_:
			pass


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
	var event = {
		"name": "Hidden Dead End",
		"effect": "dead_end",
		"amount": 0,
		"desc": "Approached a hidden obstacle! Reroute path required.",
	}
	EventBus.event_triggered.emit(event)


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