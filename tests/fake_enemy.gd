extends CharacterBody3D

## Minimal test enemy mirroring the enemy_dummy.gd concealment API.

var concealed: bool = false
var health_system: Node = null


func _ready() -> void:
	add_to_group("enemy")


func set_concealed(on: bool) -> void:
	if concealed == on:
		return
	concealed = on
	visible = not on
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("set_concealed"):
		status.set_concealed(on)
