extends Node3D

@export var save_on_escape: bool = true


func _on_escape_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("pilot") or body.name == "MechaBase":
		_return_to_board()


func _return_to_board() -> void:
	if save_on_escape:
		GlobalData.save_run()
	GameManager.enter_board()
