extends CanvasLayer

@onready var armor_bars: Dictionary = {
	"head": %HeadArmorBar,
	"body": %BodyArmorBar,
	"arm_left": %ArmLArmorBar,
	"leg_left": %LegLArmorBar,
	"arm_right": %ArmRArmorBar,
	"leg_right": %LegRArmorBar,
}

@onready var frame_bars: Dictionary = {
	"head": %HeadFrameBar,
	"body": %BodyFrameBar,
	"arm_left": %ArmLFrameBar,
	"leg_left": %LegLFrameBar,
	"arm_right": %ArmRFrameBar,
	"leg_right": %LegRFrameBar,
}

@onready var armor_values: Dictionary = {
	"head": %HeadArmorValue,
	"body": %BodyArmorValue,
	"arm_left": %ArmLArmorValue,
	"leg_left": %LegLArmorValue,
	"arm_right": %ArmRArmorValue,
	"leg_right": %LegRArmorValue,
}

@onready var frame_values: Dictionary = {
	"head": %HeadFrameValue,
	"body": %BodyFrameValue,
	"arm_left": %ArmLFrameValue,
	"leg_left": %LegLFrameValue,
	"arm_right": %ArmRFrameValue,
	"leg_right": %LegRFrameValue,
}

var health_system: Node = null

# Hit feedback: a red full-screen flash + camera shake whenever the player's
# mech takes damage, so getting shot is impossible to miss.
var _hit_flash: ColorRect = null
var _hit_flash_tween: Tween = null


func _ready() -> void:
	_create_hit_flash()
	EventBus.damage_received.connect(_on_player_damaged)
	await get_tree().process_frame
	var mecha = GameManager.get_player_mecha()
	if mecha:
		health_system = mecha.get_node_or_null("HealthSystem")
		if health_system:
			health_system.health_changed.connect(_on_health_changed)
			health_system.armor_broken.connect(_on_armor_broken)
			health_system.part_destroyed.connect(_on_part_destroyed)
			_update_all_bars()


# A transparent full-screen ColorRect sits above the HUD and flashes red on hit.
func _create_hit_flash() -> void:
	_hit_flash = ColorRect.new()
	_hit_flash.name = "HitFlash"
	_hit_flash.color = Color(1.0, 0.05, 0.02, 0.0)
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hit_flash)
	_hit_flash.set_anchors_preset(Control.PRESET_FULL_RECT)


func _on_player_damaged(_slot_name: String, _amount: float, _damage_type: String) -> void:
	if _hit_flash == null:
		return
	# Screen flash: briefly show a strong red, then fade out.
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_hit_flash.color.a = 0.5
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash, "color:a", 0.0, 0.35)

	# Distinct audio cue that the player is under fire.
	if has_node("/root/AudioManager"):
		AudioManager.play_player_hit()

	# Camera shake so the impact is felt, not just seen.
	var rig = get_tree().get_first_node_in_group("camera_rig")
	if rig and rig.has_method("add_shake"):
		rig.add_shake(0.35)


func _on_health_changed(slot_name: String, _layer: String, _current_hp: float, _max_hp: float) -> void:
	_refresh(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	_refresh(slot_name)


func _on_part_destroyed(slot_name: String) -> void:
	_refresh(slot_name)


func _refresh(slot_name: String) -> void:
	if not armor_bars.has(slot_name) or health_system == null:
		return
	if not health_system.parts.has(slot_name):
		return
	var part = health_system.parts[slot_name]
	armor_bars[slot_name].setup(part["armor_hp"], part["max_armor"], part["destroyed"])
	frame_bars[slot_name].setup(part["frame_hp"], part["max_frame"], part["destroyed"])
	armor_values[slot_name].text = "%d" % int(part["armor_hp"])
	frame_values[slot_name].text = "%d" % int(part["frame_hp"])


func _update_all_bars() -> void:
	for slot_name in armor_bars:
		_refresh(slot_name)
