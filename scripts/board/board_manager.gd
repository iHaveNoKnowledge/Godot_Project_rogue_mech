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

	current_pos = GlobalData.board.current_tile
	if not nodes_dict.has(current_pos):
		current_pos = Vector2i(0, 0)
		GlobalData.board.current_tile = current_pos

	# Objective + patrols for this sector (fresh on new sector, restored on
	# reload after combat).
	if GlobalData.board.board_objective_id == "":
		_setup_objective()
	GlobalData.board.board_patrol_engagement = -1

	# Artillery Impact Report UI (sequential cinematic strikes)
	if get_node_or_null("ArtilleryReportUI") == null:
		var art_ui := ArtilleryReportUI.new()
		art_ui.name = "ArtilleryReportUI"
		add_child(art_ui)
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
	# Restore wreckage tile from a previous mech destruction.
	_restore_wreckage_tile()

	if EnemyFactionSystem.consume_pending_escalation_event():
		EventBus.event_triggered.emit(_build_tech_copy_event())

	if EnemyFactionSystem.consume_pending_enemy_base_destroyed():
		EventBus.event_triggered.emit(_build_enemy_base_destroyed_event())
		if BoardSystem.get_objective().get("id", "") == "hq_strike":
			BoardSystem.complete()

	if GlobalData.board.run_notice != "":
		var notice := GlobalData.board.run_notice
		GlobalData.board.run_notice = ""
		EventBus.event_triggered.emit({
			"name": "CONVOY REPORT",
			"effect": "none",
			"amount": 0,
			"desc": notice,
		})

	if GlobalData.board.board_day == 1 and GlobalData.board.board_mp >= GlobalData.board.board_mp_max and not GlobalData.board.board_objective_intro_consumed:
		GlobalData.board.board_objective_intro_consumed = true
		EventBus.event_triggered.emit(_build_objective_event())

	_check_current_tile_patrol_engagement()


func _check_current_tile_patrol_engagement() -> bool:
	if GameManager.current_state != GameManager.State.BOARD:
		return false
	var patrol := PatrolSystem.get_patrol_at(current_pos)
	if patrol.is_empty():
		return false

	GlobalData.board.board_patrol_engagement = int(patrol.get("id", -1))
	if str(patrol.get("faction", "hostile")) == "unknown" and _has_available_recruit(str(patrol.get("character_id", ""))):
		_trigger_patrol_talk_event(patrol)
		return true

	if GlobalData.narrative.mech_less:
		GlobalData.board.board_patrol_engagement = -1
		_trigger_recovery_event()
		return true

	_request_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
	return true


func _setup_objective() -> void:
	var obj := BoardSystem.get_objective()
	GlobalData.board.board_objective_id = str(obj.get("id", ""))
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = int(obj.get("required", 1))


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

# Steps the token towards the target cell. If adjacent, takes 1 step directly.
# If further away, calculates a walkable path and steps cell-by-cell up to available MP / Energy.
func move_to_tile(target: Vector2i) -> bool:
	if not is_inside_tree() or get_tree().paused or _intermission_open():
		return false
	if target == current_pos:
		return false

	if _is_adjacent(current_pos, target):
		return _try_step(target)

	var path := _find_path(current_pos, target)
	if path.is_empty():
		print("Cannot move there! (no walkable path)")
		return false

	var moved_any := false
	for step in path:
		if not is_inside_tree() or get_tree().paused or _intermission_open() or GameManager.current_state != GameManager.State.BOARD:
			break
		if GlobalData.board.board_mp <= 0 or GlobalData.fuel.mech_energy <= 0.0:
			break
		var ok := _try_step(step)
		if not ok:
			break
		moved_any = true
		if not is_inside_tree() or get_tree().paused or GameManager.current_state != GameManager.State.BOARD:
			break

	return moved_any


func _find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not nodes_dict.has(start) or not nodes_dict.has(goal):
		var empty_res: Array[Vector2i] = []
		return empty_res
	var goal_tile = nodes_dict[goal]
	var goal_terrain := str(goal_tile.get_meta("terrain", "plain"))
	if not BoardConfig.is_passable(goal_terrain):
		var empty_res: Array[Vector2i] = []
		return empty_res

	var queue: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		if curr == goal:
			break

		for d: Vector2i in DIRS:
			var nxt: Vector2i = curr + d
			if not nodes_dict.has(nxt) or came_from.has(nxt):
				continue
			var tile = nodes_dict[nxt]
			var terrain := str(tile.get_meta("terrain", "plain"))
			if not BoardConfig.is_passable(terrain):
				continue
			came_from[nxt] = curr
			queue.append(nxt)

	if not came_from.has(goal):
		var empty_res: Array[Vector2i] = []
		return empty_res

	var path: Array[Vector2i] = []
	var trace: Vector2i = goal
	while trace != start:
		path.append(trace)
		trace = came_from[trace]
	path.reverse()
	return path


func _unhandled_input(event: InputEvent) -> void:
	# The token moves by CLICKING a reachable tile (board_tile._on_input_event);
	# WASD/Q/E belong to the camera (pan + rotate). Board-wide keys (end day, roller toggle)
	# are handled here.
	if not is_inside_tree() or get_tree().paused or not visible or _intermission_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("pause"):
			return
		if event.keycode == KEY_END or event.keycode == KEY_ENTER:
			_end_day()
		elif event.keycode == KEY_R or event.keycode == KEY_TAB:
			_cycle_traversal_mode()
		elif event.keycode == KEY_1:
			_switch_to_convoy_mode()
		elif event.keycode == KEY_2:
			GlobalData.fuel.deploy_mecha()
			_on_mode_switched("DEPLOYED MECHA", "Deployed Mecha from the Convoy! Base truck remains parked. Operating on mech battery.")
		elif event.keycode == KEY_3:
			GlobalData.fuel.deploy_pilot()
			_on_mode_switched("DEPLOYED PILOT", "Pilot dismounted on foot! Ultra-stealth profile active. Operating on stamina.")


func _cycle_traversal_mode() -> void:
	var cur_mode: String = GlobalData.fuel.traversal_mode
	if cur_mode == "convoy":
		GlobalData.fuel.deploy_mecha()
		_on_mode_switched("DEPLOYED MECHA", "Deployed Mecha from the Convoy! Base truck remains parked. Operating on mech battery.")
	elif cur_mode == "mecha":
		GlobalData.fuel.deploy_pilot()
		_on_mode_switched("DEPLOYED PILOT", "Pilot dismounted on foot! Ultra-stealth profile active. Operating on stamina.")
	elif cur_mode == "pilot":
		if current_pos == GlobalData.fuel.convoy_pos and GlobalData.fuel.convoy_is_deployed:
			GlobalData.fuel.reembark_convoy()
			_on_mode_switched("RE-EMBARKED CONVOY", "Re-embarked onto the Convoy truck! Base camp restored to mobile mode.")
		else:
			GlobalData.fuel.traversal_mode = "mecha"
			_on_mode_switched("MOUNTED MECHA", "Pilot entered the active Mecha! Operating on mech battery.")


func _switch_to_convoy_mode() -> void:
	if current_pos == GlobalData.fuel.convoy_pos or not GlobalData.fuel.convoy_is_deployed:
		GlobalData.fuel.reembark_convoy()
		_on_mode_switched("CONVOY MODE", "Active unit is the Convoy Truck.")
	else:
		EventBus.event_triggered.emit({
			"name": "CONVOY FAR AWAY",
			"effect": "none",
			"amount": 0,
			"desc": "The Convoy truck is parked at tile %s. Return to that tile to re-embark." % str(GlobalData.fuel.convoy_pos),
		})


func _on_mode_switched(title: String, desc_text: String) -> void:
	_update_token_position()
	EventBus.event_triggered.emit({
		"name": title,
		"effect": "none",
		"amount": 0,
		"desc": desc_text,
	})


func _try_step(target: Vector2i) -> bool:
	if not nodes_dict.has(target):
		return false
	if target == current_pos:
		return false
	var tile = nodes_dict[target]
	var terrain := str(tile.get_meta("terrain", "plain"))
	if not BoardConfig.is_passable(terrain):
		return false
	if not _is_adjacent(current_pos, target):
		return false

	var mode: String = GlobalData.fuel.traversal_mode
	var step_costs: Dictionary = GlobalData.fuel.get_mode_step_cost(terrain)
	var cost: int = int(step_costs["mp"])
	cost += PatrolSystem.interception_surcharge(current_pos, target)

	# Multi-tier energy resource check
	if mode == "convoy":
		var f_cost: float = float(step_costs["fuel"])
		if GlobalData.fuel.convoy_fuel < f_cost:
			GlobalData.narrative.blocked_intermission = false
			EventBus.event_triggered.emit({
				"name": "CONVOY OUT OF FUEL",
				"effect": "none",
				"amount": 0,
				"desc": "The convoy truck is out of diesel! Park as Base Camp and deploy Mecha or Pilot on foot.",
			})
			return false
		GlobalData.fuel.convoy_fuel = maxf(GlobalData.fuel.convoy_fuel - f_cost, 0.0)
	elif mode == "mecha":
		var e_cost: float = float(step_costs["energy"])
		if GlobalData.fuel.mech_energy < e_cost:
			GlobalData.narrative.blocked_intermission = false
			EventBus.event_triggered.emit({
				"name": "MECHA BATTERY DEPLETED",
				"effect": "none",
				"amount": 0,
				"desc": "The mech's battery is depleted! Deploy a pilot on foot or end the day to recharge.",
			})
			return false
		GlobalData.fuel.mech_energy = maxf(GlobalData.fuel.mech_energy - e_cost, 0.0)
	elif mode == "pilot":
		var s_cost: float = float(step_costs["stamina"])
		if GlobalData.fuel.pilot_stamina < s_cost:
			GlobalData.narrative.blocked_intermission = false
			EventBus.event_triggered.emit({
				"name": "PILOT EXHAUSTED",
				"effect": "none",
				"amount": 0,
				"desc": "The pilot is too exhausted to march further today. End the day to rest.",
			})
			return false
		GlobalData.fuel.pilot_stamina = maxf(GlobalData.fuel.pilot_stamina - s_cost, 0.0)

	if GlobalData.board.board_mp < cost:
		GlobalData.narrative.blocked_intermission = false
		EventBus.event_triggered.emit({
			"name": "NO MOVEMENT LEFT",
			"effect": "none",
			"amount": 0,
			"desc": "You've run out of movement for today. End the day (End key) to push on.",
		})
		return false

	GlobalData.board.board_mp = maxi(GlobalData.board.board_mp - cost, 0)

	# Re-embarkation check: if returning to the parked convoy base camp
	if GlobalData.fuel.convoy_is_deployed and target == GlobalData.fuel.convoy_pos:
		GlobalData.fuel.reembark_convoy()
		EventBus.event_triggered.emit({
			"name": "CONVOY REGROUPED",
			"effect": "none",
			"amount": 0,
			"desc": "Returned to base! Re-embarked onto the Convoy truck. Carried supplies transferred.",
		})

	# Zone of Control (ZoC) (GDD §3.3): on-foot pilots can slip past ZoC with stealth
	if mode != "pilot" and PatrolSystem.is_in_zone_of_control(target) and PatrolSystem.get_patrol_at(target).is_empty():
		if GlobalData.board.board_mp > 0:
			GlobalData.board.board_mp = 0
			EventBus.event_triggered.emit({
				"name": "ZONE OF CONTROL",
				"effect": "none",
				"amount": 0,
				"desc": "You entered a hostile fleet's Zone of Control! All remaining MP has been depleted.",
			})

	_last_dir = target - current_pos
	GlobalData.board.player_last_dir = _last_dir
	current_pos = target
	GlobalData.board.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()
	var revealed := _reveal_around(target)
	if revealed > 0:
		_refresh_patrol_markers()

	# If any hostile fleet can see the convoy on this tile, remember exactly where
	# it was — fleets that lose sight keep converging on that last position.
	PatrolSystem.record_spotting(current_pos)

	GlobalData.narrative.blocked_intermission = false

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
		GlobalData.board.board_patrol_engagement = int(patrol.get("id", -1))

	EventBus.tile_entered.emit(target, tile)
	if not engaged_patrol:
		# A chokepoint (bridge / one-wide passage) is ambush ground: hostile
		# forces spring a pincer on the convoy there. Once it fires the combat
		# spawns enemies in two opposing arcs instead of a ring.
		if _roll_chokepoint_ambush(tile):
			GlobalData.board.ambush_pincer = true
			GlobalData.narrative.blocked_intermission = true
			_request_combat("grunt")
			return true
		if _roll_travel_breakdown(terrain):
			return true
		_process_tile_effect(str(tile.get_meta("tile_type", "empty")))
	elif GameManager.current_state == GameManager.State.BOARD:
		if str(patrol.get("faction", "hostile")) == "unknown" and _has_available_recruit(str(patrol.get("character_id", ""))):
			_trigger_patrol_talk_event(patrol)
			return true
		# Pilot-only convoys can't fight on foot: the encounter becomes a
		# recovery event (same behavior the old combat tiles had).
		if GlobalData.narrative.mech_less:
			GlobalData.board.board_patrol_engagement = -1
			_trigger_recovery_event()
			return true
		_request_combat("grunt" if int(patrol.get("aces", 0)) == 0 else "ace")
		return true

	# A tile effect may have already entered combat (change_scene_to_file frees
	# this scene immediately) or opened a pause overlay (safehouse/city shop).
	# Never run the end-of-day flow on a scene that is no longer in the tree —
	# its event popup would crash on get_tree() == null.
	if GlobalData.board.board_mp <= 0 and is_inside_tree() and not get_tree().paused \
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
func _refresh_after_event_closed() -> void:
	if not is_inside_tree():
		return
	_refresh_patrol_markers()
	_clear_highlights()
	_highlight_adjacent()
	_update_token_position()


func _end_day() -> void:
	# Safety net: combat was entered this frame (the board scene is already out
	# of the tree), so the end-of-day emit would hit an orphaned EventUI.
	if not is_inside_tree() or GameManager.current_state != GameManager.State.BOARD:
		return
	GlobalData.board.board_day += 1
	GlobalData.board.board_mp = GlobalData.board.board_mp_max
	# Passive energy regen: the mech recharges while resting between days.
	GlobalData.fuel.mech_energy = minf(
		GlobalData.fuel.mech_energy + GlobalData.BOARD_ENERGY_REGEN_PER_DAY,
		GlobalData.fuel.mech_max_energy
	)
	# Convoy fuel reserve replenishes overnight.
	GlobalData.fuel.convoy_fuel_reserve = minf(
		GlobalData.fuel.convoy_fuel_reserve + GlobalData.CONVOY_DAILY_FUEL_REGEN,
		GlobalData.fuel.convoy_fuel_max
	)
	# Engine dirt slowly cleans up between days.
	GlobalData.fuel.engine_dirt = maxf(GlobalData.fuel.engine_dirt - GlobalData.ENGINE_DIRT_CLEANUP_PER_DAY, 0.0)
	# Reset daily depot seizure flag.
	GlobalData.fuel.fuel_depot_seized_today = false

	# Once-per-day systems.
	process_turn_mobilization()
	accumulate_stalker_chance()

	var spy_event := EnemyFactionSystem.roll_spy_event()
	if not spy_event.is_empty():
		EventBus.event_triggered.emit(spy_event)

	if EnemyFactionSystem.consume_enemy_base_spawn_request():
		_place_enemy_base_node()
		EventBus.event_triggered.emit(_build_enemy_base_spawn_event())

	if EnemyFactionSystem.tick_enemy_base_progress(1.0):
		EventBus.event_triggered.emit(_build_enemy_base_completed_event())
	# The base's research moved forward today — upgrade its model from a
	# temporary camp to a rooted tower once it has dug in (>= half done).
	_refresh_enemy_base_model()

	EventBus.board_day_ended.emit()

	# Patrols move after the day's systems resolve.
	var ambush := PatrolSystem.advance_day(current_pos)
	if (ambush != Vector2i(-1, -1) or not PatrolSystem.get_patrol_at(current_pos).is_empty()) and GameManager.current_state == GameManager.State.BOARD:
		if _check_current_tile_patrol_engagement():
			return

	_update_token_position()
	_refresh_patrol_markers()
	_highlight_adjacent()

	# Check Artillery Fleet Bombardment (GDD §3.3)
	var artillery_strikes := PatrolSystem.check_artillery_bombardment(current_pos)
	if not artillery_strikes.is_empty() and GameManager.current_state == GameManager.State.BOARD:
		_trigger_artillery_bombardment(artillery_strikes)

	EventBus.event_triggered.emit({
		"name": "DAY %d" % GlobalData.board.board_day,
		"effect": "none",
		"amount": 0,
		"desc": "Supplies refreshed — %d MP. %s" % [GlobalData.board.board_mp_max, BoardSystem.progress_text()],
	})


# Artillery Fleet strategic bombardment (GDD §3.3)
func _trigger_artillery_bombardment(fleets: Array[Dictionary]) -> void:
	if fleets.is_empty():
		return

	var report_ui = get_node_or_null("ArtilleryReportUI") as ArtilleryReportUI
	if report_ui == null:
		report_ui = ArtilleryReportUI.new()
		report_ui.name = "ArtilleryReportUI"
		add_child(report_ui)

	var total_fleets := fleets.size()
	for i in range(total_fleets):
		var fleet = fleets[i]
		await _execute_single_artillery_strike(fleet, i + 1, total_fleets, report_ui)


func _execute_single_artillery_strike(fleet: Dictionary, strike_idx: int, total_strikes: int, report_ui: ArtilleryReportUI) -> void:
	var fleet_grid: Vector2i = fleet.get("pos", Vector2i.ZERO)
	var fleet_name: String = str(fleet.get("name", "Hostile Artillery Fleet"))

	var target_pos := player_token.global_position if player_token and is_instance_valid(player_token) else Vector3.ZERO
	if nodes_dict.has(current_pos) and is_instance_valid(nodes_dict[current_pos]):
		target_pos = nodes_dict[current_pos].global_position + Vector3(0, 0.6, 0)

	var shooter_pos := target_pos + Vector3(8.0, 1.0, 8.0)
	if nodes_dict.has(fleet_grid) and is_instance_valid(nodes_dict[fleet_grid]):
		shooter_pos = nodes_dict[fleet_grid].global_position + Vector3(0, 1.0, 0)

	# 1. Pan Camera to the shooter
	var cam_rig = get_tree().get_first_node_in_group("camera_rig")
	if cam_rig and cam_rig.has_method("pan_to_world_pos"):
		var pan_tw = cam_rig.pan_to_world_pos(shooter_pos, 0.65)
		if pan_tw:
			await pan_tw.finished
	await get_tree().create_timer(0.35).timeout

	# 2. Shooter fires with muzzle flash, smoke, and audio
	var shoot_dir := (target_pos - shooter_pos).normalized()
	shoot_dir.y = 0.45
	shoot_dir = shoot_dir.normalized()
	EffectManager.spawn_muzzle_flash(shooter_pos, shoot_dir, Color(1.0, 0.65, 0.15))
	EffectFactory.spawn_smoke_plume(get_tree(), shooter_pos, 5, 0.35, 0.6, 1.2)
	if AudioManager:
		AudioManager.play_sfx_by_name("missile", shooter_pos)

	# 3. Launch Salvo of 3 parabolic artillery shells & Pan camera back to target
	for s in range(3):
		var delay := float(s) * 0.18
		var spread := Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		var dest := target_pos + spread
		_spawn_parabolic_shell(shooter_pos, dest, delay)

	# Pan camera back to the player token / convoy
	if cam_rig and cam_rig.has_method("pan_to_player"):
		cam_rig.pan_to_player(0.65)

	# Wait for shells to land and detonate (~0.85s)
	await get_tree().create_timer(0.85).timeout

	# 4. Calculate Before / After Damage & Apply
	# Player Active Mech:
	var cur_torso_dmg: float = float(GlobalData.weapons.part_damage.get("body", 0.0))
	var old_player_hp_pct := int(clampf(1.0 - cur_torso_dmg, 0.0, 1.0) * 100.0)
	var new_torso_dmg := minf(cur_torso_dmg + 0.12, 1.0)
	GlobalData.weapons.part_damage["body"] = new_torso_dmg
	var new_player_hp_pct := int(clampf(1.0 - new_torso_dmg, 0.0, 1.0) * 100.0)

	var cur_energy := GlobalData.fuel.mech_energy
	GlobalData.fuel.mech_energy = maxf(cur_energy - 30.0, 0.0)

	var active_name := "Active Mech"
	for m in HangarManager.get_mechs():
		if str(m.get("id", "")) == GlobalData.hangar.active_hangar_mech_id:
			active_name = str(m.get("name", "Active Mech"))
			break

	var player_unit_data := {
		"name": active_name,
		"old_hp": float(old_player_hp_pct),
		"new_hp": float(new_player_hp_pct),
		"max_hp": 100.0,
		"energy_loss": 30.0
	}

	# Squadmates / Hangar Allies:
	var squad_units_data: Array[Dictionary] = []
	for m in HangarManager.get_mechs():
		var mid := str(m.get("id", ""))
		if mid == GlobalData.hangar.active_hangar_mech_id:
			continue
		var pid := str(m.get("pilot", ""))
		if pid == "":
			continue
		var mname := str(m.get("name", "Ally Mech"))
		var pname := HangarManager.get_pilot_name(pid)
		var prole: String = ["RUSHER", "RANGED", "HEAVY", "SUPPORT"][clampi(HangarManager.get_archetype(mid), 0, 3)]
		squad_units_data.append({
			"name": mname,
			"pilot_name": pname,
			"role": prole,
			"old_hp": 100.0,
			"new_hp": 90.0,
			"max_hp": 100.0,
		})

	# Convoy Truck:
	var cur_convoy_hp := GlobalData.board.convoy_hp
	var old_convoy := cur_convoy_hp
	var new_convoy := maxf(cur_convoy_hp - 10.0, 0.0)
	GlobalData.board.convoy_hp = new_convoy

	var convoy_unit_data := {
		"old_hp": old_convoy,
		"new_hp": new_convoy,
		"max_hp": GlobalData.board.convoy_hp_max,
		"hp_loss": 10.0
	}

	# 5. Show Impact Report and wait for player to continue
	if report_ui:
		report_ui.show_report(fleet_name, strike_idx, total_strikes, player_unit_data, squad_units_data, convoy_unit_data)
		await report_ui.report_closed


func _spawn_parabolic_shell(start_pos: Vector3, dest_pos: Vector3, delay: float) -> void:
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	shell.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.7, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.1)
	mat.emission_energy_multiplier = 4.5
	shell.material_override = mat

	add_child(shell)
	shell.global_position = start_pos
	shell.visible = false

	var duration := 0.55
	var arc_height := 8.0

	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_callback(func():
		if is_instance_valid(shell):
			shell.visible = true
	)
	tween.tween_method(func(progress: float):
		if not is_instance_valid(shell):
			return
		var current_xz := start_pos.lerp(dest_pos, progress)
		var height_offset := sin(progress * PI) * arc_height
		shell.global_position = Vector3(current_xz.x, lerp(start_pos.y, dest_pos.y, progress) + height_offset, current_xz.z)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tween.tween_callback(func():
		if is_instance_valid(shell):
			shell.queue_free()
		# Detonate on impact
		EffectManager.spawn_explosion(dest_pos, 4.0)
		var rigs = get_tree().get_nodes_in_group("camera_rig")
		if not rigs.is_empty() and rigs[0].has_method("add_shake"):
			rigs[0].add_shake(0.4)
		if player_token and is_instance_valid(player_token):
			_flinch_player_token()
	)


func _flinch_player_token() -> void:
	if player_token == null or not is_instance_valid(player_token):
		return
	var orig_scale: Vector3 = player_token.scale
	var flinch := create_tween()
	flinch.tween_property(player_token, "scale", orig_scale * Vector3(1.35, 0.65, 1.35), 0.06).set_trans(Tween.TRANS_QUAD)
	flinch.tween_property(player_token, "scale", orig_scale, 0.14).set_trans(Tween.TRANS_BOUNCE)


func _check_survey_objective(newly: int) -> void:
	if BoardSystem.get_objective().get("id", "") != "survey":
		return
	if newly <= 0:
		return
	var before := GlobalData.board.board_objective_progress
	BoardSystem.add_progress(newly)
	if not BoardSystem.is_objective_complete() and GlobalData.board.board_objective_progress > before:
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
	var mode: String = GlobalData.fuel.traversal_mode
	var radius: int = 3 if mode == "pilot" else 2
	var newly := 0
	for k in _tiles_in_radius(center, radius):
		var tile = nodes_dict.get(k)
		if tile == null or tile.is_revealed:
			continue
		if _reveal_log.has(k):
			continue
		tile.reveal(true)
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
		if GlobalData.board.board_mp >= BoardConfig.move_cost(str(tile.get_meta("terrain", "plain"))):
			tile.highlight(true)


func _clear_highlights() -> void:
	for key in nodes_dict:
		nodes_dict[key].highlight(false)


var _base_camp_token: Node3D = null


func _update_token_position() -> void:
	if nodes_dict.has(current_pos):
		var tile = nodes_dict[current_pos]
		var patrol_on_tile := not PatrolSystem.get_patrol_at(current_pos).is_empty()
		# Offset player token to the west (-0.55m) if sharing the tile with a patrol fleet,
		# so the player pawn and enemy token stand side-by-side without clipping/overlapping.
		var offset_x: float = -0.55 if patrol_on_tile else 0.0
		player_token.global_position = tile.global_position + Vector3(offset_x, 0.9, 0.0)
		# Point the arrow at the last heading (east = (1,0), south = (0,1), ...).
		if player_token.has_method("face_heading"):
			player_token.face_heading(_last_dir)

		# Attach / update mode billboard tag on player token
		var tag: Label3D = player_token.get_node_or_null("ModeTag")
		if tag == null:
			tag = Label3D.new()
			tag.name = "ModeTag"
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.font_size = 38
			tag.position = Vector3(0.0, 0.9, 0.0)
			tag.outline_size = 8
			tag.outline_modulate = Color.BLACK
			player_token.add_child(tag)

		var mode: String = GlobalData.fuel.traversal_mode
		match mode:
			"mecha":
				tag.text = "🤖 MECHA MARCH\nBattery: %.0f" % GlobalData.fuel.mech_energy
				tag.modulate = Color(0.3, 0.8, 1.0)
			"pilot":
				tag.text = "🏃 PILOT SCOUT (STEALTH)\nStamina: %.0f" % GlobalData.fuel.pilot_stamina
				tag.modulate = Color(0.4, 1.0, 0.4)
			_:
				tag.text = "🚚 CONVOY TRUCK\nFuel: %.0f/%.0f" % [GlobalData.fuel.convoy_fuel, GlobalData.fuel.convoy_max_fuel]
				tag.modulate = Color(1.0, 0.88, 0.2)

	# 2. Manage Parked Convoy Base Camp Token
	if GlobalData.fuel.convoy_is_deployed:
		var c_pos: Vector2i = GlobalData.fuel.convoy_pos
		if nodes_dict.has(c_pos):
			if _base_camp_token == null:
				_base_camp_token = Node3D.new()
				_base_camp_token.name = "ConvoyBaseCampToken"
				# Add a small base depot marker mesh
				var mi := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(1.2, 0.4, 0.8)
				mi.mesh = box
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.2, 0.6, 0.9)
				mat.emission_enabled = true
				mat.emission = Color(0.1, 0.4, 0.8)
				mi.material_override = mat
				_base_camp_token.add_child(mi)

				var camp_tag := Label3D.new()
				camp_tag.name = "CampTag"
				camp_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				camp_tag.no_depth_test = true
				camp_tag.font_size = 40
				camp_tag.position = Vector3(0.0, 0.9, 0.0)
				camp_tag.outline_size = 8
				camp_tag.outline_modulate = Color.BLACK
				_base_camp_token.add_child(camp_tag)
				add_child(_base_camp_token)

			var c_tile = nodes_dict[c_pos]
			_base_camp_token.global_position = c_tile.global_position + Vector3(0, 0.7, 0)
			var camp_tag: Label3D = _base_camp_token.get_node_or_null("CampTag")
			if camp_tag:
				if GlobalData.fuel.seizure_stage > 0:
					camp_tag.text = "🚨 UNDER SEIZURE (STAGE %d)\nTurns Left: %d" % [GlobalData.fuel.seizure_stage, GlobalData.fuel.seizure_turns_left]
					camp_tag.modulate = Color(1.0, 0.2, 0.2)
				else:
					camp_tag.text = "🚚 CONVOY BASE\nFuel: %.0f/%.0f" % [GlobalData.fuel.convoy_fuel, GlobalData.fuel.convoy_max_fuel]
					camp_tag.modulate = Color(0.2, 0.8, 1.0)
	else:
		if _base_camp_token != null:
			_base_camp_token.queue_free()
			_base_camp_token = null


# ---------------------------------------------------------------------------
# PATROL FLEET MARKERS (arrow models on the board, one per fleet)
# ---------------------------------------------------------------------------

# Spawns one 3D arrow marker on every patrol fleet's tile so fleets read as
# real units on the map (styled according to fleet archetype).
func _refresh_patrol_markers() -> void:
	if _patrol_marker_container == null:
		_patrol_marker_container = Node3D.new()
		_patrol_marker_container.name = "PatrolMarkers"
		add_child(_patrol_marker_container)
	for child in _patrol_marker_container.get_children():
		child.queue_free()
	for p in GlobalData.board.board_patrols:
		# Old saves can carry pos/dir as JSON-flattened Strings — heal the
		# entry so every fleet reliably draws its arrow marker.
		PatrolSystem.normalize_patrol(p)
		var pos: Vector2i = PatrolSystem.normalize_dir(p.get("pos"))
		if not nodes_dict.has(pos):
			continue
		var marker := Node3D.new()
		marker.set_script(preload("res://scripts/board/patrol_marker.gd"))
		_patrol_marker_container.add_child(marker)

		# Offset patrol token to the east (+0.55m) if on the player's tile,
		# so player pawn and enemy fleet token stand side-by-side cleanly.
		var offset_x: float = 0.55 if pos == current_pos else 0.0
		var prev_pos: Vector2i = PatrolSystem.normalize_dir(p.get("prev_pos", pos))
		if prev_pos != pos and nodes_dict.has(prev_pos) and nodes_dict[pos].is_revealed:
			var start_offset: float = 0.55 if prev_pos == current_pos else 0.0
			marker.global_position = nodes_dict[prev_pos].global_position + Vector3(start_offset, 1.0, 0.0)
			var target_pos: Vector3 = nodes_dict[pos].global_position + Vector3(offset_x, 1.0, 0.0)
			var tween := create_tween()
			tween.tween_property(marker, "global_position", target_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		else:
			marker.global_position = nodes_dict[pos].global_position + Vector3(offset_x, 1.0, 0.0)
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


func is_any_modal_open() -> bool:
	if _intermission_open():
		return true
	for modal_name in ["EventUI", "SafehouseUI", "CityShopUI", "ResearchLabUI", "DeployTeamUI", "ArtilleryReportUI"]:
		var node := get_node_or_null(modal_name)
		if node != null and node.visible:
			return true
	return false


# ---------------------------------------------------------------------------
# HOVER RECONNAISSANCE (Updates BottomRight TileInspector in BoardHUD)
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	# Hide floating tooltip completely during paused state, popups, or open menus
	if _tooltip and _tooltip.has_method("show_tile"):
		_tooltip.show_tile("", Vector2(-1, -1), {})

	if not is_inside_tree() or get_tree().paused or is_any_modal_open():
		return

	var tile := _hovered_tile()
	if tile == null:
		return

	var pos := tile.get_meta("grid_pos", Vector2i(-1, -1)) as Vector2i
	var terrain := str(tile.get_meta("terrain", "plain"))
	var tt: String = tile.get_meta("tile_type", "empty")
	var patrol := PatrolSystem.get_patrol_at(pos)
	var e_cost := GlobalData.fuel.get_tile_energy_cost(terrain)
	var mp_cost := BoardConfig.move_cost(terrain)
	var is_zoc := PatrolSystem.is_in_zone_of_control(pos)
	var is_artillery := not PatrolSystem.check_artillery_bombardment(pos).is_empty()

	# Build rich recon data for TileInspector docked at bottom right
	var patrol_desc := ""
	if not patrol.is_empty():
		var is_unknown := str(patrol.get("faction", "hostile")) == "unknown"
		var arch_key := str(patrol.get("archetype", "armored"))
		var arch_data: Dictionary = BoardConfig.FLEET_ARCHETYPES.get(arch_key, {})
		var arch_name: String = str(arch_data.get("name", arch_key.capitalize() + " Fleet"))
		var tags: Array = arch_data.get("tags", [])
		var tags_str: String = ", ".join(tags) if not tags.is_empty() else "Standard"
		var speed_mp: int = int(arch_data.get("mp", 1))
		var bombard_range: int = int(arch_data.get("bombard_range", 0))

		var grunts_cnt: int = int(patrol.get("grunts", 1))
		var aces_cnt: int = int(patrol.get("aces", 0))
		var fleet_name: String = str(patrol.get("name", "Patrol Fleet"))

		var commander: Dictionary = patrol.get("commander", {})
		var commander_str := ""
		if not commander.is_empty():
			var rivalry_cnt := int(commander.get("rivalry_count", 0))
			var rival_badge := " [RIVAL - %d CLASHES!]" % rivalry_cnt if rivalry_cnt > 0 else ""
			commander_str = "• Commander: %s%s\n• Trait/Perk: %s (%s)\n• Bounty: %d Credits\n" % [
				commander.get("name", "Ace Pilot"), rival_badge,
				commander.get("trait", "Veteran"), commander.get("perk_name", "Standard"),
				int(commander.get("bounty", 150))
			]

		patrol_desc = "FLEET INTEL: %s [%s]\n%s• Squad: %d Grunt%s%s | Loadout: %s\n• Speed: %d MP%s" % [
			fleet_name, arch_name.to_upper(),
			commander_str,
			grunts_cnt, "s" if grunts_cnt != 1 else "",
			(" + %d Ace" % aces_cnt) if aces_cnt > 0 else "",
			tags_str, speed_mp,
			(" | Bombard: %d Tiles" % bombard_range) if bombard_range > 0 else ""
		]
		if str(patrol.get("character_id", "")) == "vagrant_ace":
			patrol_desc = "SPECIAL CONTACT: THE VAGRANT ACE [SEEKER]\n• Pilot: Gale 'The Vagrant' Kurogane\n• Trait: Pre-Cognitive Flow (Zero-Waste Movement)\n• Behavior: THE LEADING SHADOW (Walks 1 step ahead)\n• Status: UNALIGNED LEGENDARY PILOT"
		elif is_unknown:
			patrol_desc += "\n• Status: UNALIGNED MERCENARY"

	var hud = get_node_or_null("BoardHUD")
	if hud and hud.has_method("update_tile_inspector"):
		hud.update_tile_inspector(
			"%s (%d,%d)" % [tt.to_upper(), pos.x, pos.y],
			mp_cost, e_cost, is_zoc, is_artillery, terrain, patrol_desc
		)


func _hovered_tile() -> Node:
	if is_any_modal_open():
		return null
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
	var reset_pos := EnemyFactionSystem.consume_enemy_base_tile_reset()
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
	if GlobalData.board.heat < 3:
		return
	var grunt_recruit = int(GlobalData.narrative.enemy_forces["grunt_max"] * randf_range(0.10, 0.20))
	GlobalData.narrative.enemy_forces["grunt_current"] = clampi(
		GlobalData.narrative.enemy_forces["grunt_current"] + grunt_recruit,
		0, GlobalData.narrative.enemy_forces["grunt_max"]
	)
	if randf() < 0.30:
		GlobalData.narrative.enemy_forces["ace_current"] = clampi(
			GlobalData.narrative.enemy_forces["ace_current"] + 1,
			0, GlobalData.narrative.enemy_forces["ace_max"]
		)


func accumulate_stalker_chance() -> void:
	if not GlobalData.narrative.stalking_aces.is_empty():
		GlobalData.narrative.stalking_chance = minf(GlobalData.narrative.stalking_chance + 0.20, 1.0)


func _process_tile_effect(tile_type: String) -> void:
	match tile_type:
		"combat":
			# Legacy — new boards never roll combat tiles (battles come from
			# hostile patrol arrows); kept only as a safety net.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			elif GlobalData.narrative.ceasefire_turns > 0:
				GlobalData.narrative.ceasefire_turns -= 1
				_trigger_ceasefire_skip()
			elif not GlobalData.narrative.stalking_aces.is_empty() and randf() < GlobalData.narrative.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				_request_combat("grunt")
		"enemy_base":
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
				return
			if GlobalData.narrative.enemy_base_active and GlobalData.narrative.enemy_base_tile_pos == current_pos:
				_request_combat("enemy_base")
			else:
				_request_combat("grunt")
		"event":
			_trigger_random_event()
		"safehouse":
			HeatWantedSystem.modify_heat(-4)
			# Refuel at the safehouse: energy refill bonus.
			GlobalData.fuel.mech_energy = minf(
				GlobalData.fuel.mech_energy + GlobalData.SAFEHOUSE_ENERGY_REGEN,
				GlobalData.fuel.mech_max_energy
			)
			var safehouse = get_node_or_null("SafehouseUI")
			if safehouse:
				safehouse.visible = true
				get_tree().paused = true
		"fuel_depot":
			# Enemy fuel depot: seize it to gain fuel. Triggers a combat encounter;
			# the player must avoid destroying fuel tanks with heavy weapons.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			elif GlobalData.fuel.fuel_depot_seized_today:
				EventBus.event_triggered.emit({
					"name": "FUEL DEPOT — DEPLETED",
					"effect": "none",
					"amount": 0,
					"desc": "This depot has already been stripped today. Return tomorrow for a fresh supply.",
				})
			else:
				_trigger_fuel_depot_seizure()
		"supply_truck":
			# Friendly convoy supply transfer: transfer fuel from the truck to the
			# mech. Costs 1 full day turn and raises enemy alert level.
			_trigger_convoy_supply_transfer()
		"wreckage":
			# Pilot Siphon Protocol: the pilot walks to wreckage to siphon dirty
			# fuel for a re-ignition reboot.
			_trigger_wreckage_siphon()
		"research_lab":
			# Research Lab: browse and start research projects using data cores.
			var lab = get_node_or_null("ResearchLabUI")
			if lab:
				lab.visible = true
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
		"dust_storm":
			# Environmental Hazard: Dust Storm — Roller drain x1.5 + speed x0.85.
			GlobalData.board.current_hazard = GlobalData.HAZARD_DUST_STORM
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "DUST STORM ZONE",
					"effect": "hazard_dust_storm",
					"amount": 0,
					"desc": "Sand and debris whip through the air. Roller Dash drains 50%% more energy and movement speed reduced.",
				})
		"tactical_smog":
			# Environmental Hazard: Tactical Smog — Heat cool rate x0.5.
			GlobalData.board.current_hazard = GlobalData.HAZARD_TACTICAL_SMOG
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "TACTICAL SMOG ZONE",
					"effect": "hazard_tactical_smog",
					"amount": 0,
					"desc": "Chemical smoke fills the air. Weapons overheat twice as fast — manage your fire rate!",
				})
		"emp_zone":
			# Environmental Hazard: EMP & Jamming — No lock-on, no backup call.
			GlobalData.board.current_hazard = GlobalData.HAZARD_EMP_ZONE
			if player_token and is_instance_valid(player_token):
				EffectFactory.spawn_electric_burst(get_tree(), player_token.global_position, Color(0.4, 0.85, 1.0), 8, 1.5)
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "EMP JAMMING ZONE",
					"effect": "hazard_emp_zone",
					"amount": 0,
					"desc": "Electromagnetic interference disables lock-on targeting. Reserve Mech call blocked.",
				})
		"distress_signal":
			# Strategic Dilemma: Distress Signal — choice to help or ignore.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "DISTRESS SIGNAL",
					"effect": "choice",
					"amount": 0,
					"desc": "A distress signal crackles over the radio. Someone is stranded and calling for help. Responding costs energy but may yield salvage.",
					"params": {
						"choices": [{
							"effect": "distress_help",
							"label": "Respond (−30 energy)",
							"params": {"energy_cost": 30}
						}, {
							"effect": "distress_ignore",
							"label": "Ignore Signal"
						}]
					}
				})
		"scavenge_site":
			# Strategic Dilemma: Scavenge Risk — explore or leave.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "SCAVENGE SITE",
					"effect": "choice",
					"amount": 0,
					"desc": "Wreckage of a military transport lies ahead. It might hold usable parts — or drones guarding the salvage.",
					"params": {
						"choices": [{
							"effect": "scavenge_explore",
							"label": "Explore Wreckage"
						}, {
							"effect": "scavenge_leave",
							"label": "Leave It Alone"
						}]						}
				})
		"convoy_ambush":
			# Convoy Escort: ambush event — defense combat.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			elif GlobalData.board.convoy_destroyed:
				EventBus.event_triggered.emit({
					"name": "CONVOY AMBUSH — CONVOY LOST",
					"effect": "none",
					"amount": 0,
					"desc": "The convoy has already been destroyed. There is nothing left to defend.",
				})
			else:
				# Convoy ambush: announce and enter defense combat.
				GlobalData.board.convoy_defense_waves = 2
				GlobalData.board.convoy_defense_current_wave = 0
				GlobalData.board.convoy_defense_active = true
				EventBus.event_triggered.emit({
					"name": "⚠ CONVOY AMBUSH",
					"effect": "force_combat",
					"amount": 0,
					"desc": "Hostiles are attacking the supply truck! Defend the convoy!",
					"params": {"combat_type": "grunt"},
				})
		"convoy_breakdown":
			# Convoy Escort: vehicle breakdown — wave defense.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			elif GlobalData.board.convoy_destroyed:
				EventBus.event_triggered.emit({
					"name": "BREAKDOWN — CONVOY LOST",
					"effect": "none",
					"amount": 0,
					"desc": "The convoy is already destroyed. No vehicle to break down.",
				})
			else:
				# Vehicle breakdown: announce and enter defense combat.
				GlobalData.board.convoy_defense_waves = 3
				GlobalData.board.convoy_defense_current_wave = 0
				GlobalData.board.convoy_defense_active = true
				EventBus.event_triggered.emit({
					"name": "🔧 VEHICLE BREAKDOWN",
					"effect": "force_combat",
					"amount": 0,
					"desc": "The supply truck has broken down! Defend it from incoming hostiles!",
					"params": {"combat_type": "grunt"},
				})
		"unknown_signal":
			# Mystery Transmission: investigate or ignore.
			if GlobalData.narrative.mech_less:
				_trigger_recovery_event()
			else:
				EventBus.event_triggered.emit({
					"name": "❓ UNKNOWN TRANSMISSION",
					"effect": "choice",
					"amount": 0,
					"desc": "Sensors pick up an encrypted emergency beacon nearby. It could be an abandoned military cache — or a hostile lure.",
					"params": {
						"choices": [{
							"effect": "investigate_signal",
							"label": "Investigate Signal"
						}, {
							"effect": "ignore_signal",
							"label": "Ignore & Move On"
						}]
					}
				})
		_:
			pass


# Dynamic Travel Risk: moving across rough terrain causes mechanical wear and tear on the convoy.
func _roll_travel_breakdown(terrain: String) -> bool:
	if GlobalData.board.convoy_destroyed or GlobalData.narrative.mech_less:
		return false
	if GlobalData.narrative.ceasefire_turns > 0:
		return false

	var base_chance := 0.01
	match terrain:
		"road":
			base_chance = 0.0 # Road is completely safe
		"plain":
			base_chance = 0.01
		"desert", "canyon", "forest":
			base_chance = 0.04
		"mountain", "swamp", "ruins":
			base_chance = 0.07
		_:
			base_chance = 0.02

	# Convoy health penalty modifier:
	if GlobalData.board.convoy_hp < GlobalData.board.convoy_hp_max * 0.25:
		base_chance += 0.08
	elif GlobalData.board.convoy_hp < GlobalData.board.convoy_hp_max * 0.5:
		base_chance += 0.04

	if randf() < base_chance:
		GlobalData.board.convoy_defense_waves = 3
		GlobalData.board.convoy_defense_current_wave = 0
		GlobalData.board.convoy_defense_active = true
		GlobalData.narrative.blocked_intermission = true
		EventBus.event_triggered.emit({
			"name": "🔧 VEHICLE BREAKDOWN",
			"effect": "force_combat",
			"amount": 0,
			"desc": "The supply truck's drivetrain cracked while traversing harsh %s terrain! Hostiles are closing in — defend the convoy!" % terrain.capitalize(),
			"params": {"combat_type": "grunt"},
		})
		return true
	return false


# A "bait" tile reads as an abandoned supply cache but is a decoy: stepping on
# it springs a hostile pincer ambush (same no-menu aftermath as a patrol fight).
func _trigger_bait_trap() -> void:
	if current_pos in GlobalData.board.consumed_bait:
		return
	GlobalData.board.consumed_bait.append(current_pos)
	if GlobalData.narrative.mech_less:
		_trigger_recovery_event()
		return
	if GlobalData.narrative.ceasefire_turns > 0:
		GlobalData.narrative.ceasefire_turns -= 1
		_trigger_ceasefire_skip()
		return
	GlobalData.board.ambush_pincer = true
	GlobalData.narrative.blocked_intermission = true
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
	if GlobalData.narrative.mech_less:
		return false
	if GlobalData.narrative.ceasefire_turns > 0:
		return false
	var ttype := str(tile.get_meta("tile_type", "empty"))
	if ttype in ["start", "exit", "safehouse", "city", "enemy_base", "bait", "research_lab"]:
		return false
	var chance := 0.14 + float(GlobalData.board.patrol_alert) * 0.04 \
			+ minf(GlobalData.board.wanted_level, 5) * 0.03
	return randf() < chance


# Routes a board-initiated combat through the DEPLOY SQUAD screen when the
# convoy has parked mechs with seated pilots to choose from; solo convoys and
# surprise ambushes skip straight into the battle.
func _request_combat(combat_type: String) -> void:
	# Tell the arena generator what terrain this battle happens on: a forest
	# board fought on a ROAD tile gets the road-through-forest arena.
	var tile = nodes_dict.get(current_pos)
	GlobalData.board.combat_tile_terrain = str(tile.get_meta("terrain", "plain")) if tile != null else "plain"
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
		"desc": "The front is quiet. %d day(s) of ceasefire remain." % GlobalData.narrative.ceasefire_turns,
	}
	EventBus.event_triggered.emit(event)


func _trigger_data_node_event() -> void:
	GlobalData.currency.gain_data_cores(2)
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
	if GlobalData.board.board_mp >= cost:
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
	return maxi(2, int(ceil(float(GlobalData.board.board_mp_max) * 0.5)))


# The player chose to demolish a dead end's rubble (see refresh_after_event).
# The tile becomes ordinary ground, blocked rock neighbors open up so a real
# path exists past it, and the work consumes the rest of the day.
func _apply_pending_tile_clear() -> void:
	if GlobalData.board.pending_tile_clear == Vector2i(-1, -1):
		return
	var pos: Vector2i = GlobalData.board.pending_tile_clear
	GlobalData.board.pending_tile_clear = Vector2i(-1, -1)
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
	if GlobalData.narrative.mech_less:
		var event = {
			"name": "The Wanderer",
			"effect": "wanderer_join",
			"amount": 0,
			"desc": "On foot, the extraction zone is a death sentence. A lone wanderer pulls up beside your convoy and hands you the keys to a spare chassis.",
			"params": {"recovery": true},
		}
		EventBus.event_triggered.emit(event)
		ThemeSystem.apply_event_effect(event)
		GameManager.enter_combat("boss")
		return
	print("Entering Extraction Zone / Final Boss Battle!")
	GameManager.enter_combat("boss")


func _trigger_recovery_event() -> void:
	var event := ThemeSystem.get_weighted_recovery_event()
	if event.is_empty():
		_trigger_default_event()
		return
	EventBus.event_triggered.emit(event)
	ThemeSystem.apply_event_effect(event)


func _trigger_stalker_surprise_ambush() -> void:
	var active_stalker = GlobalData.narrative.stalking_aces[0]
	GlobalData.narrative.stalking_chance = 0.0
	var safehouse_ui = get_node_or_null("SafehouseUI")
	if safehouse_ui:
		safehouse_ui.status_label.text = "SIREN WARNING! Stalking Ace: " + active_stalker + " Ambushed!"
	GameManager.enter_combat("ace")


func _trigger_random_event() -> void:
	var pool := ThemeSystem.get_theme_event_pool()
	if pool.is_empty():
		_trigger_default_event()
		return
	if GlobalData.narrative.mech_less:
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
	if ThemeSystem.apply_event_effect(chosen):
		GameManager.enter_combat(str(chosen.get("params", {}).get("combat_type", "grunt")))


func _trigger_default_event() -> void:
	var event = {
		"name": "Abandoned Cache",
		"effect": "credits",
		"amount": 50,
		"desc": "Found abandoned cache! +50 credits",
	}
	EventBus.event_triggered.emit(event)
	ThemeSystem.apply_event_effect(event)


func _build_tech_copy_event() -> Dictionary:
	var tier := GlobalData.narrative.enemy_tech_tier
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
	GlobalData.narrative.enemy_base_tile_pos = target_key
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
	match GlobalData.narrative.enemy_copy_outcome:
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
	if not GlobalData.narrative.enemy_base_active:
		return
	var pos := GlobalData.narrative.enemy_base_tile_pos
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
	if not GlobalData.narrative.enemy_base_active:
		return
	var pos := GlobalData.narrative.enemy_base_tile_pos
	if pos == Vector2i(-1, -1) or not nodes_dict.has(pos):
		return
	var ratio := 0.0
	if GlobalData.narrative.enemy_base_required > 0.0:
		ratio = GlobalData.narrative.enemy_base_progress / GlobalData.narrative.enemy_base_required
	var kind := "rooted" if ratio >= 0.5 else "camp"
	var tile = nodes_dict[pos]
	if tile.has_method("set_enemy_base_model"):
		tile.set_enemy_base_model(kind)


# ---------------------------------------------------------------------------
# WRECKAGE TILE RESTORE — a wreckage tile persists across board reloads so
# the pilot can return for fuel after a mech destruction.
# ---------------------------------------------------------------------------

func _restore_wreckage_tile() -> void:
	var pos := GlobalData.fuel.wreckage_tile_pos
	if pos == Vector2i(-1, -1) or not nodes_dict.has(pos):
		return
	if GlobalData.fuel.wreckage_fuel_remaining <= 0.0:
		GlobalData.fuel.wreckage_tile_pos = Vector2i(-1, -1)
		return
	var tile = nodes_dict[pos]
	tile.set_meta("tile_type", "wreckage")
	tile.reveal()
	if tile.has_method("_update_visual"):
		tile._update_visual()


# ---------------------------------------------------------------------------
# FUEL DEPOT SEIZURE (GDD §2.4)
# A fuel_depot tile triggers a combat encounter where the player must avoid
# destroying the fuel tanks with heavy weapons. Victory grants fuel bonus.
# ---------------------------------------------------------------------------

func _trigger_fuel_depot_seizure() -> void:
	if GlobalData.narrative.ceasefire_turns > 0:
		GlobalData.narrative.ceasefire_turns -= 1
		_trigger_ceasefire_skip()
		return
	GlobalData.fuel.fuel_depot_seized_today = true
	GlobalData.narrative.blocked_intermission = true
	# Choice popup: precise vs heavy approach affects fuel reward.
	var choices: Array = [
		{
			"label": "Precise Assault",
			"desc": "Use light weapons to surgicaly eliminate guards. Fuel tanks stay intact — full fuel reward (%.0f)." % GlobalData.FUEL_DEPOT_PRECISE_BONUS,
			"effect": "depot_precise",
			"amount": 0,
		},
		{
			"label": "Heavy Assault",
			"desc": "Bring the big guns. Overwhelming firepower but some fuel tanks get destroyed — reduced reward (%.0f)." % GlobalData.FUEL_DEPOT_HEAVY_BONUS,
			"effect": "depot_heavy",
			"amount": 0,
		},
	]
	EventBus.event_triggered.emit({
		"name": "FUEL DEPOT — SEIZURE",
		"effect": "choice",
		"amount": 0,
		"desc": "An enemy fuel depot! Choose your approach — the method determines how much fuel you recover.",
		"params": {"choices": choices},
	})


# ---------------------------------------------------------------------------
# CONVOY SUPPLY TRANSFER (GDD §2.4)
# Transfer fuel from the convoy truck into the mech. Costs 1 full day turn
# and raises enemy alert level (the noise attracts patrols).
# ---------------------------------------------------------------------------

func _trigger_convoy_supply_transfer() -> void:
	var available: float = minf(
		GlobalData.fuel.convoy_fuel_reserve,
		GlobalData.CONVOY_TRANSFER_AMOUNT
	)
	if available <= 0.0:
		EventBus.event_triggered.emit({
			"name": "CONVOY SUPPLY — EMPTY",
			"effect": "none",
			"amount": 0,
			"desc": "The convoy truck has no fuel to spare. It will resupply overnight.",
		})
		return
	var deficit: float = GlobalData.fuel.mech_max_energy - GlobalData.fuel.mech_energy
	if deficit <= 0.0:
		EventBus.event_triggered.emit({
			"name": "CONVOY SUPPLY — FULL",
			"effect": "none",
			"amount": 0,
			"desc": "The mech's fuel tanks are already full.",
		})
		return
	var transferred: float = minf(available, deficit)
	GlobalData.fuel.convoy_fuel_reserve -= transferred
	GlobalData.fuel.mech_energy = minf(GlobalData.fuel.mech_energy + transferred, GlobalData.fuel.mech_max_energy)
	# Time trade-off: costs 1 full day turn + raises alert level.
	HeatWantedSystem.modify_heat(1)
	EventBus.event_triggered.emit({
		"name": "CONVOY SUPPLY TRANSFER",
		"effect": "none",
		"amount": 0,
		"desc": "Transferred %.0f fuel from the convoy truck. A full day has passed and the noise raised alert." % transferred,
	})
	# End the day as the time trade-off.
	_end_day()


# ---------------------------------------------------------------------------
# PILOT SIPHON PROTOCOL (GDD §2.4 / §2.2)
# When the mech is destroyed, a wreckage tile is placed on the board where
# it fell. The pilot (on foot) can walk to the wreckage to siphon dirty fuel
# from the enemy wreckage and bring it back for a re-ignition reboot.
# ---------------------------------------------------------------------------

# Called by the health system when the player's mech is destroyed. Places a
# wreckage tile at the combat position so the pilot can return for fuel.
func place_wreckage_tile(pos: Vector2i) -> void:
	GlobalData.fuel.wreckage_tile_pos = pos
	GlobalData.fuel.wreckage_fuel_remaining = 80.0
	if not nodes_dict.has(pos):
		return
	var tile = nodes_dict[pos]
	tile.set_meta("tile_type", "wreckage")
	tile.reveal()
	if tile.has_method("_update_visual"):
		tile._update_visual()


# Pilot reaches the wreckage and siphons dirty fuel from the wreck.
func _trigger_wreckage_siphon() -> void:
	if not GlobalData.narrative.mech_less:
		EventBus.event_triggered.emit({
			"name": "WRECKAGE",
			"effect": "none",
			"amount": 0,
			"desc": "Your destroyed mech's wreckage. The fuel tanks are ruptured but some dirty fuel remains.",
		})
		return
	if GlobalData.fuel.wreckage_fuel_remaining <= 0.0:
		EventBus.event_triggered.emit({
			"name": "WRECKAGE — DEPLETED",
			"effect": "none",
			"amount": 0,
			"desc": "The wreckage has been stripped clean. No more fuel to siphon.",
		})
		return
	var amount := minf(GlobalData.WRECKAGE_SIPHON_AMOUNT, GlobalData.fuel.wreckage_fuel_remaining)
	GlobalData.fuel.wreckage_fuel_remaining -= amount
	GlobalData.fuel.siphoned_fuel += amount
	# Engine dirt: siphoning dirty fuel contaminates the fuel system.
	GlobalData.fuel.engine_dirt = minf(GlobalData.fuel.engine_dirt + GlobalData.ENGINE_DIRT_PER_SIPHON, 1.0)
	var choices: Array = []
	if GlobalData.fuel.siphoned_fuel >= GlobalData.REIGNITION_FUEL_COST:
		choices.append({
			"label": "Re-ignition (%.0f fuel)" % GlobalData.REIGNITION_FUEL_COST,
			"desc": "Burn the siphoned fuel to reboot the mech. Extra dirt from impure fuel.",
			"effect": "reignition",
			"amount": int(GlobalData.REIGNITION_FUEL_COST),
		})
	if GlobalData.fuel.wreckage_fuel_remaining > 0.0:
		choices.append({
			"label": "Siphon more (%.0f left)" % GlobalData.fuel.wreckage_fuel_remaining,
			"desc": "Keep extracting fuel from the wreck. Each visit adds more engine dirt.",
			"effect": "siphon_more",
			"amount": 0,
		})
	choices.append({
		"label": "Leave",
		"desc": "Leave the wreckage and continue on foot.",
		"effect": "none",
		"amount": 0,
	})
	EventBus.event_triggered.emit({
		"name": "PILOT SIPHON PROTOCOL",
		"effect": "choice",
		"amount": 0,
		"desc": "Dirty fuel siphoned: +%.0f (total: %.0f / %.0f needed). Engine dirt: %d%%." % [
			amount, GlobalData.fuel.siphoned_fuel, GlobalData.REIGNITION_FUEL_COST,
			int(GlobalData.fuel.engine_dirt * 100)
		],
		"params": {"choices": choices},
	})


# Re-ignition: reboot the mech using siphoned fuel. Costs extra engine dirt.
func _do_reignition() -> void:
	if GlobalData.fuel.siphoned_fuel < GlobalData.REIGNITION_FUEL_COST:
		return
	GlobalData.fuel.siphoned_fuel -= GlobalData.REIGNITION_FUEL_COST
	GlobalData.fuel.engine_dirt = minf(GlobalData.fuel.engine_dirt + GlobalData.REIGNITION_ENGINE_DIRT_COST, 1.0)
	# Restore the mech: grant a recovery chassis via the hangar system.
	HangarManager.grant_recovery_mech()
	GlobalData.fuel.mech_energy = minf(GlobalData.fuel.mech_max_energy * 0.4, GlobalData.fuel.mech_max_energy)
	# Clear wreckage if depleted.
	if GlobalData.fuel.wreckage_fuel_remaining <= 0.0:
		_clear_wreckage_tile()
	EventBus.event_triggered.emit({
		"name": "RE-IGNITION COMPLETE",
		"effect": "none",
		"amount": 0,
		"desc": "The engine coughs to life on dirty fuel. The mech is operational again at 40%% capacity. Extra engine dirt: %d%%." % int(GlobalData.fuel.engine_dirt * 100),
	})


# Clear the wreckage tile from the board after all fuel is siphoned.
func _clear_wreckage_tile() -> void:
	var pos := GlobalData.fuel.wreckage_tile_pos
	GlobalData.fuel.wreckage_tile_pos = Vector2i(-1, -1)
	if pos == Vector2i(-1, -1) or not nodes_dict.has(pos):
		return
	var tile = nodes_dict[pos]
	tile.set_meta("tile_type", "empty")
	if tile.has_method("_update_visual"):
		tile._update_visual()
