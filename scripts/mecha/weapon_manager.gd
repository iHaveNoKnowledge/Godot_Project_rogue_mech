extends Node3D

signal weapon_switched(hand: String, weapon_name: String)
signal ammo_changed(hand: String, current: int, max_ammo: int)
signal reload_progress(hand: String, partial_text: String, reserve_ammo: int, percent: float)
signal carry_updated(carry_list: Array)
signal weapon_dropped(hand: String, weapon: WeaponPart)

# --- Slots ---
var left_hand: WeaponPart = null
var right_hand: WeaponPart = null
var carry: Array[WeaponPart] = []

# --- Ammo ---
var ammo_pool: Dictionary = {}
# Ammo brought into this battle from the Hangar loadout. Reload consumes from
# this local pool (NOT the persistent stash) so "how much ammo you carry" is the
# ammo loadout choice. Leftover ammo returns to the stash when combat ends.
var battle_reserve: Dictionary = {}

# --- Cooldowns ---
var left_cooldown: float = 0.0
var right_cooldown: float = 0.0

# --- Input State ---
var holding_left: bool = false
var holding_right: bool = false
var fire_left_holding: bool = false
var fire_right_holding: bool = false
var holding_reload: bool = false
var reloading_left: bool = false
var reloading_right: bool = false
var _hold_time_left: float = 0.0
var _hold_time_right: float = 0.0

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
var _tap_time_left: float = 0.0
var _tap_time_right: float = 0.0
const TAP_THRESHOLD: float = 0.25

# --- Default Weapons (used only when GlobalData has nothing equipped) ---
var default_left: WeaponPart = preload("res://resources/mech/stock/weapon_beam_rifle.tres")
var default_right: WeaponPart = preload("res://resources/mech/stock/weapon_heat_blade.tres")


func _ready() -> void:
	# Load the equipped loadout from the Hangar (GlobalData.weapon_loadout) so the
	# battle mech carries the SAME weapons (hands + back) that were configured in the garage.
	# An empty hand slot in the loadout means "unarmed" — kept as null.
	left_hand = GlobalData.get_equipped_weapon("left")
	right_hand = GlobalData.get_equipped_weapon("right")
	carry = GlobalData.get_carry_weapons()
	if left_hand:
		ammo_pool[left_hand.weapon_name] = left_hand.max_ammo
	if right_hand:
		ammo_pool[right_hand.weapon_name] = right_hand.max_ammo
	# Seed ammo for carried weapons so they are usable when swapped into a hand.
	for weapon in carry:
		if weapon and not ammo_pool.has(weapon.weapon_name):
			ammo_pool[weapon.weapon_name] = weapon.max_ammo
	# Battle reserve = the ammo the player chose to carry in the loadout.
	# Deduct that from the persistent stash now (what you fire is spent); any
	# leftover returns to the stash when combat ends.
	battle_reserve = GlobalData.get_loadout_ammo_dict()
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			GlobalData.consume_reserve_ammo(ammo_type, amount)
	EventBus.combat_ended.connect(_on_combat_ended)
	call_deferred("_emit_initial_state")


func _on_combat_ended(_victory: bool) -> void:
	# Return any unused carried ammo to the persistent stash so nothing is lost.
	for ammo_type in battle_reserve:
		var amount: int = battle_reserve[ammo_type]
		if amount > 0:
			GlobalData.add_reserve_ammo(ammo_type, amount)
	battle_reserve.clear()


func get_battle_reserve(ammo_type: String) -> int:
	return battle_reserve.get(ammo_type.to_lower(), 0)


func add_battle_reserve(ammo_type: String, amount: int) -> void:
	var type = ammo_type.to_lower()
	if type == "" or type == "none":
		return
	battle_reserve[type] = battle_reserve.get(type, 0) + amount


func consume_battle_reserve(ammo_type: String, amount: int) -> int:
	var type = ammo_type.to_lower()
	var current = battle_reserve.get(type, 0)
	var taken = mini(current, amount)
	battle_reserve[type] = current - taken
	return taken


func _emit_initial_state() -> void:
	if left_hand == null and right_hand == null:
		return
	if left_hand:
		weapon_switched.emit("left", left_hand.weapon_name)
		ammo_changed.emit("left", _get_ammo(left_hand), left_hand.max_ammo)
	if right_hand:
		weapon_switched.emit("right", right_hand.weapon_name)
		ammo_changed.emit("right", _get_ammo(right_hand), right_hand.max_ammo)
	call_deferred("_update_weapon_visuals")
	carry_updated.emit(carry)


func _physics_process(delta: float) -> void:
	if left_cooldown > 0.0:
		left_cooldown -= delta
	if right_cooldown > 0.0:
		right_cooldown -= delta

	if holding_left:
		_hold_time_left += delta
	if holding_right:
		_hold_time_right += delta

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

	# --- RELOAD (key R) ---
	if event.is_action_pressed("reload"):
		holding_reload = true
	if event.is_action_released("reload"):
		holding_reload = false

	# --- FIRE / RELOAD LEFT ---
	if event.is_action_pressed("fire_left"):
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("left")
		else:
			fire_left_holding = true
			if left_hand:
				if left_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					_toggle_shield("left")
				else:
					_try_fire("left", left_hand)
	if event.is_action_released("fire_left"):
		fire_left_holding = false

	# --- FIRE / RELOAD RIGHT ---
	if event.is_action_pressed("fire_right"):
		if holding_reload or Input.is_action_pressed("reload"):
			reload_weapon("right")
		else:
			fire_right_holding = true
			if right_hand:
				if right_hand.weapon_type == WeaponPart.WeaponType.SHIELD:
					_toggle_shield("right")
				else:
					_try_fire("right", right_hand)
	if event.is_action_released("fire_right"):
		fire_right_holding = false


func reload_weapon(hand: String) -> void:
	var is_left = (hand == "left")
	if is_left and reloading_left:
		return
	if not is_left and reloading_right:
		return

	var weapon: WeaponPart = left_hand if is_left else right_hand
	if weapon == null:
		return

	var ammo_type = weapon.get_ammo_type()
	if ammo_type == "none":
		return

	var current_mag = _get_ammo(weapon)
	var needed = weapon.max_ammo - current_mag
	if needed <= 0:
		return

	var reserve = get_battle_reserve(ammo_type)
	if reserve <= 0:
		EffectManager.spawn_damage_number(global_position + Vector3(0, 2.5, 0), 0, Color(1.0, 0.2, 0.2))
		return

	if is_left:
		reloading_left = true
	else:
		reloading_right = true

	var target_word: String = "reload!"
	var char_count = target_word.length()
	var total_reload_time: float = 1.0
	var time_per_char = total_reload_time / float(char_count + 1)

	for i in range(1, char_count + 1):
		var partial_text = target_word.substr(0, i)
		reload_progress.emit(hand, partial_text, reserve, float(i) / float(char_count))
		await get_tree().create_timer(time_per_char).timeout
		var check_weapon = left_hand if is_left else right_hand
		if check_weapon != weapon:
			if is_left: reloading_left = false
			else: reloading_right = false
			return

	var refilled = consume_battle_reserve(ammo_type, needed)
	ammo_pool[weapon.weapon_name] = current_mag + refilled

	if is_left:
		reloading_left = false
	else:
		reloading_right = false

	if has_node("/root/AudioManager"):
		AudioManager.play_reload_complete()

	ammo_changed.emit(hand, _get_ammo(weapon), weapon.max_ammo)
	EffectManager.spawn_damage_number(global_position + Vector3(0, 2.5, 0), refilled, Color(0.2, 1.0, 0.4))


# ====================================================================
# WEAPON SELECTION (1/3 + scroll)
# ====================================================================

func _start_selection(hand: String) -> void:
	var is_left = (hand == "left")

	if is_left:
		_hold_time_left = 0.0
		_tap_time_left = 0.0
	else:
		_hold_time_right = 0.0
		_tap_time_right = 0.0

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
	_update_weapon_visuals()


func _commit_selection(hand: String) -> void:
	var is_left = (hand == "left")
	var selecting = _selecting_left if is_left else _selecting_right
	if not selecting:
		return

	var did_scroll = _select_scrolled_left if is_left else _select_scrolled_right
	var idx = _select_idx_left if is_left else _select_idx_right
	var hold_time = _hold_time_left if is_left else _hold_time_right

	if is_left:
		holding_left = false
		_selecting_left = false
	else:
		holding_right = false
		_selecting_right = false

	# Quick tap without scroll → cycle to next weapon
	if not did_scroll and hold_time < TAP_THRESHOLD and carry.size() > 1:
		var old_weapon = carry[idx]
		carry.remove_at(idx)
		carry.append(old_weapon)
		var new_weapon = carry[0]
		if is_left:
			left_hand = new_weapon
		else:
			right_hand = new_weapon
		carry.remove_at(0)
		weapon_switched.emit(hand, new_weapon.weapon_name)
		ammo_changed.emit(hand, _get_ammo(new_weapon), new_weapon.max_ammo)
		carry_updated.emit(carry)
		_update_weapon_visuals()
		return

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
	_update_weapon_visuals()


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
	_update_weapon_visuals()


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
	_update_weapon_visuals()


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
		_update_weapon_visuals()


# Called by HealthSystem when the arm frame on this hand is destroyed.
# The weapon itself is NOT destroyed (only the frame holding it broke), so it is
# removed from the hand and returned so the caller can spawn a recoverable pickup.
func drop_weapon_from_destroyed_arm(hand: String) -> WeaponPart:
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
		_update_weapon_visuals()
	return weapon


# ====================================================================
# WEAPON MANAGEMENT
# ====================================================================

func add_weapon(weapon: WeaponPart) -> void:
	# Registers the weapon in the central stash (same-ID pickups increment the
	# count, so owning the same weapon twice enables equipping both hands with it).
	GlobalData.register_weapon(weapon.resource_path, weapon.weapon_name)
	# The ammo the weapon carries is usable immediately in this battle.
	add_battle_reserve(weapon.get_ammo_type(), weapon.max_ammo)

	# Always add a physical copy so picking up the same weapon gives you a second
	# one (dual-wield the same model) instead of silently converting to ammo.
	carry.append(weapon)
	ammo_pool[weapon.weapon_name] = weapon.max_ammo
	carry_updated.emit(carry)
	_update_weapon_visuals()


func add_ammo(amount: int, hand: String = "", ammo_type: String = "") -> void:
	var target_type = ammo_type
	var target_weapon: WeaponPart = null
	if hand == "left":
		target_weapon = left_hand
	elif hand == "right":
		target_weapon = right_hand
	else:
		target_weapon = left_hand if left_hand else right_hand

	if target_type.is_empty() and target_weapon:
		target_type = target_weapon.get_ammo_type()
	if target_type.is_empty():
		target_type = "kinetic"

	# Ammo found mid-battle is added to the local battle reserve so it is usable
	# right away; unused leftovers return to the stash when combat ends.
	add_battle_reserve(target_type, amount)

	if target_weapon:
		var current = _get_ammo(target_weapon)
		ammo_changed.emit(hand if not hand.is_empty() else "left", current, target_weapon.max_ammo)


# ====================================================================
# FIRING
# ====================================================================

func _try_fire(hand: String, weapon: WeaponPart) -> void:
	if (hand == "left" and reloading_left) or (hand == "right" and reloading_right):
		return
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

	match weapon.weapon_type:
		WeaponPart.WeaponType.MELEE:
			_melee_attack(hand, weapon)
		WeaponPart.WeaponType.SHOTGUN:
			_fire_shotgun(hand, weapon)
		WeaponPart.WeaponType.MISSILE:
			_fire_missile(hand, weapon)
		_:
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
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.8, 0.2, 1)
	mat.emission_enabled = true
	mat.emission = Color(1, 0.6, 0.1)
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	projectile.add_child(mesh)

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
	# Orient capsule along travel direction (must be in tree for look_at)
	mesh.global_position = spawn_pos
	mesh.look_at(spawn_pos + direction, Vector3.UP)
	mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	projectile.speed = weapon.projectile_speed
	projectile.damage = weapon.damage
	projectile.damage_type = "kinetic"
	projectile.direction = direction

	EffectManager.spawn_muzzle_flash(spawn_pos, direction)
	AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)
	_spawn_shell_casing(spawn_pos, hand)


func _fire_missile(hand: String, weapon: WeaponPart) -> void:
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
	projectile.speed = weapon.projectile_speed
	projectile.damage = weapon.damage
	projectile.damage_type = "explosive"
	projectile.direction = direction

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.1, 0.1, 0.4)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.1, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	projectile.add_child(mesh)

	get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
	mesh.global_position = spawn_pos
	mesh.look_at(spawn_pos + direction, Vector3.UP)

	EffectManager.spawn_muzzle_flash(spawn_pos, direction)
	AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)


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
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.8, 0.2, 1)
		mat.emission_enabled = true
		mat.emission = Color(1, 0.6, 0.1)
		mat.emission_energy_multiplier = 2.0
		mesh.material_override = mat
		projectile.add_child(mesh)

		get_tree().current_scene.add_child(projectile)
		projectile.global_position = spawn_pos
		mesh.global_position = spawn_pos
		mesh.look_at(spawn_pos + pellet_dir, Vector3.UP)
		mesh.rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
		projectile.speed = weapon.projectile_speed
		projectile.damage = weapon.damage
		projectile.damage_type = "kinetic"
		projectile.direction = pellet_dir

	EffectManager.spawn_muzzle_flash(spawn_pos, ray_dir)
	AudioManager.play_weapon_sfx_with_override(weapon, spawn_pos)
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

	# Eject spent shell casing for Pile Bunker / kinetic melee
	if weapon and (weapon.ammo_per_shot > 0 or weapon.weapon_name.to_lower().contains("pile") or weapon.get_ammo_type() != "none"):
		var spawn_pos = mecha.global_position + (Vector3(-0.6, 1.5, 0.5) if hand == "left" else Vector3(0.6, 1.5, 0.5))
		_spawn_shell_casing(spawn_pos, hand)
		
	# Execute lunging punch animation (Anticipation -> Thrust -> Camera Shake -> Recovery)
	_perform_pile_bunker_lunge_anim(mecha, dir, weapon)

	_spawn_melee_trail(mecha, dir)
	_check_melee_hit(mecha, dir, weapon.damage)
	AudioManager.play_weapon_sfx_with_override(weapon, mecha.global_position)

func _perform_pile_bunker_lunge_anim(mecha: Node3D, dir: Vector3, weapon: WeaponPart) -> void:
	if not mecha:
		return
	var orig_pos = mecha.global_position
	var is_pile = weapon and weapon.weapon_name.to_lower().contains("pile")
	var lunge_dist = 2.4 if is_pile else 1.2
	
	var tween = mecha.create_tween().set_parallel(false)
	# 1. Anticipation: Pull back slightly & crouch
	tween.tween_property(mecha, "global_position", orig_pos - dir * 0.4, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Explosive Forward Thrust
	tween.tween_property(mecha, "global_position", orig_pos + dir * lunge_dist, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	
	# Screen Shake on Impact
	if is_pile:
		var camera_rig = get_tree().get_nodes_in_group("camera_rig")
		if not camera_rig.is_empty() and camera_rig[0].has_method("add_shake"):
			camera_rig[0].add_shake(0.35)
			
	# 3. Recovery
	tween.tween_property(mecha, "global_position", orig_pos, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


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

func _update_weapon_visuals() -> void:
	var mecha = get_parent() as Node3D
	if not mecha:
		return
	_update_hand_weapon_visual(mecha, "left", left_hand)
	_update_hand_weapon_visual(mecha, "right", right_hand)
	_update_carry_visuals(mecha)

func _update_hand_weapon_visual(mecha: Node3D, hand: String, weapon: WeaponPart) -> void:
	var node_name = "WeaponMesh_" + hand
	var existing = mecha.get_node_or_null(node_name)
	if existing:
		existing.queue_free()
	
	if weapon == null:
		return
		
	var mount = Node3D.new()
	mount.name = node_name
	
	var is_left = (hand == "left")
	mount.position = Vector3(-0.85, 1.4, 0.4) if is_left else Vector3(0.85, 1.4, 0.4)
	
	mount.add_child(WeaponVisualFactory.build(weapon))
	
	mecha.add_child(mount)

# Renders the weapons carried on the mech's back (from the loadout).
func _update_carry_visuals(mecha: Node3D) -> void:
	var existing = mecha.get_node_or_null("CarryWeapons")
	if existing:
		existing.queue_free()
	if carry.is_empty():
		return

	var back_mount = Node3D.new()
	back_mount.name = "CarryWeapons"
	# Spread carried weapons horizontally across the back pack.
	var offset := -((carry.size() - 1) * 0.22)
	for weapon in carry:
		if weapon == null:
			continue
		var mount = Node3D.new()
		mount.position = Vector3(offset, 1.65, -0.55)
		mount.rotation_degrees = Vector3(-15, 0, 0)
		mount.add_child(WeaponVisualFactory.build(weapon))
		back_mount.add_child(mount)
		offset += 0.44
	mecha.add_child(back_mount)
