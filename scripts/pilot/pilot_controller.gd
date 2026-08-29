extends CharacterBody3D

const MechaEject = preload("res://scripts/mecha/mecha_eject.gd")

@export var move_speed: float = 5.0
@export var jump_force: float = 4.5

var gravity := 20.0

# Sprint + stamina system
@export var sprint_speed: float = 8.2
@export var max_stamina: float = 100.0
@export var sprint_drain: float = 22.0
@export var stamina_regen: float = 14.0

var stamina: float = 100.0
var _is_sprinting: bool = false

# Pilot personal weapons
var _weapons: Array = []
var _weapon_index: int = 0
var _fire_core: WeaponCore = null
var _fire_timer: float = 0.0
var _weapon_mesh: Node3D = null
var _human_visual: Node3D = null

# TPS Magazine & Reload System
var current_magazine: int = 0
var is_reloading: bool = false
var reload_timer: float = 0.0
var reload_duration: float = 1.8
var _orig_weapon_pos: Vector3 = Vector3(0.28, 1.00, -0.20)
var _orig_weapon_rot: Vector3 = Vector3(0, 0, -0.15)


func _ready() -> void:
	add_to_group("pilot")
	_build_tactical_human_mesh()
	_weapons = PilotSystem.get_weapons()
	if not _weapons.is_empty():
		_equip_weapon(0)
	_rebuild_weapon_mesh()


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if amount <= 0.0 or PilotSystem.is_dead():
		return
	PilotSystem.take_damage(amount)
	EffectManager.spawn_damage_number(global_position + Vector3(0, 1.6, 0), amount, Color(1.0, 0.4, 0.3))
	if AudioManager:
		AudioManager.play_impact_by_type(damage_type, global_position)
	if PilotSystem.is_dead():
		_die()


func _die() -> void:
	if GameManager.current_state == GameManager.State.EJECT:
		GlobalData.board.run_notice = "Your pilot was shot and killed. The run ends here."
		EventBus.combat_ended.emit(false)


func get_max_magazine() -> int:
	if _weapons.is_empty():
		return 0
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		return 999
	var n := weapon.weapon_name.to_lower()
	if "pistol" in n: return 12
	if "assault" in n or "rifle" in n or "carbine" in n: return 30
	if "anti_tank" in n or "sniper" in n: return 5
	if "bazooka" in n or "missile" in n: return 1
	return maxi(weapon.max_ammo, 15)


func get_reload_duration() -> float:
	if _weapons.is_empty():
		return 1.8
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	var n := weapon.weapon_name.to_lower()
	if "pistol" in n: return 1.2
	if "assault" in n or "rifle" in n: return 1.8
	if "anti_tank" in n or "sniper" in n: return 2.4
	if "bazooka" in n or "missile" in n: return 2.8
	return 1.8


func get_reserve_ammo() -> int:
	if _weapons.is_empty():
		return 0
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	var ammo_type := weapon.get_ammo_type()
	if ammo_type == "none" or weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		return 999
	return PilotSystem.get_ammo(ammo_type)


func get_current_magazine() -> int:
	return current_magazine


func is_currently_reloading() -> bool:
	return is_reloading


func get_reload_progress() -> float:
	if not is_reloading or reload_duration <= 0.0:
		return 0.0
	return clampf(reload_timer / reload_duration, 0.0, 1.0)


func _equip_weapon(index: int) -> void:
	if _weapons.is_empty():
		_weapon_index = 0
		_fire_core = null
		current_magazine = 0
		return
	is_reloading = false
	reload_timer = 0.0
	_weapon_index = posmod(index, _weapons.size())
	var weapon: WeaponPart = _weapons[_weapon_index]
	_fire_core = WeaponCore.from_weapon(weapon)
	_fire_core.fire_interval = 0.0
	_fire_core.auto_reload = false
	_fire_core.manual_reload = true
	_fire_core.unlimited_ammo = weapon.max_ammo <= 0

	var max_mag := get_max_magazine()
	current_magazine = mini(max_mag, get_reserve_ammo())
	_rebuild_weapon_mesh()


func _rebuild_weapon_mesh() -> void:
	if _weapon_mesh and is_instance_valid(_weapon_mesh):
		_weapon_mesh.queue_free()
	_weapon_mesh = null
	if _weapons.is_empty():
		return
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	_weapon_mesh = Node3D.new()
	_weapon_mesh.name = "PilotWeaponMesh"
	_weapon_mesh.add_child(WeaponVisualFactory.build_pilot_weapon(weapon))

	var is_pistol := weapon.weapon_name.to_lower().contains("pistol")
	if is_pistol:
		_orig_weapon_pos = Vector3(0.24, 1.02, -0.22)
		_orig_weapon_rot = Vector3(0, 0, -0.08)
	else:
		_orig_weapon_pos = Vector3(0.26, 0.98, -0.18)
		_orig_weapon_rot = Vector3(0, 0, -0.15)

	_weapon_mesh.position = _orig_weapon_pos
	_weapon_mesh.rotation = _orig_weapon_rot
	add_child(_weapon_mesh)


func _build_tactical_human_mesh() -> void:
	# Hide default placeholder capsule mesh
	var placeholder := get_node_or_null("BodyMesh")
	if placeholder:
		placeholder.visible = false

	if _human_visual and is_instance_valid(_human_visual):
		_human_visual.queue_free()

	_human_visual = Node3D.new()
	_human_visual.name = "TacticalHumanVisual"

	var suit_mat = StandardMaterial3D.new()
	suit_mat.albedo_color = Color(0.18, 0.24, 0.28) # Tactical Slate / Navy
	suit_mat.roughness = 0.65

	var armor_mat = StandardMaterial3D.new()
	armor_mat.albedo_color = Color(0.12, 0.16, 0.20) # Armored plating
	armor_mat.metallic = 0.4
	armor_mat.roughness = 0.35

	var visor_mat = StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.1, 0.85, 0.95) # Glowing Cyan Visor
	visor_mat.emission_enabled = true
	visor_mat.emission = Color(0.1, 0.85, 0.95)
	visor_mat.emission_energy_multiplier = 3.5

	# Head & Tactical Helmet (Realistic 1.80m human - head top ~1.78m)
	var head_mesh = MeshInstance3D.new()
	var head_sphere = SphereMesh.new()
	head_sphere.radius = 0.13
	head_sphere.height = 0.24
	head_mesh.mesh = head_sphere
	head_mesh.position = Vector3(0, 1.66, 0)
	head_mesh.set_surface_override_material(0, armor_mat)
	_human_visual.add_child(head_mesh)

	# Visor HUD
	var visor_mesh = MeshInstance3D.new()
	var visor_box = BoxMesh.new()
	visor_box.size = Vector3(0.16, 0.06, 0.08)
	visor_mesh.mesh = visor_box
	visor_mesh.position = Vector3(0, 1.67, -0.10)
	visor_mesh.set_surface_override_material(0, visor_mat)
	_human_visual.add_child(visor_mesh)

	# Torso Tactical Vest (Chest 1.22m, size 0.46 -> top 1.45 bottom 0.99)
	var torso_mesh = MeshInstance3D.new()
	var torso_box = BoxMesh.new()
	torso_box.size = Vector3(0.36, 0.46, 0.22)
	torso_mesh.mesh = torso_box
	torso_mesh.position = Vector3(0, 1.22, 0)
	torso_mesh.set_surface_override_material(0, armor_mat)
	_human_visual.add_child(torso_mesh)

	# Utility Belt (waist 0.96)
	var belt_mesh = MeshInstance3D.new()
	var belt_box = BoxMesh.new()
	belt_box.size = Vector3(0.38, 0.08, 0.24)
	belt_mesh.mesh = belt_box
	belt_mesh.position = Vector3(0, 0.96, 0)
	belt_mesh.set_surface_override_material(0, suit_mat)
	_human_visual.add_child(belt_mesh)

	# Left & Right Legs - realistic 0.82m thigh+shin, continuous to boots
	for side in [-1.0, 1.0]:
		var leg_mesh = MeshInstance3D.new()
		var leg_cyl = CylinderMesh.new()
		leg_cyl.top_radius = 0.075
		leg_cyl.bottom_radius = 0.065
		leg_cyl.height = 0.82
		leg_mesh.mesh = leg_cyl
		leg_mesh.position = Vector3(side * 0.11, 0.56, 0)
		leg_mesh.set_surface_override_material(0, suit_mat)
		_human_visual.add_child(leg_mesh)

		# Combat Boots - sole at ground 0, top 0.14, seamless with leg bottom (0.15)
		var boot_mesh = MeshInstance3D.new()
		var boot_box = BoxMesh.new()
		boot_box.size = Vector3(0.10, 0.14, 0.20)
		boot_mesh.mesh = boot_box
		boot_mesh.position = Vector3(side * 0.11, 0.07, -0.02)
		boot_mesh.set_surface_override_material(0, armor_mat)
		_human_visual.add_child(boot_mesh)

		# Arms - realistic 0.52m upper+forearm
		var arm_mesh = MeshInstance3D.new()
		var arm_cyl = CylinderMesh.new()
		arm_cyl.top_radius = 0.06
		arm_cyl.bottom_radius = 0.05
		arm_cyl.height = 0.52
		arm_mesh.mesh = arm_cyl
		arm_mesh.position = Vector3(side * 0.24, 1.18, -0.04)
		arm_mesh.rotation = Vector3(0.15, 0, side * -0.1)
		arm_mesh.set_surface_override_material(0, suit_mat)
		_human_visual.add_child(arm_mesh)

	add_child(_human_visual)


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

	# Reload Input ([R] key or reload action)
	if (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_R or event.physical_keycode == KEY_R)) or (InputMap.has_action("reload") and event.is_action_pressed("reload")):
		get_viewport().set_input_as_handled()
		start_reload()
		return

	if event.is_action_pressed("fire_left") or event.is_action_pressed("fire_right"):
		_try_fire()
	elif event.is_action_pressed("weapon_left") or event.is_action_pressed("weapon_right"):
		if _weapons.size() > 1:
			_equip_weapon(_weapon_index + 1)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed and _weapons.size() > 1:
			_equip_weapon(_weapon_index + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed and _weapons.size() > 1:
			_equip_weapon(_weapon_index - 1)


func start_reload() -> void:
	if _weapons.is_empty() or is_reloading:
		return
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	if weapon.weapon_type == WeaponPart.WeaponType.MELEE:
		return
	var max_mag := get_max_magazine()
	if current_magazine >= max_mag:
		return # Magazine already full
	if get_reserve_ammo() <= 0:
		return # No reserve ammo available

	is_reloading = true
	reload_duration = get_reload_duration()
	reload_timer = 0.0

	# Tactical weapon dipping animation during reload
	if _weapon_mesh and is_instance_valid(_weapon_mesh):
		var tw = create_tween()
		tw.tween_property(_weapon_mesh, "position", _orig_weapon_pos + Vector3(0.0, -0.15, 0.05), 0.25)
		tw.parallel().tween_property(_weapon_mesh, "rotation", _orig_weapon_rot + Vector3(0.3, 0.2, 0.0), 0.25)


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
				continue
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
		_melee_swing(weapon)
		return

	if is_reloading:
		return # Cannot shoot while reloading

	# Magazine check
	if current_magazine <= 0:
		start_reload()
		return

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
		current_magazine = maxi(current_magazine - weapon.ammo_per_shot, 0)
		if AudioManager:
			AudioManager.play_sfx("machine_gun", muzzle, -8.0)
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
	# Handle reload timer progression
	if is_reloading:
		reload_timer += delta
		if reload_timer >= reload_duration:
			_finish_reload()

	if GameManager.current_state != GameManager.State.EJECT and not has_meta("test_mode"):
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


func _finish_reload() -> void:
	is_reloading = false
	reload_timer = 0.0
	if _weapons.is_empty():
		return
	var weapon: WeaponPart = _weapons[_weapon_index % _weapons.size()]
	var ammo_type := weapon.get_ammo_type()
	var needed := get_max_magazine() - current_magazine
	var available := PilotSystem.get_ammo(ammo_type) if ammo_type != "none" else 999
	var to_load := mini(needed, available)
	if ammo_type != "none":
		PilotSystem.consume_ammo(ammo_type, to_load)
	current_magazine += to_load

	# Snap weapon back to aim stance
	if _weapon_mesh and is_instance_valid(_weapon_mesh):
		var tw = create_tween()
		tw.tween_property(_weapon_mesh, "position", _orig_weapon_pos, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(_weapon_mesh, "rotation", _orig_weapon_rot, 0.15)


func get_stamina_ratio() -> float:
	return clampf(stamina / maxf(max_stamina, 0.001), 0.0, 1.0)
