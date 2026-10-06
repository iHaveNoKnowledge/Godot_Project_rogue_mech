class_name CampaignNodeInspectionPanel
extends Control

## ---------------------------------------------------------------------------
## CAMPAIGN NODE INSPECTION PANEL — Phase 5V (read-only node inspection).
##
## Audit evidence (do not re-decide lightly):
##   - The 5U movement panel owns a movement flow (force -> destination ->
##     Move). Inspection has a separate read lifecycle (select any node ->
##     aggregate -> display, reused for current/destination/post-move
##     nodes), so folding it into the movement panel would push that panel
##     toward a god-object. Hence this dedicated panel (Option B); no
##     generic CampaignUI/Interaction/Orchestrator manager was created.
##   - There is no canonical "battles at node" read API, so v1 shows NO
##     battle section (spec default) rather than inventing an abstraction.
##   - Destinations/neighbors come only from CampaignNodeRegistry routes;
##     BoardTile connections are never consulted.
##
## Authority split: this panel owns TRANSIENT UI state only
## (selected_node_id, last inspection, widgets). All data is re-read from
## CampaignNodeRegistry (topology), CampaignForce (forces verbatim),
## CampaignTerritory (first covering territory verbatim), and CampaignBase
## (base at node verbatim). No setter/register/add/remove/move/begin/
## resolve/cancel is ever called from the inspection path: READ ONLY.
## Force records are shown verbatim — unit_count/strength stay abstract
## campaign values, never rosters/HP/power. Presence is never worded as
## ownership, control, or capture. No signals, no persistence.
## ---------------------------------------------------------------------------

var _selected_node_id := ""
var _last_inspection: Dictionary = {}
var _built := false

var _node_option: OptionButton
var _info_label: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.name = "InspectionPanel"
	add_child(root)
	_node_option = OptionButton.new()
	_node_option.name = "NodeOption"
	root.add_child(_node_option)
	_node_option.item_selected.connect(_on_node_item_selected)
	_info_label = Label.new()
	_info_label.name = "NodeInfo"
	root.add_child(_info_label)
	_built = true
	refresh()


## All registered node ids, sorted. Rebuilds the node list widget.
func refresh_nodes() -> Array:
	var ids: Array = []
	for n in CampaignNodeRegistry.get_nodes():
		ids.append(str(n.get("id", "")))
	ids.sort()
	if _built:
		_node_option.clear()
		for nid in ids:
			_node_option.add_item(str(nid))
		_sync_node_widget()
	return ids


## Inspects a node from canonical authorities. Unknown ids fail safely
## ({ok:false, reason:"unknown_node"}) with selection unchanged.
func inspect_node(node_id: String) -> Dictionary:
	if node_id == "" or not CampaignNodeRegistry.has_node(node_id):
		var failure := {
			"ok": false, "reason": "unknown_node",
			"node": {}, "routes": [], "forces": [],
			"territory": {}, "base": {},
		}
		if _built:
			_info_label.text = "Unknown node"
		return failure
	_selected_node_id = node_id
	_last_inspection = _build_inspection(node_id)
	refresh()
	return _last_inspection.duplicate(true)


func get_selected_node_id() -> String:
	return _selected_node_id


func get_last_inspection() -> Dictionary:
	return _last_inspection.duplicate(true)


## Clears transient selection (canonical registries untouched).
func clear() -> void:
	_selected_node_id = ""
	_last_inspection = {}
	refresh()


## Re-reads canonical state into selection and widgets.
func refresh() -> void:
	refresh_nodes()
	if _built:
		if _selected_node_id != "" and CampaignNodeRegistry.has_node(_selected_node_id):
			_last_inspection = _build_inspection(_selected_node_id)
		_info_label.text = _summary_text()


## Human-readable summary lines of the last inspection ("" when none).
func get_summary_lines() -> Array:
	var lines: Array = []
	if _last_inspection.is_empty() or not bool(_last_inspection.get("ok", false)):
		return lines
	var node: Dictionary = _last_inspection.get("node", {})
	lines.append("Node: %s" % str(node.get("id", "")))
	lines.append("Type: %s (sector %s)" % [
		str(node.get("node_type", "")), str(node.get("sector", ""))])
	var routes: Array = _last_inspection.get("routes", [])
	lines.append("Routes: %s" % (", ".join(routes) if not routes.is_empty() else "none"))
	var forces: Array = _last_inspection.get("forces", [])
	if forces.is_empty():
		lines.append("Forces: none")
	else:
		for f in forces:
			lines.append("Force %s [%s] faction=%s state=%s units=%s strength=%s" % [
				str(f.get("id", "")), str(f.get("force_type", "")),
				str(f.get("faction", "")), CampaignForce.state_to_name(int(f.get("state", 0))),
				str(f.get("unit_count", "")), str(f.get("strength", ""))])
	var territory: Dictionary = _last_inspection.get("territory", {})
	if territory.is_empty():
		lines.append("Territory: none")
	else:
		lines.append("Territory: %s control=%s controller=%s contesting=%s" % [
			str(territory.get("id", "")),
			CampaignTerritory.control_to_name(int(territory.get("control", 0))),
			str(territory.get("controller", "")), str(territory.get("contesting", ""))])
	var base: Dictionary = _last_inspection.get("base", {})
	if base.is_empty():
		lines.append("Base: none")
	else:
		lines.append("Base: %s type=%s state=%s controller=%s" % [
			str(base.get("id", "")), str(base.get("base_type", "")),
			CampaignBase.state_to_name(int(base.get("state", 0))),
			str(base.get("controller", ""))])
	return lines


func _build_inspection(node_id: String) -> Dictionary:
	var node := CampaignNodeRegistry.get_node(node_id)
	var routes: Array = []
	for r in CampaignNodeRegistry.get_routes_for(node_id):
		for key in ["a", "b"]:
			var other := str((r as Dictionary).get(key, ""))
			if other != "" and other != node_id and not routes.has(other):
				routes.append(other)
	routes.sort()
	var forces: Array = []
	for fid in CampaignForce.get_forces_at_node(node_id):
		forces.append(CampaignForce.get_force(str(fid)))
	var territory := {}
	var covering := CampaignTerritory.get_territories_for_node(node_id)
	if not covering.is_empty():
		territory = CampaignTerritory.get_territory(str(covering[0].get("id", "")))
	var base := CampaignBase.get_base_at_node(node_id)
	return {
		"ok": true, "reason": "inspected",
		"node": node, "routes": routes, "forces": forces,
		"territory": territory, "base": base,
	}


func _summary_text() -> String:
	var lines := get_summary_lines()
	if lines.is_empty():
		if _selected_node_id == "":
			return "No node selected"
		return "Unknown node"
	return "\n".join(lines)


func _sync_node_widget() -> void:
	for i in _node_option.item_count:
		if _node_option.get_item_text(i) == _selected_node_id:
			_node_option.select(i)
			return
	_node_option.select(-1)


func _on_node_item_selected(index: int) -> void:
	inspect_node(_node_option.get_item_text(index))
