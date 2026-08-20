class_name MechaHealthBase
extends Node3D

signal health_changed(slot_name: String, layer: String, current_hp: float, max_hp: float)
signal armor_broken(slot_name: String)
signal part_destroyed(slot_name: String)
signal mecha_destroyed()

@export var is_player: bool = false

var parts: Dictionary = {}
var total_armor_hp: float = 0.0
var total_frame_hp: float = 0.0
var max_total_armor: float = 0.0
var max_total_frame: float = 0.0
var is_destroyed: bool = false
var _near_death_recorded: bool = false  # tracks if near-death bond was already awarded

var _original_colors: Dictionary = {}
var _armor_color: Color = Color(0.6, 0.65, 0.7, 1)
var _frame_color: Color = Color(0.4, 0.4, 0.45, 1)
var _damage_color: Color = Color(0.8, 0.2, 0.2, 1)
var _broken_color: Color = Color(0.2, 0.2, 0.2, 1)

# --- Pilot status light + damage sparks ---------------------------------------
# A mech with a pilot on board wears a status light at its head (blue for the
# player's side, red for hostiles) and throws electrical sparks from destroyed
# part joints. An EMPTY mech shows no light and throws no sparks — nothing is
# running the machine.
var _piloted: bool = true
var _pilot_light: OmniLight3D = null
var _spark_timer: float = 0.0

# Friendly-side override: the health system's _ready() runs BEFORE its parent
# mech joins the "ally" group (children ready first), so the auto-detection in
# _is_friendly() can't see an ally yet and paints its head light red. Allies
# call set_friendly_light(true) from their own _ready() to correct the color.
var _friendly_light_override: int = -1  # -1 = auto, 0 = hostile, 1 = friendly

# Core-breach heat glow: an OmniLight3D on the body that ramps up while the
# machine warns before detonation — reads as the heat building up to blow.
var _breach_glow: OmniLight3D = null


func _ready() -> void:
	_init_parts()
	_find_meshes()
	_calculate_totals()
	EventBus.damage_received.connect(_on_damage_received)
	_setup_pilot_light()
	# Only the PLAYER's health system follows the occupancy signal — enemy /
	# ally mechs manage their own pilot state via set_piloted().
	if is_player:
		EventBus.mecha_occupancy_changed.connect(_on_mecha_occupancy_changed)
	# A MANUAL drop (hold 1/3 + scroll + X) must leave the weapon as a
	# recoverable pickup at the mech's feet — the signal used to fire into
	# nothing, so the weapon simply vanished.
	var mecha := get_parent()
	if mecha != null:
		var wm := mecha.get_node_or_null("WeaponManager")
		if wm != null and wm.has_signal("weapon_dropped"):
			wm.weapon_dropped.connect(_on_weapon_dropped)


func _init_parts() -> void:
	pass


func _find_meshes() -> void:
	pass


## Normalizes every damage-type string down to the three attack types
## (heat / pierce / blunt). Legacy labels (kinetic, explosive, beam, melee)
## map onto the new system so armor/shield defenses always compare one of the
## three. Anything already one of the three passes through untouched.
static func normalize_damage_type(t: String) -> String:
	match str(t).to_lower():
		"heat", "beam", "energy", "thermal", "plasma", "fire", "explosive":
			return "heat"
		"pierce", "piercing", "kinetic", "rail", "bullet", "shell":
			return "pierce"
		"blunt", "impact", "crush", "melee", "force":
			return "blunt"
		_:
			return str(t).to_lower()


func _calculate_totals() -> void:
	total_armor_hp = 0.0
	total_frame_hp = 0.0
	max_total_armor = 0.0
	max_total_frame = 0.0
	for slot in parts:
		total_armor_hp += parts[slot]["armor_hp"]
		total_frame_hp += parts[slot]["frame_hp"]
		max_total_armor += parts[slot]["max_armor"]
		max_total_frame += parts[slot]["max_frame"]


func take_damage(amount: float, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	var target_slot = _select_target()
	if target_slot == "":
		return

	var part = parts[target_slot]

	if not part["armor_broken"]:
		_apply_armor_damage(target_slot, amount, damage_type)
	else:
		_apply_frame_damage(target_slot, amount, damage_type)

	# Convoy Defense: during defense missions, player damage also damages the convoy.
	if is_player and GlobalData.convoy_defense_active:
		var scene = get_tree().current_scene if get_tree() else null
		var convoy = scene.get_node_or_null("ConvoyEscort") if scene else null
		if convoy and convoy.has_method("_damage_convoy"):
			convoy._damage_convoy(amount * 0.1)  # 10% of damage spills to convoy


# `layer` routes damage straight to a surface: "armor" hits armor first (only
# while it is intact), "frame" always hits the frame. Empty means the classic
# armor-first behaviour (armor absorbs until it breaks, then frame takes over).
func take_damage_to_part(slot_name: String, amount: float, damage_type: String = "kinetic", layer: String = "") -> void:
	if is_destroyed:
		return
	# Drop tank intercept: body hits that land on the torso can damage external
	# fuel tanks before the armor plate. A percentage of the damage is absorbed
	# by the tanks (they are bolted to the back, so they catch some fire).
	if slot_name == "body" and is_player and _intercept_drop_tank_damage(amount):
		amount *= 0.7  # tanks absorbed 30% of the hit
	if not parts.has(slot_name):
		slot_name = _select_target()
	if slot_name == "":
		return

	var part = parts[slot_name]
	if part["destroyed"]:
		return

	match layer.to_lower():
		"armor":
			if not part["armor_broken"]:
				_apply_armor_damage(slot_name, amount, damage_type)
			else:
				_apply_frame_damage(slot_name, amount, damage_type)
			return
		"frame":
			_apply_frame_damage(slot_name, amount, damage_type)
			return

	if not part["armor_broken"]:
		_apply_armor_damage(slot_name, amount, damage_type)
	else:
		_apply_frame_damage(slot_name, amount, damage_type)


# Location-based damage: the impact point decides which part AND which surface
# (armor plate vs exposed frame) takes the hit.
# When the attack is explosive (missiles, rockets, grenades, detonating barrels),
# the blast also radiates splash damage across adjacent parts on the mech.
func take_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return

	if damage_type.to_lower() == "explosive":
		_take_explosive_damage_at_point(amount, world_pos, damage_type)
		return

	var hit := _resolve_hit(world_pos)
	if hit["slot"] != "":
		take_damage_to_part(hit["slot"], amount, damage_type, hit["layer"])


func _take_explosive_damage_at_point(amount: float, world_pos: Vector3, damage_type: String = "explosive") -> void:
	var primary_hit := _resolve_hit(world_pos)
	var primary_slot: String = primary_hit.get("slot", "")
	var blast_radius := 3.8

	# 1. Primary hit part absorbs direct blast impact (primary focus)
	if primary_slot != "" and parts.has(primary_slot):
		var primary_dmg: float = amount * 0.65
		take_damage_to_part(primary_slot, primary_dmg, damage_type, primary_hit.get("layer", ""))

	# 2. Adjacent parts take lighter radial splash damage based on distance
	for slot in parts:
		if slot == primary_slot:
			continue
		if parts[slot]["destroyed"]:
			continue

		var slot_pos := _get_slot_center(slot)
		var dist: float = world_pos.distance_to(slot_pos)
		if dist <= blast_radius:
			var falloff: float = clampf(1.0 - 0.6 * (dist / blast_radius), 0.2, 1.0)
			var splash_dmg: float = amount * 0.35 * falloff
			var layer := _resolve_layer_for_slot(slot, world_pos)
			take_damage_to_part(slot, splash_dmg, damage_type, layer)


func _get_slot_center(slot_name: String) -> Vector3:
	var section := _get_section_node(slot_name)
	if section != null and is_instance_valid(section):
		return section.global_position

	var mecha = get_parent()
	var base_pos: Vector3 = mecha.global_position if mecha else global_position
	var fwd: Vector3 = -mecha.global_transform.basis.z if mecha else Vector3.FORWARD
	var right: Vector3 = mecha.global_transform.basis.x if mecha else Vector3.RIGHT
	var up: Vector3 = mecha.global_transform.basis.y if mecha else Vector3.UP
	match slot_name:
		"head":
			return base_pos + up * 1.9 + fwd * 0.1
		"body":
			return base_pos + up * 1.2
		"arm_left":
			return base_pos + up * 1.4 - right * 0.9
		"arm_right":
			return base_pos + up * 1.4 + right * 0.9
		"leg_left":
			return base_pos + up * 0.5 - right * 0.5
		"leg_right":
			return base_pos + up * 0.5 + right * 0.5
	return base_pos


# Drop tank damage intercept: routes a portion of body damage to external
# fuel canisters. Returns true when drop tanks absorbed some damage.
func _intercept_drop_tank_damage(amount: float) -> bool:
	var mecha = get_parent()
	if mecha == null:
		return false
	var energy_sys = mecha.get_node_or_null("EnergySystem")
	if energy_sys == null or not energy_sys.has_method("apply_drop_tank_damage"):
		return false
	if not energy_sys._drop_tank_active:
		return false
	# 30% of body damage is deflected to the drop tanks.
	energy_sys.apply_drop_tank_damage(amount * 0.3)
	return true



# Variant used by enemy mechas: they resolve the part themselves (their meshes
# have no armor/frame split), we only need to resolve the surface layer here.
func take_damage_to_part_at(slot_name: String, amount: float, world_pos: Vector3, damage_type: String = "kinetic") -> void:
	if is_destroyed:
		return
	if not parts.has(slot_name):
		take_damage_at_point(amount, world_pos, damage_type)
		return
	var layer := _resolve_layer_for_slot(slot_name, world_pos)
	take_damage_to_part(slot_name, amount, damage_type, layer)


func _select_target() -> String:
	var candidates = []
	for slot in parts:
		if not parts[slot]["destroyed"]:
			candidates.append(slot)

	if candidates.is_empty():
		return ""

	candidates.sort_custom(func(a, b):
		var hp_a = parts[a]["armor_hp"] if not parts[a]["armor_broken"] else parts[a]["frame_hp"]
		var hp_b = parts[b]["armor_hp"] if not parts[b]["armor_broken"] else parts[b]["frame_hp"]
		return hp_a < hp_b
	)

	return candidates[0]


# Resolves which slot + surface layer a world-space impact point hits.
# The armor protects its covered area. Frame geometry whose AABB overlaps the
# armor AABB (it pokes through the armor) is also protected — hits there damage
# armor while it is intact. Only frame geometry that never overlaps any armor
# AABB (e.g. spikes mounted beside the armor) is exposed and takes frame damage.
func _resolve_hit(world_pos: Vector3) -> Dictionary:
	var armor_slot := ""
	var armor_dist := INF
	var shielded_slot := ""
	var shielded_dist := INF
	var exposed_slot := ""
	var exposed_dist := INF

	var fallback_slot := ""
	var fallback_dist := INF

	for slot in parts:
		if parts[slot]["destroyed"]:
			continue

		var armor_meshes := _get_slot_surfaces(slot, "ArmorMesh")
		var frame_meshes := _get_slot_surfaces(slot, "FrameMesh")
		var armor_intact: bool = not parts[slot]["armor_broken"]

		if armor_intact:
			for mesh in armor_meshes:
				var d := _surface_hit_distance(mesh, world_pos)
				if d >= 0.0 and d < armor_dist:
					armor_dist = d
					armor_slot = slot
			for mesh in frame_meshes:
				if _frame_shielded_by_armor(mesh, armor_meshes):
					var d := _surface_hit_distance(mesh, world_pos)
					if d >= 0.0 and d < shielded_dist:
						shielded_dist = d
						shielded_slot = slot

		for mesh in frame_meshes:
			if armor_intact and _frame_shielded_by_armor(mesh, armor_meshes):
				continue
			var d := _surface_hit_distance(mesh, world_pos)
			if d >= 0.0 and d < exposed_dist:
				exposed_dist = d
				exposed_slot = slot

		var section := _get_section_node(slot)
		if section:
			var d := world_pos.distance_to(section.global_position)
			if d < fallback_dist:
				fallback_dist = d
				fallback_slot = slot

	if armor_slot != "":
		return {"slot": armor_slot, "layer": "armor"}
	if shielded_slot != "":
		return {"slot": shielded_slot, "layer": "armor"}
	if exposed_slot != "":
		return {"slot": exposed_slot, "layer": "frame"}
	return {"slot": fallback_slot, "layer": ""}


# True when a frame mesh passes through the area an armor plate covers, meaning
# the armor is mounted over it and shields it from direct frame damage.
func _frame_shielded_by_armor(frame_mesh: MeshInstance3D, armor_meshes: Array) -> bool:
	var frame_aabb := _mesh_global_aabb(frame_mesh)
	if frame_aabb.size == Vector3.ZERO:
		return false
	for armor_mesh in armor_meshes:
		var armor_aabb := _mesh_global_aabb(armor_mesh)
		if armor_aabb.size != Vector3.ZERO and armor_aabb.intersects(frame_aabb):
			return true
	return false


func _resolve_layer_for_slot(slot_name: String, world_pos: Vector3) -> String:
	if not parts.has(slot_name) or parts[slot_name]["destroyed"]:
		return ""
	var armor_meshes := _get_slot_surfaces(slot_name, "ArmorMesh")
	var frame_meshes := _get_slot_surfaces(slot_name, "FrameMesh")
	var armor_intact: bool = not parts[slot_name]["armor_broken"]

	var armor_dist := INF
	var frame_dist := INF
	if armor_intact:
		for mesh in armor_meshes:
			var d := _surface_hit_distance(mesh, world_pos)
			if d >= 0.0:
				armor_dist = minf(armor_dist, d)
		for mesh in frame_meshes:
			if _frame_shielded_by_armor(mesh, armor_meshes):
				var d := _surface_hit_distance(mesh, world_pos)
				if d >= 0.0:
					armor_dist = minf(armor_dist, d)
	for mesh in frame_meshes:
		if armor_intact and _frame_shielded_by_armor(mesh, armor_meshes):
			continue
		var d := _surface_hit_distance(mesh, world_pos)
		if d >= 0.0:
			frame_dist = minf(frame_dist, d)

	if armor_dist < frame_dist:
		return "armor"
	if frame_dist < INF:
		return "frame"
	return ""


# Returns the distance to a mesh surface if world_pos is inside its AABB,
# or -1.0 when the point misses that mesh.
func _surface_hit_distance(mesh: MeshInstance3D, world_pos: Vector3) -> float:
	var aabb := _mesh_global_aabb(mesh)
	if aabb.size == Vector3.ZERO or not aabb.has_point(world_pos):
		return -1.0
	return world_pos.distance_to(mesh.global_position)


func _mesh_global_aabb(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	if local.size == Vector3.ZERO:
		return AABB()
	var t := mesh.get_global_transform()
	var p := local.position
	var e := local.size
	var corners := PackedVector3Array([
		t * (p + Vector3(0, 0, 0)),
		t * (p + Vector3(e.x, 0, 0)),
		t * (p + Vector3(0, e.y, 0)),
		t * (p + Vector3(0, 0, e.z)),
		t * (p + Vector3(e.x, e.y, 0)),
		t * (p + Vector3(e.x, 0, e.z)),
		t * (p + Vector3(0, e.y, e.z)),
		t * (p + Vector3(e.x, e.y, e.z)),
	])
	var aabb := AABB(corners[0], Vector3.ZERO)
	for c in corners:
		aabb = aabb.expand(c)
	return aabb


# Collects every rendered mesh under a slot's ArmorMesh/FrameMesh containers
# (including lower-joint containers such as Forearm/Shin sub-meshes).
func _get_slot_surfaces(slot_name: String, container_name: String) -> Array:
	var section := _get_section_node(slot_name)
	var result: Array = []
	if section == null:
		return result
	_collect_surface_meshes(section, container_name, result)
	return result


func _collect_surface_meshes(node: Node, container_name: String, into: Array) -> void:
	if node is Node3D and node.name == container_name:
		_collect_mesh_descendants(node, into)
		return
	for child in node.get_children():
		_collect_surface_meshes(child, container_name, into)


func _collect_mesh_descendants(node: Node, into: Array) -> void:
	if node is MeshInstance3D:
		into.append(node)
	for child in node.get_children():
		_collect_mesh_descendants(child, into)


func _apply_armor_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var part = parts[slot_name]
	# Armor only dampens attacks of its OWN defense type. A plate defends
	# against one of heat/pierce/blunt; when the incoming attack type matches
	# it, armor_class applies normally. When it doesn't match, the plate can't
	# shed the damage — it takes the hit at full strength (no armor_class
	# reduction) until it breaks. Empty defense_type = balanced plate, so the
	# old armor_class behaviour stays for untyped parts (and scrap patches).
	var attack := normalize_damage_type(damage_type)
	var defense := str(part.get("defense_type", "")).to_lower()
	var resistance := 1.0
	if defense == "" or defense == "balanced" or defense == attack:
		resistance = float(part.get("armor_class", 1.0))
	var reduced = amount / maxf(resistance, 0.1)
	part["armor_hp"] = maxf(part["armor_hp"] - reduced, 0.0)

	_update_part_visual(slot_name)
	health_changed.emit(slot_name, "armor", part["armor_hp"], part["max_armor"])
	# Metallic clank at the mech: rounds pinging off the armor plate.
	if AudioManager:
		AudioManager.play_mech_hit(global_position)

	# Persist damage to GlobalData so Hangar shows correct state after combat.
	# Key format: "slot_name" for armor damage ratio (0.0 = full, 1.0 = destroyed)
	if is_player and part["max_armor"] > 0.0:
		GlobalData.part_damage[slot_name] = 1.0 - (part["armor_hp"] / part["max_armor"])

	if is_player:
		EventBus.damage_received.emit(slot_name, reduced, damage_type)
	if _is_friendly():
		EventBus.friendly_damage_received.emit(reduced)

	if part["armor_hp"] <= 0.0:
		_on_armor_broken(slot_name)


func _apply_frame_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var part = parts[slot_name]
	part["frame_hp"] = maxf(part["frame_hp"] - amount, 0.0)

	_update_part_visual(slot_name)
	health_changed.emit(slot_name, "frame", part["frame_hp"], part["max_frame"])
	# Duller clank for the exposed frame underneath the broken plate.
	if AudioManager:
		AudioManager.play_mech_hit(global_position, -3.5)

	# Persist frame damage to GlobalData with "_frame" suffix to distinguish from armor.
	# Key format: "slot_name_frame" for frame damage ratio (0.0 = full, 1.0 = destroyed)
	if is_player and part["max_frame"] > 0.0:
		GlobalData.part_damage[slot_name + "_frame"] = 1.0 - (part["frame_hp"] / part["max_frame"])

	if is_player:
		EventBus.damage_received.emit(slot_name, amount, damage_type)
		# Near-death escape detection (GDD §5): bond increases when HP drops below 20%.
		# Only fires once per near-death event (tracked by _near_death_recorded flag).
		var hp_ratio := total_frame_hp / maxf(max_total_frame, 1.0)
		if hp_ratio < 0.2 and total_frame_hp > 0.0 and not _near_death_recorded:
			_near_death_recorded = true
			GlobalData.record_near_death_escape()
	elif not is_player:
		_near_death_recorded = false
	if _is_friendly():
		EventBus.friendly_damage_received.emit(amount)

	if part["frame_hp"] <= 0.0:
		_on_frame_destroyed(slot_name)


func _on_armor_broken(slot_name: String) -> void:
	parts[slot_name]["armor_broken"] = true
	parts[slot_name]["armor_hp"] = 0.0
	# An EMERGENCY SCRAP PATCH behaves exactly like normal armor: when its HP
	# hits zero it shatters and is GONE. Remove the patch from the persistent
	# stash so the crude plates fall off the mech, the hangar stops showing it,
	# and the next battle doesn't re-apply its weak scrap stats.
	if is_player and GlobalData.scrap_patches.has(slot_name):
		GlobalData.scrap_patches.erase(slot_name)
		_refresh_patch_visuals(slot_name)
	_show_frame(slot_name)
	armor_broken.emit(slot_name)
	_calculate_totals()
	if AudioManager:
		AudioManager.play_armor_break(global_position + Vector3(0, 1.5, 0))


# After a scrap patch shatters, refresh the mech's visuals so the crude patch
# primitives disappear (the slot reverts to its inner frame / armor state).
# refresh_scrap_patches() rebuilds every patched slot from the stash, so with
# the slot erased above it removes the container and drops the patch meshes.
func _refresh_patch_visuals(_slot_name: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var pmm = mecha.get_node_or_null("CatalogBody")
	if pmm and pmm.has_method("refresh_scrap_patches"):
		pmm.refresh_scrap_patches()


func _on_frame_destroyed(slot_name: String) -> void:
	parts[slot_name]["destroyed"] = true
	parts[slot_name]["frame_hp"] = 0.0
	_hide_part(slot_name)
	if is_player:
		_spawn_scrap_wreckage(slot_name)
		_spawn_part_scrap_pickup(slot_name)
		# The arm frame holding the weapon broke → the weapon on that hand is
		# dropped as a recoverable pickup (the weapon itself is NOT destroyed).
		if slot_name == "arm_left":
			_drop_hand_weapon_pickup("left", slot_name)
		elif slot_name == "arm_right":
			_drop_hand_weapon_pickup("right", slot_name)
	part_destroyed.emit(slot_name)
	_calculate_totals()
	# Any destroyed frame can kill the status light: the head (light is on the
	# head) or the BODY (the engine core is gone — no power for any light).
	if slot_name == "head" or slot_name == "body":
		_update_pilot_light()

	if total_frame_hp <= 0.0:
		_on_mecha_destroyed()


# How long the core-breach warning lasts before the machine detonates (safety
# window so the pilot can eject / the player can see the mech is going down).
const CORE_BREACH_DELAY := 1.8

# How long the destroyed mech's NODE stays alive after death: the warning
# window + the explosion + a short breather. The dummy scripts (enemy/ally)
# free themselves after this long so the downed machine is seen collapsing,
# flashing, and blowing up instead of vanishing early.
const DESTROYED_NODE_LIFETIME := CORE_BREACH_DELAY + 1.0


func _on_mecha_destroyed() -> void:
	is_destroyed = true
	mecha_destroyed.emit()
	# SAFETY SEQUENCE: the mech goes down and flashes a warning for ~1.8s
	# before the actual detonation — never an instant explosion. This gives the
	# pilot the standard eject window (and makes the destruction readable).
	_start_core_breach_sequence()

	# Handle player death: the pilot ejects and the destroyed machine is removed
	# from the convoy roster. Losing your mech is not automatically a game over —
	# the pilots retreat from the field. If squadmates still hold the convoy, the
	# run continues pilot-only (no mech) until a recovery event grants a new one.
	# A parked reserve mech means the player just falls back to that machine.
	# The 2s delay below (combat end) overlaps the core-breach window, so the
	# eject happens while the warning still plays and the explosion lands with
	# the retreat.
	if is_player:
		if GameManager.is_escaping:
			return
		# The pilot ejects from the destroyed machine and takes eject damage —
		# the pilot's own HP drops (separate from the mech's). Wounded pilots
		# heal with items bought at city nodes / rest before the next sortie.
		PilotSystem.on_mecha_destroyed()
		# PERMANENT DEATH: if the eject drops the pilot's HP to 0 (they were
		# already badly hurt, e.g. shot earlier in the battle) the pilot is dead
		# for good — same rule as being shot on foot. The run ends right here.
		if PilotSystem.is_dead():
			GlobalData.run_notice = "Your pilot was killed when the mech went down. The run ends here."
			EventBus.combat_ended.emit(false)
			GameManager.game_over()
			return
		await get_tree().create_timer(2.0).timeout
		if GameManager.is_escaping:
			return
		EventBus.combat_ended.emit(false)
		HangarManager.remove_mech(GlobalData.active_hangar_mech_id)
		GlobalData.mech_less = GlobalData.hangar_mechs.is_empty()
		# Place wreckage tile at the combat position for the Siphon Protocol.
		if GlobalData.mech_less and not GameManager.is_escaping:
			GlobalData.wreckage_tile_pos = GlobalData.current_tile
			GlobalData.wreckage_fuel_remaining = 80.0
			GlobalData.siphoned_fuel = 0.0
		if HangarManager.can_mechless_retreat():
			GlobalData.run_notice = "Your mech is destroyed! The pilot siphons fuel from the wreckage to reboot. Walk to the wreckage tile (burnt orange) to siphon."
			GameManager.return_to_board()
		elif GlobalData.mech_less:
			GameManager.game_over()
		else:
			GlobalData.run_notice = "Your mech was destroyed, but a reserve machine is still parked in the convoy."
			GameManager.return_to_board()


# --- Core-breach death sequence (fall -> warning -> detonate) -------------

func _start_core_breach_sequence() -> void:
	_collapse_mech()
	_play_core_breach_warning()
	_spawn_breach_glow()
	_spawn_breach_countdown()
	var elapsed := 0.0
	var flash_on := false
	while elapsed < CORE_BREACH_DELAY:
		await get_tree().create_timer(0.15).timeout
		if not is_instance_valid(self):
			return
		elapsed += 0.15
		flash_on = not flash_on
		_core_breach_flash(flash_on)
		_update_breach_glow(elapsed / CORE_BREACH_DELAY, flash_on)
		_update_breach_countdown(elapsed)
	if not is_instance_valid(self):
		return
	_core_breach_flash(false)
	_hide_breach_countdown()
	_detonate_mech()


# The mech goes limp: the shared mech animation (if attached) switches into its
# death-collapse pose AND the whole machine RAGDOLLS over onto the ground right
# away (rotation.x -> -82°, drop to y 0.55) — the same collapse downed enemies
# use. Everything but the eject seat is dead: no movement, no weapons, no HUD.
func _collapse_mech() -> void:
	var mecha = get_parent()
	if mecha == null or not is_instance_valid(mecha):
		return
	for child in mecha.get_children():
		if child.has_method("set_core_breach"):
			child.set_core_breach(true)
	var tween = mecha.create_tween().set_parallel(true)
	tween.tween_property(mecha, "rotation:x", deg_to_rad(-82.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(mecha, "position:y", 0.55, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# The heat-glow core light: a small orange OmniLight on the body that swells and
# brightens over the warning window like the reactor heating up to blow.
func _spawn_breach_glow() -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	_breach_glow = OmniLight3D.new()
	_breach_glow.name = "BreachGlow"
	_breach_glow.light_color = Color(1.0, 0.45, 0.15)
	_breach_glow.light_energy = 0.0
	_breach_glow.omni_range = 2.5
	_breach_glow.shadow_enabled = false
	_breach_glow.position = Vector3(0, 1.3, 0)  # body core
	mecha.add_child(_breach_glow)


# Ramps the breach glow toward white-hot as the countdown nears its end; the
# existing red/white emissive flash adds an extra pulse so the heat visibly
# throbs out of the machine.
func _update_breach_glow(progress: float, flash_on: bool) -> void:
	if _breach_glow == null or not is_instance_valid(_breach_glow):
		return
	_breach_glow.light_energy = lerpf(1.5, 6.0, progress) + (1.2 if flash_on else 0.0)
	_breach_glow.omni_range = lerpf(3.0, 8.0, progress)
	_breach_glow.light_color = Color(1.0, 0.45, 0.15).lerp(Color(1.0, 0.9, 0.65), progress)


# Alternating red/white emissive flash across the whole machine during the
# warning window — unmistakable from across the battlefield.
func _core_breach_flash(on: bool) -> void:
	var mecha = get_parent()
	if mecha == null or not is_instance_valid(mecha):
		return
	var color := Color(1.0, 0.15, 0.1) if on else Color(0.95, 0.9, 0.85)
	for child in mecha.get_children():
		if child is MeshInstance3D and child.material_override:
			child.material_override.emission_enabled = on
			child.material_override.emission = color
			child.material_override.emission_energy_multiplier = 3.0 if on else 0.0


# Warning klaxon for the breach window: the rising attack-alert tone plus the
# descending retreat klaxon layered — reads as "about to blow" without adding
# a brand-new sound asset.
func _play_core_breach_warning() -> void:
	if AudioManager:
		AudioManager.play_enemy_warning(global_position + Vector3(0, 2.0, 0))
		AudioManager.play_sfx("enemy_retreat", global_position + Vector3(0, 2.0, 0), -1.0)


# --- Core-breach countdown label (screen-space) ----------------------------
# A big red "CORE BREACH" banner with a ticking countdown pinned to the center
# of the screen so the player can't miss that the machine is about to blow.
# The label pulses in and out to match the emissive flash rhythm.
var _breach_countdown_layer: CanvasLayer = null
var _breach_countdown_label: Label = null
var _breach_countdown_tween: Tween = null


func _spawn_breach_countdown() -> void:
	var mecha = get_parent()
	if mecha == null or not is_instance_valid(mecha):
		return
	_breach_countdown_layer = CanvasLayer.new()
	_breach_countdown_layer.name = "BreachCountdown"
	_breach_countdown_layer.layer = 10  # above combat HUD (layer 5)
	mecha.add_child(_breach_countdown_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_breach_countdown_layer.add_child(root)

	_breach_countdown_label = Label.new()
	_breach_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breach_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_breach_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_breach_countdown_label.offset_left = -220
	_breach_countdown_label.offset_right = 220
	_breach_countdown_label.offset_top = -40
	_breach_countdown_label.offset_bottom = 40
	_breach_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.85, 0.08, 0.05, 0.88)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_breach_countdown_label.add_theme_stylebox_override("normal", style)
	_breach_countdown_label.add_theme_font_size_override("font_size", 32)
	_breach_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	_breach_countdown_label.text = "CORE BREACH %.1fs" % CORE_BREACH_DELAY
	root.add_child(_breach_countdown_label)

	# Pulse the alpha so the banner throbs like the emissive flash.
	_breach_countdown_tween = create_tween().set_loops()
	_breach_countdown_tween.tween_property(_breach_countdown_label, "modulate:a", 0.4, 0.3)
	_breach_countdown_tween.tween_property(_breach_countdown_label, "modulate:a", 1.0, 0.3)


func _update_breach_countdown(elapsed: float) -> void:
	if _breach_countdown_label == null or not is_instance_valid(_breach_countdown_label):
		return
	var remaining := maxf(CORE_BREACH_DELAY - elapsed, 0.0)
	_breach_countdown_label.text = "CORE BREACH %.1fs" % remaining
	# Urgency ramp: the background shifts from red toward white-hot near the
	# end, matching the breach glow's colour ramp.
	var progress := clampf(elapsed / CORE_BREACH_DELAY, 0.0, 1.0)
	var bg := Color(0.85, 0.08, 0.05, 0.88).lerp(Color(1.0, 0.75, 0.6, 0.95), progress)
	var style: StyleBoxFlat = _breach_countdown_label.get_theme_stylebox("normal") as StyleBoxFlat
	if style:
		style.bg_color = bg


func _hide_breach_countdown() -> void:
	if _breach_countdown_tween and _breach_countdown_tween.is_valid():
		_breach_countdown_tween.kill()
		_breach_countdown_tween = null
	if _breach_countdown_layer != null and is_instance_valid(_breach_countdown_layer):
		_breach_countdown_layer.queue_free()
		_breach_countdown_layer = null
		_breach_countdown_label = null


# The actual detonation (delayed by the core-breach window): explosion effect +
# sound, a white-hot light flash, then the wrecked parts drop away.
func _detonate_mech() -> void:
	if not is_instance_valid(self):
		return
	var blast_pos := global_position + Vector3(0, 1.5, 0)
	EffectManager.spawn_explosion(blast_pos, 10.0)
	var mecha := get_parent()
	var is_enemy := mecha.is_in_group("enemy") if mecha else true
	EffectManager.apply_area_explosion_damage(blast_pos, 60.0, 10.0, is_enemy, "explosive", mecha)
	# Detonation flash: the breach glow slams white-hot and wide for a beat, then
	# dies with the blast. Freed via the timer's own signal (no coroutine on this
	# node, so a scene swap mid-flash can't leave a dangling await behind).
	if _breach_glow != null and is_instance_valid(_breach_glow):
		_breach_glow.light_energy = 14.0
		_breach_glow.omni_range = 12.0
		_breach_glow.light_color = Color.WHITE
		var glow := _breach_glow
		get_tree().create_timer(0.35).timeout.connect(glow.queue_free)
	for slot in parts:
		_hide_part(slot)


func _get_section_node(slot_name: String) -> Node3D:
	var mecha = get_parent()
	if mecha == null:
		return null
	match slot_name:
		"head":
			return mecha.get_node_or_null("Head")
		"body":
			return mecha.get_node_or_null("Body")
		"arm_left":
			return mecha.get_node_or_null("ArmLeft")
		"arm_right":
			return mecha.get_node_or_null("ArmRight")
		"leg_left":
			return mecha.get_node_or_null("LegLeft")
		"leg_right":
			return mecha.get_node_or_null("LegRight")
	return null


func _get_visual_container(slot_name: String, container_name: String) -> Node3D:
	var section = _get_section_node(slot_name)
	if section == null:
		return null
	return section.get_node_or_null(container_name)


func _apply_color_to_container(container: Node3D, color: Color) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.metallic = 0.6
			mat.roughness = 0.4
			child.material_override = mat


func _update_part_visual(slot_name: String) -> void:
	var mesh = parts[slot_name]["mesh"]
	var part = parts[slot_name]

	if part["armor_broken"]:
		var frame_ratio = part["frame_hp"] / maxf(part["max_frame"], 0.001)
		var color = _frame_color.lerp(_damage_color, 1.0 - frame_ratio)
		_apply_color_to_container(_get_visual_container(slot_name, "FrameMesh"), color)
		if mesh and mesh.material_override:
			mesh.material_override.albedo_color = color
	else:
		var armor_ratio = part["armor_hp"] / maxf(part["max_armor"], 0.001)
		var color = _armor_color.lerp(_damage_color, 1.0 - armor_ratio)
		_apply_color_to_container(_get_visual_container(slot_name, "ArmorMesh"), color)
		if mesh and mesh.material_override:
			mesh.material_override.albedo_color = color


func _show_frame(slot_name: String) -> void:
	var armor_container = _get_visual_container(slot_name, "ArmorMesh")
	if armor_container:
		armor_container.visible = false
	var frame_container = _get_visual_container(slot_name, "FrameMesh")
	if frame_container:
		frame_container.visible = true
	var mesh = parts[slot_name]["mesh"]
	if mesh and mesh.material_override:
		mesh.material_override.albedo_color = _frame_color


func _hide_part(slot_name: String) -> void:
	var armor_container = _get_visual_container(slot_name, "ArmorMesh")
	if armor_container:
		armor_container.visible = false
	var frame_container = _get_visual_container(slot_name, "FrameMesh")
	if frame_container:
		frame_container.visible = false
	var mesh = parts[slot_name]["mesh"]
	if mesh:
		mesh.visible = false


func _spawn_scrap_wreckage(slot_name: String) -> void:
	var section = _get_section_node(slot_name)
	if section == null:
		return
	var world = get_tree().current_scene
	if world == null:
		return

	var scrap := RigidBody3D.new()
	scrap.name = "Scrap_%s" % slot_name
	scrap.position = section.global_position + Vector3(0, 0.5, 0)
	scrap.add_to_group("scrap")
	scrap.collision_layer = 8
	scrap.collision_mask = 1

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = _get_scrap_size(slot_name)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	mat.metallic = 0.7
	mat.roughness = 0.6
	mesh_inst.material_override = mat
	scrap.add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	scrap.add_child(col)

	world.add_child(scrap)
	scrap.apply_central_impulse(Vector3(randf_range(-3, 3), randf_range(4, 8), randf_range(-3, 3)))
	scrap.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


func _get_scrap_size(slot_name: String) -> Vector3:
	match slot_name:
		"head":
			return Vector3(0.5, 0.45, 0.55)
		"body":
			return Vector3(0.9, 1.1, 0.7)
		"arm_left", "arm_right":
			return Vector3(0.4, 0.8, 0.4)
		"leg_left", "leg_right":
			return Vector3(0.5, 0.9, 0.5)
	return Vector3(0.5, 0.5, 0.5)


# The destroyed player part leaves a collectible scrap-material pickup so the
# wreckage actually becomes crafting material (matches the visual debris above).
func _spawn_part_scrap_pickup(slot_name: String) -> void:
	var scrap_amount := 3
	match slot_name:
		"head":
			scrap_amount = 4
		"body":
			scrap_amount = 5
		"arm_left", "arm_right", "leg_left", "leg_right":
			scrap_amount = 3
	var section = _get_section_node(slot_name)
	if section == null:
		return
	var loot = get_node_or_null("/root/GameWorld/LootSystem")
	if loot == null or not loot.has_method("spawn_scrap_pickup"):
		return
	loot.spawn_scrap_pickup(section.global_position + Vector3(0, 0.5, 0), scrap_amount)


# The arm frame holding the weapon broke → drop the weapon on that hand as a
# recoverable pickup. The weapon itself is NOT destroyed, only the frame was.
func _drop_hand_weapon_pickup(hand: String, arm_slot: String) -> void:
	var mecha = get_parent()
	if mecha == null:
		return
	var wm = mecha.get_node_or_null("WeaponManager")
	if wm == null or not wm.has_method("drop_weapon_from_destroyed_arm"):
		return
	var weapon: WeaponPart = wm.drop_weapon_from_destroyed_arm(hand)
	if weapon == null:
		return

	var section = _get_section_node(arm_slot)
	var drop_pos: Vector3 = global_position + Vector3(0, 1.0, 0)
	if section:
		drop_pos = section.global_position + Vector3(0, 0.5, 0)
	_spawn_weapon_pickup(drop_pos, weapon)


# Pressing X while selecting a weapon drops it as a recoverable pickup.
func _on_weapon_dropped(hand: String, weapon: WeaponPart) -> void:
	if weapon == null:
		return
	var drop_pos: Vector3 = global_position + Vector3(0, 1.0, 0)
	var section = _get_section_node("arm_left" if hand == "left" else "arm_right")
	if section:
		drop_pos = section.global_position + Vector3(0, 0.5, 0)
	_spawn_weapon_pickup(drop_pos, weapon)


func _spawn_weapon_pickup(drop_pos: Vector3, weapon: WeaponPart) -> void:
	var world = get_tree().current_scene
	if world == null:
		return

	var pickup := Area3D.new()
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	pickup.weapon_resource = weapon
	world.add_child(pickup)
	pickup.global_position = drop_pos

	# Keep the same pickup shape as the stock pickups in game_world.tscn.
	# The weapon model visual is created automatically by weapon_pickup._create_visual().
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 1.3)
	collision.shape = shape
	pickup.add_child(collision)


func _on_damage_received(_slot: String, _amount: float, _type: String) -> void:
	pass


# A friendly unit is the player mech or a fielded ally (group "ally"). An
# explicit set_friendly_light() override wins over the group check (allies set
# it because their group join happens after this system's _ready).
func _is_friendly() -> bool:
	if _friendly_light_override >= 0:
		return _friendly_light_override == 1
	if is_player:
		return true
	var parent = get_parent()
	return parent != null and parent.is_in_group("ally")


func get_health_percent() -> float:
	var max_total = max_total_armor + max_total_frame
	if max_total <= 0.0:
		return 0.0
	return (total_armor_hp + total_frame_hp) / max_total


func get_armor_percent() -> float:
	if max_total_armor <= 0.0:
		return 0.0
	return total_armor_hp / max_total_armor


func get_frame_percent() -> float:
	if max_total_frame <= 0.0:
		return 0.0
	return total_frame_hp / max_total_frame


func is_part_destroyed(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("destroyed", false)


# ---------------------------------------------------------------------------
# PILOT LIGHT + SPARKS
# ---------------------------------------------------------------------------

# Sets whether a pilot is on board. False turns the head light off and stops
# the damage sparks (an empty mech isn't being run by anyone).
func set_piloted(value: bool) -> void:
	_piloted = value
	_update_pilot_light()


# Overrides the head-light color (blue = friendly, red = hostile). Allies call
# this from their own _ready() because their health system initializes before
# they join the "ally" group, which would otherwise misread them as hostiles.
func set_friendly_light(friendly: bool) -> void:
	_friendly_light_override = 1 if friendly else 0
	if _pilot_light:
		_pilot_light.light_color = Color(0.3, 0.6, 1.0) if friendly else Color(1.0, 0.25, 0.2)


func _on_mecha_occupancy_changed(occupied: bool) -> void:
	set_piloted(occupied)


func _setup_pilot_light() -> void:
	var mecha := get_parent()
	if mecha == null:
		return
	_pilot_light = OmniLight3D.new()
	_pilot_light.name = "PilotLight"
	_pilot_light.light_color = Color(0.3, 0.6, 1.0) if _is_friendly() else Color(1.0, 0.25, 0.2)
	_pilot_light.light_energy = 2.5
	_pilot_light.omni_range = 4.0
	var head := mecha.get_node_or_null("Head")
	if head != null:
		_pilot_light.position = Vector3(0, 0.15, 0)
		head.add_child(_pilot_light)
	else:
		_pilot_light.position = Vector3(0, 2.4, 0)
		add_child(_pilot_light)
	_update_pilot_light()


func _update_pilot_light() -> void:
	if _pilot_light == null:
		return
	# The head light dies with the machine: no pilot, wrecked mech, lost head,
	# OR a destroyed BODY — the torso carries the engine core, so when it is
	# gone there is no power left for any light.
	_pilot_light.visible = _piloted and not is_destroyed \
		and not is_part_destroyed("head") and not is_part_destroyed("body")


# Damaged parts throw electrical sparks at their joints — but only while a
# pilot is running the machine.
func _process(delta: float) -> void:
	# No pilot, a wrecked mech, OR a destroyed BODY: the torso holds the engine
	# core, so when it is gone nothing on the mech is powered — no electrical
	# sparks anywhere, even from other destroyed limbs.
	if not _piloted or is_destroyed or is_part_destroyed("body"):
		return
	_spark_timer -= delta
	if _spark_timer > 0.0:
		return
	_spark_timer = 0.35
	for slot in parts:
		if parts[slot].get("destroyed", false):
			_spawn_part_spark(slot)


# A brief electric-arc flash at a destroyed part's joint (shoulder for arms,
# hip for legs, head position for a lost head).
func _spawn_part_spark(slot: String) -> void:
	var section := _get_section_node(slot)
	if section == null:
		return
	var world = get_tree().current_scene
	if world == null:
		return
	var spark_pos := section.global_position + Vector3(randf_range(-0.2, 0.2), randf_range(0.1, 0.4), randf_range(-0.2, 0.2))
	EffectFactory.spawn_box_spark(get_tree(), spark_pos,
		Vector3(0.06, 0.06, 0.5), Color(1.0, 0.85, 0.4), 0.1, 3.0)


func is_armor_broken(slot_name: String) -> bool:
	return parts.get(slot_name, {}).get("armor_broken", false)
