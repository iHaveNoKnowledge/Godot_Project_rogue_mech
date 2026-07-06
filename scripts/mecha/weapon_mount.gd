extends Node3D

var weapon_manager: Node = null
var weapon_index_label: Label
var ammo_label: Label


func _ready() -> void:
	weapon_manager = get_node_or_null("../WeaponManager")
	if weapon_manager:
		weapon_manager.weapon_switched.connect(_on_weapon_switched)
		weapon_manager.ammo_changed.connect(_on_ammo_changed)


func _unhandled_input(event: InputEvent) -> void:
	if weapon_manager == null:
		return
	if event.is_action_pressed("fire"):
		weapon_manager.start_firing()
	if event.is_action_released("fire"):
		weapon_manager.stop_firing()
	if event.is_action_pressed("weapon_next"):
		weapon_manager.switch_weapon(1)
	if event.is_action_pressed("weapon_prev"):
		weapon_manager.switch_weapon(-1)


func _on_weapon_switched(weapon_name: String) -> void:
	pass


func _on_ammo_changed(current: int, max_ammo: int) -> void:
	pass
