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
var fire_left_holding: bool = false
var fire_right_holding: bool = false

# --- Shield State ---
var shield_active: bool = false
var shield_current_hp: float = 0.0
var shield_max_hp: float = 0.0
var shield_recharge_timer: float = 0.0
const SHIELD_RECHARGE_DELAY: float = 3.0
var _shield_visual: MeshInstance3D = null

# --- Weapon Scroll State (per hand) ---
var _selecting_left: bool = false
var _selecting_right: bool = false
var _select_idx_left: int = 0
var _select_idx_right: int = 0
var _select_scrolled_left: bool = false
var _select_scrolled_right: bool = false

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

	if fire_left_holding and left_hand and left_cooldown <= 0.0:
		if left_hand.weapon_type != WeaponPart.WeaponType.SHIELD:
			_try_fire("left", left_hand)
	if fire_right_holding and right_hand and right_cooldown <= 0.0:
		if right_hand.weapon_type != WeaponPart.WeaponType.SHIELD:
			_try_fire("right", right_hand)

	# Shield recharge
	if shield_active and shield_current_hp < shield_max_hp:
		shield_recharge_timer = SHIELD_RECHARGE_DELAY
	elif not shield_active and shield_current_hp < shield_max_hp:
		shield_recharge_timer -= delta
		if shield_recharge_timer <= 0.0:
			shield_current_hp = minf(shield_current_hp + shield_max_hp * 0.15 * delta, shield_max_hp)
	_update_shield_visual()


# ====================================================================
# INPUT
# ====================================================================

func _input(event: InputEvent) -> void:
	# --- LEFT HAND SWAP (key 1) ---
	if event.is_action_pressed("weapon_left"):
		_start_selection("left")
	if event.is_action_released("weapon_left"):
		_commit_selection("left")

	# --- RIGHT HAND SWAP (key 3) ---
	if event.is_action_pressed("weapon_right"):
		_start_selection("right")
	if event.is_action_released("weapon_right"):
		_commit_selection("right")

	# --- DROP (key X) ---
	if event.is_action_pressed("weapon_drop"):
		if holding_left:
			_drop_weapon("left")
		elif holding_right:
			_drop_weapon("right")

	# --- SCROLL while selecting ---
	if event is InputEventMouseButton:
		var dir = 0
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dir = -1   # up = lower index
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dir = 1    # down = higher index
		if dir != 0:
			if holding_left:
				_scroll("left", dir)
			elif holding_right:
				_scroll("right", dir)

	# --- FIRE LEFT ---
	if event.is_action_pressed("fire_left"):
		fire_left_holding = true
		if left_hand:
			if left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
				_toggle_shield("left")
			else:
				_try_fire("left", left_hand)
	if event.is_action_released("fire_left"):
		fire_left_holding = false

	# --- FIRE RIGHT ---
	if event.is_action_pressed("fire_right"):
		fire_right_holding = true
		if right_hand:
			if right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
				_toggle_shield("right")
			else:
				_try_fire("right", right_hand)
	if event.is_action_released("fire_right"):
		fire_right_holding = false


# ====================================================================
# WEAPON SELECTION (1/3 + scroll)
# ====================================================================

func _start_selection(hand: String) -> void:
	var is_left = (hand == "left")
	var hw = left_hand if is_left else right_hand
	if hw:
		carry.insert(0, hw)

	if is_left:
		holding_left = true
		_selecting_left = true
		_select_idx_left = 0
		_select_scrolled_left = false
		left_hand = null
	else:
		holding_right = true
		_selecting_right = true
		_select_idx_right = 0
		_select_scrolled_right = false
		right_hand = null

	carry_updated.emit(carry)


func _scroll(hand: String, direction: int) -> void:
	if carry.is_empty():
		return

	var is_left = (hand == "left")
	var idx = _select_idx_left if is_left else _select_idx_right
	var new_idx = clampi(idx + direction, 0, carry.size() - 1)

	if new_idx == idx:
		return

	if is_left:
		_select_idx_left = new_idx
		_select_scrolled_left = true
	else:
		_select_idx_right = new_idx
		_select_scrolled_right = true

	# Preview: show highlighted weapon in hand (don't touch carry)
	var preview = carry[new_idx]
	if is_left:
		left_hand = preview
	else:
		right_hand = preview

	weapon_switched.emit(hand, preview.weapon_name)
	ammo_changed.emit(hand, _get_ammo(preview), preview.max_ammo)
	carry_updated.emit(carry)


func _commit_selection(hand: String) -> void:
	var is_left = (hand == "left")
	var selecting = _selecting_left if is_left else _selecting_right
	if not selecting:
		return

	var did_scroll = _select_scrolled_left if is_left else _select_scrolled_right
	var idx = _select_idx_left if is_left else _select_idx_right

	if is_left:
		holding_left = false
		_selecting_left = false
	else:
		holding_right = false
		_selecting_right = false

	# Take the highlighted weapon out of carry into hand
	if idx < carry.size():
		if is_left:
			left_hand = carry[idx]
		else:
			right_hand = carry[idx]
		carry.remove_at(idx)

	weapon_switched.emit(hand, (left_hand if is_left else right_hand).weapon_name)
	var w = left_hand if is_left else right_hand
	if w:
		ammo_changed.emit(hand, _get_ammo(w), w.max_ammo)
	carry_updated.emit(carry)


# ====================================================================
# CYCLE (legacy — kept for compatibility)
# ====================================================================

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


# ====================================================================
# DROP
# ====================================================================

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


# ====================================================================
# WEAPON MANAGEMENT
# ====================================================================

func add_weapon(weapon: WeaponPart) -> void:
	# Check for duplicate by resource path
	for w in carry:
		if w.resource_path == weapon.resource_path:
			# Duplicate ranged: just add ammo
			if weapon.weapon_type != WeaponPart.WeaponType.MELEE:
				add_ammo(weapon.max_ammo / 2)
				return
			# Melee duplicates allowed for dual wield
			break

	# Check if already in hand
	if left_hand and left_hand.resource_path == weapon.resource_path:
		if weapon.weapon_type != WeaponPart.WeaponType.MELEE:
			add_ammo(weapon.max_ammo / 2)
			return
	if right_hand and right_hand.resource_path == weapon.resource_path:
		if weapon.weapon_type != WeaponPart.WeaponType.MELEE:
			add_ammo(weapon.max_ammo / 2)
			return

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
		# No hand specified — add to whichever hand has a weapon, prefer left
		if left_hand:
			var c = _get_ammo(left_hand)
			ammo_pool[left_hand.weapon_name] = mini(c + amount, left_hand.max_ammo)
			ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
		elif right_hand:
			var c = _get_ammo(right_hand)
			ammo_pool[right_hand.weapon_name] = mini(c + amount, right_hand.max_ammo)
			ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)


# ====================================================================
# FIRING
# ====================================================================

func _try_fire(hand: String, weapon: WeaponPart) -> void:
	if weapon.weapon_type == WeaponPart.WeaponType.SHIELD:
		return

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
	elif weapon.weapon_type == 2:
		_fire_shotgun(hand, weapon)
	else:
		_fire_projectile(hand, weapon)


func _fire_projectile(hand: String, weapon: WeaponPart) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var offset = Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5)
	var spawn_pos = mecha.global_position + mecha.global_transform.basis * offset

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var direction = (target_point - spawn_pos).normalized()

	var proj_script = load("res://scripts/systems/projectile.gd")
	var projectile = CharacterBody3D.new()
	projectile.set_script(proj_script)
	projectile.collision_layer = 0
	projectile.collision_mask = 0

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.1
	collision.shape = shape
	projectile.add_child(collision)

	var mesh = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.03
	capsule.height = 0.25
	mesh.mesh = capsule
	# Orient capsule along travel direction (capsule default is Y-up)
	mesh.look_at(mesh.global_position + direction, Vector3.UP)
	mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	projectile.add_child(mesh)

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
	projectile.speed = weapon.projectile_speed
	projectile.damage = weapon.damage
	projectile.damage_type = "kinetic"
	projectile.direction = direction

	EffectManager.spawn_muzzle_flash(spawn_pos, direction)
	AudioManager.play_weapon_sfx(weapon.weapon_type, spawn_pos)
	_spawn_shell_casing(spawn_pos, hand)


func _fire_shotgun(hand: String, weapon: WeaponPart) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var offset = Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5)
	var spawn_pos = mecha.global_position + mecha.global_transform.basis * offset

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result = space_state.intersect_ray(query)

	var target_point: Vector3
	if result:
		target_point = result["position"]
	else:
		target_point = ray_origin + ray_dir * 500.0

	var base_dir = (target_point - spawn_pos).normalized()

	var pellet_count = 7
	for i in range(pellet_count):
		var spread_x = randf_range(-weapon.spread, weapon.spread)
		var spread_y = randf_range(-weapon.spread, weapon.spread)
		var pellet_dir = (base_dir + Vector3(spread_x, spread_y, 0)).normalized()

		var proj_script = load("res://scripts/systems/projectile.gd")
		var projectile = CharacterBody3D.new()
		projectile.set_script(proj_script)
		projectile.collision_layer = 0
		projectile.collision_mask = 0

		var collision = CollisionShape3D.new()
		var shape = SphereShape3D.new()
		shape.radius = 0.08
		collision.shape = shape
		projectile.add_child(collision)

		var mesh = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.02
		capsule.height = 0.15
		mesh.mesh = capsule
		mesh.look_at(mesh.global_position + pellet_dir, Vector3.UP)
		mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.8, 0.2, 1)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.6, 0.1)
		mat.emission_energy_multiplier = 2.0
		mesh.material_override = mat
		projectile.add_child(mesh)

		get_tree().current_scene.add_child(projectile)
		projectile.global_position = spawn_pos
		projectile.speed = weapon.projectile_speed
		projectile.damage = weapon.damage
		projectile.damage_type = "kinetic"
		projectile.direction = pellet_dir

	EffectManager.spawn_muzzle_flash(spawn_pos, ray_dir)
	AudioManager.play_weapon_sfx(weapon.weapon_type, spawn_pos)
	_spawn_shell_casing(spawn_pos, hand)


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
	query.collision_mask = 10
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
	AudioManager.play_weapon_sfx(weapon.weapon_type, mecha.global_position)


var _melee_combo: int = 0

func _spawn_melee_trail(mecha: Node3D, direction: Vector3) -> void:
	var is_first_swing = (_melee_combo % 2 == 0)
	_melee_combo += 1

	var trail_count = 5
	var sweep_width = 5.0

	for i in range(trail_count):
		var t = float(i) / float(trail_count - 1)
		var trail = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(sweep_width, 0.08, 0.2)
		trail.mesh = box

		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var alpha = 1.0 - t * 0.6
		mat.albedo_color = Color(0.8, 0.9, 1.0, alpha)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.5, 1.0)
		mat.emission_energy_multiplier = 5.0 - t * 3.0
		mat.no_depth_test = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail.material_override = mat

		get_tree().current_scene.add_child(trail)

		var height_offset = lerp(1.8, 0.8, t)
		var forward_offset = direction * (1.5 + t * 1.0)
		trail.global_position = mecha.global_position + Vector3(0, height_offset, 0) + forward_offset
		trail.look_at(trail.global_position + direction, Vector3.UP)
		trail.rotate_object_local(Vector3.FORWARD, deg_to_rad(90))

		if is_first_swing:
			trail.rotate_object_local(Vector3.UP, deg_to_rad(-30 + t * 60))
		else:
			trail.rotate_object_local(Vector3.UP, deg_to_rad(30 - t * 60))

		var delay = t * 0.04
		var tween = get_tree().create_tween()
		tween.tween_interval(delay)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		tween.tween_callback(trail.queue_free)


func _check_melee_hit(mecha: Node3D, direction: Vector3, damage: float) -> void:
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var center = viewport_size / 2.0
	var ray_origin = cam.project_ray_origin(center)
	var ray_dir = cam.project_ray_normal(center)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 10.0)
	query.collision_mask = 8
	var result = space_state.intersect_ray(query)

	var aim_point: Vector3
	if result:
		aim_point = result["position"]
	else:
		aim_point = ray_origin + ray_dir * 10.0

	var enemies = get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var to_enemy = enemy.global_position + Vector3(0, 1.5, 0) - mecha.global_position
		var dist = to_enemy.length()
		if dist > 5.0:
			continue
		var dot = direction.dot(to_enemy.normalized())
		if dot > 0.3:
			if enemy.has_method("take_damage_at_point"):
				enemy.take_damage_at_point(damage, aim_point, "melee")
			elif enemy.has_method("take_damage"):
				enemy.take_damage(damage, "melee")
			EffectManager.spawn_damage_number(enemy.global_position + Vector3(0, 2.5, 0), damage, Color(1, 0.5, 0))


# ====================================================================
# HELPERS
# ====================================================================

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


# ====================================================================
# SHIELD
# ====================================================================

func _toggle_shield(hand: String) -> void:
	var weapon = left_hand if hand == "left" else right_hand
	if weapon == null or weapon.weapon_type != WeaponPart.WeaponType.SHIELD:
		return

	if shield_active:
		shield_active = false
		shield_recharge_timer = SHIELD_RECHARGE_DELAY
		weapon_switched.emit(hand, weapon.weapon_name + " [DOWN]")
		_hide_shield_visual()
	else:
		shield_active = true
		shield_max_hp = weapon.shield_hp
		if shield_current_hp <= 0.0:
			shield_current_hp = shield_max_hp
		weapon_switched.emit(hand, weapon.weapon_name + " [UP]")
		_show_shield_visual()


func absorb_damage_with_shield(amount: float) -> float:
	if not shield_active or shield_current_hp <= 0.0:
		return amount
	var absorbed = minf(amount, shield_current_hp)
	shield_current_hp -= absorbed
	var remaining = amount - absorbed
	if shield_current_hp <= 0.0:
		shield_active = false
		shield_current_hp = 0.0
		var hand = "left" if left_hand and left_hand.weapon_type == WeaponPart.WeaponType.SHIELD else "right"
		weapon_switched.emit(hand, "Shield BROKEN")
	return remaining


func get_shield_hp() -> float:
	return shield_current_hp


func get_shield_max_hp() -> float:
	return shield_max_hp


func is_shield_active() -> bool:
	return shield_active


func _show_shield_visual() -> void:
	if _shield_visual == null:
		_shield_visual = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 2.2
		sphere.height = 4.0
		_shield_visual.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.6, 1.0, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.5, 1.0)
		mat.emission_energy_multiplier = 2.0
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shield_visual.material_override = mat
		add_child(_shield_visual)
	_shield_visual.visible = true
	_shield_visual.position = Vector3(0, 1.5, 0)


func _hide_shield_visual() -> void:
	if _shield_visual:
		_shield_visual.visible = false


func _update_shield_visual() -> void:
	if _shield_visual == null or not shield_active:
		return
	var hp_ratio = shield_current_hp / maxf(shield_max_hp, 1.0)
	var mat = _shield_visual.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color.a = lerp(0.05, 0.3, hp_ratio)
		mat.emission_energy_multiplier = lerp(0.5, 2.0, hp_ratio)


# ====================================================================
# SHELL EJECTION
# ====================================================================

func _spawn_shell_casing(spawn_pos: Vector3, hand: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return

	var side = -1.0 if hand == "left" else 1.0
	var right = mecha.global_transform.basis.x * side
	var shell_dir = (right + Vector3(0, 0.5, 0)).normalized()

	var shell = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.06, 0.04, 0.12)
	shell.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.7, 0.2, 1)
	mat.metallic = 0.8
	mat.roughness = 0.3
	shell.material_override = mat

	get_tree().current_scene.add_child(shell)
	shell.global_position = spawn_pos + right * 0.3 + Vector3(0, 0.2, 0)

	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "position",
		shell.position + shell_dir * randf_range(1.5, 3.0) + Vector3(0, randf_range(0.5, 1.5), 0),
		0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "rotation",
		Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)),
		0.4)
	tween.chain().tween_property(shell, "position:y", -0.5, 0.4).set_ease(Tween.EASE_IN)
	tween.tween_callback(shell.queue_free).set_delay(0.6)
