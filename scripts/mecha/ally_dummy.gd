extends CharacterBody3D

## Allied mech AI (our side). Fights alongside the player by chasing and
## engaging enemies (group "enemy"). Uses the shared enemy health system and
## archetype stat templates so it behaves like a friendly counterpart to the
## enemy grunts (GM vs Zaku).

@export var move_speed: float = 4.0
@export var attack_range: float = 60.0
@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 0.9

## Archetype: 0=Rusher melee, 1=Ranged, 2=Heavy, 3=Support
@export var archetype: int = 1

## Fleet roster template id used to resolve name/hp/color.
@export var template_id: String = ""

var target: Node3D = null
var attack_timer: float = 0.0
var strafe_timer: float = 0.0
var strafe_direction: float = 1.0
var scan_timer: float = 0.0
var health_system: Node = null
var template_color: Color = Color(0.3, 0.6, 0.9, 1)

## Pilot display name (from the ally template) shown on the combat HUD: the
## billboard name plate above the mech and the squad summary panel.
var display_name: String = "ALLY"

# Ammo for ranged archetypes. Ammo/reload state lives in a shared WeaponCore
# (same rules as the player's weapons); these fields feed the core's build and
# the getters delegate to it.
var max_ammo: int = 0
var reload_time: float = 3.0
var fire_core: WeaponCore = null

var is_reloading: bool:
	get:
		return fire_core != null and fire_core.reloading


func _ready() -> void:
	add_to_group("ally")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	health_system = $HealthSystem
	if template_id != "":
		_apply_template(GlobalData.get_ally_template(template_id))
	_init_ammo()
	_setup_enemy_status()
	health_system.mecha_destroyed.connect(_on_destroyed)
	health_system.armor_broken.connect(_on_armor_broken)
	# The HUD squad panel shows the pilot's live HP; keep it in sync.
	health_system.health_changed.connect(func(_s, _l, _c, _m): if is_instance_valid(self): _emit_squad_hp())


# Broadcasts this ally's live HP for the squad panel (and any other HUD that
# subscribes). Polled by the panel too, but the signal makes bars update the
# instant a hit lands instead of waiting for the next frame.
func _emit_squad_hp() -> void:
	if health_system == null:
		return
	EventBus.ally_squad_updated.emit({
		"template_id": template_id,
		"name": display_name,
		"health": SquadHud.live_health_percent(health_system),
		"destroyed": bool(health_system.get("is_destroyed")),
	})


# Applied by the spawner AFTER the template stats land (_ready): when an ally
# comes from a piloted hangar mech, the berth's combat role + the pilot's name
# win over the template defaults. Ammo is rebuilt because the ammo pool depends
# on the archetype (RANGED/HEAVY), which may have changed.
func apply_mech_override(archetype_override: int, name_override: String) -> void:
	archetype = clampi(archetype_override, 0, 3)
	display_name = name_override
	_init_ammo()
	_set_name_label(display_name)
	_setup_enemy_status()


# Applied by the spawner AFTER apply_mech_override: replaces the template stats
# with the hangar mech's ACTUAL loadout — the armor/frame plates it wears (with
# their persistent combat damage) and the weapons it carries. The ally then
# fights with the berth's real gear instead of generic template numbers.
func apply_mech_loadout(mech: Dictionary) -> void:
	if mech.is_empty():
		return
	_apply_mech_armor(mech)
	_apply_mech_weapons(mech)


# Writes the mech's equipped armor + inner frame HP (and any persistent damage)
# into the shared health system, exactly like the player mech reads its own
# loadout at combat start. Falls back to template/part defaults when a slot has
# no plate or the snapshot predates the field.
func _apply_mech_armor(mech: Dictionary) -> void:
	if health_system == null or not (health_system.parts is Dictionary):
		return
	var mech_parts: Dictionary = mech.get("parts", {})
	var mech_frames: Dictionary = mech.get("frames", {})
	var mech_damage: Dictionary = mech.get("damage", {})
	var mech_patches: Dictionary = mech.get("scrap_patches", {})
	for slot in health_system.parts:
		var part: Dictionary = health_system.parts[slot]
		# Inner frame HP (same formula as the player mech: frame hp + upgrade bonus).
		if mech_frames.has(slot):
			var f = SaveGameIO.resolve_frame_value(mech_frames[slot])
			if f is Dictionary:
				var f_hp = float(f.get("hp", part["max_frame"])) + GlobalData.get_frame_upgrade_hp_bonus()
				part["frame_hp"] = f_hp
				part["max_frame"] = f_hp
		# Outer armor HP + armor_class from the equipped plate (same rules as the
		# player mech's mecha_health.gd: dicts store "armor" as a class*10 value,
		# ArmorPart resources expose armor_class directly).
		if mech_parts.has(slot):
			var p = SaveGameIO.resolve_equipped_part(mech_parts[slot])
			if p != null:
				var p_hp: float = GlobalData.part_stat(p, "max_hp", 0.0)
				if p_hp > 0.0:
					part["armor_hp"] = p_hp
					part["max_armor"] = p_hp
				if p is Dictionary:
					if p.get("armor_class") != null:
						part["armor_class"] = maxf(float(p.armor_class), 0.1)
					elif p.get("armor") != null:
						part["armor_class"] = maxf(float(p.get("armor", 10.0)) / 10.0, 0.1)
				elif p is ArmorPart:
					part["armor_class"] = maxf(p.armor_class, 0.1)
		# Scrap emergency patch rebuilt this slot (mirror the player mech).
		if mech_patches.has(slot):
			var patch: Dictionary = mech_patches[slot]
			part["armor_hp"] = float(patch.get("scrap_armor_hp", part["max_armor"]))
			part["max_armor"] = part["armor_hp"]
			part["armor_class"] = float(patch.get("armor_class", part["armor_class"]))
			if float(mech_damage.get(slot + "_frame", 0.0)) >= 1.0:
				part["frame_hp"] = float(patch.get("scrap_frame_hp", part["max_frame"]))
				part["max_frame"] = part["frame_hp"]
			continue
		# Persistent damage ratios from previous battles ("slot" armor, "slot_frame" frame).
		var armor_dmg: float = float(mech_damage.get(slot, 0.0))
		if armor_dmg > 0.0:
			var lost: float = part["max_armor"] * clampf(armor_dmg, 0.0, 1.0)
			part["armor_hp"] = maxf(part["max_armor"] - lost, 0.0)
			if part["armor_hp"] <= 0.0:
				part["armor_broken"] = true
				part["armor_hp"] = 0.0
		var frame_dmg: float = float(mech_damage.get(slot + "_frame", 0.0))
		if frame_dmg > 0.0:
			var lost_f: float = part["max_frame"] * clampf(frame_dmg, 0.0, 1.0)
			part["frame_hp"] = maxf(part["max_frame"] - lost_f, 0.0)
			if part["frame_hp"] <= 0.0:
				part["destroyed"] = true
				part["frame_hp"] = 0.0
	if health_system.has_method("_calculate_totals"):
		health_system._calculate_totals()


# Builds attack stats + the WeaponCore from the mech's ACTUAL equipped weapon
# (right hand, then left, then back carry) instead of the template numbers:
# damage, range, fire rate, ammo and damage type all come from the weapon the
# berth really carries. Falls back to template stats when nothing is equipped.
func _apply_mech_weapons(mech: Dictionary) -> void:
	var weapon := _primary_mech_weapon(mech.get("weapon_loadout", {}))
	if weapon == null:
		return
	attack_damage = weapon.damage
	attack_range = maxf(weapon.range_distance, 8.0)
	attack_cooldown = maxf(weapon.get_fire_interval(), 0.25)
	max_ammo = weapon.max_ammo
	reload_time = maxf(2.0, weapon.max_ammo * 0.04)
	_build_fire_core_from_weapon(weapon)
	_mount_mech_weapon_visual(weapon, mech.get("weapon_loadout", {}))


# Picks the weapon the ally fights with. Preference order matches the hangar
# loadout (right hand, left hand, then back carry); a RUSHER berth prefers its
# melee blade, the other roles prefer a real gun.
func _primary_mech_weapon(loadout: Dictionary) -> WeaponPart:
	var paths: Array = []
	for key in ["right", "left"]:
		var p := str(loadout.get(key, ""))
		if p != "":
			paths.append(p)
	var carry = loadout.get("carry", [])
	if carry is Array:
		for p in carry:
			if p is String and p != "":
				paths.append(p)
	var prefer_melee: bool = archetype == 0
	var fallback: WeaponPart = null
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var w = load(path)
		if not (w is WeaponPart):
			continue
		var is_melee: bool = w.weapon_type == WeaponPart.WeaponType.MELEE
		if prefer_melee == is_melee:
			return w
		if fallback == null:
			fallback = w
	return fallback


# Builds the shared WeaponCore from the actual WeaponPart so the ally's shots
# (damage, ammo, reload, heat, pellets, damage type) behave like the player
# firing the same gun. Fire rate stays AI-paced (fire_interval = 0, the ally
# attack_timer gates shots).
func _build_fire_core_from_weapon(weapon: WeaponPart) -> void:
	fire_core = WeaponCore.from_weapon(weapon)
	fire_core.fire_interval = 0.0
	fire_core.reload_time = reload_time
	fire_core.projectile_color = template_color
	fire_core.unlimited_ammo = weapon.max_ammo <= 0
	fire_core.auto_reload = not fire_core.unlimited_ammo


# Mounts the equipped weapon's model on the ally's hand so the squad visibly
# carries the mech's actual gun (same factory the hangar + player mech use).
func _mount_mech_weapon_visual(weapon: WeaponPart, loadout: Dictionary) -> void:
	var hand := "right"
	if str(loadout.get("right", "")) != weapon.resource_path and str(loadout.get("left", "")) == weapon.resource_path:
		hand = "left"
	WeaponVisualFactory.mount_hand(self, hand, weapon, "AllyWeaponVisual")


func _apply_template(template: Dictionary) -> void:
	if template.is_empty():
		return
	move_speed = float(template.get("move_speed", move_speed))
	attack_range = float(template.get("attack_range", attack_range))
	attack_damage = float(template.get("attack_damage", attack_damage))
	attack_cooldown = float(template.get("attack_cooldown", attack_cooldown))
	archetype = int(template.get("archetype", archetype))
	template_color = template.get("color", template_color)
	_scale_to_template_hp(float(template.get("frame_hp", 55.0)))
	display_name = str(template.get("name", "ALLY"))
	_set_name_label(display_name)
	_apply_ally_color()


# Ranged/heavy allies need ammo, exactly like their enemy counterparts, or the
# "has_ammo" gate in _perform_attack blocks every shot and they stand there idle.
func _init_ammo() -> void:
	if archetype == 1:  # RANGED
		max_ammo = 25
		reload_time = 3.0
	elif archetype == 2:  # HEAVY
		max_ammo = 5
		reload_time = 4.0
	_build_fire_core()


# Scale all frame_hp values so the total matches the template's frame HP budget.
func _scale_to_template_hp(target_total: float) -> void:
	if health_system == null or not health_system.parts is Dictionary:
		return
	var current_total = 0.0
	for slot in health_system.parts:
		current_total += float(health_system.parts[slot]["max_frame"])
	if current_total <= 0.0:
		return
	var factor = target_total / current_total
	for slot in health_system.parts:
		var part = health_system.parts[slot]
		part["max_frame"] = part["max_frame"] * factor
		part["frame_hp"] = part["max_frame"]
	if health_system.has_method("_calculate_totals"):
		health_system._calculate_totals()


func _set_name_label(text: String) -> void:
	var label = get_node_or_null("NameLabel3D")
	if label:
		label.text = text


func _apply_ally_color() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.material_override:
			child.material_override.albedo_color = template_color
		for sub in child.get_children():
			if sub is MeshInstance3D and sub.material_override:
				sub.material_override.albedo_color = template_color


func _setup_enemy_status() -> void:
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("setup_target"):
		status.setup_target(self, display_name)


func _physics_process(delta: float) -> void:
	if health_system == null or health_system.get("is_destroyed"):
		velocity = Vector3.ZERO
		return

	# Staggered: freeze AI actions while the stumble plays out.
	if stagger_timer > 0.0:
		stagger_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, 25.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 25.0 * delta)
		move_and_slide()
		return

	if fire_core:
		fire_core.tick(delta)

	_acquire_target()
	if target == null:
		velocity.y -= 10.0 * delta
		move_and_slide()
		return

	var distance = global_position.distance_to(target.global_position)

	if distance > attack_range:
		_move_toward_target(delta)
	else:
		_strafe_and_attack(delta)


func _acquire_target() -> void:
	if target and is_instance_valid(target) and target.health_system and not target.health_system.is_destroyed:
		return
	target = null
	scan_timer -= get_physics_process_delta_time()
	if scan_timer > 0.0:
		return
	scan_timer = 0.5
	var enemies = get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0
	for e in enemies:
		if not is_instance_valid(e) or e.get("health_system") == null:
			continue
		if e.health_system.is_destroyed:
			continue
		var dist = global_position.distance_to(e.global_position)
		if dist < nearest_dist:
			nearest = e
			nearest_dist = dist
	target = nearest


func _move_toward_target(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	velocity = direction * move_speed
	velocity.y = -10.0
	move_and_slide()
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 5.0 * delta)


func _strafe_and_attack(delta: float) -> void:
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0.0
	if direction.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 8.0 * delta)

	strafe_timer += delta
	if strafe_timer > 2.0:
		strafe_timer = 0.0
		strafe_direction *= -1.0

	var strafe = global_transform.basis.x * strafe_direction * move_speed * 0.3
	velocity = strafe
	velocity.y = -10.0
	move_and_slide()

	attack_timer -= delta
	if attack_timer <= 0.0:
		attack_timer = attack_cooldown
		_perform_attack()


func _perform_attack() -> void:
	match archetype:
		0:  # RUSHER - melee swing (collision-based, see _perform_melee)
			_perform_melee()
		1, 2:  # RANGED / HEAVY - projectile
			if has_ammo():
				_fire_ranged()
		3:  # SUPPORT - heal nearest ally
			_heal_nearest_ally()


func _perform_melee() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir = target.global_position - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	rotation.y = atan2(dir.x, dir.z)
	# Positional swing voice (blade slash) so ally melee reads at range.
	if AudioManager:
		AudioManager.play_ally_melee_swing(global_position)
	# Shared melee FX + collision hit check (same rules as enemies and the player).
	EffectManager.spawn_melee_trail(global_position, dir, Color(0.5, 0.9, 1.0), Color(0.3, 0.7, 1.0))
	var hit := EffectManager.melee_hit_ray(self, dir, attack_range, 8 | 2, attack_damage)
	if hit and AudioManager:
		AudioManager.play_npc_melee_hit(global_position)


func _heal_nearest_ally() -> void:
	var allies = get_tree().get_nodes_in_group("ally")
	var nearest: Node3D = null
	var nearest_dist: float = 999.0
	for a in allies:
		if not is_instance_valid(a) or a == self:
			continue
		if a.get("health_system") == null or a.health_system.is_destroyed:
			continue
		var dist = global_position.distance_to(a.global_position)
		if dist < 40.0 and dist < nearest_dist:
			nearest = a
			nearest_dist = dist
	if nearest and nearest.health_system and nearest.health_system.has_method("take_heal"):
		nearest.health_system.take_heal(5.0)
		EffectManager.spawn_damage_number(nearest.global_position + Vector3(0, 3, 0), 5.0, Color(0.2, 1.0, 0.2))


func has_ammo() -> bool:
	return fire_core != null and (fire_core.unlimited_ammo or fire_core.ammo > 0)


# Builds the shared WeaponCore from the ally's template stats. Fire rate is
# paced by the ally AI (attack_timer), so the core's own cooldown is disabled
# (fire_interval = 0) — it owns ammo/reload/heat + projectile spawning.
func _build_fire_core() -> void:
	fire_core = WeaponCore.from_stats({
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"max_ammo": max_ammo,
		"reload_time": reload_time,
		"projectile_speed": 35.0,
		"damage_type": "kinetic",
		"projectile_color": template_color,
	})
	fire_core.fire_interval = 0.0


func _fire_ranged() -> void:
	var from_pos = global_position + Vector3(0, 2, 0)
	var to_pos = target.global_position + Vector3(0, 1.5, 0)

	var space_state = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = 2
	var result = space_state.intersect_ray(query)
	if result:
		var obstacle_dist = from_pos.distance_to(result["position"])
		var target_dist = from_pos.distance_to(to_pos)
		if obstacle_dist < target_dist * 0.8:
			return

	# Fire sound at the muzzle so the player can hear their ally fighting back.
	if AudioManager:
		AudioManager.play_sfx("machine_gun", from_pos, -8.0)

	var dir = (to_pos - from_pos).normalized()
	fire_core.try_fire(from_pos, dir, false, self)


func _on_destroyed() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	visible = false
	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)


func _on_armor_broken(slot_name: String) -> void:
	if slot_name == "body":
		if health_system:
			health_system.set("is_destroyed", true)
			if health_system.has_signal("mecha_destroyed"):
				health_system.mecha_destroyed.emit()
		EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if health_system:
		health_system.take_damage(amount, damage_type)


# Called when the ally eats an impact-heavy enemy shot. Brief stagger so hits
# feel real, mirroring the enemy behavior (enemy_dummy.apply_impact).
var stagger_timer: float = 0.0


func apply_impact(amount: float, from_dir: Vector3) -> void:
	stagger_timer = maxf(stagger_timer, clampf(0.25 + amount * 0.02, 0.3, 1.2))
	from_dir.y = 0.0
	if from_dir.length() > 0.001:
		var shove = from_dir.normalized() * minf(amount * 2.5, 9.0)
		velocity.x += shove.x
		velocity.z += shove.z
	attack_timer = maxf(attack_timer, 0.0)
