class_name EnemyHealth
extends MechaHealthBase

# Which enemy body layout this health system drives. The scene (or the spawning
# code for tanks) picks the variant; each one defines its own part table and
# mesh lookups. SIMPLE = single-body placeholder grunt (enemy_dummy.tscn),
# FULL = six-slot mech (ranged/heavy/support/boss/ally scenes), TANK =
# hull/turret/treads with mobility/turret-kill behavior (enemy_tank.gd).
enum Layout { SIMPLE, FULL, TANK }

@export var layout: Layout = Layout.SIMPLE

# Tank-specific signals (only emitted by the TANK layout).
signal mobility_lost()
signal turret_disabled()

# -----------------------------------------------------------------------------
# SHIELD ABSORPTION
# Shield archetypes (enemy_dummy archetype 4/5) carry an energy shield on the
# mech root. Every damage path funnels into _apply_armor_damage/_apply_frame_
# damage, so absorbing here covers bullets, splash, melee and direct calls —
# exactly once per hit (the base call chain never re-enters these two).
# -----------------------------------------------------------------------------

func _apply_armor_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var remaining := _absorb_with_shield(amount, damage_type)
	if remaining <= 0.0:
		return
	super._apply_armor_damage(slot_name, remaining, damage_type)


func _apply_frame_damage(slot_name: String, amount: float, damage_type: String) -> void:
	var remaining := _absorb_with_shield(amount, damage_type)
	if remaining <= 0.0:
		return
	super._apply_frame_damage(slot_name, remaining, damage_type)


# Asks the parent mech (enemy_dummy.gd) to absorb damage into its raised
# plate. Non-shield enemies simply pass the amount through untouched.
func _absorb_with_shield(amount: float, damage_type: String) -> float:
	var mecha := get_parent()
	if mecha == null or not mecha.get("shield_active") or not mecha.has_method("absorb_damage_with_shield"):
		return amount
	var remaining: float = mecha.absorb_damage_with_shield(amount, damage_type)
	var absorbed := amount - remaining
	if absorbed > 0.0:
		var barrier_pos := global_position + Vector3(0, 1.5, 0)
		# Shield-hit feedback: a spark at the plate plus a metallic clang, so
		# blocked shots read as blocked instead of silently vanishing. The
		# shatter only plays when the hit actually drained the shield to zero
		# (a blocked hit that leaves HP remaining still just clangs).
		EffectManager.spawn_impact(barrier_pos, Vector3.UP)
		if AudioManager:
			if mecha.shield_current_hp <= 0.0:
				AudioManager.play_shield_break(barrier_pos)
			else:
				AudioManager.play_shield_block(barrier_pos)
	return remaining


func take_heal(amount: float) -> void:
	if is_destroyed:
		return
	# The legacy tank health had no take_heal, so support units (which gate on
	# has_method("take_heal")) could never heal tanks. Preserve that behavior.
	if layout == Layout.TANK:
		return
	# Heal the most damaged alive part. SIMPLE has a single "body" part, so it
	# behaves exactly like the legacy single-part heal (even at full HP the part
	# is selected and the heal just clamps); FULL/TANK heal the wounded slot
	# they actually track.
	var worst_slot := ""
	var worst_ratio := INF
	for slot in parts:
		if parts[slot]["destroyed"]:
			continue
		var ratio = parts[slot]["frame_hp"] / parts[slot]["max_frame"]
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst_slot = slot
	if worst_slot != "":
		parts[worst_slot]["frame_hp"] = minf(
			parts[worst_slot]["frame_hp"] + amount,
			parts[worst_slot]["max_frame"]
		)
		health_changed.emit(worst_slot, "frame", parts[worst_slot]["frame_hp"], parts[worst_slot]["max_frame"])


func _init_parts() -> void:
	match layout:
		Layout.FULL:
			parts = {
				"head": {
					"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 1.0,
					"frame_hp": 30.0, "max_frame": 30.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"body": {
					"armor_hp": 80.0, "max_armor": 80.0, "armor_class": 0.9,
					"frame_hp": 60.0, "max_frame": 60.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"arm_left": {
					"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
					"frame_hp": 20.0, "max_frame": 20.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"arm_right": {
					"armor_hp": 30.0, "max_armor": 30.0, "armor_class": 0.8,
					"frame_hp": 20.0, "max_frame": 20.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"leg_left": {
					"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.7,
					"frame_hp": 30.0, "max_frame": 30.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"leg_right": {
					"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.7,
					"frame_hp": 30.0, "max_frame": 30.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
			}
		Layout.TANK:
			parts = {
				"hull": {
					"armor_hp": 80.0, "max_armor": 80.0, "armor_class": 1.2,
					"frame_hp": 60.0, "max_frame": 60.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"turret": {
					"armor_hp": 40.0, "max_armor": 40.0, "armor_class": 0.9,
					"frame_hp": 30.0, "max_frame": 30.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
				"treads": {
					"armor_hp": 50.0, "max_armor": 50.0, "armor_class": 0.7,
					"frame_hp": 40.0, "max_frame": 40.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				}
			}
		_:  # Layout.SIMPLE
			parts = {
				"body": {
					"armor_hp": 100.0, "max_armor": 100.0, "armor_class": 0.8,
					"frame_hp": 100.0, "max_frame": 100.0,
					"armor_broken": false, "destroyed": false, "mesh": null
				},
			}
	is_player = false


func _find_meshes() -> void:
	match layout:
		Layout.FULL:
			var mappings = {
				"head": "../Head/HeadMesh",
				"body": "../Body/BodyMesh",
				"arm_left": "../ArmLeft/ArmLeftMesh",
				"arm_right": "../ArmRight/ArmRightMesh",
				"leg_left": "../LegLeft/LegLeftMesh",
				"leg_right": "../LegRight/LegRightMesh",
			}
			for slot in mappings:
				var node = get_node_or_null(mappings[slot])
				if node:
					parts[slot]["mesh"] = node
					_original_colors[slot] = node.material_override.albedo_color if node.material_override else Color(0.8, 0.2, 0.2, 1)
		Layout.TANK:
			var hull_node = get_node_or_null("../HullMesh")
			var turret_node = get_node_or_null("../TurretMesh")
			var treads_node = get_node_or_null("../TreadsMesh")
			if hull_node: parts["hull"]["mesh"] = hull_node
			if turret_node: parts["turret"]["mesh"] = turret_node
			if treads_node: parts["treads"]["mesh"] = treads_node
		_:  # Layout.SIMPLE
			var node = get_node_or_null("../BodyMesh")
			if node:
				parts["body"]["mesh"] = node
				_original_colors["body"] = node.material_override.albedo_color if node.material_override else Color(0.8, 0.2, 0.2, 1)


# TANK-only: a destroyed part permanently cripples the vehicle (mobility kill /
# turret kill). Other layouts keep the base part-destroyed behavior untouched.
func _on_frame_destroyed(slot_name: String) -> void:
	super._on_frame_destroyed(slot_name)
	if layout != Layout.TANK:
		return

	match slot_name:
		"treads":
			mobility_lost.emit()
			if get_parent() and get_parent().has_method("disable_movement"):
				get_parent().disable_movement()
		"turret":
			turret_disabled.emit()
			if get_parent() and get_parent().has_method("disable_weapons"):
				get_parent().disable_weapons()
		"hull":
			# super._on_frame_destroyed already fires _on_mecha_destroyed when
			# total_frame_hp hits 0 — guard against double explosion / loot.
			if not is_destroyed:
				_on_mecha_destroyed()
