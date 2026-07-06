extends Node3D

signal weapon_fired(ammo_left: int)
signal weapon_switched(weapon_name: String)
signal ammo_changed(current: int, max_ammo: int)
signal weapon_picked_up(weapon: WeaponPart)

var weapons: Array[WeaponPart] = []
var current_weapon_index: int = 0
var ammo_pool: Dictionary = {}
var fire_cooldown: float = 0.0
var is_firing: bool = false


func _ready() -> void:
	EventBus.weapon_fired.connect(_on_weapon_fired)


func _physics_process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown -= delta
	if is_firing and fire_cooldown <= 0.0:
		_try_fire()


func add_weapon(weapon: WeaponPart) -> void:
	weapons.append(weapon)
	ammo_pool[weapon.weapon_name] = weapon.max_ammo
	if weapons.size() == 1:
		_equip_weapon(0)
	weapon_picked_up.emit(weapon)


func switch_weapon(direction: int) -> void:
	if weapons.size() <= 1:
		return
	current_weapon_index = (current_weapon_index + direction) % weapons.size()
	_equip_weapon(current_weapon_index)


func switch_to_weapon(index: int) -> void:
	if index >= 0 and index < weapons.size():
		_equip_weapon(index)


func _equip_weapon(index: int) -> void:
	current_weapon_index = index
	var weapon = weapons[index]
	weapon_switched.emit(weapon.weapon_name)
	ammo_changed.emit(_get_current_ammo(), weapon.max_ammo)


func start_firing() -> void:
	is_firing = true
	_try_fire()


func stop_firing() -> void:
	is_firing = false


func _try_fire() -> void:
	if current_weapon_index >= weapons.size():
		return
	var weapon = weapons[current_weapon_index]
	var current_ammo = _get_current_ammo()
	if not weapon.can_fire(current_ammo):
		return
	fire_cooldown = weapon.get_fire_interval()
	ammo_pool[weapon.weapon_name] = current_ammo - weapon.ammo_per_shot
	ammo_changed.emit(_get_current_ammo(), weapon.max_ammo)
	_fire_projectile(weapon)


func _fire_projectile(weapon: WeaponPart) -> void:
	var projectile = CharacterBody3D.new()
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	projectile.add_child(collision)

	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	mesh.mesh = sphere
	projectile.add_child(mesh)

	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var direction = -cam.global_transform.basis.z
	if weapon.spread > 0.0:
		direction.x += randf_range(-weapon.spread, weapon.spread)
		direction.z += randf_range(-weapon.spread, weapon.spread)
		direction = direction.normalized()

	get_parent().get_parent().add_child(projectile)
	projectile.global_position = global_position
	projectile.velocity = direction * weapon.projectile_speed
	weapon_fired.emit(_get_current_ammo())


func add_ammo(amount: int) -> void:
	if current_weapon_index < weapons.size():
		var weapon = weapons[current_weapon_index]
		var current = _get_current_ammo()
		ammo_pool[weapon.weapon_name] = mini(current + amount, weapon.max_ammo)
		ammo_changed.emit(_get_current_ammo(), weapon.max_ammo)


func _get_current_ammo() -> int:
	if current_weapon_index >= weapons.size():
		return 0
	var weapon = weapons[current_weapon_index]
	return ammo_pool.get(weapon.weapon_name, 0)


func get_all_weapons() -> Array[WeaponPart]:
	return weapons


func get_current_weapon() -> WeaponPart:
	if current_weapon_index < weapons.size():
		return weapons[current_weapon_index]
	return null


func _on_weapon_fired(_target_pos: Vector3) -> void:
	pass
