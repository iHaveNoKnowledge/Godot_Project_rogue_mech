extends CanvasLayer

@onready var bars: Dictionary = {
	"head": {"armor_bar": %HeadArmorBar, "frame_bar": %HeadFrameBar, "label": %HeadLabel,
		"armor_value": %HeadArmorValue, "frame_value": %HeadFrameValue},
	"body": {"armor_bar": %BodyArmorBar, "frame_bar": %BodyFrameBar, "label": %BodyLabel,
		"armor_value": %BodyArmorValue, "frame_value": %BodyFrameValue},
}
@onready var armor_total: Label = %ArmorTotal
@onready var frame_total: Label = %FrameTotal

var health_system: Node = null

const ARMOR_COLOR := Color("#c4c3c0")
const FRAME_COLOR := Color("#87c790")
const TRACK_COLOR := Color(0.08, 0.08, 0.1, 0.9)

var _armor_texture: GradientTexture2D = null
var _frame_texture: GradientTexture2D = null
var _armor_track_texture: GradientTexture2D = null
var _frame_track_texture: GradientTexture2D = null

const ARMOR_BAR_HEIGHT := 8
const FRAME_BAR_HEIGHT := 5


func _ready() -> void:
	_apply_bar_style()
	await get_tree().process_frame
	var mecha = get_tree().current_scene.get_node_or_null("Mecha")
	if mecha:
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			_update_all_bars()


func _make_gradient_texture(base: Color, bar_height: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, base.lightened(0.18))
	gradient.set_color(1, base.darkened(0.28))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 512
	tex.height = bar_height
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	return tex


func _make_track_texture(bar_height: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, TRACK_COLOR)
	gradient.set_color(1, TRACK_COLOR)
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 4
	tex.height = bar_height
	return tex


func _apply_bar_style() -> void:
	_armor_texture = _make_gradient_texture(ARMOR_COLOR, ARMOR_BAR_HEIGHT)
	_frame_texture = _make_gradient_texture(FRAME_COLOR, FRAME_BAR_HEIGHT)
	_armor_track_texture = _make_track_texture(ARMOR_BAR_HEIGHT)
	_frame_track_texture = _make_track_texture(FRAME_BAR_HEIGHT)
	for slot in bars:
		var entry = bars[slot]
		_setup_bar(entry["armor_bar"], _armor_texture, _armor_track_texture)
		_setup_bar(entry["frame_bar"], _frame_texture, _frame_track_texture)


func _setup_bar(bar: TextureProgressBar, fill: GradientTexture2D, track: GradientTexture2D) -> void:
	bar.texture_under = track
	bar.texture_progress = fill
	bar.fill_mode = TextureProgressBar.FILL_LEFT_TO_RIGHT


func _on_health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float) -> void:
	if not bars.has(slot_name):
		return
	var entry = bars[slot_name]
	var percent = current_hp / max_hp * 100.0

	if layer == "armor":
		entry["armor_bar"].value = percent
	else:
		entry["frame_bar"].value = percent

	_update_label(slot_name)
	_update_totals()


func _update_label(slot_name: String) -> void:
	if not bars.has(slot_name) or health_system == null:
		return
	var part = health_system.parts[slot_name]
	var entry = bars[slot_name]
	entry["armor_value"].text = "%d" % int(part["armor_hp"])
	entry["frame_value"].text = "%d" % int(part["frame_hp"])


func _update_all_bars() -> void:
	if health_system == null:
		return
	for slot in health_system.parts:
		if not bars.has(slot):
			continue
		var part = health_system.parts[slot]
		_on_health_changed(slot, "armor", part["armor_hp"], part["max_armor"])
		_on_health_changed(slot, "frame", part["frame_hp"], part["max_frame"])


func _update_totals() -> void:
	if health_system == null:
		return
	armor_total.text = "ARMOR: %d%%" % int(health_system.get_armor_percent() * 100.0)
	frame_total.text = "FRAME: %d%%" % int(health_system.get_frame_percent() * 100.0)