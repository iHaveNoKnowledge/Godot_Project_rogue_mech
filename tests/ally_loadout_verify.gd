extends Node

## Headless verification that a fielded ally fights with its hangar mech's ACTUAL
## loadout instead of the generic template stats: the armor/frame HP written into
## the health system comes from the berth's equipped plates, and the attack
## stats + WeaponCore come from the equipped weapon.
## Run: godot --headless --path . res://tests/ally_loadout_verify.tscn

var _fails: int = 0
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _verify_armor_loadout()
	await _verify_weapon_loadout()
	await _verify_empty_loadout_falls_back()
	await _verify_friendly_light()
	await _verify_catalog_body()
	await _verify_weapon_ai_decisions()
	await _verify_ammo_scavenging()
	await _verify_destroyed_ally_leaves_team()
	print("ALLY_LOADOUT_VERIFY: checks=%d fails=%d" % [_checks, _fails])
	await get_tree().process_frame
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("FAIL: " + label)


# A berth snapshot with a heavy chest plate (hp 110, armor 75) on a reinforced
# composite torso frame (hp 75). After apply_mech_loadout the ally's body slot
# must carry those exact values.
func _verify_armor_loadout() -> void:
	var ally = _spawn_ally()
	var mech := {
		"id": "mech_test",
		"parts": {"body": {"id": "body_002"}},
		"frames": {"body": {"id": "frame_body_03"}},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	ally.apply_mech_loadout(mech)
	var body: Dictionary = ally.health_system.parts["body"]
	var frame_hp: float = 75.0 + GlobalData.get_frame_upgrade_hp_bonus()
	_check(is_equal_approx(body["max_armor"], 110.0), "ally body armor HP comes from the equipped plate")
	_check(is_equal_approx(body["armor_hp"], 110.0), "ally body armor starts full")
	_check(is_equal_approx(body["max_frame"], frame_hp), "ally body frame HP comes from the equipped inner frame")
	_check(is_equal_approx(body["armor_class"], 7.5), "ally body armor_class derives from the plate armor value")
	# Total HP reflects the real plates, not the template's frame_hp budget.
	# FULL-layout defaults sum to 260 armor; the body plate override (80 -> 110)
	# pushes the total to 290, proving the mech plates were applied.
	_check(is_equal_approx(ally.health_system.max_total_armor, 290.0), "ally total armor HP uses the mech plates")
	ally.queue_free()
	await get_tree().process_frame


# A RANGED berth carrying a Beam Rifle (damage 25, range 55, mag 40): the ally's
# attack stats and fire core must match the gun, and a weapon model gets mounted.
func _verify_weapon_loadout() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Test Pilot")  # RANGED archetype
	var mech := {
		"id": "mech_test",
		"parts": {},
		"frames": {},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {
			"left": "",
			"right": "res://resources/mech/stock/weapon_beam_rifle.tres",
			"carry": [],
		},
	}
	ally.apply_mech_loadout(mech)
	_check(is_equal_approx(ally.attack_damage, 25.0), "ally attack damage comes from the equipped weapon")
	_check(is_equal_approx(ally.attack_range, 55.0), "ally attack range comes from the weapon range")
	_check(ally.fire_core != null and ally.fire_core.max_ammo == 40, "ally fire core carries the weapon magazine")
	_check(ally.fire_core != null and is_equal_approx(ally.fire_core.damage, 25.0), "ally fire core damage matches the weapon")
	_check(ally.get_node_or_null("AllyWeaponVisualRight") != null, "ally mounts the equipped weapon model")
	ally.queue_free()
	await get_tree().process_frame


# A berth with no weapons keeps the template combat stats instead of zeroing out.
func _verify_empty_loadout_falls_back() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Empty Pilot")
	var mech := {
		"id": "mech_test",
		"parts": {},
		"frames": {},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	ally.apply_mech_loadout(mech)
	_check(ally.attack_damage > 0.0, "empty loadout keeps template attack damage")
	_check(ally.fire_core != null and ally.fire_core.damage == ally.attack_damage, "empty loadout keeps template fire core")
	ally.queue_free()
	await get_tree().process_frame


# Allies are OUR side: the head light must read friendly blue (not hostile red)
# even though the health system's _ready runs before the ally joins the group.
func _verify_friendly_light() -> void:
	var ally = _spawn_ally()
	var hs = ally.health_system
	_check(hs.get("_friendly_light_override") == 1, "ally health system is flagged friendly")
	var light = hs.get("_pilot_light") as OmniLight3D
	_check(light != null, "ally has a pilot head light")
	if light:
		_check(light.light_color.b > 0.7 and light.light_color.r < 0.5, "ally head light is blue (friendly)")
		_check(light.visible, "ally pilot light is on")
	ally.queue_free()
	await get_tree().process_frame


# The ally's body must be rebuilt from the berth's armor/frame plates via
# PartMeshManager (same path as the hangar), not the scene's placeholder meshes.
func _verify_catalog_body() -> void:
	var ally = _spawn_ally()
	var mech := {
		"id": "mech_test",
		"parts": {"body": {"id": "body_002"}},
		"frames": {"body": {"id": "frame_body_03"}},
		"damage": {},
		"scrap_patches": {},
		"weapon_loadout": {"left": "", "right": "", "carry": []},
	}
	ally.apply_mech_loadout(mech)
	_check(ally.get_node_or_null("CatalogBody") != null, "ally builds a CatalogBody PartMeshManager")
	_check(ally.catalog_body != null and ally.catalog_body.slot_meshes is Dictionary, "catalog body has per-slot mesh entries")
	_check(not ally.get_node_or_null("Body/BodyMesh").visible, "placeholder body mesh hidden behind catalog plates")
	_check(ally.catalog_body.slot_meshes.has("body"), "catalog body assembled the body slot")
	ally.queue_free()
	await get_tree().process_frame


# Weapon-situation AI: blade-only berth always melee, gun-only always ranged,
# both weapons -> blade in reach, gun at range, blade when the gun is dry.
func _verify_weapon_ai_decisions() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Decider")
	var blade := {"left": "", "right": "res://resources/mech/stock/weapon_heat_blade.tres", "carry": []}
	var gun := {"left": "", "right": "res://resources/mech/stock/weapon_beam_rifle.tres", "carry": []}
	var both := {"left": "res://resources/mech/stock/weapon_heat_blade.tres", "right": "res://resources/mech/stock/weapon_beam_rifle.tres", "carry": []}

	ally.apply_mech_loadout({"weapon_loadout": blade})
	_check(ally._prefers_melee(999.0), "blade-only loadout always melee even far away")

	ally.apply_mech_loadout({"weapon_loadout": gun})
	_check(not ally._prefers_melee(3.0), "gun-only loadout always ranged even up close")

	ally.apply_mech_loadout({"weapon_loadout": both})
	_check(ally._prefers_melee(2.0), "gun+blade loadout uses the blade when the enemy is in reach")
	_check(not ally._prefers_melee(30.0), "gun+blade loadout uses the gun at range")
	ally.fire_core.ammo = 0
	_check(ally._prefers_melee(30.0), "gun+blade loadout falls back to the blade when out of ammo")
	ally.queue_free()
	await get_tree().process_frame


# Ammo scavenging: the ally notices a dry magazine, walks to the nearest ground
# ammo box and refills the magazine from it.
func _verify_ammo_scavenging() -> void:
	var ally = _spawn_ally()
	ally.apply_mech_override(1, "Scavenger")
	var gun := {"left": "", "right": "res://resources/mech/stock/weapon_beam_rifle.tres", "carry": []}
	ally.apply_mech_loadout({"weapon_loadout": gun})
	ally.global_position = Vector3.ZERO
	var pickup := Area3D.new()
	pickup.add_to_group("loot_pickup")
	pickup.set_meta("loot_data", {"type": "ammo", "amount": 15})
	add_child(pickup)
	pickup.global_position = Vector3(4, 0, 0)

	_check(not ally._wants_ammo_pickup(), "full magazine does not trigger scavenging")
	ally.fire_core.ammo = 0
	_check(ally._wants_ammo_pickup(), "dry magazine triggers scavenging")
	var found = ally._find_ammo_pickup()
	_check(found == pickup, "ally finds the nearest ground ammo box")
	# Simulate reaching the box: collect refills the magazine and frees the box.
	ally._collect_ammo_pickup(pickup)
	_check(ally.fire_core.ammo == 15, "collecting ammo refills the magazine")
	await get_tree().process_frame
	_check(not is_instance_valid(pickup), "collected ammo box is freed")
	ally.queue_free()
	await get_tree().process_frame


func _spawn_ally() -> Node:
	var scene = load("res://scenes/mecha/ally_dummy.tscn")
	var ally = scene.instantiate()
	ally.template_id = "ally_gm"
	add_child(ally)
	return ally


# A destroyed squadmate is GONE for the rest of the run: the fleet roster entry
# is flagged destroyed (so they never field again) and the berth they piloted
# is pulled from the hangar (a wrecked mech doesn't stay in the convoy).
func _verify_destroyed_ally_leaves_team() -> void:
	var template_id := "ally_gm"
	var pilot_id := "fleet_" + template_id
	# Make sure this template is registered, then park a berth assigned to it.
	FleetSystem.add_ally_unit(template_id)
	var parked := HangarManager.park_ally_mech("Wing Mech", pilot_id, 1)
	_check(not parked.is_empty(), "test parked an ally berth")
	var mech_id := str(parked.get("id", ""))
	var before := GlobalData.get_hangar_mechs().size()

	var ally = _spawn_ally()
	var unit = FleetSystem.get_fleet_unit(template_id)
	_check(not unit.is_empty() and not bool(unit.get("destroyed", false)), "ally unit starts alive")
	ally._on_destroyed()
	_check(bool(unit.get("destroyed", false)), "destroyed ally unit is flagged dead in the fleet roster")
	_check(GlobalData.get_hangar_mechs().size() == before - 1, "destroyed ally's berth is removed from the hangar")
	_check(GlobalData.get_hangar_mechs().size() == before - 1 and not _hangar_has_mech(mech_id), "the piloted mech id is gone from the convoy")
	# A second destroy emit (body-break + frame-loss double fire) must not double-remove.
	ally._on_destroyed()
	_check(GlobalData.get_hangar_mechs().size() == before - 1, "double destroy emit does not remove twice")
	ally.queue_free()
	await get_tree().process_frame


func _hangar_has_mech(mech_id: String) -> bool:
	for mech in GlobalData.get_hangar_mechs():
		if mech is Dictionary and str(mech.get("id", "")) == mech_id:
			return true
	return false
