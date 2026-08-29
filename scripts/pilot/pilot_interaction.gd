extends Node

const MechaEject = preload("res://scripts/mecha/mecha_eject.gd")

@onready var pilot: CharacterBody3D = get_parent()
@onready var interact_area: Area3D = pilot.get_node_or_null("InteractArea")

var nearby_mech: Node3D = null


func _ready() -> void:
	if interact_area:
		interact_area.body_entered.connect(_on_body_entered)
		interact_area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("boardable_mech") or body.is_in_group("backup_mech") or body.is_in_group("mecha"):
		if body.has_meta("is_unoccupied") or body.has_meta("is_parked"):
			nearby_mech = body


func _on_body_exited(body: Node3D) -> void:
	if body == nearby_mech:
		nearby_mech = null
