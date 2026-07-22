extends Node3D

var loot_items: Array = []
var pickup_radius: float = 2.0


func spawn_loot(position: Vector3, loot_table: Array) -> void:
	for item in loot_table:
		if randf() < item.get("drop_chance", 0.5):
			_create_loot_pickup(position + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), item)


func _create_loot_pickup(pos: Vector3, loot_data: Dictionary) -> void:
	var pickup = Area3D.new()
	pickup.collision_layer = 1
	pickup.collision_mask = 1

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = pickup_radius
	collision.shape = shape
	pickup.add_child(collision)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = box
	mesh.position.y = 0.5
	pickup.add_child(mesh)

	var material = StandardMaterial3D.new()
	match loot_data.get("type", "ammo"):
		"weapon":
			material.albedo_color = Color(0.9, 0.7, 0.1)
		"ammo":
			material.albedo_color = Color(0.2, 0.8, 0.2)
		"repair":
			material.albedo_color = Color(0.2, 0.2, 0.9)
	mesh.set_surface_override_material(0, material)

	pickup.set_meta("loot_data", loot_data)
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup))
	get_parent().add_child(pickup)
	pickup.global_position = pos


func _on_pickup_body_entered(body: Node3D, pickup: Area3D) -> void:
	if not body.is_in_group("mecha"):
		return
	var loot_data = pickup.get_meta("loot_data", {})
	match loot_data.get("type", "ammo"):
		"weapon":
			var weapon: WeaponPart = loot_data.get("weapon")
			if weapon:
				var wm = body.get_node_or_null("WeaponManager")
				if wm:
					wm.add_weapon(weapon)
		"ammo":
			var amount: int = loot_data.get("amount", 10)
			var wm = body.get_node_or_null("WeaponManager")
			if wm:
				wm.add_ammo(amount)
		"repair":
			var slot: String = loot_data.get("slot", "")
			if slot:
				GlobalData.part_damage.erase(slot + "_armor")
				GlobalData.part_damage.erase(slot + "_frame")
				EventBus.weight_changed.emit(0.0)
	pickup.queue_free()


func spawn_enemy_loot(enemy_position: Vector3) -> void:
	var loot_table = [
		{"type": "ammo", "amount": 15, "drop_chance": 0.7},
		{"type": "ammo", "amount": 25, "drop_chance": 0.3},
		{"type": "repair", "slot": "body", "drop_chance": 0.15},
	]
	spawn_loot(enemy_position, loot_table)
