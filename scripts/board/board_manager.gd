extends Node3D

@onready var tile_container: Node3D = $TileContainer
@onready var player_token: MeshInstance3D = $PlayerToken

var current_pos: Vector2i = Vector2i.ZERO
var nodes_dict: Dictionary = {}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var generator = get_node_or_null("BoardGenerator")
	if generator:
		var data = generator.generate_board()
		nodes_dict = data["nodes"]
		
		# Add tiles to container
		for key in nodes_dict:
			tile_container.add_child(nodes_dict[key])

		# Generate 3D visual path bridges between connected nodes
		for key in nodes_dict:
			var tile = nodes_dict[key]
			if tile.has_method("create_path_visuals"):
				tile.create_path_visuals(nodes_dict)

	current_pos = GlobalData.current_tile
	if not nodes_dict.has(current_pos):
		current_pos = Vector2i(0, 0)
		GlobalData.current_tile = current_pos

	_update_token_position()
	_highlight_adjacent()

	# If the enemy upgraded after the last combat, surface the popup now that
	# we're back on the board.
	if GlobalData.consume_pending_escalation_event():
		EventBus.event_triggered.emit(_build_tech_copy_event())


func move_to_tile(target: Vector2i) -> bool:
	if not _is_connected_path(current_pos, target):
		print("Invalid path! Must follow connected branching node paths.")
		return false

	current_pos = target
	GlobalData.current_tile = target
	_update_token_position()
	_clear_highlights()
	_highlight_adjacent()

	# Moving again means the ambush is behind us — re-enable the intermission.
	GlobalData.blocked_intermission = false

	var tile_data = nodes_dict[target]
	var tile_type = tile_data.get_meta("tile_type", "empty")

	# Turn Mobilization & Stalking Ace Interception
	process_turn_mobilization()
	accumulate_stalker_chance()

	# Enemy espionage: each board move the enemy may send a spy to steal mech
	# data. Security determines whether the spy is caught.
	var spy_event := GlobalData.roll_spy_event()
	if not spy_event.is_empty():
		EventBus.event_triggered.emit(spy_event)

	EventBus.tile_entered.emit(target, tile_data)
	_process_tile_effect(tile_type)

	if tile_type not in ["combat", "exit"]:
		var intermission = get_node_or_null("IntermissionUI")
		if intermission:
			intermission.visible = true
			intermission.status_label.text = intermission._get_status_text()
	return true


func _is_connected_path(from_key: Vector2i, to_key: Vector2i) -> bool:
	if not nodes_dict.has(from_key):
		return false
	var from_tile = nodes_dict[from_key]
	var connects = from_tile.get_meta("connections", [])
	return to_key in connects


func _highlight_adjacent() -> void:
	if not nodes_dict.has(current_pos):
		return
	var current_tile = nodes_dict[current_pos]
	var connects = current_tile.get_meta("connections", [])
	for target_key in connects:
		if nodes_dict.has(target_key):
			nodes_dict[target_key].highlight(true)


func _clear_highlights() -> void:
	for key in nodes_dict:
		nodes_dict[key].highlight(false)


func _update_token_position() -> void:
	if nodes_dict.has(current_pos):
		var tile = nodes_dict[current_pos]
		player_token.global_position = tile.global_position + Vector3(0, 0.5, 0)


# Turn mobilization refilling (Low Heat Grace Period: suppressed when Heat < 3)
func process_turn_mobilization() -> void:
	if GlobalData.heat < 3:
		# Low Heat Grace Period: Mobilization suppressed to keep early-game accessible
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
			if GlobalData.ceasefire_turns > 0:
				GlobalData.ceasefire_turns -= 1
				_trigger_ceasefire_skip()
			elif not GlobalData.stalking_aces.is_empty() and randf() < GlobalData.stalking_chance:
				_trigger_stalker_surprise_ambush()
			else:
				GameManager.enter_combat("grunt")
		"event":
			_trigger_random_event()
		"safehouse":
			HeatWantedSystem.modify_heat(-4)
			var safehouse = get_node_or_null("../SafehouseUI")
			if safehouse:
				safehouse.visible = true
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
		"desc": "The front is quiet. %d tile(s) of ceasefire remain." % GlobalData.ceasefire_turns,
	}
	EventBus.event_triggered.emit(event)


func _trigger_data_node_event() -> void:
	GlobalData.data_cores += 2
	var event = {
		"name": "Data Terminal Extraction",
		"effect": "data_cores",
		"amount": 2,
		"desc": "Extracted blueprint data core! +2 Data Cores."
	}
	EventBus.event_triggered.emit(event)


func _trigger_dead_end_event() -> void:
	var event = {
		"name": "Hidden Dead End",
		"effect": "dead_end",
		"amount": 0,
		"desc": "Approached a hidden wall/obstacle! Reroute path required."
	}
	EventBus.event_triggered.emit(event)


func _trigger_exit_event() -> void:
	print("Entering Extraction Zone / Final Boss Battle!")
	GameManager.enter_combat("boss")


func _trigger_stalker_surprise_ambush() -> void:
	var active_stalker = GlobalData.stalking_aces[0]
	GlobalData.stalking_chance = 0.0

	var safehouse_ui = get_node_or_null("../SafehouseUI")
	if safehouse_ui:
		safehouse_ui.status_label.text = "SIREN WARNING! Stalking Ace: " + active_stalker + " Ambushed!"

	GameManager.enter_combat("ace")


func _trigger_random_event() -> void:
	var pool := GlobalData.get_theme_event_pool()
	if pool.is_empty():
		_trigger_default_event()
		return

	# Weighted pick: theme-specific events get a bonus so the common pool does
	# not drown them out entirely.
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
		# force_combat — the intermission is blocked; jump straight into battle.
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


func get_tile_type(pos: Vector2i) -> String:
	if nodes_dict.has(pos):
		return nodes_dict[pos].get_meta("tile_type", "empty")
	return "empty"
