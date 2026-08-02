extends Area3D

@export var weapon_resource: WeaponPart
@export var bob_speed: float = 2.0
@export var bob_amount: float = 0.3
@export var rotate_speed: float = 1.5

var mesh: MeshInstance3D = null
var original_y: float = 0.0
var timer: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_create_visual()


func _create_visual() -> void:
	mesh = MeshInstance3D.new()

	# Show the actual weapon model when a weapon resource is set (matches hangar).
	if weapon_resource:
		# Hide any placeholder box mesh defined in the scene (stock pickups).
		for child in get_children():
			if child is MeshInstance3D:
				child.visible = false
		var visual := Node3D.new()
		visual.add_child(WeaponVisualFactory.build(weapon_resource))
		add_child(visual)
		original_y = position.y
		return

	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.3, 1.2)
	mesh.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.5, 0.1)
	mat.emission_energy_multiplier = 1.5
	mesh.material_override = mat

	add_child(mesh)
	original_y = position.y


func _process(delta: float) -> void:
	timer += delta
	rotate_y(rotate_speed * delta)
	if mesh and mesh.is_inside_tree():
		mesh.position.y = sin(timer * bob_speed) * bob_amount


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("mecha"):
		var weapon_manager = body.get_node_or_null("WeaponManager")
		if weapon_manager and weapon_resource:
			weapon_manager.add_weapon(weapon_resource)
			queue_free()
