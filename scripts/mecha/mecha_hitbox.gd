extends Area3D

@export var health_system_path: NodePath

var health_system: Node = null


func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	if health_system_path:
		health_system = get_node(health_system_path)


func set_health_system(system: Node) -> void:
	health_system = system


func _on_body_entered(body: Node3D) -> void:
	_damage_if_projectile(body)


func _on_area_entered(area: Area3D) -> void:
	if area.get_parent():
		_damage_if_projectile(area.get_parent())


func _damage_if_projectile(body: Node3D) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("projectile"):
		return
	if not body.has_method("get_damage"):
		return

	var dmg = body.get_damage()
	var dmg_type = "kinetic"
	if body.get("damage_type"):
		dmg_type = body.damage_type

	EffectManager.spawn_impact(body.global_position, Vector3.UP)

	if health_system:
		if health_system.has_method("take_damage_at_point"):
			health_system.take_damage_at_point(dmg, body.global_position, dmg_type)
		else:
			health_system.take_damage(dmg, dmg_type)
		EffectManager.spawn_damage_number(body.global_position + Vector3(0, 2, 0), dmg, Color.WHITE)

	body.queue_free()
