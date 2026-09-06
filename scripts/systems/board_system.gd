class_name BoardSystem
extends RefCounted

# -----------------------------------------------------------------------------
# BOARD DAY / OBJECTIVE STATE
# Thin static helpers the board manager + patrol + intermission use to advance
# per-day systems and track the sector's map objective. State lives in GlobalData
# so it survives saves; objective definitions live in BoardConfig.
# -----------------------------------------------------------------------------


static func get_objective() -> Dictionary:
	return BoardConfig.get_objective(GlobalData.board.board_theme_id)


static func is_objective_complete() -> bool:
	if not GlobalData.board.active_contract.is_empty():
		return GlobalData.board.primary_objective_done
	var obj := get_objective()
	return GlobalData.board.board_objective_progress >= int(obj.get("required", 1))


static func add_progress(amount: int) -> int:
	GlobalData.board.board_objective_progress = clampi(
		GlobalData.board.board_objective_progress + amount,
		0,
		int(get_objective()["required"])
	)
	return GlobalData.board.board_objective_progress


static func complete() -> void:
	GlobalData.board.board_objective_progress = int(get_objective()["required"])


static func progress_text() -> String:
	var obj := get_objective()
	return "%s: %d / %d" % [
		str(obj.get("name", "Objective")),
		GlobalData.board.board_objective_progress,
		GlobalData.board.board_objective_required
	]


static func objective_desc() -> String:
	var obj := get_objective()
	var required := int(obj.get("required", 1))
	return str(obj.get("desc", "")).format({"0": required})


# How many MP it costs to enter this cell (or -1 if impassable).
static func cell_cost(tile: Node) -> int:
	if tile == null:
		return 1
	return BoardConfig.move_cost(str(tile.get_meta("terrain", "plain")))