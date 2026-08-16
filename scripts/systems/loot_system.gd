extends Node3D

var loot_items: Array = []
var pickup_radius: float = 2.0


func spawn_loot(position: Vector3, loot_table: Array) -> void:
	for item in loot_table:
		if randf() < item.get("drop_chance", 0.5):
			_create_loot_pickup(position + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), item)


func _create_loot_pickup(pos: Vector3, loot_data: Dictionary) -> void:
	# Weapon drops use the same interactable pickup as stock pickups so the player
	# can decide (press F) whether to take the weapon or just its ammo.
	if loot_data.get("type", "ammo") == "weapon" and loot_data.get("weapon") is WeaponPart:
		_create_weapon_pickup(pos, loot_data["weapon"])
		return

	var pickup = Area3D.new()
	pickup.collision_layer = 1
	pickup.collision_mask = 1

	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.radius = pickup_radius
	collision.shape = shape
	pickup.add_child(collision)

	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.5)
	mesh.mesh = box
	mesh.position.y = 0.5
	pickup.add_child(mesh)

	var material = StandardMaterial3D.new()
	match loot_data.get("type", "ammo"):
		"weapon":
			material.albedo_color = Color(0.9, 0.7, 0.1)
		"ammo":
			material.albedo_color = Color(0.2, 0.8, 0.2)
		"repair":
			material.albedo_color = Color(0.2, 0.2, 0.9)
		"scrap":
			material.albedo_color = Color(0.75, 0.55, 0.25)
			box.size = Vector3(0.4, 0.4, 0.4)
		"armor":
			material.albedo_color = Color(0.85, 0.35, 0.85)
			box.size = Vector3(0.5, 0.5, 0.5)
	mesh.set_surface_override_material(0, material)

	pickup.set_meta("loot_data", loot_data)
	pickup.add_to_group("loot_pickup")
	pickup.body_entered.connect(_on_pickup_body_entered.bind(pickup))
	get_parent().add_child(pickup)
	pickup.global_position = pos


func _create_weapon_pickup(pos: Vector3, weapon: WeaponPart) -> void:
	var pickup := Area3D.new()
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.set_script(load("res://scripts/mecha/weapon_pickup.gd"))
	pickup.weapon_resource = weapon
	get_parent().add_child(pickup)
	pickup.global_position = pos

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.5, 1.3)
	collision.shape = shape
	pickup.add_child(collision)


func _on_pickup_body_entered(body: Node3D, pickup: Area3D) -> void:
	if not body.is_in_group("mecha"):
		return
	var loot_data = pickup.get_meta("loot_data", {})
	match loot_data.get("type", "ammo"):
		"weapon":
			var weapon: WeaponPart = loot_data.get("weapon")
			if weapon:
				var wm = body.get_node_or_null("WeaponManager")
				if wm:
					wm.add_weapon(weapon)
		"ammo":
			var amount: int = loot_data.get("amount", 10)
			var wm = body.get_node_or_null("WeaponManager")
			if wm:
				wm.add_ammo(amount)
		"repair":
			var slot: String = loot_data.get("slot", "")
			if slot:
				# Armor damage key is the bare slot name ("body"); frame damage
				# uses the "_frame" suffix. (Do NOT use slot + "_armor".)
				GlobalData.part_damage.erase(slot)
				GlobalData.part_damage.erase(slot + "_frame")
				EventBus.weight_changed.emit(0.0)
		"scrap":
			GlobalData.gain_scrap(loot_data.get("amount", 1))
		"armor":
			# Salvaged plate from a destroyed enemy: grants a real armor instance
		# (slot picked at drop time) into the convoy's armor inventory.
			var inst: Dictionary = loot_data.get("instance", {})
			if not inst.is_empty() and GlobalData.get_armor_instance(str(inst.get("uid", ""))).is_empty():
				GlobalData.armor_inventory.append(inst)
				GlobalData.run_notice = "Salvaged armor: %s" % str(inst.get("name", "plate"))
	pickup.queue_free()


# Spawns a single scrap-material pickup (used by wreckage debris when a player
# part is destroyed mid-combat). Amount is the scrap granted on collection.
func spawn_scrap_pickup(pos: Vector3, amount: int) -> void:
	_create_loot_pickup(pos, {"type": "scrap", "amount": maxi(1, amount)})


# Weapon pools per enemy archetype. Loot drops the SAME kind of weapon the
# enemy fought with (melee rushers drop blades, ranged drop guns, heavies drop
# heavy cannons, supports drop support systems), picked occasionally.
const ARCHETYPE_WEAPON_POOLS: Dictionary = {
	0: [
		preload("res://resources/mech/stock/weapon_combat_knife.tres"),
		preload("res://resources/mech/stock/weapon_mace.tres"),
		preload("res://resources/mech/stock/weapon_sawed_off.tres"),
		preload("res://resources/mech/stock/weapon_heat_blade.tres"),
		preload("res://resources/mech/stock/weapon_pile_bunker.tres"),
		preload("res://resources/mech/stock/weapon_combat_shotgun.tres"),
	],
	1: [
		preload("res://resources/mech/stock/weapon_beam_carbine.tres"),
		preload("res://resources/mech/stock/weapon_light_machine_gun.tres"),
		preload("res://resources/mech/stock/weapon_machine_gun.tres"),
		preload("res://resources/mech/stock/weapon_beam_rifle.tres"),
		preload("res://resources/mech/stock/weapon_beam_rifle_mk2.tres"),
		preload("res://resources/mech/stock/weapon_beam_sniper.tres"),
		preload("res://resources/mech/stock/weapon_railgun.tres"),
	],
	2: [
		preload("res://resources/mech/stock/weapon_heavy_machine_gun.tres"),
		preload("res://resources/mech/stock/weapon_assault_cannon.tres"),
		preload("res://resources/mech/stock/weapon_gatling_gun.tres"),
		preload("res://resources/mech/stock/weapon_heavy_missile.tres"),
	],
	3: [
		preload("res://resources/mech/stock/weapon_micro_missile.tres"),
		preload("res://resources/mech/stock/weapon_swarm_missile.tres"),
		preload("res://resources/mech/stock/weapon_light_buckler.tres"),
		preload("res://resources/mech/stock/weapon_heavy_shield.tres"),
	],
	4: [
		# Shield melee: blades + shields (drop what it fought with)
		preload("res://resources/mech/stock/weapon_combat_knife.tres"),
		preload("res://resources/mech/stock/weapon_mace.tres"),
		preload("res://resources/mech/stock/weapon_heat_blade.tres"),
		preload("res://resources/mech/stock/weapon_pile_bunker.tres"),
		preload("res://resources/mech/stock/weapon_light_buckler.tres"),
		preload("res://resources/mech/stock/weapon_shield.tres"),
	],
	5: [
		# Shield ranged: guns + shields
		preload("res://resources/mech/stock/weapon_beam_carbine.tres"),
		preload("res://resources/mech/stock/weapon_machine_gun.tres"),
		preload("res://resources/mech/stock/weapon_light_machine_gun.tres"),
		preload("res://resources/mech/stock/weapon_light_buckler.tres"),
		preload("res://resources/mech/stock/weapon_shield.tres"),
	],
}

# Chance a defeated enemy drops the weapon it actually used (grunts modest,
# aces/bosses richer). Tuned so loot stays occasional.
const BASE_WEAPON_DROP_CHANCE: float = 0.12


func spawn_enemy_loot(enemy_position: Vector3, archetype: int = -1) -> void:
	var loot_table = [
		{"type": "ammo", "amount": 15, "drop_chance": 0.7},
		{"type": "ammo", "amount": 25, "drop_chance": 0.3},
		{"type": "scrap", "amount": 3, "drop_chance": 0.35},
		{"type": "scrap", "amount": 5, "drop_chance": 0.2},
		{"type": "repair", "slot": "body", "drop_chance": 0.15},
		{"type": "armor", "instance": _roll_salvaged_armor(), "drop_chance": 0.14},
	]

	# Occasionally drop the same kind of weapon the enemy used in combat. A
	# single archetype-matched pool keeps the drop thematic and readable.
	if archetype >= 0 and ARCHETYPE_WEAPON_POOLS.has(archetype):
		var pool: Array = ARCHETYPE_WEAPON_POOLS[archetype]
		if not pool.is_empty():
			var weapon: WeaponPart = pool[randi() % pool.size()]
			loot_table.append({"type": "weapon", "weapon": weapon, "drop_chance": BASE_WEAPON_DROP_CHANCE})

	# Weapons and armor parts are held for the POST-BATTLE summary instead of
	# becoming walk-over pickups: the player picks what to take back from the
	# summary screen (combat_rewards_ui). Ammo / scrap / repair still drop as
	# physical pickups for instant use mid-battle.
	var pickup_table: Array = []
	for item in loot_table:
		var drop_type := str(item.get("type", "ammo"))
		if drop_type == "weapon" or drop_type == "armor":
			if randf() < item.get("drop_chance", 0.5):
				GlobalData.battle_loot.append(item)
		else:
			pickup_table.append(item)
	spawn_loot(enemy_position, pickup_table)


# A random non-blueprint armor plate off the enemy's wreck, as a real armor
# instance the hangar can equip. Occasional (not every kill) by design.
func _roll_salvaged_armor() -> Dictionary:
	var slots: Array[String] = ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]
	var slot: String = slots[randi() % slots.size()]
	var catalog: Array = GlobalData.armor_catalog.get(slot, [])
	var eligible: Array = []
	for entry in catalog:
		if entry is Dictionary and not entry.get("blueprint_only", false):
			eligible.append(entry)
	if eligible.is_empty():
		return {}
	var picked: Dictionary = eligible[randi() % eligible.size()]
	# Build the instance WITHOUT adding it to the inventory — the pickup grants
	# it when the player actually walks over the wreck (make_armor_instance_from_catalog
	# appends immediately, which would hand out the plate even if never picked up).
	var instance := picked.duplicate(true)
	instance["uid"] = GlobalData._new_uid("a")
	instance["db_id"] = picked.get("id", "")
	instance["slot"] = slot
	instance["durability"] = 1.0
	instance["upgrade_level"] = 1
	instance["equipped"] = false
	return instance
