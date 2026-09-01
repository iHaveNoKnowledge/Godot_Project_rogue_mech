extends CharacterBody3D

var _loot_script = preload("res://scripts/systems/loot_system.gd")

@export var move_speed: float = 3.0
@export var attack_range: float = 15.0
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 2.0

## Archetype: 0=Rusher, 1=Ranged, 2=Heavy, 3=Support,
## 4=ShieldMelee (โล่+ดาบ), 5=ShieldRanged (โล่+ปืน)
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
# Per-archetype economy, set by _apply_energy_tuning() (the defaults are the
# neutral starting point before archetype stats are applied):
#   rusher  — burns hard on dashes/swings, recharges fast, makes SHORT fast
#             withdrawals and comes right back (brawler pacing)
#   ranged  — sustained fire outpaces regen, so it pulls out EARLY to keep
#             distance and only returns once the pool is truly full
#   heavy   — very efficient (charge is the only real drain), rarely runs dry,
#             but a retreating heavy is SLOW and easy to punish
#   support — heals are cheap, stays in the fight
var dash_energy_cost: float = 18.0        # energy per Rusher dash burst
var attack_energy_cost: float = 4.0       # energy per attack cycle
var charge_energy_cost: float = 5.0       # energy per Heavy charge attack
var energy_regen_rate: float = 9.0        # per second while not boosting
var low_energy_threshold: float = 20.0    # below this the enemy withdraws
var recharged_energy: float = 60.0        # flee ends once the pool is back above this
var flee_speed_mult: float = 1.2          # how fast the enemy retreats

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

# Behavior Tree AI Brain (Beehave)
var beehave_tree: BeehaveTree = null
var pilot_trait: String = "Balanced"


## Attaches a Beehave Behavior Tree tailored to the enemy pilot's personality trait.
func setup_beehave_tree(trait_name: String = "Balanced") -> void:
	if beehave_tree != null and is_instance_valid(beehave_tree):
		beehave_tree.queue_free()
	if state_machine:
		state_machine.set_physics_process(false)
	
	if trait_name == "Balanced" and pilot_data.has("trait") and str(pilot_data["trait"]).strip_edges() != "":
		trait_name = str(pilot_data["trait"])
	pilot_trait = trait_name
	beehave_tree = MechaBehaviorTreeFactory.create_tree(self, trait_name)
	if beehave_tree and beehave_tree.blackboard:
		beehave_tree.blackboard.set_value("pilot_data", pilot_data)
		beehave_tree.blackboard.set_value("squad_coordinator", squad_coordinator)
		beehave_tree.blackboard.set_value("tactical_role", tactical_role)
	add_child(beehave_tree)

# PartMeshManager that renders this enemy from the mech armor catalog.
var catalog_body: Node = null

# Procedural Enemy Pilot & Tactical Squad Assignment
var pilot_data: Dictionary = {}
var squad_coordinator: Node = null
var tactical_role: String = ""

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

# --- Enemy shield -----------------------------------------------------------
# Shield archetypes (4/5) fight with a PHYSICAL plate held on one arm (no
# energy barrier, no regeneration — the plate just degrades as it takes hits
# and stays damaged until the mech is gone). While raised it fully blocks
# attacks and drains its HP at 40% rate against its OWN damage type and 100%
# against the other two (see enemy_health.gd, which asks the parent mech to
# absorb before touching parts). The AI drops the shield around its own
# attacks (state_attack) so the player gets a punish window.
var shield_active: bool = false
var shield_max_hp: float = 0.0
var shield_current_hp: float = 0.0
# Which attack type this plate resists best: "heat" / "pierce" / "blunt".
var shield_type: String = ""

# Weapon visuals mounted on the hands (shield + melee / shield + gun) so the
# loadout reads at a glance. Hidden when the carrying arm is destroyed.
var _shield_hand_mount: Node3D = null
var _weapon_hand_mount: Node3D = null

# Ammo system for ranged enemies. Ammo/reload state lives in a shared
# WeaponCore (same rules as the player's weapons); these fields feed the core's
# from_stats() build and the getters below delegate to it.
var max_ammo: int = 0
var reserve_ammo: int = -1
var reload_time: float = 3.0
var fire_core: WeaponCore = null
var is_melee_fallback_active: bool = false

var is_reloading: bool:
	get:
		return fire_core != null and fire_core.reloading

# Red telegraph flash: the state machine toggles this just before attacking so
# the player can read that a shot is coming. Original material overrides are
# cached on first flash and restored afterwards. The color is parameterized so
# the same machinery renders the amber "drained" flash while retreating.
var _flash_original_materials: Dictionary = {}
var _flash_material: StandardMaterial3D = null

# Energy-retreat feedback: while a drained enemy withdraws to recharge it wears
# an amber emissive flash (signal lights) and a pulsing "RETREATING" plate above
# its head, and fires a descending klaxon when the withdrawal starts. Toggled by
# StateFlee via set_retreating(); the label is a child so it follows the enemy.
var is_retreating: bool = false
var _retreat_label: Label3D = null
var _retreat_tween: Tween = null

# --- Part destruction: blown-off legs force a ragdoll, broken arms disarm ---
# With both legs gone the torso drops to the ground and can't move: ranged /
# support mechs keep firing from the dirt, melee brawlers eject their pilot to
# flee. Both arms gone means nothing left to attack with — the mech withdraws.
var ragdolled: bool = false
var piloted: bool = true
var _ragdoll_tween: Tween = null


func _ready() -> void:
	add_to_group("enemy")
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(60)
	health_system = $HealthSystem
	_setup_hitbox()
	_setup_enemy_status()
	health_system.mecha_destroyed.connect(_on_destroyed)
	health_system.armor_broken.connect(_on_armor_broken)
	if health_system.has_signal("part_destroyed"):
		health_system.part_destroyed.connect(_on_part_destroyed)
	_apply_catalog_health()
	_scale_by_wanted_level()
	_apply_archetype_stats()
	_apply_energy_tuning()
	_build_catalog_body()
	_mount_visual_loadout()
	_apply_shield_stats()
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
			# The plate defends against one attack type (heat/pierce/blunt);
			# balanced plates (no field) keep the plain armor_class behaviour.
			var def_type := str(armor.get("defense_type", ""))
			if def_type != "":
				part["defense_type"] = def_type
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

	# Extra bulk for heavy grunts so the silhouette reads at a glance (true scale 4.725m base).
	# Scale the root so collision, hitboxes, and visuals scale uniformly. Keep within realistic 4.7m - 5.2m band.
	if archetype == 2:
		scale = Vector3(1.10, 1.10, 1.10) # Heavy Titan: 5.20m
	elif archetype == 3:
		scale = Vector3(1.03, 1.03, 1.03) # Support: 4.86m
	else:
		scale = Vector3(1.0, 1.0, 1.0) # Rusher / Ranged / Shield: 4.725m (identical base to player)

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
# Sockets mirror mecha_base.tscn upper and lower pivots at true world scale (4.725m tall).
func _ensure_slot_nodes() -> void:
	var slot_positions := {
		"Head": Vector3(0, 3.864, -0.0672),
		"Body": Vector3(0, 3.024, 0),
		"ArmLeft": Vector3(-1.1424, 3.444, 0),
		"ArmRight": Vector3(1.1424, 3.444, 0),
		"LegLeft": Vector3(-0.6384, 2.184, 0),
		"LegRight": Vector3(0.6384, 2.184, 0),
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
		"ArmLeft/ForearmLeft": Vector3(0, -0.6384, 0),
		"ArmRight/ForearmRight": Vector3(0, -0.6384, 0),
		"LegLeft/ShinLeft": Vector3(0, -0.924, 0),
		"LegRight/ShinRight": Vector3(0, -0.924, 0),
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
# light. Blueprint-only tiers (Valkyrion etc.) are never worn by grunts.
# If pilot_data carries a canonical mech_loadout (from the board fleet roster),
# that loadout is the single source of truth (WYSIWYG) and is returned directly.
func _enemy_loadout() -> Dictionary:
	if not pilot_data.is_empty() and pilot_data.has("mech_loadout") and pilot_data["mech_loadout"] is Dictionary and not (pilot_data["mech_loadout"] as Dictionary).is_empty():
		var stored: Dictionary = pilot_data["mech_loadout"] as Dictionary
		# Heal Colors that were JSON-serialized as {r,g,b,a} dicts during save.
		var healed: Dictionary = {}
		for slot in stored:
			var entry = stored[slot]
			if not (entry is Dictionary):
				healed[slot] = entry
				continue
			var dup: Dictionary = (entry as Dictionary).duplicate(true)
			for sub in ["frame", "armor"]:
				var part = dup.get(sub, null)
				if part is Dictionary and part.get("color") is Dictionary:
					var cd: Dictionary = part["color"]
					part["color"] = Color(float(cd.get("r", 0.5)), float(cd.get("g", 0.5)), float(cd.get("b", 0.5)), float(cd.get("a", 1.0)))
			healed[slot] = dup
		# Ensure every expected slot exists (heal missing slots for older saves)
		for slot in GlobalData.MECHA_SLOTS:
			if not healed.has(slot):
				healed[slot] = {"frame": {}, "armor": {}}
		return healed
	var palette := _archetype_palette()
	var wants_heavy := archetype == 2
	var loadout: Dictionary = {}
	for slot in GlobalData.MECHA_SLOTS:
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


# Blueprint-only catalog entries (Valkyrion tier) must never be worn by grunts.
# Armor carries an explicit `blueprint_only` flag; frames mark the tier via the
# `type` field instead, so detect it by name.
func _is_blueprint_frame(entry: Dictionary) -> bool:
	return str(entry.get("type", "")).contains("Valkyrion")


# Frame durability tier per archetype. frame_catalog[slot] is ordered
# [standard, valkyrion, medium, heavy]; the Valkyrion tier is filtered out above,
# leaving [standard, medium, heavy] to index into.
func _archetype_frame_index() -> int:
	match archetype:
		1:
			return 1  # Ranged: medium (slightly sturdier than a Rusher)
		2:
			return 2  # Heavy: heaviest non-blueprint frame
		3:
			return 1  # Support: medium
		4, 5:
			return 1  # Shield melee/ranged: medium (they carry extra gear)
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
		4:
			return {"default": Color(0.25, 0.35, 0.55), "head": Color(0.3, 0.5, 0.8)}   # Shield melee: steel knight
		5:
			return {"default": Color(0.6, 0.4, 0.2), "head": Color(0.85, 0.6, 0.25)}    # Shield ranged: bronze gunner
		_:
			return {"default": Color(0.75, 0.2, 0.2), "head": Color(0.85, 0.25, 0.25)}


# Attaches the SAME animation script the player's mech uses (mecha_animation.gd)
# so enemies move with the identical stride, bob and idle combat stance instead
# of a separate implementation. Runs after _build_catalog_body so the
# Head/Body/Leg*/Shin* slot nodes exist to drive.
func _setup_leg_animation() -> void:
	if get_node_or_null("MechaAnimation") != null or get_node_or_null("EnemyAnimation") != null:
		return
	var anim := Node.new()
	anim.name = "MechaAnimation"
	anim.set_script(load("res://scripts/mecha/mecha_animation.gd"))
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

	var is_boss: bool = (squad_role == "commander") or (pilot_data.get("is_boss", false))
	var is_ace: bool = int(pilot_data.get("tier", 1)) >= 3 or pilot_trait in ["Aggressive", "Tactical"]

	# Set finite magazine & reserve ammo per tier and archetype
	if archetype == 1:  # RANGED
		max_ammo = 25
		reload_time = 3.0
		var mag_mult: int = 8 if is_boss else (4 if is_ace else 3)
		reserve_ammo = max_ammo * mag_mult
	elif archetype == 2:  # HEAVY (cannon / charge)
		max_ammo = 6
		reload_time = 4.0
		var mag_mult: int = 6 if is_boss else (3 if is_ace else 2)
		reserve_ammo = max_ammo * mag_mult
	elif archetype == 5:  # SHIELD_RANGED (shield + gun)
		max_ammo = 25
		reload_time = 3.0
		var mag_mult: int = 6 if is_boss else (3 if is_ace else 2)
		reserve_ammo = max_ammo * mag_mult
	else:
		max_ammo = 0
		reserve_ammo = -1 # Melee / Support archetypes stay ammo-free

	_build_fire_core()


func has_ammo() -> bool:
	return fire_core != null and (fire_core.unlimited_ammo or fire_core.ammo > 0)


func is_out_of_ammo() -> bool:
	return fire_core != null and fire_core.is_completely_dry()


## Tactical switch to CQB Melee mode when firearm is totally dry
func switch_to_melee_fallback() -> void:
	if is_melee_fallback_active:
		return
	is_melee_fallback_active = true
	# Mount Heat Blade in right hand
	if _weapon_hand_mount and is_instance_valid(_weapon_hand_mount):
		_weapon_hand_mount.queue_free()
	_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_heat_blade.tres"), "EnemyWeaponMount")
	attack_range = 3.8
	move_speed = maxf(move_speed * 1.25, 4.2)
	attack_damage = maxf(attack_damage * 1.35, 18.0)


# Builds the shared WeaponCore from the archetype's attack stats. Fire rate is
# paced by the AI state machine (attack_timer), so the core's own cooldown is
# disabled (fire_interval = 0) — it owns ammo/reload/heat + projectile spawning.
func _build_fire_core() -> void:
	var color := Color(1.0, 0.35, 0.2)
	match archetype:
		0: color = Color(1.0, 0.55, 0.2)   # Rusher: orange
		2: color = Color(0.9, 0.25, 0.25)  # Heavy: red
		3: color = Color(0.6, 0.85, 0.35)  # Support: lime
		4: color = Color(0.35, 0.6, 1.0)   # Shield melee: steel blue
		5: color = Color(1.0, 0.6, 0.2)    # Shield ranged: amber
	# Each ranged archetype fires one of the three attack types (heat/pierce/
	# blunt) so the type minigame applies to enemy fire too — pierce bullets,
	# blunt cannon shells, heat missiles.
	var attack_type := "pierce"
	match archetype:
		2: attack_type = "blunt"
		3: attack_type = "heat"
	fire_core = WeaponCore.from_stats({
		"attack_damage": attack_damage,
		"attack_cooldown": attack_cooldown,
		"max_ammo": max_ammo,
		"reserve_ammo": reserve_ammo,
		"reload_time": reload_time,
		"projectile_speed": 30.0,
		"damage_type": attack_type,
		"projectile_color": color,
	})
	fire_core.fire_interval = 0.0


func _process(delta: float) -> void:
	if fire_core:
		fire_core.tick(delta)
		if not is_melee_fallback_active and is_out_of_ammo():
			switch_to_melee_fallback()
	# Recharge the pool whenever the enemy isn't mid-dash. The cost is charged
	# up front in start_dash(), so an enemy that never boosts stays topped up.
	if not is_dashing:
		energy = minf(energy + energy_regen_rate * delta, max_energy)
	# Physical shield plates never regenerate — a damaged plate stays damaged.


# --- Enemy shield -----------------------------------------------------------
# Applies per-archetype shield stats. Only the shield archetypes (4/5) carry a
# shield; everyone else stays at 0 HP / inactive, so every set_shield_up call
# is a safe no-op for non-shield enemies. Plates never regenerate — HP shown
# here is all they get for the fight.
func _apply_shield_stats() -> void:
	match archetype:
		4:  # SHIELD_MELEE — heavy anti-blunt slab (soaks the player's swings)
			shield_max_hp = 180.0
			shield_current_hp = shield_max_hp
			shield_type = "blunt"
		5:  # SHIELD_RANGED — lighter anti-pierce field plate
			shield_max_hp = 120.0
			shield_current_hp = shield_max_hp
			shield_type = "pierce"
		_:
			shield_max_hp = 0.0
			shield_current_hp = 0.0
			shield_type = ""
	if shield_max_hp > 0.0:
		shield_active = true


func set_shield_up(on: bool) -> void:
	if shield_max_hp <= 0.0 or shield_current_hp <= 0.0:
		shield_active = false
		return
	shield_active = on


func is_shield_active() -> bool:
	return shield_active


# Absorbs incoming damage into the shield while it is up. A raised plate fully
# blocks the attack (0.0 leaks) and pays the damage from its own HP — 40% cost
# against its own damage type, 100% against the other two. When the plate runs
# out it breaks and stops blocking.
func absorb_damage_with_shield(amount: float, damage_type: String = "") -> float:
	if not shield_active or shield_max_hp <= 0.0 or shield_current_hp <= 0.0:
		return amount
	var attack: String = MechaHealthBase.normalize_damage_type(damage_type)
	var drain_mult := 0.4 if attack == shield_type else 1.0
	shield_current_hp = maxf(shield_current_hp - amount * drain_mult, 0.0)
	if shield_current_hp <= 0.0:
		shield_current_hp = 0.0
		shield_active = false
	return 0.0


# Mounts the visible loadout on the hands: a shield plate on one arm and the
# archetype's weapon (blade for shield-melee, gun for shield-ranged) on the
# other, reusing the same WeaponVisualFactory models the player's mech uses.
func _mount_visual_loadout() -> void:
	match archetype:
		0:  # RUSHER: heat blade
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_heat_blade.tres"), "EnemyWeaponMount")
		1:  # RANGED: beam carbine
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_beam_carbine.tres"), "EnemyWeaponMount")
		2:  # HEAVY: assault cannon
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_assault_cannon.tres"), "EnemyWeaponMount")
		3:  # SUPPORT: beam carbine
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_beam_carbine.tres"), "EnemyWeaponMount")
		4:  # SHIELD_MELEE: shield + heat blade
			_shield_hand_mount = WeaponVisualFactory.mount_hand(self, "left", preload("res://resources/mech/stock/weapon_shield.tres"), "EnemyShieldMount")
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_heat_blade.tres"), "EnemyWeaponMount")
		5:  # SHIELD_RANGED: shield + beam carbine
			_shield_hand_mount = WeaponVisualFactory.mount_hand(self, "left", preload("res://resources/mech/stock/weapon_shield.tres"), "EnemyShieldMount")
			_weapon_hand_mount = WeaponVisualFactory.mount_hand(self, "right", preload("res://resources/mech/stock/weapon_beam_carbine.tres"), "EnemyWeaponMount")


# The arm frame holding the shield/weapon broke: the hand-mounted gear is gone
# with it (the mech can no longer grip).
func _hide_hand_mounts(arm_slot: String) -> void:
	if arm_slot == "arm_left" and _shield_hand_mount:
		_shield_hand_mount.visible = false
	if arm_slot == "arm_right" and _weapon_hand_mount:
		_weapon_hand_mount.visible = false


# True while the mech still has at least one arm to hold a weapon.
func can_attack() -> bool:
	if health_system == null or not health_system.has_method("is_part_destroyed"):
		return true
	return not (health_system.is_part_destroyed("arm_left") and health_system.is_part_destroyed("arm_right"))


func _both_arms_destroyed() -> bool:
	if health_system == null or not health_system.has_method("is_part_destroyed"):
		return false
	return health_system.is_part_destroyed("arm_left") and health_system.is_part_destroyed("arm_right")


func _both_legs_destroyed() -> bool:
	if health_system == null or not health_system.has_method("is_part_destroyed"):
		return false
	return health_system.is_part_destroyed("leg_left") and health_system.is_part_destroyed("leg_right")


func _on_part_destroyed(slot_name: String) -> void:
	# A lost arm takes its hand-mounted shield/weapon model with it - and DROPS that weapon with HIGH chance.
	_hide_hand_mounts(slot_name)
	if slot_name == "arm_left" or slot_name == "arm_right":
		var arm_node := get_node_or_null("ArmLeft" if slot_name == "arm_left" else "ArmRight")
		# Fallback to Body if arm node missing (e.g., simple layout)
		var drop_pos: Vector3 = global_position
		if arm_node and is_instance_valid(arm_node):
			drop_pos = (arm_node as Node3D).global_position
		else:
			drop_pos = global_position + Vector3(randf_range(-1,1), 1.2, randf_range(-1,1))
		var loot = get_node_or_null("/root/GameWorld/LootSystem")
		if loot == null:
			loot = get_tree().current_scene.get_node_or_null("LootSystem") if get_tree().current_scene else null
		if loot == null:
			# Search any LootSystem in tree
			var nodes := get_tree().get_nodes_in_group("loot_system") if get_tree() else []
			if not nodes.is_empty():
				loot = nodes[0]
		if loot and loot.has_method("spawn_arm_weapon_drop"):
			loot.spawn_arm_weapon_drop(drop_pos, archetype, slot_name)
		elif loot and loot.has_method("_create_weapon_pickup"):
			# Fallback: try to spawn via pool directly
			pass
	var arms_gone := _both_arms_destroyed()
	var legs_gone := _both_legs_destroyed()
	if arms_gone and legs_gone:
		# Nothing left to fight or flee with — the pilot bails out.
		_ragdoll()
		_eject_pilot()
		return
	if arms_gone:
		# Disarmed: the mech withdraws instead of standing there helplessly.
		flee_reason = "disabled"
		if state_machine and state_machine.has_node("StateFlee"):
			state_machine.transition_to("StateFlee")
		return
	if legs_gone:
		_ragdoll()


# True if both legs are lost but arms remain: the torso drags itself along.
func _can_crawl() -> bool:
	return ragdolled and piloted and _both_legs_destroyed() and not _both_arms_destroyed()


func _process_crawl(delta: float) -> void:
	var crawl_speed := move_speed * 0.25
	var dir := Vector3.ZERO
	if state_machine and state_machine.current_state and state_machine.current_state.name == "StateFlee":
		if target and is_instance_valid(target):
			dir = (global_position - target.global_position)
	elif target and is_instance_valid(target):
		dir = (target.global_position - global_position)

	dir.y = 0.0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * crawl_speed
		velocity.z = dir.z * crawl_speed
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 5.0 * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y -= 20.0 * delta
	move_and_slide()


# Only long-range archetypes keep fighting after losing both legs — a melee
# brawler has nothing it can do from the ground unless it still has arms to crawl.
func _can_fight_from_ground() -> bool:
	return archetype == 1 or archetype == 3 or archetype == 5


func _ragdoll() -> void:
	if ragdolled:
		return
	ragdolled = true
	if _can_fight_from_ground() or _can_crawl():
		# Keep firing / crawling from the ground.
		return
	_eject_pilot()


# The pilot bails out of the crippled mech and flees the field on foot.
func _eject_pilot() -> void:
	if not piloted:
		return
	piloted = false
	if health_system and health_system.has_method("set_piloted"):
		health_system.set_piloted(false)
	if state_machine:
		state_machine.transition_to("StateIdle")

	var pilot := CharacterBody3D.new()
	pilot.set_script(preload("res://scripts/mecha/enemy_pilot.gd"))
	var color: Color = Color(0.75, 0.2, 0.2)
	if not faction_paint.is_empty():
		color = faction_paint.get("base", color)
	pilot.setup_fighting(target, color, archetype)
	get_parent().add_child(pilot)
	pilot.global_position = global_position + Vector3(0, 1.2, 0)

	_tilt_over()


# The wreck falls over — if a true physics ragdoll exists (spawned by
# MechaHealthBase._collapse_mech via MechaRagdoll), skip the fake tween because
# the RigidBody pieces already handle the fall. Otherwise legacy fake tilt.
func _tilt_over() -> void:
	if has_meta("ragdoll_bodies") and get_meta("ragdoll_bodies") is Array and not (get_meta("ragdoll_bodies") as Array).is_empty():
		return
	if _ragdoll_tween and _ragdoll_tween.is_valid():
		_ragdoll_tween.kill()
	_ragdoll_tween = create_tween().set_parallel(true)
	_ragdoll_tween.tween_property(self, "rotation:x", deg_to_rad(-82.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ragdoll_tween.tween_property(self, "position:y", 0.55, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _on_destroyed() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	if state_machine:
		state_machine.set_physics_process(false)
	if beehave_tree != null and is_instance_valid(beehave_tree):
		beehave_tree.set_physics_process(false)
	_eject_pilot()
	# Faction: enemy loss triggers R&D (heat + combat necessity)
	if ResourceLoader.exists("res://scripts/systems/faction_system.gd"):
		var FS = load("res://scripts/systems/faction_system.gd")
		FS.record_enemy_loss(1)
		FS.evaluate_triggers()

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
		const SpawnManagerScript := preload("res://scripts/systems/spawn_manager.gd")
		SpawnManagerScript.check_all_enemies_defeated()

	# Stay alive through core-breach warning + detonation + charred smoke wreckage display
	var delay: float = float(health_system.CORE_BREACH_DELAY) + 2.5 if health_system else 3.5
	var tween = create_tween()
	tween.tween_interval(delay)
	tween.tween_property(self, "position:y", position.y - 1.2, 0.8)
	tween.tween_callback(queue_free)



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
	# Update 3D name plate from pilot_data (canonical roster) so every grunt shows its name.
	var label: Label3D = get_node_or_null("NameLabel3D")
	if label:
		var pname: String = ""
		if not pilot_data.is_empty():
			pname = str(pilot_data.get("display_name", pilot_data.get("name", ""))).strip_edges()
		if pname == "":
			pname = "ENEMY"
		label.text = pname
		# Color by rank: commander gold, sergeant silver, grunt white
		var rank: String = str(pilot_data.get("rank_title", "")) if not pilot_data.is_empty() else ""
		if rank == "[CMDR]":
			label.modulate = Color(1.0, 0.88, 0.2)
			label.outline_modulate = Color(0.3, 0.2, 0.0)
		elif rank == "[SGT]":
			label.modulate = Color(0.75, 0.85, 0.95)
			label.outline_modulate = Color(0.15, 0.2, 0.3)
		else:
			label.modulate = Color(0.9, 0.9, 0.9)
			label.outline_modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 8
		label.font_size = 24 if rank == "[CMDR]" else 20
		# Ensure visibility (old scenes may have it hidden for SIMPLE layout)
		label.visible = true


# Hides/shows the enemy HUD status billboard from the player.
# Physical 3D mesh remains visible in physical space so enemies don't glitch or vanish next to cover.
func set_concealed(on: bool) -> void:
	if concealed == on:
		return
	concealed = on
	var status = get_node_or_null("EnemyStatus")
	if status and status.has_method("set_concealed"):
		status.set_concealed(on)


# Toggles an emissive flash across every rendered mesh of the enemy. Used as
# the red pre-attack telegraph and, with an amber tint, as the energy-retreat
# signal (see set_retreating). The first call caches each mesh's original
# material_override so the flash can be removed cleanly (the original never gets
# overwritten).
func set_attack_flash(on: bool, flash_color: Color = Color(1.0, 0.12, 0.05)) -> void:
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.metallic = 0.3
		_flash_material.roughness = 0.4
	_flash_material.albedo_color = flash_color
	_flash_material.emission_enabled = true
	_flash_material.emission = flash_color
	_flash_material.emission_energy_multiplier = 4.0

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


# Shows/hides the energy-retreat feedback: an amber emissive flash across the
# body (signal lights), a pulsing "RETREATING" plate above the head, and a
# one-shot positional klaxon when the withdrawal begins. Called by StateFlee
# when an energy-drained enemy breaks off; everything is cleaned up when the
# enemy returns to combat or dies.
func set_retreating(on: bool) -> void:
	if is_retreating == on:
		return
	is_retreating = on

	if on:
		set_attack_flash(true, _retreat_flash_color())
		if AudioManager:
			AudioManager.play_enemy_retreat(global_position + Vector3(0, 2, 0))
		_show_retreat_label()
	else:
		set_attack_flash(false)
		_hide_retreat_label()


func _retreat_flash_color() -> Color:
	return Color(1.0, 0.55, 0.05)


func _show_retreat_label() -> void:
	if _retreat_label != null:
		return
	_retreat_label = Label3D.new()
	_retreat_label.name = "RetreatLabel"
	_retreat_label.text = "RETREATING"
	_retreat_label.font_size = 22
	_retreat_label.outline_size = 12
	_retreat_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_retreat_label.no_depth_test = true
	_retreat_label.modulate = Color(1.0, 0.8, 0.25, 1.0)
	_retreat_label.position = Vector3(0, 4.8, 0)
	add_child(_retreat_label)

	# Pulse the plate so it draws the eye without hiding the enemy behind it.
	if _retreat_tween and _retreat_tween.is_valid():
		_retreat_tween.kill()
	_retreat_tween = create_tween().set_loops()
	_retreat_tween.tween_property(_retreat_label, "modulate:a", 0.35, 0.4)
	_retreat_tween.tween_property(_retreat_label, "modulate:a", 1.0, 0.4)


func _hide_retreat_label() -> void:
	if _retreat_tween and _retreat_tween.is_valid():
		_retreat_tween.kill()
	_retreat_tween = null
	if _retreat_label != null:
		_retreat_label.queue_free()
		_retreat_label = null


func _physics_process(delta: float) -> void:
	if health_system == null or health_system.get("is_destroyed"):
		velocity = Vector3.ZERO
		return

	# Both legs blown off: the torso lies on the ground. If arms remain, the
	# enemy can drag itself along at a slow crawl (25% speed); if both arms and
	# legs are destroyed, the mech cannot move at all and sits inert.
	if ragdolled:
		if state_machine and piloted:
			state_machine._physics_process(delta)
		if _can_crawl():
			_process_crawl(delta)
			return
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y -= 20.0 * delta
		move_and_slide()
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
# Applies the per-archetype energy economy after archetype stats land (so the
# costs/drains match how each enemy fights). See the tuning table above.
func _apply_energy_tuning() -> void:
	match archetype:
		0:  # RUSHER — aggressive brawler: dashes + swings are pricey, regen fast,
			# short withdrawals, sprints away and comes right back.
			dash_energy_cost = 20.0
			attack_energy_cost = 6.0
			energy_regen_rate = 12.0
			low_energy_threshold = 15.0
			recharged_energy = 50.0
			flee_speed_mult = 1.5
		1:  # RANGED — sustained fire outpaces regen (6/shot @ 0.6s > 8/s), pulls
			# out early to keep distance and returns only when fully recharged.
			dash_energy_cost = 18.0
			attack_energy_cost = 6.0
			energy_regen_rate = 8.0
			low_energy_threshold = 25.0
			recharged_energy = 70.0
			flee_speed_mult = 1.1
		2:  # HEAVY — near-efficient: the charge is the only real drain, so it
			# rarely runs dry; a fleeing heavy is SLOW (easy to punish).
			dash_energy_cost = 18.0
			attack_energy_cost = 5.0
			charge_energy_cost = 5.0
			energy_regen_rate = 7.0
			low_energy_threshold = 15.0
			recharged_energy = 40.0
			flee_speed_mult = 0.9
		3:  # SUPPORT — heals are cheap (5 per 1s cycle < 9/s regen), stays in
			# the fight and retreats at a normal pace.
			dash_energy_cost = 18.0
			attack_energy_cost = 5.0
			energy_regen_rate = 9.0
			low_energy_threshold = 20.0
			recharged_energy = 60.0
			flee_speed_mult = 1.2
		4:  # SHIELD MELEE — deliberate brawler: slow-ish regen, fights long.
			dash_energy_cost = 18.0
			attack_energy_cost = 6.0
			energy_regen_rate = 8.0
			low_energy_threshold = 15.0
			recharged_energy = 45.0
			flee_speed_mult = 1.1
		5:  # SHIELD RANGED — sustained fire drains it like a regular ranged unit.
			dash_energy_cost = 18.0
			attack_energy_cost = 6.0
			energy_regen_rate = 8.0
			low_energy_threshold = 25.0
			recharged_energy = 70.0
			flee_speed_mult = 1.1


# --- Rusher dash ------------------------------------------------------------
# Only the Rusher archetype lunges; the burst costs a chunk of the energy pool
# so a rusher can't dash forever. Returns false when the pool/cooldown isn't
# ready so callers fall back to plain pursuit.
func start_dash(dir: Vector3) -> bool:
	if archetype != 0:
		return false
	if energy < dash_energy_cost or dash_cooldown_timer > 0.0 or is_dashing:
		return false
	dash_direction = dir.normalized()
	dash_direction.y = 0.0
	if dash_direction.length() < 0.05:
		dash_direction = -transform.basis.z
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	energy = maxf(energy - dash_energy_cost, 0.0)
	if AudioManager:
		AudioManager.play_dash(global_position)
	return true


# True when the pool is too drained to keep fighting — the enemy should break
# off and withdraw to recharge (see StateFlee).
func is_low_energy() -> bool:
	return energy < low_energy_threshold


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
	if health_system == null or not is_inside_tree():
		return

	if damage_type.to_lower() == "explosive":
		# Delegate to the shared explosive blast helper on the health system.
		var local_pos := to_local(world_pos)
		var primary_slot: String = str(health_system._determine_hit_from_local(local_pos))
		if primary_slot == "" or not health_system.parts.has(primary_slot) or health_system.parts[primary_slot]["destroyed"]:
			primary_slot = health_system._find_alive_part()

		var slot_centers: Dictionary = {}
		for slot in health_system.parts:
			slot_centers[slot] = _get_part_world_pos(slot)

		MechaHealthBase.apply_explosive_blast(amount, world_pos, damage_type, primary_slot, "", slot_centers, func(slot: String, dmg: float, pos: Vector3) -> void:
			if health_system.has_method("take_damage_to_part_at"):
				health_system.take_damage_to_part_at(slot, dmg, pos, damage_type)
			else:
				health_system.take_damage_to_part(slot, dmg, damage_type)
		)
		return

	var local_pos = to_local(world_pos)
	var target_part = health_system._determine_hit_from_local(local_pos)

	# Fallback if part doesn't exist in this enemy's health system
	if not health_system.parts.has(target_part):
		target_part = health_system._find_alive_part()
		if target_part == "":
			return

	if health_system.parts[target_part]["destroyed"]:
		target_part = health_system._find_alive_part()
		if target_part == "":
			return

	if health_system.has_method("take_damage_to_part_at"):
		health_system.take_damage_to_part_at(target_part, amount, world_pos, damage_type)
	else:
		health_system.take_damage_to_part(target_part, amount, damage_type)


func _get_part_world_pos(slot: String) -> Vector3:
	if not is_inside_tree():
		return position + GlobalData.SLOT_OFFSETS.get(slot, Vector3.ZERO)
	return to_global(GlobalData.SLOT_OFFSETS.get(slot, Vector3.ZERO))


func _scale_by_wanted_level() -> void:
	var wanted = GlobalData.board.wanted_level
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
	if not is_inside_tree():
		return (player_pos - position).normalized()
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
