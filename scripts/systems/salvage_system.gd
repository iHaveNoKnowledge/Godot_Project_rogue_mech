class_name SalvageSystem
extends Node

var salvaged_weapons: Array[WeaponPart] = []
var salvaged_ammo: Dictionary = {}
var salvaged_items: Array[Dictionary] = []


func tag_for_salvage(weapon: WeaponPart) -> void:
	if not salvaged_weapons.has(weapon):
		salvaged_weapons.append(weapon)


func untag_salvage(weapon: WeaponPart) -> void:
	salvaged_weapons.erase(weapon)


func is_tagged(weapon: WeaponPart) -> bool:
	return salvaged_weapons.has(weapon)


func salvage_all() -> void:
	# Salvaged weapons are added to the central weapon_inventory stash so they
	# can be equipped from the Hangar (via the weapon tabs). Old save files may
	# still reference equipped_parts["salvaged_weapons"]; that slot is obsolete.
	for weapon in salvaged_weapons:
		LoadoutSystem.register_weapon(weapon.resource_path, weapon.weapon_name)
	GlobalData.save_run()
	salvaged_weapons.clear()


func get_salvaged_count() -> int:
	return salvaged_weapons.size()


## Collects a physical salvage piece (wreckage, component, raw material).
## If the physical salvage object references a tech_id, records technology salvage evidence.
func collect_salvage(salvage_item: Dictionary) -> void:
	salvaged_items.append(salvage_item.duplicate(true))
	var tid := extract_tech_id(salvage_item)
	if tid != "":
		# If previously unknown, observing this physical wreckage encounters it first
		if TechnologySystem.get_discovery_state(tid) == TechnologySystem.DiscoveryState.UNKNOWN:
			TechnologySystem.record_technology_encountered(tid, {"source": "salvage_observed", "salvage_item": salvage_item})
		# Acquiring the physical evidence transitions to SALVAGED
		TechnologySystem.record_technology_salvaged(tid, {"source": "salvage_acquired", "salvage_item": salvage_item})
		TechnologySystem.add_technology_evidence(tid, 1.0, {"source": "salvage_acquired", "salvage_item": salvage_item})
		var tree := Engine.get_main_loop() as SceneTree
		if tree and tree.root and tree.root.has_node("EventBus"):
			var bus = tree.root.get_node("EventBus")
			if bus.has_signal("technology_salvaged"):
				bus.technology_salvaged.emit(tid, salvage_item)


## Returns all physical salvage items that reference a specific tech_id.
func get_salvaged_evidence_for_tech(tech_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for it in salvaged_items:
		if extract_tech_id(it) == tech_id:
			result.append(it.duplicate(true))
	return result


## Checks if physical salvage evidence has been acquired for a specific technology.
func has_salvaged_evidence_for_tech(tech_id: String) -> bool:
	for it in salvaged_items:
		if extract_tech_id(it) == tech_id:
			return true
	return false


## Static helper to extract technology ID referenced by a salvage item dictionary or object.
static func extract_tech_id(salvage_item: Variant) -> String:
	return TechnologySystem.resolve_item_technology_id(salvage_item)


## Static helper to check whether a salvage object carries technology evidence.
static func is_technology_evidence(salvage_item: Variant) -> bool:
	return TechnologySystem.is_technology_evidence(salvage_item)


func serialize_salvage() -> Dictionary:
	return {
		"items": salvaged_items.duplicate(true)
	}


func deserialize_salvage(data: Variant) -> void:
	salvaged_items.clear()
	if data is Dictionary and data.has("items") and data["items"] is Array:
		salvaged_items = Array(data["items"]).duplicate(true)


func reset() -> void:
	salvaged_weapons.clear()
	salvaged_ammo.clear()
	salvaged_items.clear()
