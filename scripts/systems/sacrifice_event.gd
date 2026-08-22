extends Node

## Sacrifice Event & Grand Entry System (GDD §5)
##
## When the pilot-mech bond is strong enough (>= 80) and the mech is heavily
## damaged, the Sacrifice Event becomes available. The player can choose to
## push the old mech to its limits in a critical mission. If the mech is
## destroyed during this mission, the Grand Entry triggers — a new, more
## powerful mech arrives from the sky.

signal sacrifice_event_started()
signal sacrifice_event_completed(victory: bool)
signal grand_entry_started(new_mech_name: String)
signal grand_entry_completed()


func _ready() -> void:
	# Discoverable by UIs (Safehouse) via group — the node lives in both the
	# board scene (to START the mission) and the combat scene (to RESOLVE it);
	# a scene swap frees one before the other loads, so only one is ever alive.
	add_to_group("sacrifice_event")
	EventBus.combat_ended.connect(_on_combat_ended)


func _on_combat_ended(victory: bool) -> void:
	# If a sacrifice combat just ended, resolve the outcome.
	if GameManager.combat_node_type == "sacrifice":
		on_sacrifice_ended(victory)
	# If grand entry is pending after the sacrifice, complete it.
	if GlobalData.narrative.grand_entry_pending:
		complete_grand_entry()


## Checks if the sacrifice event should be offered to the player.
## A mech-less pilot has no machine to sacrifice.
func is_sacrifice_available() -> bool:
	return GlobalData.narrative.sacrifice_event_available \
		and not GlobalData.narrative.sacrifice_event_triggered \
		and not GlobalData.narrative.mech_less


## Starts the sacrifice event — the critical mission begins.
func start_sacrifice_event() -> void:
	if not is_sacrifice_available():
		return
	GlobalData.narrative.trigger_sacrifice_event("")  # Will be set when Grand Entry triggers
	sacrifice_event_started.emit()
	GlobalData.board.run_notice = "The Sacrifice Event begins! Push your mech to its limits!"
	# Enter a special boss combat.
	GameManager.combat_node_type = "sacrifice"
	GameManager.enter_combat("boss")


## Called when the sacrifice combat ends.
func on_sacrifice_ended(victory: bool) -> void:
	sacrifice_event_completed.emit(victory)
	if victory:
		# Player won the sacrifice event — the mech survived!
		# Grant a bonus: the mech gets a permanent bond boost.
		GlobalData.narrative.increase_bond(20.0)
		GlobalData.board.run_notice = "Your mech survived the sacrifice! The bond deepens."
	else:
		# Player lost — the mech was destroyed during the sacrifice.
		# Trigger the Grand Entry.
		_trigger_grand_entry()


## Triggers the Grand Entry — a new mech arrives from the sky.
func _trigger_grand_entry() -> void:
	# Pick a replacement mech based on the current tier.
	var new_mech_id := _select_replacement_mech()
	GlobalData.narrative.grand_entry_mech_id = new_mech_id
	GlobalData.narrative.grand_entry_pending = true
	grand_entry_started.emit(_get_mech_name(new_mech_id))
	GlobalData.board.run_notice = "A new mech descends from the sky! The Grand Entry!"
	# The new mech will be granted after the combat ends.


## Completes the Grand Entry — the new mech is now the player's active mech.
func complete_grand_entry() -> void:
	if not GlobalData.narrative.grand_entry_pending:
		return
	var new_mech_id := GlobalData.narrative.grand_entry_mech_id
	# Build and equip the new mech.
	var new_mech = HangarManager.build("Hero Unit", 0)
	if not new_mech.is_empty():
		# Apply a stronger chassis based on tier.
		var chassis_id := "gundam" if GlobalData.board.current_sector >= 2 else "gm"
		new_mech["chassis_id"] = chassis_id
		new_mech["name"] = _get_mech_name(new_mech_id)
		# Set as active mech.
		GlobalData.hangar.active_hangar_mech_id = str(new_mech.get("id", ""))
		GlobalData.narrative.mech_less = false
	GlobalData.narrative.grand_entry_pending = false
	grand_entry_completed.emit()


func _select_replacement_mech() -> String:
	# Return a mech id based on current progression.
	if GlobalData.board.current_sector >= 3:
		return "freedom"
	elif GlobalData.board.current_sector >= 2:
		return "gundam"
	else:
		return "gm_custom"


func _get_mech_name(mech_id: String) -> String:
	match mech_id:
		"freedom":
			return "Freedom Gundam"
		"gundam":
			return "Strike Gundam"
		"gm_custom":
			return "GM Custom"
		_:
			return "New Mech"
