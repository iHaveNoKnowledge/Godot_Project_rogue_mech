extends CharacterBody3D

const MechaEject = preload("res://scripts/mecha/mecha_eject.gd")

@export var move_speed: float = 5.0
@export var jump_force: float = 4.5

var gravity := 20.0

# Sprint + stamina are the PILOT'S OWN system — fully separate from the mech's
# energy pool. Sprinting drains pilot stamina; it regenerates while walking /
# standing. Out of stamina, the pilot can't sprint until it recovers.
@export var sprint_speed: float = 8.2
@export var max_stamina: float = 100.0
@export var sprint_drain: float = 22.0
@export var stamina_regen: float = 14.0

var stamina: float = 100.0
var _is_sprinting: bool = false

# The pilot fights with their OWN body weapons (PilotSystem), completely
# separate from the parked mech's loadout. One shared WeaponCore drives ammo /
# cooldown / projectiles for whichever weapon is in hand; firing consumes the
# pilot's personal ammo reserves.
var _weapons: Array = []
var _weapon_index: int = 0
var _fire_core: WeaponCore = null
var _fire_timer: float = 0.0
var _weapon_mesh: Node3D = null


func _ready() -> void:
	add_to_group("pilot")
	_weapons = PilotSystem.get_weapons()
	if not _weapons.is_empty():
		_equip_weapon(0)
	_rebuild_weapon_mesh()


# The pilot on foot is a real target: enemy fire (projectiles + melee) hits
# them and drains the SAME PilotSystem HP pool that the mech-eject wounding
# uses. A pilot whose HP reaches 0 is dead permanently — the run ends. This
# is the same permanent-death rule enemy pilots use, so getting shot can end
# a pilot for good instead of the player always ejecting and fleeing.
func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if amount <= 0.0 or PilotSystem.is_dead():
		return
	PilotSystem.take_damage(amount)
	EffectManager.spawn_damage_number(global_position + Vector3(0, 1.6, 0), amount, Color(1.0, 0.4, 0.3))
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, global_position)
	if PilotSystem.is_dead():
		_die()


# Permanent death on foot: the pilot collapses and the run is over. The same
# death rule applies to every pilot (player and enemy) — HP 0 is gone for good.
func _die() -> void:
	if GameManager.current_state == GameManager.State.EJECT:
		GlobalData.board.run_notice = "Your pilot was shot and killed. The run ends here."
		EventBus.combat_ended.emit(false)


func _equip_weapon(index: int) -> void:
	if _weapons.is_empty():
		_weapon_index = 0
		_fire_core = null
		return
	_weapon_index = posmod(index, _weapons.size())
	var weapon: WeaponPart = _weapons[_weapon_index]
	_fire_core = WeaponCore.from_weapon(weapon)
	_fire_core.fire_interval = 0.0
	_fire_core.auto_reload = false
	_fire_core.manual_reload = true
	_fire_core.unlimited_ammo = weapon.max_ammo <= 0
	_rebuild_weapon_mesh()


# Rebuilds the pilot's carried-weapon model from the CURRENT weapon in hand.
# Null clears it.
func _rebuild_weapon_mesh() -> void:
	if _weapon_mesh and is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	if _weapons.is_empty():
		return
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	_weapon_mesh = Node3D.new()
	_weapon_mesh.add_child(WeaponVisualFactory.build(weapon))
	# Held at the pilot's side, like a carried rifle.
	_weapon_mesh.position = Vector3(0.45, 1.05, -0.15)
	_weapon_mesh.rotation = Vector3(0, 0, -0.35)
	add_child(_weapon_mesh)


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state != GameManager.State.EJECT:
		return
	if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_F and not event.echo):
		var now := Time.get_ticks_msec()
		var last_time: int = int(get_meta("last_mount_toggle_time", 0))
		if now - last_time < 500:
			return
		var target_mech := find_nearest_boardable_mech()
		if target_mech:
			get_viewport().set_input_as_handled()
			MechaEject.board_mecha(target_mech)
			return
	if event.is_action_pressed("fire_left"):
		_try_fire()
	elif event.is_action_pressed("fire_right"):
		_try_fire()
	elif event.is_action_pressed("weapon_left") or event.is_action_pressed("weapon_right"):
		# Cycle personal weapons (key 1 / 3) — the pilot swaps their own sidearm.
		if _weapons.size() > 1:
			_equip_weapon(_weapon_index + 1)
	elif event is InputEventMouseButton:
		# Scroll wheel swaps the pilot's carried weapon (third-person shooter
		# style): wheel up = next, wheel down = previous.
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and _weapons.size() > 1:
			_equip_weapon(_weapon_index + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and _weapons.size() > 1:
			_equip_weapon(_weapon_index - 1)


## Finds the closest boardable/unoccupied mecha within interaction distance (< 4.5m)
func find_nearest_boardable_mech() -> CharacterBody3D:
	var tree := get_tree()
	if tree == null:
		return null
	var candidates: Array = []
	candidates.append_array(tree.get_nodes_in_group("boardable_mech"))
	candidates.append_array(tree.get_nodes_in_group("backup_mech"))
	candidates.append_array(tree.get_nodes_in_group("mecha"))

	var best: CharacterBody3D = null
	var best_dist: float = 4.5

	for node in candidates:
		if node is CharacterBody3D and is_instance_valid(node) and node != self:
			var hs = node.get_node_or_null("HealthSystem")
			if hs and bool(hs.get("is_destroyed")):
				continue # Destroyed mechas cannot be boarded
			# Must be unoccupied, parked, or without a live pilot
			if node.has_meta("is_unoccupied") or node.has_meta("is_parked") or not node.has_meta("has_pilot"):
				var d := global_position.distance_to(node.global_position)
				if d < best_dist:
					best_dist = d
					best = node
	return best


func _try_fire() -> void:
	if _fire_core == null or _weapons.is_empty():
		return
	var weapon: WeaponPart = _weapons[_weapon_index]
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		# On-foot melee: a short lunging swing with the sidearm's blade.
		_melee_swing(weapon)
		return

	# Personal ammo: the pilot's own reserve (not the mech's). Melee / infinite
	# weapons ignore it.
	var ammo_type := weapon.get_ammo_type()
	if ammo_type != "none" and not _fire_core.unlimited_ammo:
		if PilotSystem.get_ammo(ammo_type) <= 0:
			return
		PilotSystem.consume_ammo(ammo_type, weapon.ammo_per_shot)

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := get_viewport().get_visible_rect().size / 2.0
	var ray_origin := cam.project_ray_origin(center)
	var ray_dir := cam.project_ray_normal(center)

	var space_state := get_viewport().get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 500.0)
	query.collision_mask = 10
	var result := space_state.intersect_ray(query)

	var muzzle := global_position + Vector3(0, 1.4, 0)
	var aim_dir: Vector3
	if result:
		aim_dir = (result["position"] - muzzle).normalized()
	else:
		aim_dir = (ray_origin + ray_dir * 500.0 - muzzle).normalized()

	if _fire_core.try_fire(muzzle, aim_dir, false, self):
		if AudioManager:
			AudioManager.play_sfx("machine_gun", muzzle, -8.0)
		# Pilot weapons recoil the pilot's own aim slightly (no mech to absorb it).
		velocity.x += -aim_dir.x * 0.8
		velocity.z += -aim_dir.z * 0.8


func _melee_swing(weapon: WeaponPart) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := get_viewport().get_visible_rect().size / 2.0
	var ray_origin := cam.project_ray_origin(center)
	var ray_dir := cam.project_ray_normal(center)
	var dir := Vector3(ray_dir.x, 0.0, ray_dir.z).normalized()
	rotation.y = atan2(dir.x, dir.z)
	EffectManager.spawn_melee_trail(global_position + Vector3(0, 1.2, 0), dir,
		Color(0.9, 0.95, 1.0), Color(0.5, 0.7, 1.0), 1.0, 0.8)
	var hit := EffectManager.melee_hit_ray(self, dir, weapon.range_distance, 8 | 2, weapon.damage, "blunt")
	if hit and AudioManager:
		AudioManager.play_npc_melee_hit(global_position)


func _physics_process(delta: float) -> void:
	if GameManager.current_state != GameManager.State.EJECT:
		return
	var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam = get_viewport().get_camera_3d()
	if cam == null:
		return
	var forward = -cam.global_transform.basis.z
	var right = cam.global_transform.basis.x
	forward.y = 0.0
	forward = forward.normalized()
	right.y = 0.0
	right = right.normalized()

	# Sprint: Shift while moving. Drains pilot stamina (separate from the mech's
	# energy). Stamina regens while walking/standing; empty stamina = no sprint.
	var wants_sprint := Input.is_action_pressed("strafe") and input.length() > 0.1
	_is_sprinting = wants_sprint and stamina > 0.0
	if _is_sprinting:
		stamina = maxf(stamina - sprint_drain * delta, 0.0)
	else:
		stamina = minf(stamina + stamina_regen * delta, max_stamina)
	var speed := sprint_speed if _is_sprinting else move_speed

	var velocity_dir = (forward * -input.y + right * input.x)
	velocity.x = velocity_dir.x * speed
	velocity.z = velocity_dir.z * speed
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_force
	velocity.y -= gravity * delta
	move_and_slide()

	# Update boardable mech HUD prompt
	var nearby_mech := find_nearest_boardable_mech()
	if nearby_mech:
		var m_name: String = str(nearby_mech.get_meta("mech_name", nearby_mech.name))
		EventBus.interaction_prompt_updated.emit("[ F ] Board Mecha: %s" % m_name, true)
	else:
		EventBus.interaction_prompt_updated.emit("", false)


# Current stamina fraction 0..1 (for the pilot HUD).
func get_stamina_ratio() -> float:
	return clampf(stamina / maxf(max_stamina, 0.001), 0.0, 1.0)
