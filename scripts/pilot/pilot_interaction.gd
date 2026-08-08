extends Node

@onready var pilot: CharacterBody3D = get_parent()
@onready var interact_area: Area3D = pilot.get_node("InteractArea")

var nearby_backup: Node3D = null


func _ready() -> void:
	interact_area.body_entered.connect(_on_body_entered)
	interact_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("backup_mech"):
		nearby_backup = body


func _on_body_exited(body: Node3D) -> void:
	if body == nearby_backup:
		nearby_backup = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and nearby_backup:
		var mecha = GameManager.get_player_mecha()
		if mecha:
			var eject = mecha.get_node_or_null("MechaEject")
			if eject:
				eject.board_backup_mech(nearby_backup)
