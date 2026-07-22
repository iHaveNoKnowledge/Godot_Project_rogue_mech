extends Node3D

signal weapon_switched(hand: String, weapon_name: String)
signal ammo_changed(hand: String, current: int, max_ammo: int)
signal carry_updated(carry_list: Array)
signal weapon_dropped(hand: String, weapon: WeaponPart)

# --- Slots ---
var left_hand: WeaponPart = null
var right_hand: WeaponPart = null
var carry: Array[WeaponPart] = []

# --- Ammo ---
var ammo_pool: Dictionary = {}

# --- Cooldowns ---
var left_cooldown: float = 0.0
var right_cooldown: float = 0.0

# --- Input State ---
var holding_left: bool = false
var holding_right: bool = false
var scroll_index: int = 0

# --- Default Weapons ---
var default_left: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
var default_right: WeaponPart = preload("res://resources/mech/stock/weapon_heat_blade.tres")


func _ready() -> void:
	left_hand = default_left
	right_hand = default_right
	ammo_pool[left_hand.weapon_name] = left_hand.max_ammo
	ammo_pool[right_hand.weapon_name] = right_hand.max_ammo
	call_deferred("_emit_initial_state")


func _emit_initial_state() -> void:
	weapon_switched.emit("left", left_hand.weapon_name)
	ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	weapon_switched.emit("right", right_hand.weapon_name)
	ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	carry_updated.emit(carry)


func _physics_process(delta: float) -> void:
	if left_cooldown > 0.0:
		left_cooldown -= delta
	if right_cooldown > 0.0:
		right_cooldown -= delta


func _input(event: InputEvent) -> void:
	# --- LEFT HAND SWAP (key 1) ---
	if event.is_action_pressed("weapon_left"):
		holding_left = true
		scroll_index = 0
		_cycle_left()
	if event.is_action_released("weapon_left"):
		holding_left = false

	# --- RIGHT HAND SWAP (key 3) ---
	if event.is_action_pressed("weapon_right"):
		holding_right = true
		scroll_index = 0
		_cycle_right()
	if event.is_action_released("weapon_right"):
		holding_right = false

	# --- DROP (key 2) ---
	if event.is_action_pressed("weapon_drop"):
		if holding_left:
			_drop_weapon("left")
		elif holding_right:
			_drop_weapon("right")

	# --- SCROLL while holding 1 or 3 ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if holding_left or holding_right:
				_scroll_select(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if holding_left or holding_right:
				_scroll_select(-1)

	# --- FIRE LEFT (left mouse button) ---
	if event.is_action_pressed("fire_left"):
		if left_hand:
			_try_fire("left", left_hand)

	# --- FIRE RIGHT (right mouse button) ---
	if event.is_action_pressed("fire_right"):
		if right_hand:
			_try_fire("right", right_hand)


func _cycle_left() -> void:
	if carry.is_empty():
		return
	var old_weapon = left_hand
	if old_weapon:
		carry.append(old_weapon)
	left_hand = carry.pop_at(0) if not carry.is_empty() else null
	weapon_switched.emit("left", left_hand.weapon_name if left_hand else "Empty")
	if left_hand:
		ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	carry_updated.emit(carry)


func _cycle_right() -> void:
	if carry.is_empty():
		return
	var old_weapon = right_hand
	if old_weapon:
		carry.append(old_weapon)
	right_hand = carry.pop_at(0) if not carry.is_empty() else null
	weapon_switched.emit("right", right_hand.weapon_name if right_hand else "Empty")
	if right_hand:
		ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	carry_updated.emit(carry)


func _scroll_select(direction: int) -> void:
	if carry.is_empty():
		return
	scroll_index = clampi(scroll_index + direction, 0, carry.size() - 1)
	if holding_left:
		var temp = left_hand
		left_hand = carry[scroll_index]
		carry[scroll_index] = temp if temp else carry[scroll_index]
		if temp == null:
			carry.remove_at(scroll_index)
		weapon_switched.emit("left", left_hand.weapon_name if left_hand else "Empty")
		if left_hand:
			ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	elif holding_right:
		var temp = right_hand
		right_hand = carry[scroll_index]
		carry[scroll_index] = temp if temp else carry[scroll_index]
		if temp == null:
			carry.remove_at(scroll_index)
		weapon_switched.emit("right", right_hand.weapon_name if right_hand else "Empty")
		if right_hand:
			ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	carry_updated.emit(carry)


func _drop_weapon(hand: String) -> void:
	var weapon: WeaponPart = null
	if hand == "left":
		weapon = left_hand
		left_hand = null
	elif hand == "right":
		weapon = right_hand
		right_hand = null
	if weapon:
		weapon_dropped.emit(hand, weapon)
		weapon_switched.emit(hand, "Empty")


# ========================
# WEAPON MANAGEMENT
# ========================

func add_weapon(weapon: WeaponPart) -> void:
	carry.append(weapon)
	ammo_pool[weapon.weapon_name] = weapon.max_ammo
	carry_updated.emit(carry)


func add_ammo(amount: int, hand: String = "") -> void:
	if hand == "left" and left_hand:
		var current = _get_ammo(left_hand)
		ammo_pool[left_hand.weapon_name] = mini(current + amount, left_hand.max_ammo)
		ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	elif hand == "right" and right_hand:
		var current = _get_ammo(right_hand)
		ammo_pool[right_hand.weapon_name] = mini(current + amount, right_hand.max_ammo)
		ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	else:
		if left_hand:
			var c = _get_ammo(left_hand)
			ammo_pool[left_hand.weapon_name] = mini(c + amount, left_hand.max_ammo)
			ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)


# ========================
# FIRING
# ========================

func _try_fire(hand: String, weapon: WeaponPart) -> void:
	var current_ammo = _get_ammo(weapon)
	if not weapon.can_fire(current_ammo):
		return
	if hand == "left" and left_cooldown > 0.0:
		return
	if hand == "right" and right_cooldown > 0.0:
		return

	if hand == "left":
		left_cooldown = weapon.get_fire_interval()
	elif hand == "right":
		right_cooldown = weapon.get_fire_interval()

	ammo_pool[weapon.weapon_name] = current_ammo - weapon.ammo_per_shot
	ammo_changed.emit(hand, _get_ammo(weapon), weapon.max_ammo)

	if weapon.weapon_type == 4:
		_melee_attack(hand, weapon)
	else:
		_fire_projectile(hand, weapon)


func _fire_projectile(hand: String, weapon: WeaponPart) -> void:
	var projectile = CharacterBody3D.new()
	var script = load("res://scripts/systems/projectile.gd")
	projectile.set_script(script)

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.15
	collision.shape = shape
	projectile.add_child(collision)

	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.15
	mesh.mesh = sphere
	projectile.add_child(mesh)

	var direction = _get_fire_direction()
	if weapon.spread > 0.0:
		direction.x += randf_range(-weapon.spread, weapon.spread)
		direction.z += randf_range(-weapon.spread, weapon.spread)
		direction = direction.normalized()

	get_tree().current_scene.add_child(projectile)
	var offset = Vector3(-0.5, 1.0, 0) if hand == "left" else Vector3(0.5, 1.0, 0)
	var spawn_pos = get_parent().global_position + offset
	projectile.global_position = spawn_pos
	projectile.setup(direction, weapon.projectile_speed, weapon.damage)

	EffectManager.spawn_muzzle_flash(spawn_pos, direction)


func _melee_attack(hand: String, weapon: WeaponPart) -> void:
	var mecha = get_parent()
	var cam = get_viewport().get_camera_3d()
	if cam == null or mecha == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 13
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var dir = (target_point - mecha.global_position).normalized()
	dir.y = 0.0
	if dir.length() > 0.1:
		var target_angle = atan2(dir.x, dir.z)
		mecha.rotation.y = lerp_angle(mecha.rotation.y, target_angle, 0.3)

	_spawn_melee_trail(mecha, dir)
	_check_melee_hit(mecha, dir, weapon.damage)


func _spawn_melee_trail(mecha: Node3D, direction: Vector3) -> void:
	for i in range(3):
		var trail = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.15, 2.0, 0.8 - i * 0.2)
		trail.mesh = box

		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.9, 1.0, 0.7 - i * 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.7, 1.0)
		mat.emission_energy_multiplier = 3.0 - i
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		get_tree().current_scene.add_child(trail)
		var offset = direction * (1.2 + i * 0.3) + Vector3(0, 1.5, 0)
		trail.global_position = mecha.global_position + offset
		trail.look_at(trail.global_position + direction, Vector3.UP)
		trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))

		var tween = get_tree().create_tween()
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3 - i * 0.05)
		tween.tween_callback(trail.queue_free)


func _check_melee_hit(mecha: Node3D, direction: Vector3, damage: float) -> void:
	var space_state = get_viewport().get_world_3d().direct_space_state
	var mecha_pos = mecha.global_position + Vector3(0, 1.5, 0)
	var end_pos = mecha_pos + direction * 3.0

	var query = PhysicsRayQueryParameters3D.create(mecha_pos, end_pos)
	query.collision_mask = 8
	var result = space_state.intersect_ray(query)

	if result:
		var collider = result["collider"]
		if collider.has_method("take_damage"):
			collider.take_damage(damage, "melee")
			EffectManager.spawn_damage_number(result["position"] + Vector3(0, 1, 0), damage, Color(1, 0.5, 0))


func _get_fire_direction() -> Vector3:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return -Vector3.FORWARD

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 13
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var mecha = get_parent()
	if mecha:
		var mecha_pos = mecha.global_position + Vector3(0, 1.5, 0)
		var dir = (target_point - mecha_pos).normalized()
		return dir

	return ray_dir


# ========================
# HELPERS
# ========================

func _get_ammo(weapon: WeaponPart) -> int:
	return ammo_pool.get(weapon.weapon_name, 0)


func get_left_hand() -> WeaponPart:
	return left_hand


func get_right_hand() -> WeaponPart:
	return right_hand


func get_carry() -> Array[WeaponPart]:
	return carry


func get_all_weapons() -> Array:
	var all: Array = []
	if left_hand:
		all.append(left_hand)
	if right_hand:
		all.append(right_hand)
	all.append_array(carry)
	return all
