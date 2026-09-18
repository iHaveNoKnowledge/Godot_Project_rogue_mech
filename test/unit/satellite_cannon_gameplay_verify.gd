extends Node
## SATELLITE CANNON GAMEPLAY INTEGRATION VERIFICATION (Phase 2E-7)
##
## Validates data-driven Satellite Cannon definition, generic strategic_strike resolution,
## authorization gating, beam-line area targeting, pure EffectRequest creation,
## authoritative damage routing through StuntWeaponSystem -> HealthSystem -> DamageCalculator,
## resource & cooldown consumption, technology observation, and architectural boundaries.

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")
const StuntWeaponSys = preload("res://scripts/war/stunt_weapon_system.gd")
const DamageCalc = preload("res://scripts/systems/damage_calculator.gd")

const EnemyScene = preload("res://scenes/mecha/enemy_dummy.tscn")

class MockEnergySystem extends RefCounted:
	var energy: float = 100.0


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("SATELLITE_OK: " + msg)
	else:
		_fails += 1
		printerr("SATELLITE_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING SATELLITE CANNON GAMEPLAY VERIFICATION (PHASE 2E-7) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_a_data_definition()
	_test_b_generic_resolution()
	_test_c_activation_authorization()
	_test_d_beam_targeting()
	_test_e_effect_request_pure_creation()
	_test_f_damage_application_and_mitigation()
	_test_g_resource_and_cooldown()
	_test_h_multiple_targets()
	_test_i_technology_observation()
	_test_j_no_weapon_id_branching()
	_test_k_regression_checks()
	_test_architecture_boundary()
	_test_negative_invariants()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_7_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_7_FAILURE")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST A: SATELLITE CANNON DATA DEFINITION
# -----------------------------------------------------------------------------
func _test_a_data_definition() -> void:
	print("\n-- [Test A] Satellite Cannon Data Definition --")

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	_check(sc_res != null, "[A1] weapon_satellite_cannon.tres loads successfully")
	_check(sc_res is WeaponPart, "[A2] Resource is a WeaponPart")
	_check(sc_res.has_special_capability(), "[A3] Satellite Cannon declares special capability")
	_check(sc_res.get_special_capability_type() == "strategic_strike", "[A4] Capability type is strategic_strike")
	_check(sc_res.get_targeting_mode() == "beam_line", "[A5] Targeting mode is beam_line")
	_check(sc_res.damage == 350.0, "[A6] Damage is 350.0")
	_check(sc_res.get_damage_type() == "heat", "[A7] Damage type is heat")
	_check(sc_res.tech_id == "tech_beam_weaponry", "[A8] Tech ID is tech_beam_weaponry")


# -----------------------------------------------------------------------------
# TEST B: GENERIC CAPABILITY RESOLUTION
# -----------------------------------------------------------------------------
func _test_b_generic_resolution() -> void:
	print("\n-- [Test B] Generic Resolution --")

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc_res)

	_check(bool(cap.get("has_capability", false)) == true, "[B1] resolve_special_capability reports has_capability true")
	_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE, "[B2] Capability normalized to strategic_strike")
	_check(cap.get("targeting_mode") == SpecialWeaponSys.TARGETING_BEAM_LINE, "[B3] Targeting mode is beam_line")
	_check(cap.get("area_shape") == SpecialWeaponSys.SHAPE_LINE, "[B4] Area shape is line")
	var area_params: Dictionary = cap.get("area_parameters", {})
	_check(float(area_params.get("length", 0.0)) == 150.0, "[B5] Beam length is 150.0")
	_check(float(area_params.get("width", 0.0)) == 12.0, "[B6] Beam width is 12.0")
	_check(float(cap.get("cooldown", 0.0)) == 25.0, "[B7] Cooldown is 25.0s")
	_check(float(cap.get("energy_cost", 0.0)) == 50.0, "[B8] Energy cost is 50.0")
	var eff_payload: Dictionary = cap.get("effect_payload", {})
	_check(float(eff_payload.get("damage", 0.0)) == 350.0, "[B9] Effect payload damage is 350.0")
	_check(str(eff_payload.get("damage_type", "")) == "heat", "[B10] Effect payload damage_type is heat")


# -----------------------------------------------------------------------------
# TEST C: ACTIVATION AUTHORIZATION
# -----------------------------------------------------------------------------
func _test_c_activation_authorization() -> void:
	print("\n-- [Test C] Activation Authorization --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var tech_id := "tech_beam_weaponry"

	# 1. Tech is UNKNOWN -> rejected
	var val_locked := SpecialWeaponSys.validate_special_activation(sc_res)
	_check(not bool(val_locked.get("can_activate", false)), "[C1] Activation rejected when technology is locked")
	_check(val_locked.get("reason") == "technology_locked", "[C2] Reason is technology_locked")

	# 2. Tech is USABLE but incompatible frame -> rejected
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE
	var incompatible_frame: Dictionary = {
		"id": "frame_ballistic_chassis",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	var val_incomp := SpecialWeaponSys.validate_special_activation(sc_res, {"frame_data": incompatible_frame})
	_check(not bool(val_incomp.get("can_activate", false)), "[C3] Activation rejected on incompatible frame")
	_check(val_incomp.get("reason") == "physically_incompatible", "[C4] Reason is physically_incompatible")

	# 3. Compatible frame + usable tech -> permitted
	var compatible_frame: Dictionary = {
		"id": "frame_energy_chassis",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	}
	var val_comp := SpecialWeaponSys.validate_special_activation(sc_res, {"frame_data": compatible_frame})
	_check(bool(val_comp.get("can_activate", false)), "[C5] Activation permitted with compatible frame and usable tech")

	# 4. Energy check: insufficient energy -> rejected
	var val_no_energy := SpecialWeaponSys.validate_special_activation(sc_res, {
		"frame_data": compatible_frame,
		"current_energy": 30.0 # needs 50.0
	})
	_check(not bool(val_no_energy.get("can_activate", false)), "[C6] Activation rejected when energy is insufficient")
	_check(val_no_energy.get("reason") == "insufficient_energy", "[C7] Reason is insufficient_energy")

	# 5. Cooldown check: on cooldown -> rejected
	var val_cd := SpecialWeaponSys.validate_special_activation(sc_res, {
		"frame_data": compatible_frame,
		"current_energy": 100.0,
		"cooldown_remaining": 12.5
	})
	_check(not bool(val_cd.get("can_activate", false)), "[C8] Activation rejected while on cooldown")
	_check(val_cd.get("reason") == "on_cooldown", "[C9] Reason is on_cooldown")


# -----------------------------------------------------------------------------
# TEST D: BEAM TARGETING & FILTERING
# -----------------------------------------------------------------------------
func _test_d_beam_targeting() -> void:
	print("\n-- [Test D] Beam Targeting & Filtering --")

	var origin := Vector3(0, 0, 0)
	var forward := Vector3(0, 0, -1) # Godot forward is -Z
	var area_params := {"length": 150.0, "width": 12.0} # half-width 6.0

	var source_node := Node3D.new()
	source_node.name = "AttackerMecha"
	add_child(source_node)
	source_node.global_position = origin

	var t_direct := Node3D.new()
	t_direct.name = "TargetDirectHit"
	add_child(t_direct)
	t_direct.global_position = Vector3(0, 0, -60)

	var t_grazing := Node3D.new()
	t_grazing.name = "TargetGrazingHit"
	add_child(t_grazing)
	t_grazing.global_position = Vector3(5.0, 0, -80) # perp dist 5.0 <= 6.0

	var t_wide := Node3D.new()
	t_wide.name = "TargetWideMiss"
	add_child(t_wide)
	t_wide.global_position = Vector3(10.0, 0, -80) # perp dist 10.0 > 6.0

	var t_behind := Node3D.new()
	t_behind.name = "TargetBehind"
	add_child(t_behind)
	t_behind.global_position = Vector3(0, 0, 20) # behind origin

	var t_beyond := Node3D.new()
	t_beyond.name = "TargetBeyond"
	add_child(t_beyond)
	t_beyond.global_position = Vector3(0, 0, -200) # beyond 150.0 length

	var t_dead := Node3D.new()
	t_dead.name = "TargetDead"
	t_dead.set_meta("is_destroyed", true)
	add_child(t_dead)
	t_dead.global_position = Vector3(0, 0, -40)

	var candidates := [source_node, t_direct, t_grazing, t_wide, t_behind, t_beyond, t_dead]
	var filtered := SpecialWeaponSys.filter_valid_targets(candidates, SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE, source_node)

	_check(not filtered.has(source_node), "[D1] Source node is excluded from target candidates")
	_check(not filtered.has(t_dead), "[D2] Destroyed node is excluded from target candidates")
	_check(filtered.has(t_direct) and filtered.has(t_grazing), "[D3] Active targets retained in candidate list")

	var resolved := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_BEAM_LINE,
		origin,
		forward,
		area_params,
		filtered
	)

	_check(resolved.size() == 2, "[D4] Exactly 2 valid targets resolved within beam geometry (got %d)" % resolved.size())
	_check(resolved.has(t_direct), "[D5] Direct target resolved in beam corridor")
	_check(resolved.has(t_grazing), "[D6] Grazing target resolved in beam corridor")
	_check(not resolved.has(t_wide), "[D7] Wide target excluded from beam corridor")
	_check(not resolved.has(t_behind), "[D8] Behind target excluded from beam corridor")
	_check(not resolved.has(t_beyond), "[D9] Beyond target excluded from beam corridor")

	source_node.queue_free()
	t_direct.queue_free()
	t_grazing.queue_free()
	t_wide.queue_free()
	t_behind.queue_free()
	t_beyond.queue_free()
	t_dead.queue_free()


# -----------------------------------------------------------------------------
# TEST E: EFFECT REQUEST PURE CREATION
# -----------------------------------------------------------------------------
func _test_e_effect_request_pure_creation() -> void:
	print("\n-- [Test E] Effect Request Pure Creation --")

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var cap := SpecialWeaponSys.resolve_special_capability(sc_res)
	var origin := Vector3(0, 100, 0)

	var dummy := CharacterBody3D.new()
	dummy.name = "DummyTarget"
	dummy.set_meta("test_hp", 1000.0)
	add_child(dummy)
	dummy.global_position = Vector3(0, 0, -30)

	var req := SpecialWeaponSys.create_effect_request(
		SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
		cap,
		origin,
		[dummy],
		{"source_test": true}
	)

	_check(req.get("capability_type") == SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE, "[E1] Request capability_type is strategic_strike")
	var payload: Dictionary = req.get("effect_payload", {})
	_check(float(payload.get("damage", 0.0)) == 350.0, "[E2] Request payload damage is 350.0")
	_check(str(payload.get("damage_type", "")) == "heat", "[E3] Request payload damage_type is heat")
	_check(req.get("targets", []).size() == 1, "[E4] Request targets array populated")

	# Pure creation verification: dummy must NOT have received damage or state mutations
	_check(float(dummy.get_meta("test_hp", 0.0)) == 1000.0, "[E5] create_effect_request is pure (does NOT mutate target HP)")
	_check(not dummy.has_meta("disrupted_until"), "[E6] create_effect_request does not attach disruption metadata")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# TEST F: DAMAGE APPLICATION AND MITIGATION
# -----------------------------------------------------------------------------
func _test_f_damage_application_and_mitigation() -> void:
	print("\n-- [Test F] Damage Application & Mitigation --")

	var mock_target = EnemyScene.instantiate()
	add_child(mock_target)
	mock_target.global_position = Vector3(0, 0, -20)

	var initial_health: float = mock_target.health_system.current_health if mock_target.health_system else 0.0
	_check(initial_health > 0.0, "[F1] Target initialized with healthy HP (total: %.1f)" % initial_health)

	var effect_req: Dictionary = {
		"capability_type": "strategic_strike",
		"origin": Vector3(0, 50, 0),
		"targets": [mock_target],
		"effect_payload": {
			"damage": 120.0,
			"damage_type": "heat"
		}
	}

	var affected_count := StuntWeaponSys.apply_effect_request(effect_req)
	_check(affected_count == 1, "[F2] StuntWeaponSystem.apply_effect_request affected 1 target")

	var after_health: float = mock_target.health_system.current_health
	_check(after_health < initial_health, "[F3] Target health decreased through authoritative damage pipeline (from %.1f to %.1f)" % [initial_health, after_health])

	# Direct apply_damage_effect test
	var mock_target2 = EnemyScene.instantiate()
	add_child(mock_target2)
	var hp2_before: float = mock_target2.health_system.current_health

	var applied := StuntWeaponSys.apply_damage_effect(mock_target2, 80.0, "heat", Vector3(0, 0, -20))
	_check(applied == true, "[F4] StuntWeaponSystem.apply_damage_effect returned true on valid target")
	var hp2_after: float = mock_target2.health_system.current_health
	_check(hp2_after < hp2_before, "[F5] Target2 took damage via apply_damage_effect (from %.1f to %.1f)" % [hp2_before, hp2_after])

	mock_target.queue_free()
	mock_target2.queue_free()


# -----------------------------------------------------------------------------
# TEST G: RESOURCE AND COOLDOWN CONSUMPTION
# -----------------------------------------------------------------------------
func _test_g_resource_and_cooldown() -> void:
	print("\n-- [Test G] Resource & Cooldown Consumption --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var frame_data := {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	}

	var mock_energy_sys := MockEnergySystem.new()
	mock_energy_sys.energy = 100.0

	var mock_core = WeaponCore.new()
	mock_core.cooldown = 0.0
	mock_core.ammo = 1
	mock_core.max_ammo = 1

	var user_ctx: Dictionary = {
		"frame_data": frame_data,
		"current_energy": 100.0,
		"energy_system": mock_energy_sys,
		"cooldown_remaining": 0.0,
		"core": mock_core,
		"origin": Vector3.ZERO
	}

	var dummy_target = EnemyScene.instantiate()
	add_child(dummy_target)
	dummy_target.global_position = Vector3(0, 0, -30)

	var res := SpecialWeaponSys.activate_special_weapon(sc_res, null, user_ctx, [dummy_target])

	_check(bool(res.get("success", false)), "[G1] Special weapon activation succeeded")
	_check(int(res.get("targets_affected", 0)) == 1, "[G2] 1 target affected by activation")
	_check(mock_core.cooldown == 25.0, "[G3] Cooldown set to 25.0 on WeaponCore")
	_check(mock_energy_sys.energy == 50.0, "[G4] Energy deducted by 50.0 (100 -> 50)")

	# Failed activation test: tech locked -> NO cooldown / energy mutation
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.UNKNOWN
	mock_core.cooldown = 0.0
	mock_energy_sys.energy = 100.0
	var res_fail := SpecialWeaponSys.activate_special_weapon(sc_res, null, user_ctx, [dummy_target])
	_check(not bool(res_fail.get("success", false)), "[G5] Activation rejected when tech is locked")
	_check(mock_core.cooldown == 0.0, "[G6] Cooldown unchanged on failed activation")
	_check(mock_energy_sys.energy == 100.0, "[G7] Energy unchanged on failed activation")

	dummy_target.queue_free()


# -----------------------------------------------------------------------------
# TEST H: MULTIPLE TARGETS INDEPENDENCE
# -----------------------------------------------------------------------------
func _test_h_multiple_targets() -> void:
	print("\n-- [Test H] Multiple Targets Independence --")

	var targets: Array = []
	for i in range(3):
		var dummy = EnemyScene.instantiate()
		add_child(dummy)
		dummy.global_position = Vector3(0, 0, -20.0 * (i + 1))
		targets.append(dummy)

	var initial_hps := [
		targets[0].health_system.current_health,
		targets[1].health_system.current_health,
		targets[2].health_system.current_health
	]

	var req: Dictionary = {
		"capability_type": "strategic_strike",
		"origin": Vector3.ZERO,
		"targets": targets,
		"effect_payload": {
			"damage": 100.0,
			"damage_type": "heat"
		}
	}

	var count := StuntWeaponSys.apply_effect_request(req)
	_check(count == 3, "[H1] All 3 targets affected by single strategic strike request")

	for i in range(3):
		var after_hp: float = targets[i].health_system.current_health
		_check(after_hp < initial_hps[i], "[H2.%d] Target %d took independent damage (%.1f -> %.1f)" % [i + 1, i + 1, initial_hps[i], after_hp])

	for t in targets:
		t.queue_free()


# -----------------------------------------------------------------------------
# TEST I: TECHNOLOGY OBSERVATION
# -----------------------------------------------------------------------------
func _test_i_technology_observation() -> void:
	print("\n-- [Test I] Technology Observation Path --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_beam_weaponry"
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[I1] Tech starts UNKNOWN")

	var sc_res = load("res://resources/mech/stock/weapon_satellite_cannon.tres")
	var dummy_src = Node3D.new()
	dummy_src.name = "EnemySatellitePlatform"
	add_child(dummy_src)

	SpecialWeaponSys.report_special_weapon_observed(tech_id, dummy_src, "strategic_strike", {"weapon": sc_res})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[I2] Firing satellite cannon observed tech via generic EventBus path")

	dummy_src.queue_free()


# -----------------------------------------------------------------------------
# TEST J: NO WEAPON-ID BRANCHING (SYNTHETIC WEAPON)
# -----------------------------------------------------------------------------
func _test_j_no_weapon_id_branching() -> void:
	print("\n-- [Test J] No Weapon-ID Branching --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_modular_energy_interface"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	var synthetic_weapon := {
		"uid": "custom_uid_orbital_lance_99",
		"name": "Unmarked Planetary Kinetic Lance",
		"tech_id": tech_id,
		"special_capability": {
			"capability_type": SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
			"targeting_mode": SpecialWeaponSys.TARGETING_BEAM_LINE,
			"area_parameters": {"length": 200.0, "width": 10.0},
			"cooldown": 30.0,
			"energy_cost": 40.0,
			"effect_payload": {"damage": 220.0, "damage_type": "heat"}
		}
	}

	var frame_data := {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_INTERFACE, TechSys.FAMILY_ENERGY]
	}

	var dummy_target = EnemyScene.instantiate()
	add_child(dummy_target)
	dummy_target.global_position = Vector3(0, 0, -50)
	var hp_before: float = dummy_target.health_system.current_health

	var user_ctx := {
		"frame_data": frame_data,
		"current_energy": 100.0,
		"cooldown_remaining": 0.0
	}

	var res := SpecialWeaponSys.activate_special_weapon(synthetic_weapon, null, user_ctx, [dummy_target])
	_check(bool(res.get("success", false)), "[J1] Synthetic weapon without 'satellite' in ID or name activates successfully")
	_check(int(res.get("targets_affected", 0)) == 1, "[J2] Synthetic weapon affects target through same generic pipeline")
	var hp_after: float = dummy_target.health_system.current_health
	_check(hp_after < hp_before, "[J3] Victim took damage from synthetic weapon (%.1f -> %.1f)" % [hp_before, hp_after])

	dummy_target.queue_free()


# -----------------------------------------------------------------------------
# TEST K: REGRESSION CHECKS
# -----------------------------------------------------------------------------
func _test_k_regression_checks() -> void:
	print("\n-- [Test K] Regression Checks --")

	# 1. Jammer weapon continues to resolve disruption
	var jammer_res = load("res://resources/mech/stock/weapon_jammer.tres")
	_check(jammer_res != null, "[K1] weapon_jammer.tres loads successfully")
	var jammer_cap := SpecialWeaponSys.resolve_special_capability(jammer_res)
	_check(jammer_cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[K2] Jammer capability remains disruption")

	# 2. Normal weapon has no special capability
	var rifle_res = load("res://resources/mech/stock/weapon_beam_rifle.tres")
	if rifle_res:
		_check(not rifle_res.has_special_capability(), "[K3] Beam rifle reports has_special_capability false")


# -----------------------------------------------------------------------------
# TEST ARCHITECTURE BOUNDARY
# -----------------------------------------------------------------------------
func _test_architecture_boundary() -> void:
	print("\n-- [Architecture Test] Authority Boundary Verification --")

	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	var hp_init: float = dummy.health_system.current_health

	var cap_data := {
		"duration": 0.0,
		"area_parameters": {"length": 100.0, "width": 8.0},
		"effect_payload": {"damage": 200.0, "damage_type": "heat"}
	}

	# 1. SpecialWeaponSystem.create_effect_request must NOT mutate target HP
	var req := SpecialWeaponSys.create_effect_request(
		SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
		cap_data,
		Vector3.ZERO,
		[dummy]
	)
	_check(dummy.health_system.current_health == hp_init, "[ARCH1] SpecialWeaponSystem.create_effect_request does not mutate target HP")

	# 2. StuntWeaponSystem dispatch mutates target HP through Damage Pipeline
	var affected := SpecialWeaponSys.dispatch_effect_request(req)
	_check(affected == 1, "[ARCH2] dispatch_effect_request delegates to StuntWeaponSystem")
	_check(dummy.health_system.current_health < hp_init, "[ARCH3] StuntWeaponSystem mutates target HP authoritatively through damage pipeline")

	dummy.queue_free()


# -----------------------------------------------------------------------------
# NEGATIVE TESTS
# -----------------------------------------------------------------------------
func _test_negative_invariants() -> void:
	print("\n-- [Negative Tests] Architectural Invariants --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_beam_weaponry"
	var wp = load("res://resources/mech/stock/weapon_satellite_cannon.tres")

	# 1. Spawn != Observe
	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[NEG1] Spawning/instantiating weapon does NOT observe technology")

	# 2. Technology authorization != Effect execution
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE
	var dummy = EnemyScene.instantiate()
	add_child(dummy)
	var init_hp: float = dummy.health_system.current_health
	var _val = SpecialWeaponSys.validate_special_activation(wp)
	_check(dummy.health_system.current_health == init_hp, "[NEG2] Authorizing technology does NOT execute effect or mutate HP")

	# 3. Capability resolution != State mutation
	var _cap = SpecialWeaponSys.resolve_special_capability(wp)
	_check(dummy.health_system.current_health == init_hp, "[NEG3] Resolving capability does NOT mutate node state")

	# 4. Target resolution != State mutation
	var _targets = SpecialWeaponSys.resolve_affected_targets("beam_line", Vector3.ZERO, Vector3.FORWARD, {"length": 100.0, "width": 10.0}, [dummy])
	_check(dummy.health_system.current_health == init_hp, "[NEG4] Target resolution does NOT mutate target HP")

	dummy.queue_free()
