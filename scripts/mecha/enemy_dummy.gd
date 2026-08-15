extends CharacterBody3D

var _loot_script = preload("res://scripts/systems/loot_system.gd")

@export var move_speed: float = 3.0
@export var attack_range: float = 15.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 2.0

## Archetype: 0=Rusher, 1=Ranged, 2=Heavy, 3=Support
@export var archetype: int = 0

var target: Node3D = null
var attack_timer: float = 0.0
var health_system: Node = null
var state_machine: EnemyStateMachine

# Stagger from heavy impacts: briefly interrupts the enemy so it can't act.
var stagger_timer: float = 0.0

# --- Enemy energy pool -------------------------------------------------------
# Hostiles run on the SAME economy the player does: normal walking is nearly
# free, but a Rusher's dash burst costs a chunk of energy and the pool only
# recharges while the enemy isn't boosting. That keeps enemies from spamming
# dashes all fight — and when the tank runs dry the enemy breaks off and
# retreats to recharge instead of fighting on empty (see flee_reason).
var max_energy: float = 100.0
var energy: float = 100.0
const DASH_ENERGY_COST := 18.0        # energy per Rusher dash burst
const ATTACK_ENERGY_COST := 4.0       # energy per attack cycle (every archetype)
const ENERGY_REGEN_RATE := 9.0        # per second while not boosting
const LOW_ENERGY_THRESHOLD := 20.0    # below this the enemy withdraws to regen
const RECHARGED_ENERGY := 60.0        # flee ends once the pool is back above this

# Why the enemy is currently fleeing: "hp" (frame damage) or "energy" (drained
# pool). StateFlee reassesses differently per reason — an energy-fleeing enemy
# only re-engages after recharging, while a hurt one returns once patched up.
var flee_reason: String = ""

# Rusher dash burst (combat only — triggered from StateChase, never while
# patrolling). Movement is applied here in _physics_process so the state
# machine is paused for the burst's duration.
var is_dashing: bool = false
var dash_speed: float = 20.0
var dash_duration: float = 0.3
var dash_cooldown: float = 3.2
var dash_cooldown_timer: float = 0.0
var dash_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

# PartMeshManager that renders this enemy from the mech armor catalog.
var catalog_body: Node = null

# Faction paint assigned by SpawnManager before ready (see run theme enemy_org).
# Overrides the archetype palette so military squads share a uniform color while
# commanders flare their shoulder plates with the accent color.
var faction_paint: Dictionary = {}
# "commander" / "member" within a squad fire team ("" for ragtag units).
var squad_role: String = ""

# Concealment state: set by the arena concealment system when this enemy stands
# inside a cover footprint (tree/building). While concealed the mech + its name
# plate and health billboard are hidden so the player can't see it lurking.
var concealed: bool = false

# Ammo system for ranged enemies. Ammo/reload state lives in a shared
# WeaponCore (same rules as the player's weapons); these fields feed the core's
# from_stats() build and the getters below delegate to it.
var max_ammo: int = 0
var reload_time: float = 3.0
var fire_core: WeaponCore = null

var is_reloading: bool:
	get:
		return fire_core != null and fire_core.reloading

# Red telegraph flash: the state machine toggles this just before attacking so
# the player can read that a shot is coming. Original material overrides are
# cached on first flash and restored afterwards.
var _flash_original_materials: Dictionary = {}
var _flash_material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	health_system = $HealthSystem
	_setup_hitbox()
	_setup_enemy_status()
	health_system.mecha_destroyed.connect(_on_destroyed)
	health_system.armor_broken.connect(_on_armor_broken)
	_apply_catalog_health()
	_scale_by_wanted_level()
	_apply_archetype_stats()
	_build_catalog_body()
	_setup_leg_animation()
	_setup_state_machine()


# Writes the armor/frame HP of the loadout this enemy wears into its health
# system, so durability matches the plates the mech displays on screen. Slots
# the simple health system doesn't track (single-body capsule) are skipped.
# armor_class stays per-slot combat default (player's mecha fights the same way
# — its equipped dict carries no armor key), so balance is preserved.
func _apply_catalog_health() -> void:
	if health_system == null:
		return
	var loadout := _enemy_loadout()
	for slot in loadout:
		var part: Dictionary = health_system.parts.get(slot, {})
		if part.is_empty():
			continue
		var armor: Dictionary = loadout[slot].get("armor", {})
		if not armor.is_empty():
			var hp: float = float(armor.get("hp", part["max_armor"]))
			part["armor_hp"] = hp
			part["max_armor"] = hp
		var frame: Dictionary = loadout[slot].get("frame", {})
		if not frame.is_empty():
			var fp: float = float(frame.get("hp", part["max_frame"]))
			part["frame_hp"] = fp
			part["max_frame"] = fp
	health_system._calculate_totals()


# Assembles the enemy from the SAME mech armor catalog the player uses
# (GlobalData.armor_catalog / frame_catalog) so grunts look like real mechs
# instead of placeholder capsules. Per-archetype colors keep them readable.
func _build_catalog_body() -> void:
	if get_node_or_null("CatalogBody") != null:
		return
	_ensure_slot_nodes()
	var pmm = Node3D.new()
	pmm.name = "CatalogBody"
	pmm.set_script(preload("res://scripts/mecha/part_mesh_manager.gd"))
	catalog_body = pmm
	add_child(pmm)

	# Extra bulk for heavy grunts so the silhouette reads at a glance.
	if archetype == 2:
		pmm.scale = Vector3(1.6, 1.6, 1.6)
	elif archetype == 3:
		pmm.scale = Vector3(1.05, 1.05, 1.05)
	elif archetype == 0:
		pmm.scale = Vector3(0.95, 0.95, 0.95)

	var loadout := _enemy_loadout()
	pmm.refresh_from_loadout(loadout)

	# Placeholder scenes (capsule rusher) put their legacy mesh at the root, not
	# under a slot node, so slot hiding never touches it. Hide it explicitly.
	# Label3D is also a VisualInstance3D, so keep the name plates visible.
	for child in get_children():
		if child == pmm or child.name == "HealthSystem" or child is Area3D or child is CollisionShape3D:
			continue
		if child is MeshInstance3D or (child is VisualInstance3D and not child is Label3D):
			child.visible = false


# The PartMeshManager assembles meshes inside Head/Body/ArmLeft/... nodes.
# Placeholder scenes (e.g. the capsule rusher) may not ship those nodes, so we
# create matching ones (with the same offsets as real enemy scenes) if missing.
func _ensure_slot_nodes() -> void:
	var slot_positions := {
		"Head": Vector3(0, 2.2, 0),
		"Body": Vector3(0, 1.3, 0),
		"ArmLeft": Vector3(-0.75, 1.3, 0),
		"ArmRight": Vector3(0.75, 1.3, 0),
		"LegLeft": Vector3(-0.35, 0.6, 0),
		"LegRight": Vector3(0.35, 0.6, 0),
	}
	for name in slot_positions:
		if get_node_or_null(name) != null:
			continue
		var slot_node := Node3D.new()
		slot_node.name = name
		slot_node.position = slot_positions[name]
		add_child(slot_node)

	# Lower-joint containers (Forearm/Shin) must exist too or the catalog
	# builder has nowhere to mount the elbow/knee segments.
	var lower_parent_names: Array[String] = [
		"ArmLeft/ForearmLeft",
		"ArmRight/ForearmRight",
		"LegLeft/ShinLeft",
		"LegRight/ShinRight",
	]
	var lower_offsets := {
		"ArmLeft/ForearmLeft": Vector3(0, -0.38, 0),
		"ArmRight/ForearmRight": Vector3(0, -0.38, 0),
		"LegLeft/ShinLeft": Vector3(0, -0.55, 0),
		"LegRight/ShinRight": Vector3(0, -0.55, 0),
	}
	for node_path in lower_parent_names:
		if get_node_or_null(node_path) != null:
			continue
		var parts_path: PackedStringArray = node_path.split("/")
		var lower := Node3D.new()
		lower.name = parts_path[1]
		lower.position = lower_offsets[node_path]
		get_node(parts_path[0]).add_child(lower)


# Picks a per-slot frame + armor entry from the catalogs and applies the
# archetype's faction color so each enemy variety remains visually distinct.
# Durability tiers follow the archetype: Heavy gets the bulkiest non-blueprint
# plates/frames (so its HP matches its 1.6x silhouette), faster archetypes stay
# light. Blueprint-only tiers (Gundam etc.) are never worn by grunts.
func _enemy_loadout() -> Dictionary:
	var palette := _archetype_palette()
	var wants_heavy := archetype == 2
	var loadout: Dictionary = {}
	for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
		var frame_entry: Dictionary = {}
		var frames = GlobalData.frame_catalog.get(slot, [])
		var eligible_frames: Array = []
		if frames is Array:
			for entry in frames:
				if entry is Dictionary and not _is_blueprint_frame(entry):
					eligible_frames.append(entry)
		if eligible_frames.size() > 0:
			var f_idx: int = clampi(_archetype_frame_index(), 0, eligible_frames.size() - 1)
			frame_entry = (eligible_frames[f_idx] as Dictionary).duplicate(true)

		var armor_entry: Dictionary = {}
		var eligible: Array = []
		var armors = GlobalData.armor_catalog.get(slot, [])
		if armors is Array:
			for entry in armors:
				if not entry.get("blueprint_only", false):
					eligible.append(entry as Dictionary)
		if eligible.size() > 0:
			# Heaviest grunt wears the most durable plate; faster archetypes the
			# lightest. Picking by HP is safer than by index (catalog order isn't
			# always worst->best, e.g. head_002 is a light recon helmet).
			armor_entry = _pick_armor_by_tier(eligible, wants_heavy).duplicate(true)
		if not armor_entry.is_empty():
			armor_entry["equipped"] = true
			armor_entry["color"] = palette.get(slot, palette.get("default", Color(0.7, 0.15, 0.15)))

		loadout[slot] = {"frame": frame_entry, "armor": armor_entry}
	return loadout


# Blueprint-only catalog entries (Gundam tier) must never be worn by grunts.
# Armor carries an explicit `blueprint_only` flag; frames mark the tier via the
# `type` field instead, so detect it by name.
func _is_blueprint_frame(entry: Dictionary) -> bool:
	return str(entry.get("type", "")).contains("Gundam")


# Frame durability tier per archetype. frame_catalog[slot] is ordered
# [standard, gundam, medium, heavy]; the Gundam tier is filtered out above,
# leaving [standard, medium, heavy] to index into.
func _archetype_frame_index() -> int:
	match archetype:
		1:
			return 1  # Ranged: medium (slightly sturdier than a Rusher)
		2:
			return 2  # Heavy: heaviest non-blueprint frame
		3:
			return 1  # Support: medium
		_:
			return 0  # Rusher: lightest


# Returns the armor entry with the greatest (heavy) or smallest (light) HP
# among the non-blueprint plates a slot has available.
func _pick_armor_by_tier(eligible: Array, heaviest: bool) -> Dictionary:
	var best := eligible[0] as Dictionary
	for entry in eligible:
		var hp: float = float(entry.get("hp", 0.0))
		var best_hp: float = float(best.get("hp", 0.0))
		if heaviest and hp > best_hp:
			best = entry
		elif not heaviest and hp < best_hp:
			best = entry
	return best


func _archetype_palette() -> Dictionary:
	# Faction paint from the run theme wins when present. A squad commander keeps
	# the base color everywhere except its head visor and shoulder plates, which
	# flare with the accent (e.g. a red-shouldered officer).
	if not faction_paint.is_empty():
		var base: Color = faction_paint.get("base", Color(0.6, 0.6, 0.6))
		var accent: Color = faction_paint.get("accent", base)
		var trim: Color = faction_paint.get("trim", base)
		var is_commander := squad_role == "commander"
		return {
			"default": base,
			"head": accent if is_commander else trim,
			"arm_left": accent if is_commander else base,
			"arm_right": accent if is_commander else base,
		}
	match archetype:
		1:
			return {"default": Color(0.25, 0.55, 0.8), "head": Color(0.2, 0.5, 0.75)}
		2:
			return {"default": Color(0.65, 0.15, 0.2), "head": Color(0.75, 0.2, 0.15)}
		3:
			return {"default": Color(0.75, 0.65, 0.2), "head": Color(0.8, 0.7, 0.25)}
		_:
			return {"default": Color(0.75, 0.2, 0.2), "head": Color(0.85, 0.25, 0.25)}


# Attaches the SAME animation script the player's mech uses (mecha_animation.gd)
# so enemies move with the identical stride, bob and idle combat stance instead
# of a separate implementation. Runs after _build_catalog_body so the
# Head/Body/Leg*/Shin* slot nodes exist to drive.
func _setup_leg_animation() -> void:
	if get_node_or_null("EnemyAnimation") != null:
		return
	var anim := Node.new()
	anim.name = "EnemyAnimation"
	anim.set_script(preload("res://scripts/mecha/mecha_animation.gd"))
	add_child(anim)


func _setup_state_machine() -> void:
	state_machine = EnemyStateMachine.new()
	state_machine.name = "StateMachine"
	add_child(state_machine)

	# Create all states
	var idle = EnemyState.new()
	idle.name = "StateIdle"
	idle.set_script(preload("res://scripts/mecha/ai/states/state_idle.gd"))
	state_machine.add_child(idle)

	var chase = EnemyState.new()
	chase.name = "StateChase"
	chase.set_script(preload("res://scripts/mecha/ai/states/state_chase.gd"))
	state_machine.add_child(chase)

	var attack = EnemyState.new()
	attack.name = "StateAttack"
	attack.set_script(preload("res://scripts/mecha/ai/states/state_attack.gd"))
	state_machine.add_child(attack)

	var flee = EnemyState.new()
	flee.name = "StateFlee"
	flee.set_script(preload("res://scripts/mecha/ai/states/state_flee.gd"))
	state_machine.add_child(flee)

	# Ranged-only states
	if archetype == 1:  # RANGED
		var strafe = EnemyState.new()
		strafe.name = "StateStrafe"
		strafe.set_script(preload("res://scripts/mecha/ai/states/state_strafe.gd"))
		state_machine.add_child(strafe)

	if archetype == 2:  # HEAVY
		var charge = EnemyState.new()
		charge.name = "StateCharge"
		charge.set_script(preload("res://scripts/mecha/ai/states/state_charge.gd"))
		state_machine.add_child(charge)

	# Start in idle
	state_machine.initialize_states()
	state_machine.transition_to("StateIdle")


func _apply_archetype_stats() -> void:
	var stats = EnemyAttackTemplates.get_stats(archetype)
	if stats.is_empty():
		return
	move_speed = stats["move_speed"]
	attack_range = stats["attack_range"]
	attack_damage = stats["attack_damage"]
	attack_cooldown = stats["attack_cooldown"]

	# Set ammo for ranged types
	if archetype == 1:  # RANGED
		max_ammo = 25
		reload_time = 3.0
	elif archetype == 2:  # HEAVY (charge uses stamina-like ammo)
		max_ammo = 5
		reload_time = 4.0
	_build_fire_core()


func has_ammo() -> bool:
	return fire_core != null and (fire_core.unlimited_ammo or fire_core.ammo > 0)


# Builds the shared WeaponCore from the archetype's attack stats. Fire rate is
# paced by the AI state machine (attack_timer), so the core's own cooldown is
# disabled (fire_interval = 0) — it owns ammo/reload/heat + projectile spawning.
func _build_fire_core() -> void:
	var color := Color(1.0, 0.35, 0.2)
	match archetype:
		0: color = Color(1.0, 0.55, 0.2)   # Rusher: orange
		2: color = Color(0.9, 0.25, 0.25)  # Heavy: red
		3: color = Color(0.6, 0.85, 0.35)  # Support: lime
	fire_core = WeaponCore.from_stats({
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"max_ammo": max_ammo,
		"reload_time": reload_time,
		"projectile_speed": 30.0,
		"damage_type": "kinetic",
		"projectile_color": color,
	})
	fire_core.fire_interval = 0.0


func _process(delta: float) -> void:
	if fire_core:
		fire_core.tick(delta)
	# Recharge the pool whenever the enemy isn't mid-dash. The cost is charged
	# up front in start_dash(), so an enemy that never boosts stays topped up.
	if not is_dashing:
		energy = minf(energy + ENERGY_REGEN_RATE * delta, max_energy)


func _on_destroyed() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	visible = false

	# Spawn loot
	var loot = get_node_or_null("/root/GameWorld/LootSystem")
	if loot == null:
		loot = Node3D.new()
		loot.set_script(_loot_script)
		loot.name = "LootSystem"
		get_tree().current_scene.add_child(loot)
	loot.spawn_enemy_loot(global_position, archetype)

	var spawn_mgr = get_node_or_null("/root/GameWorld/SpawnManager")
	if spawn_mgr and spawn_mgr.has_method("notify_enemy_killed"):
		spawn_mgr.notify_enemy_killed()
	else:
		_check_fallback_victory()

	var tween = create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(queue_free)


func _check_fallback_victory() -> void:
	var enemies = get_tree().get_nodes_in_group("enemy")
	var alive = 0
	for e in enemies:
		if is_instance_valid(e) and e != self and e.get("health_system") != null:
			var hs = e.health_system
			if not hs.get("is_destroyed"):
				alive += 1
	if alive == 0:
		EventBus.combat_ended.emit(true)



func _on_armor_broken(slot_name: String) -> void:
	if slot_name == "body":
		if health_system:
			health_system.set("is_destroyed", true)
			if health_system.has_signal("mecha_destroyed"):
				health_system.mecha_destroyed.emit()
		EffectManager.spawn_explosion(global_position + Vector3(0, 1.5, 0))


func _setup_hitbox() -> void:
	var hitbox = $Hitbox
	if hitbox and hitbox.has_method("set_health_system"):
		hitbox.set_health_system(health_system)


func _setup_enemy_status() -> void:
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("setup_target"):
		status.setup_target(self)


# Hides/shows the whole enemy from the player. Concealed enemies (standing in a
# cover footprint) are visually removed along with their name plate and health
# billboard, so the player can't tell a hostile is lurking there.
func set_concealed(on: bool) -> void:
	if concealed == on:
		return
	concealed = on
	visible = not on
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("set_concealed"):
		status.set_concealed(on)


# Toggles a red emissive flash across every rendered mesh of the enemy. Used as
# the pre-attack telegraph so the player can tell which hostile is about to fire.
# The first call caches each mesh's original material_override so the flash can
# be removed cleanly (the original never gets overwritten).
func set_attack_flash(on: bool) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.albedo_color = Color(1.0, 0.12, 0.05)
		_flash_material.emission_enabled = true
		_flash_material.emission = Color(1.0, 0.15, 0.06)
		_flash_material.emission_energy_multiplier = 4.0
		_flash_material.metallic = 0.3
		_flash_material.roughness = 0.4

	var meshes := _flash_meshes()
	if on:
		for m in meshes:
			if not _flash_original_materials.has(m):
				_flash_original_materials[m] = m.material_override
			m.material_override = _flash_material
	else:
		for m in meshes:
			if _flash_original_materials.has(m):
				m.material_override = _flash_original_materials[m]
				_flash_original_materials.erase(m)


# Collects every MeshInstance3D on the enemy body (catalog meshes and any legacy
# primitive meshes), skipping the status Label3D and the health/hitbox internals.
func _flash_meshes() -> Array:
	var result: Array = []
	for child in get_children():
		_collect_flash_meshes(child, result)
	return result


func _collect_flash_meshes(node: Node, into: Array) -> void:
	if node is MeshInstance3D:
		into.append(node)
	# Don't recurse into the health/hitbox logic nodes or the status billboard.
	if node is Area3D or node is CollisionShape3D or node is Label3D:
		return
	for child in node.get_children():
		_collect_flash_meshes(child, into)


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

	# Mid-dash: the burst owns movement for its short duration (the state
	# machine is paused so the enemy can't act while boosting). Costs are
	# charged up front by start_dash(); regen resumes once the burst ends.
	if is_dashing:
		dash_timer -= delta
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		velocity.y = -10.0
		move_and_slide()
		if dash_direction.length() > 0.1:
			rotation.y = lerp_angle(rotation.y, atan2(dash_direction.x, dash_direction.z), 10.0 * delta)
		if dash_timer <= 0.0:
			is_dashing = false
		return

	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)

	# Delegate to state machine
	if state_machine:
		state_machine._physics_process(delta)


# Called by the player's weapons when they land an impact-heavy hit. Stall the
# current action: interrupt the attack briefly (stagger) and shove the enemy.
# --- Rusher dash ------------------------------------------------------------
# Only the Rusher archetype lunges; the burst costs a chunk of the energy pool
# so a rusher can't dash forever. Returns false when the pool/cooldown isn't
# ready so callers fall back to plain pursuit.
func start_dash(dir: Vector3) -> bool:
	if archetype != 0:
		return false
	if energy < DASH_ENERGY_COST or dash_cooldown_timer > 0.0 or is_dashing:
		return false
	dash_direction = dir.normalized()
	dash_direction.y = 0.0
	if dash_direction.length() < 0.05:
		dash_direction = -transform.basis.z
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	energy = maxf(energy - DASH_ENERGY_COST, 0.0)
	if AudioManager:
		AudioManager.play_dash(global_position)
	return true


# True when the pool is too drained to keep fighting — the enemy should break
# off and withdraw to recharge (see StateFlee).
func is_low_energy() -> bool:
	return energy < LOW_ENERGY_THRESHOLD


func apply_impact(amount: float, from_dir: Vector3) -> void:
	stagger_timer = maxf(stagger_timer, clampf(0.25 + amount * 0.02, 0.3, 1.2))
	from_dir.y = 0.0
	if from_dir.length() > 0.001:
		var shove = from_dir.normalized() * minf(amount * 2.5, 9.0)
		velocity.x += shove.x
		velocity.z += shove.z
	if state_machine:
		var attack_state = state_machine.get_node_or_null("StateAttack")
		if attack_state and attack_state.get("attack_timer") != null and attack_state.attack_timer > 0.0:
			attack_state.attack_timer = maxf(0.0, attack_state.attack_timer - amount * 0.25)



func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if health_system:
		health_system.take_damage(amount, damage_type)


func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if health_system == null:
		return

	var local_pos = to_local(world_pos)
	var target_part = _determine_hit_part(local_pos)

	# Fallback if part doesn't exist in this enemy's health system
	if not health_system.parts.has(target_part):
		target_part = _find_alive_part()
		if target_part == "":
			return

	if health_system.parts[target_part]["destroyed"]:
		target_part = _find_alive_part()
		if target_part == "":
			return

	if health_system.has_method("take_damage_to_part_at"):
		health_system.take_damage_to_part_at(target_part, amount, world_pos, damage_type)
	else:
		health_system.take_damage_to_part(target_part, amount, damage_type)


func _find_alive_part() -> String:
	for slot in health_system.parts:
		if not health_system.parts[slot]["destroyed"]:
			return slot
	return ""


func _determine_hit_part(local_pos: Vector3) -> String:
	if local_pos.y > 2.0:
		return "head"
	elif local_pos.y > 0.5:
		if local_pos.x < -0.3:
			return "arm_left"
		elif local_pos.x > 0.3:
			return "arm_right"
		else:
			return "body"
	else:
		if local_pos.x < 0.0:
			return "leg_left"
		else:
			return "leg_right"


func _scale_by_wanted_level() -> void:
	var wanted = GlobalData.wanted_level
	if wanted <= 0:
		return

	var scale_factor = 1.0 + (wanted * 0.15)  # Revised: +15% per wanted level
	move_speed *= scale_factor
	attack_damage *= scale_factor
	attack_cooldown /= scale_factor

	# HP scaling is handled by SpawnManager (wanted + grunt multiplier) after
	# ready; scaling it here too would double-dip and inflate durability
	# quadratically at high wanted levels.

	# Visual feedback
	if wanted >= 3:
		_apply_archetype_color()


func _apply_archetype_color() -> void:
	var color: Color
	if not faction_paint.is_empty():
		color = faction_paint.get("base", Color(0.8, 0.2, 0.2, 1))
	else:
		match archetype:
			0: color = Color(0.55, 0.27, 0.07, 1)   # Rusher: dark orange
			1: color = Color(0.27, 0.51, 0.71, 1)    # Ranged: steel blue
			2: color = Color(0.55, 0.0, 0.0, 1)      # Heavy: dark red
			3: color = Color(0.33, 0.42, 0.18, 1)    # Support: olive green
			_: color = Color(0.8, 0.2, 0.2, 1)

	# Apply to all MeshInstance3D children
	for child in get_children():
		if child is MeshInstance3D and child.material_override:
			child.material_override.albedo_color = color
		for sub in child.get_children():
			if sub is MeshInstance3D and sub.material_override:
				sub.material_override.albedo_color = color


func get_attack_aim_direction(player_pos: Vector3) -> Vector3:
	var base_dir = (player_pos - global_position).normalized()
	
	# ตรวจหาว่าหัวศัตรูโดนทำลายไปแล้วหรือยัง
	var is_head_broken = false
	if health_system and health_system.has_method("is_part_destroyed"):
		is_head_broken = health_system.is_part_destroyed("head")
	elif health_system and health_system.get("parts") != null and health_system.parts.has("head"):
		is_head_broken = health_system.parts["head"].get("destroyed", false)
		
	if is_head_broken:
		# หัวหัก/หัวหลุด: สาดกระสุนกระเจิง ส่ายเบี้ยวออกทิศทางเดิมอย่างรุนแรง (Precision Penalty)
		var spread_angle = randf_range(-0.35, 0.35) # ส่ายเกือบ 20 องศา
		var offset = Vector3(
			sin(spread_angle),
			randf_range(-0.1, 0.1),
			cos(spread_angle) - 1.0
		)
		return (base_dir + offset).normalized()
	else:
		# สภาพปกติ: ยิงปืนนิ่งตามความสามารถเกรดหุ่น (มีจังหวะยิงเป็นเซ็ต Burst หลบง่าย)
		return base_dir
