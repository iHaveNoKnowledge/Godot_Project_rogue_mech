extends Node
## TECHNOLOGY OBSERVATION BOUNDARY VERIFICATION (PHASE 2E-3B)
## Validates the gameplay-driven observation boundary:
## 1. Legitimate gameplay observation causes UNKNOWN -> ENCOUNTERED
## 2. Repeated observation is idempotent (no duplicate transition)
## 3. Observation cannot jump UNKNOWN -> SALVAGED
## 4. Observation cannot regress ENCOUNTERED -> UNKNOWN
## 5. Enemy spawn alone does NOT automatically discover technology (possession != observation)
## 6. Faction technology availability does not change player discovery
## 7. Active prototype state does not change player discovery until combat observation occurs
## 8. Player observation does not modify faction technology state
## 9. Existing Phase 2E-3A salvage behavior remains intact
## 10. Existing save/load persistence remains compatible

var _fails: int = 0
var _checks: int = 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const EraProgSys = preload("res://scripts/systems/era_progression_system.gd")
const RivalProgSys = preload("res://scripts/systems/rival_progression_system.gd")
const SalvageSys = preload("res://scripts/systems/salvage_system.gd")
const WeaponCoreScript = preload("res://scripts/systems/weapon_core.gd")


func _check(cond: bool, test_name: String) -> void:
	_checks += 1
	if cond:
		print("OBS_BOUND_OK: " + test_name)
	else:
		_fails += 1
		printerr("OBS_BOUND_FAIL: " + test_name)


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	print("\n=== STARTING TECHNOLOGY OBSERVATION BOUNDARY VERIFICATION (PHASE 2E-3B) ===")
	_test_gameplay_observation_unknown_to_encountered()
	_test_repeated_observation_idempotent()
	_test_observation_cannot_jump_to_salvaged()
	_test_observation_cannot_regress_state()
	_test_enemy_spawn_alone_does_not_discover()
	_test_faction_availability_does_not_discover()
	_test_active_prototype_requires_actual_observation()
	_test_player_observation_does_not_alter_faction_state()
	_test_phase_2e_3a_salvage_path_preserved()
	_test_save_load_persistence_compatibility()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_3B_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_3B_FAILED")
		get_tree().quit(1)


func _spawn_mock_enemy(tech_id: String) -> CharacterBody3D:
	var scene = load("res://scenes/mecha/enemy_dummy.tscn")
	var enemy = scene.instantiate()
	enemy.observed_tech_id = tech_id
	add_child(enemy)
	return enemy


func _test_gameplay_observation_unknown_to_encountered() -> void:
	print("\n-- [1] Legitimate Gameplay Observation (UNKNOWN -> ENCOUNTERED) --")
	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()

	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[1a] Tech starts UNKNOWN")

	# Mock an EnemyDummy instance in combat
	var enemy = _spawn_mock_enemy(tech_id)
	enemy.name = "EnemyPrototypeTest"

	# Firing in combat exposes the technology through EventBus
	enemy.report_technology_observation("weapon_fired")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[1b] Weapon firing transitioned tech to ENCOUNTERED")
	_check(TechSys.get_discovery_state_name(tech_id) == "ENCOUNTERED", "[1c] Discovery state name is ENCOUNTERED")

	enemy.queue_free()


func _test_repeated_observation_idempotent() -> void:
	print("\n-- [2] Repeated Observation Idempotence --")
	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2a] Current state is ENCOUNTERED")

	# Multiple shots or multiple enemies observing the same technology
	var enemy2 = _spawn_mock_enemy(tech_id)

	# First report on new enemy instance
	enemy2.report_technology_observation("weapon_fired")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2b] State remains ENCOUNTERED (no duplicate mutation)")

	# Subsequent reports on same instance are filtered locally
	enemy2.report_technology_observation("weapon_fired")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[2c] Multiple calls filtered without error")

	enemy2.queue_free()


func _test_observation_cannot_jump_to_salvaged() -> void:
	print("\n-- [3] Observation Cannot Jump to SALVAGED --")
	var tech_id := "tech_high_energy_barrier"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	var enemy = _spawn_mock_enemy(tech_id)

	# Observe barrier deflection in combat
	enemy.report_technology_observation("barrier_deflection")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[3a] Barrier observation only advances to ENCOUNTERED")
	_check(TechSys.get_discovery_state(tech_id) != TechSys.DiscoveryState.SALVAGED, "[3b] Observation cannot jump directly to SALVAGED")

	enemy.queue_free()


func _test_observation_cannot_regress_state() -> void:
	print("\n-- [4] Observation Cannot Regress State --")
	var tech_id := "tech_cryo_cooling"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.SALVAGED)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4a] Starting at SALVAGED")

	# An enemy firing a cryo weapon after the player already salvaged evidence
	var enemy = _spawn_mock_enemy(tech_id)

	enemy.report_technology_observation("weapon_fired")
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[4b] Observing technology while SALVAGED preserves SALVAGED state (no regression)")

	enemy.queue_free()


func _test_enemy_spawn_alone_does_not_discover() -> void:
	print("\n-- [5] Enemy Spawn Alone Does NOT Discover Technology --")
	var tech_id := "tech_valkryon_actuator_chassis"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[5a] Tech starts UNKNOWN")

	# Spawn enemy instance carrying the technology in metadata
	var enemy = _spawn_mock_enemy(tech_id)

	# Enemy spawned into the tree, but has NOT engaged or acted
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[5b] Merely spawning in scene tree leaves state at UNKNOWN")
	_check(TechSys.get_discovery_state_name(tech_id) == "UNKNOWN", "[5c] Discovery state name remains UNKNOWN")

	# Enemy is defeated or leaves without firing
	enemy.queue_free()
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[5d] State remains UNKNOWN if enemy never performs observable action")


func _test_faction_availability_does_not_discover() -> void:
	print("\n-- [6] Faction Availability Does NOT Discover Technology --")
	TechSys.reset_world_diffusion_state()
	var tech_id := "tech_modular_energy_interface"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	# Rival faction researches and unlocks the technology
	TechSys.grant_faction_technology("rival", tech_id)
	_check(TechSys.has_faction_technology("rival", tech_id), "[6a] Rival faction possesses technology")

	# Player discovery MUST remain UNKNOWN
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[6b] Player discovery remains UNKNOWN after rival research")
	_check(not TechSys.is_technology_usable(tech_id), "[6c] Player cannot use faction technology")


func _test_active_prototype_requires_actual_observation() -> void:
	print("\n-- [7] Active Prototype Requires Actual Observation --")
	RivalProgSys.reset()
	var proto_tech := "tech_beam_weaponry"
	TechSys.set_discovery_state(proto_tech, TechSys.DiscoveryState.UNKNOWN)

	# RivalProgression creates an active prototype behind the scenes
	RivalProgSys.active_prototype = {
		"name": "Type-Null Particle Lance",
		"tier": 2,
		"tech_id": proto_tech
	}
	_check(RivalProgSys.has_active_prototype(), "[7a] Rival has active prototype")
	_check(RivalProgSys.get_active_prototype_tech_id() == proto_tech, "[7b] Prototype tech_id matches")

	# Prototype state active does NOT automatically discover technology
	_check(TechSys.get_discovery_state(proto_tech) == TechSys.DiscoveryState.UNKNOWN, "[7c] Prototype state in rival system does NOT discover tech")

	# Now player actually locks onto / targets the prototype in combat
	var proto_enemy = _spawn_mock_enemy(proto_tech)

	# Simulate sensor lock-on event
	if EventBus:
		EventBus.lock_on_target_acquired.emit(proto_enemy)
	_check(TechSys.get_discovery_state(proto_tech) == TechSys.DiscoveryState.ENCOUNTERED, "[7d] Sensor lock-on in combat advances UNKNOWN -> ENCOUNTERED")

	proto_enemy.queue_free()


func _test_player_observation_does_not_alter_faction_state() -> void:
	print("\n-- [8] Player Observation Does NOT Alter Faction State --")
	var tech_id := "tech_passive_cooling"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.UNKNOWN)

	var rival_had := TechSys.has_faction_technology("rival", tech_id)
	var convoy_had := TechSys.has_faction_technology("convoy", tech_id)

	# Player observes technology
	if EventBus:
		EventBus.technology_observed.emit(tech_id, {"source": "recon"})
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[8a] Player discovery advanced to ENCOUNTERED")

	# Faction technology lists remain completely unaltered
	_check(TechSys.has_faction_technology("rival", tech_id) == rival_had, "[8b] Rival faction state unaffected by player observation")
	_check(TechSys.has_faction_technology("convoy", tech_id) == convoy_had, "[8c] Convoy faction state unaffected by player observation")


func _test_phase_2e_3a_salvage_path_preserved() -> void:
	print("\n-- [9] Existing Phase 2E-3A Salvage Path Preserved --")
	var tech_id := "tech_combustion_power"
	TechSys.set_discovery_state(tech_id, TechSys.DiscoveryState.ENCOUNTERED)

	var salvage_sys := SalvageSys.new()
	var salvage_part := {
		"salvage_id": "combustion_core_piece",
		"name": "Scorched Piston Assembly",
		"tech_id": tech_id,
		"weight": 12.0
	}

	salvage_sys.collect_salvage(salvage_part)
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.SALVAGED, "[9a] Collecting physical evidence advances ENCOUNTERED -> SALVAGED")
	_check(salvage_sys.has_salvaged_evidence_for_tech(tech_id), "[9b] SalvageSystem stores evidence")

	salvage_sys.free()


func _test_save_load_persistence_compatibility() -> void:
	print("\n-- [10] Save/Load Persistence Compatibility --")
	TechSys.reset_discovery_states()
	TechSys.set_discovery_state("tech_beam_weaponry", TechSys.DiscoveryState.ENCOUNTERED)
	TechSys.set_discovery_state("tech_passive_cooling", TechSys.DiscoveryState.SALVAGED)

	var serialized := TechSys.serialize_discovery_states()
	_check(serialized.get("tech_beam_weaponry") == TechSys.DiscoveryState.ENCOUNTERED, "[10a] ENCOUNTERED preserved in serialization")
	_check(serialized.get("tech_passive_cooling") == TechSys.DiscoveryState.SALVAGED, "[10b] SALVAGED preserved in serialization")

	TechSys.reset_discovery_states()
	TechSys.deserialize_discovery_states(serialized)
	_check(TechSys.get_discovery_state("tech_beam_weaponry") == TechSys.DiscoveryState.ENCOUNTERED, "[10c] ENCOUNTERED restored after deserialization")
	_check(TechSys.get_discovery_state("tech_passive_cooling") == TechSys.DiscoveryState.SALVAGED, "[10d] SALVAGED restored after deserialization")
