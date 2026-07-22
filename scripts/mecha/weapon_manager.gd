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


func _unhandled_input(event: InputEvent) -> void:
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

	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var direction = -cam.global_transform.basis.z
	if weapon.spread > 0.0:
		direction.x += randf_range(-weapon.spread, weapon.spread)
		direction.z += randf_range(-weapon.spread, weapon.spread)
		direction = direction.normalized()

	get_tree().current_scene.add_child(projectile)
	var offset = Vector3(-0.5, 1.0, 0) if hand == "left" else Vector3(0.5, 1.0, 0)
	projectile.global_position = get_parent().global_position + offset
	projectile.setup(direction, weapon.projectile_speed)


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
