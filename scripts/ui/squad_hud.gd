extends CanvasLayer
class_name SquadHud

## Combat squad HUD: a fixed panel (bottom-left) listing every fielded ally's
## pilot name and live health bar while they fight alongside the player.
##
## Ally mechs emit `ally_squad_updated` whenever their HP changes, so bars stay
## fresh without polling; a light per-frame poll reconciles adds/removals
## (allies spawn in the SpawnManager and are freed on destruction).


# Live combined HP ratio computed from the parts table, NOT the cached totals.
# The health system only recalculates total_armor_hp/total_frame_hp when armor
# breaks, so reading those right after a hit reports the pre-damage value.
static func live_health_percent(health_system: Node) -> float:
	if health_system == null or not (health_system.get("parts") is Dictionary):
		return 0.0
	var cur := 0.0
	var max_total := 0.0
	for slot in health_system.parts:
		var part: Dictionary = health_system.parts[slot]
		cur += float(part.get("armor_hp", 0.0)) + float(part.get("frame_hp", 0.0))
		max_total += float(part.get("max_armor", 0.0)) + float(part.get("max_frame", 0.0))
	if max_total <= 0.0:
		return 0.0
	return clampf(cur / max_total, 0.0, 1.0)


var panel: PanelContainer = null
var rows: Dictionary = {}  # template_id -> {"label": Label, "bar": ProgressBar, "ally": Node3D}


func _ready() -> void:
	layer = 4
	_create_ui()
	EventBus.ally_squad_updated.connect(_on_ally_squad_updated)


func _create_ui() -> void:
	var root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 20
	panel.offset_top = -150
	panel.offset_right = 300
	panel.offset_bottom = -20
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.75, 1.0, 0.5)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.name = "AllyRows"
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "SQUAD"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	vbox.add_child(title)


# A fresh update is a rebuild signal: drain the old rows, then re-snapshot the
# ally group (cheap, typically 1-3 units) so adds/removals/destructions all
# reconcile here in one place.
func _process(_delta: float) -> void:
	var allies = get_tree().get_nodes_in_group("ally") if get_tree() else []
	var alive := 0
	for ally in allies:
		if not is_instance_valid(ally):
			continue
		var hs: Node = ally.health_system
		if hs == null or bool(hs.get("is_destroyed")):
			continue
		alive += 1
	if alive != rows.size() or not _all_rows_valid():
		_rebuild(allies)


func _all_rows_valid() -> bool:
	for template_id in rows:
		var ally: Node3D = rows[template_id]["ally"]
		if not is_instance_valid(ally) or not ally.is_in_group("ally"):
			return false
	return true


func _on_ally_squad_updated(data: Dictionary) -> void:
	var template_id := str(data.get("template_id", ""))
	if not rows.has(template_id):
		return
	var bar: ProgressBar = rows[template_id]["bar"]
	bar.value = clampf(float(data.get("health", 0.0)), 0.0, 1.0) * 100.0
	if bool(data.get("destroyed")):
		bar.modulate = Color(0.55, 0.55, 0.55, 0.7)
		rows[template_id]["label"].modulate = Color(0.6, 0.6, 0.6, 0.8)


func _rebuild(allies: Array) -> void:
	rows.clear()
	var vbox = panel.get_node_or_null("AllyRows")
	if vbox == null:
		return
	for child in vbox.get_children():
		if child is Label and child.text == "SQUAD":
			continue
		vbox.remove_child(child)
		child.queue_free()

	for ally in allies:
		if not is_instance_valid(ally):
			continue
		var hs: Node = ally.health_system
		if hs == null or bool(hs.get("is_destroyed")):
			continue  # destroyed allies drop off the panel entirely
		var template_id := str(ally.template_id) if ally.get("template_id") != null else ""
		var display_name := str(ally.display_name) if ally.get("display_name") != null else "ALLY"
		rows[template_id] = _build_row(vbox, ally, display_name)


func _build_row(vbox: VBoxContainer, ally: Node3D, display_name: String) -> Dictionary:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var label = Label.new()
	label.text = display_name
	label.custom_minimum_size = Vector2(150, 0)
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	row.add_child(label)

	var bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(110, 14)
	bar.max_value = 100.0
	bar.value = live_health_percent(ally.health_system) * 100.0
	bar.show_percentage = false
	row.add_child(bar)

	var hs = ally.health_system
	if bool(hs.get("is_destroyed")):
		label.modulate = Color(0.6, 0.6, 0.6, 0.8)
		bar.modulate = Color(0.55, 0.55, 0.55, 0.7)

	return {"label": label, "bar": bar, "ally": ally}
