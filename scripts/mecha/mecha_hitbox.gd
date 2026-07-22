extends Area3D

@export var health_system_path: NodePath

var health_system: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if health_system_path:
		health_system = get_node(health_system_path)


func set_health_system(system: Node) -> void:
	health_system = system


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("projectile"):
		return

	if body.has_method("get_damage"):
		var dmg = body.get_damage()
		var dmg_type = body.get("damage_type") or "kinetic"

		EffectManager.spawn_impact(body.global_position, Vector3.UP)

		if health_system:
			health_system.take_damage(dmg, dmg_type)
			EffectManager.spawn_damage_number(body.global_position + Vector3(0, 2, 0), dmg, Color.WHITE)

		body.queue_free()
