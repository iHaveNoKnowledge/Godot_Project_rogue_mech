extends Node3D


func _unhandled_input(event: InputEvent) -> void:
	var wm = get_node_or_null("WeaponManager")
	if wm:
		wm.handle_input(event)
