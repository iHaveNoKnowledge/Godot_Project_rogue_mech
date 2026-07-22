extends Area3D

@export var health_system_path: NodePath

var health_system: Node = null


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	if health_system_path:
		health_system = get_node(health_system_path)


func set_health_system(system: Node) -> void:
	health_system = system


func _on_area_entered(area: Area3D) -> void:
	if not area.is_in_group("projectile"):
		return

	var projectile = area.get_parent()
	if projectile.has_method("get_damage"):
		var dmg = projectile.get_damage()
		var dmg_type = projectile.get("damage_type") or "kinetic"

		EffectManager.spawn_impact(projectile.global_position, Vector3.UP)

		if health_system:
			health_system.take_damage(dmg, dmg_type)
			EffectManager.spawn_damage_number(projectile.global_position + Vector3(0, 2, 0), dmg, Color.WHITE)

		projectile.queue_free()
