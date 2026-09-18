extends Node
## SPECIAL WEAPON INTEGRATION CONTRACT VERIFICATION (Phase 2E-5)
##
## Validates the generic data contract, capability resolution, targeting models,
## effect payload structures, observation path, and authority boundaries for special weapons.

var _checks := 0
var _fails := 0

const TechSys = preload("res://scripts/systems/technology_system.gd")
const FrameSys = preload("res://scripts/systems/frame_system.gd")
const LoadoutSys = preload("res://scripts/systems/loadout_system.gd")
const ArmorSys = preload("res://scripts/systems/armor_system.gd")
const SpecialWeaponSys = preload("res://scripts/systems/special_weapon_system.gd")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("SPECIAL_CONTRACT_OK: " + msg)
	else:
		_fails += 1
		printerr("SPECIAL_CONTRACT_FAIL: " + msg)


func _ready() -> void:
	await get_tree().process_frame

	print("=== STARTING ADVANCED SPECIAL WEAPON CONTRACT VERIFICATION (PHASE 2E-5) ===")

	TechSys.init_catalog_if_needed()
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	_test_generic_disruption_capability()
	_test_generic_strategic_strike_capability()
	_test_no_weapon_id_branching()
	_test_targeting_contract_geometries()
	_test_effect_payload_and_disruption_application()
	_test_technology_observation_path()
	_test_existing_weapon_regression()
	_test_technology_lifecycle_regression()
	_test_equipment_authorization_regression()

	print("\n=== VERIFICATION COMPLETE: %d checks, %d failures ===" % [_checks, _fails])
	if _fails == 0:
		print("PHASE_2E_5_SUCCESS")
		get_tree().quit(0)
	else:
		printerr("PHASE_2E_5_FAILURE")
		get_tree().quit(1)


# -----------------------------------------------------------------------------
# TEST A: GENERIC DISRUPTION CAPABILITY RESOLUTION (Capability A)
# -----------------------------------------------------------------------------
func _test_generic_disruption_capability() -> void:
	print("\n-- [Test A] Generic Disruption Capability --")

	var wp := WeaponPart.new()
	wp.weapon_name = "Synthetic Pulse Disruption Emitter"
	wp.tech_id = "tech_synthetic_disruption"
	wp.special_capability = {
		"capability_type": SpecialWeaponSys.CAPABILITY_DISRUPTION,
		"targeting_mode": SpecialWeaponSys.TARGETING_AREA_RADIUS,
		"area_shape": SpecialWeaponSys.SHAPE_SPHERE,
		"area_parameters": {"radius": 18.0},
		"duration": 5.5,
		"cooldown": 14.0,
		"energy_cost": 22.0,
		"effect_payload": {"movement_inhibition": 0.8, "electronic_scramble": true}
	}

	_check(wp.has_special_capability(), "[A1] WeaponPart reports has_special_capability true")
	_check(wp.get_special_capability_type() == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[A2] get_special_capability_type is disruption")
	_check(wp.get_targeting_mode() == SpecialWeaponSys.TARGETING_AREA_RADIUS, "[A3] get_targeting_mode is area_radius")
	_check(wp.get_duration() == 5.5, "[A4] get_duration returns 5.5")

	var cap := SpecialWeaponSys.resolve_special_capability(wp)
	_check(bool(cap.get("has_capability", false)), "[A5] Resolved capability has_capability is true")
	_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[A6] Resolved capability_type matches")
	_check(cap.get("area_shape") == SpecialWeaponSys.SHAPE_SPHERE, "[A7] Resolved area_shape is sphere")
	_check(float(cap.get("energy_cost", 0.0)) == 22.0, "[A8] Energy cost parsed correctly")


# -----------------------------------------------------------------------------
# TEST B: GENERIC STRATEGIC / LARGE-AREA ATTACK RESOLUTION (Capability B)
# -----------------------------------------------------------------------------
func _test_generic_strategic_strike_capability() -> void:
	print("\n-- [Test B] Generic Strategic Strike Capability --")

	var dict_weapon := {
		"id": "item_strategic_beam_array",
		"name": "Orbital Energy Relay Array",
		"tech_id": "tech_synthetic_strategic",
		"special_capability": {
			"capability_type": SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
			"targeting_mode": SpecialWeaponSys.TARGETING_BEAM_LINE,
			"area_shape": SpecialWeaponSys.SHAPE_LINE,
			"area_parameters": {"length": 250.0, "width": 8.0},
			"cooldown": 45.0,
			"energy_cost": 60.0,
			"effect_payload": {"damage": 350.0, "penetration": 0.9}
		}
	}

	var cap := SpecialWeaponSys.resolve_special_capability(dict_weapon)
	_check(bool(cap.get("has_capability", false)), "[B1] Dictionary weapon resolves special capability")
	_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE, "[B2] Resolved type is strategic_strike")
	_check(cap.get("targeting_mode") == SpecialWeaponSys.TARGETING_BEAM_LINE, "[B3] Targeting mode is beam_line")
	_check(cap.get("area_shape") == SpecialWeaponSys.SHAPE_LINE, "[B4] Area shape is line")
	_check(cap.get("area_parameters", {}).get("length", 0.0) == 250.0, "[B5] Beam length is 250.0")
	_check(cap.get("area_parameters", {}).get("width", 0.0) == 8.0, "[B6] Beam width is 8.0")


# -----------------------------------------------------------------------------
# TEST C: NO WEAPON-ID BRANCHING
# -----------------------------------------------------------------------------
func _test_no_weapon_id_branching() -> void:
	print("\n-- [Test C] No Weapon-ID Branching --")

	var generic_names := [
		"Synthetic Weapon Alpha-1",
		"Unmarked Experimental Node",
		"Modular Chassis Adapter 77",
		"Heavy Industrial Rig"
	]

	for gname in generic_names:
		var custom_weapon := {
			"id": "custom_uid_" + str(gname.hash()),
			"name": gname,
			"special_capability": {
				"capability_type": SpecialWeaponSys.CAPABILITY_DISRUPTION,
				"targeting_mode": SpecialWeaponSys.TARGETING_AREA_RADIUS,
				"area_parameters": {"radius": 12.0},
				"duration": 4.0
			}
		}
		var cap := SpecialWeaponSys.resolve_special_capability(custom_weapon)
		_check(cap.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[C] Arbitrary weapon name '%s' resolves capability purely from data" % gname)


# -----------------------------------------------------------------------------
# TEST D: TARGETING CONTRACT GEOMETRIES
# -----------------------------------------------------------------------------
func _test_targeting_contract_geometries() -> void:
	print("\n-- [Test D] Targeting Contract Geometries --")

	var origin := Vector3(0, 0, 0)
	var forward := Vector3(0, 0, -1) # Godot forward is -Z

	var t_inside_radius := {"name": "Target Radius In", "position": Vector3(5, 0, -5)} # dist ~7.07
	var t_outside_radius := {"name": "Target Radius Out", "position": Vector3(25, 0, 0)} # dist 25.0

	var radius_targets := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_AREA_RADIUS,
		origin,
		forward,
		{"radius": 15.0},
		[t_inside_radius, t_outside_radius]
	)
	_check(radius_targets.size() == 1 and radius_targets[0]["name"] == "Target Radius In", "[D1] Area radius includes inside target and excludes outside target")

	# Beam Line: Length 100, Width 6 (half-width 3.0) along -Z
	var t_beam_direct := {"name": "Beam Direct", "position": Vector3(0, 0, -50)} # on center line
	var t_beam_grazing := {"name": "Beam Grazing", "position": Vector3(2.5, 0, -30)} # perp dist 2.5 <= 3.0
	var t_beam_wide := {"name": "Beam Wide", "position": Vector3(5.0, 0, -30)} # perp dist 5.0 > 3.0
	var t_beam_behind := {"name": "Beam Behind", "position": Vector3(0, 0, 10)} # behind origin
	var t_beam_too_far := {"name": "Beam Too Far", "position": Vector3(0, 0, -120)} # beyond length

	var beam_targets := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_BEAM_LINE,
		origin,
		forward,
		{"length": 100.0, "width": 6.0},
		[t_beam_direct, t_beam_grazing, t_beam_wide, t_beam_behind, t_beam_too_far]
	)
	_check(beam_targets.size() == 2, "[D2] Beam targeting selects exactly the 2 within beam cylinder (found %d)" % beam_targets.size())
	var beam_names: Array = []
	for bt in beam_targets:
		beam_names.append(bt["name"])
	_check(beam_names.has("Beam Direct") and beam_names.has("Beam Grazing"), "[D3] Beam targets are Beam Direct and Beam Grazing")

	# Sweep Cone: Range 50, Angle 60 deg (half-angle 30 deg)
	var t_cone_center := {"name": "Cone Center", "position": Vector3(0, 0, -20)} # angle 0 deg
	var t_cone_edge := {"name": "Cone Edge", "position": Vector3(10, 0, -30)} # angle ~18.4 deg <= 30
	var t_cone_outside := {"name": "Cone Outside", "position": Vector3(30, 0, -10)} # angle ~71.5 deg > 30

	var cone_targets := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_SWEEP_CONE,
		origin,
		forward,
		{"range": 50.0, "angle": 60.0},
		[t_cone_center, t_cone_edge, t_cone_outside]
	)
	_check(cone_targets.size() == 2, "[D4] Sweep cone selects exactly targets within cone arc")

	# Map Sector: Bounding Box
	var t_box_in := {"name": "Box In", "position": Vector3(10, 5, -20)}
	var t_box_out := {"name": "Box Out", "position": Vector3(100, 5, -20)}

	var sector_targets := SpecialWeaponSys.resolve_affected_targets(
		SpecialWeaponSys.TARGETING_MAP_SECTOR,
		origin,
		forward,
		{"min": Vector3(-50, -50, -50), "max": Vector3(50, 50, 50)},
		[t_box_in, t_box_out]
	)
	_check(sector_targets.size() == 1 and sector_targets[0]["name"] == "Box In", "[D5] Map sector bounding box selects internal target")


# -----------------------------------------------------------------------------
# TEST E: EFFECT PAYLOAD AND DISRUPTION APPLICATION
# -----------------------------------------------------------------------------
func _test_effect_payload_and_disruption_application() -> void:
	print("\n-- [Test E] Effect Payload & Disruption Application --")

	var cap_data := {
		"duration": 4.5,
		"intensity": 1.5,
		"area_parameters": {"radius": 20.0},
		"effect_payload": {"type": "electromagnetic_dampener", "movement_speed_factor": 0.25}
	}
	var origin := Vector3(10, 0, 10)
	var targets := [Vector3(15, 0, 12), Vector3(18, 0, 14)]

	var payload := SpecialWeaponSys.build_effect_payload(
		SpecialWeaponSys.CAPABILITY_DISRUPTION,
		cap_data,
		origin,
		targets,
		{"source_player": true}
	)
	_check(payload.get("capability_type") == SpecialWeaponSys.CAPABILITY_DISRUPTION, "[E1] Payload capability_type is correct")
	_check(payload.get("duration") == 4.5, "[E2] Payload duration is correct")
	_check(payload.get("intensity") == 1.5, "[E3] Payload intensity is correct")
	_check(payload.get("target_positions", []).size() == 2, "[E4] Target positions recorded")
	_check(payload.get("extra", {}).get("source_player") == true, "[E5] Extra context preserved")

	# Target Disruption Mutation
	var dummy_node := Node3D.new()
	add_child(dummy_node)

	var applied := SpecialWeaponSys.apply_disruption_effect(dummy_node, 3.0, {"dampen": true})
	_check(applied == true, "[E6] apply_disruption_effect returns true on valid node")
	_check(dummy_node.has_meta("disrupted_until"), "[E7] Target node has disrupted_until metadata")
	var expire := int(dummy_node.get_meta("disrupted_until", 0))
	_check(expire > Time.get_ticks_msec(), "[E8] Disruption expiration is set in the future")

	dummy_node.queue_free()


# -----------------------------------------------------------------------------
# TEST F: TECHNOLOGY OBSERVATION PATH
# -----------------------------------------------------------------------------
func _test_technology_observation_path() -> void:
	print("\n-- [Test F] Technology Observation Path --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_observation_spec"
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Observation Test Spec",
		"generation": 2,
		"technology_family": TechSys.FAMILY_INTERFACE,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN}
	})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.UNKNOWN, "[F1] Tech starts UNKNOWN")

	var dummy_emitter := Node3D.new()
	dummy_emitter.name = "TestEnemyEmitter"
	add_child(dummy_emitter)

	SpecialWeaponSys.report_special_weapon_observed(tech_id, dummy_emitter, SpecialWeaponSys.CAPABILITY_DISRUPTION, {"combat_action": "pulse_fired"})

	_check(TechSys.get_discovery_state(tech_id) == TechSys.DiscoveryState.ENCOUNTERED, "[F2] Special weapon observation transitioned tech from UNKNOWN to ENCOUNTERED")

	dummy_emitter.queue_free()


# -----------------------------------------------------------------------------
# TEST G: EXISTING WEAPON REGRESSION
# -----------------------------------------------------------------------------
func _test_existing_weapon_regression() -> void:
	print("\n-- [Test G] Existing Weapon Regression --")

	var normal_weapon := WeaponPart.new()
	normal_weapon.weapon_name = "Standard Machine Gun"
	normal_weapon.weapon_type = WeaponPart.WeaponType.MACHINE_GUN
	normal_weapon.damage = 20.0
	normal_weapon.max_ammo = 120

	_check(normal_weapon.has_special_capability() == false, "[G1] Standard weapon has_special_capability is false")
	_check(normal_weapon.get_special_capability_type() == "", "[G2] get_special_capability_type is empty")
	_check(normal_weapon.get_targeting_mode() == "point", "[G3] Standard weapon defaults to point targeting")

	var cap := SpecialWeaponSys.resolve_special_capability(normal_weapon)
	_check(bool(cap.get("has_capability", false)) == false, "[G4] resolve_special_capability reports has_capability false")

	var val := SpecialWeaponSys.validate_special_activation(normal_weapon)
	_check(bool(val.get("can_activate", false)) == false, "[G5] Normal weapon activation rejected as special weapon")
	_check(val.get("reason") == "no_special_capability", "[G6] Rejection reason is no_special_capability")


# -----------------------------------------------------------------------------
# TEST H: TECHNOLOGY LIFECYCLE REGRESSION
# -----------------------------------------------------------------------------
func _test_technology_lifecycle_regression() -> void:
	print("\n-- [Test H] Technology Lifecycle Regression --")
	TechSys.reset_discovery_states()

	var tech_id := "tech_lifecycle_gate"
	TechSys.register_technology({
		"tech_id": tech_id,
		"name": "Lifecycle Gate Spec",
		"generation": 2,
		"technology_family": TechSys.FAMILY_ENERGY,
		"discovery_metadata": {"base_state": TechSys.DiscoveryState.UNKNOWN}
	})

	var special_wp := WeaponPart.new()
	special_wp.weapon_name = "Tech Gated Special Beam"
	special_wp.tech_id = tech_id
	special_wp.special_capability = {
		"capability_type": SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
		"targeting_mode": SpecialWeaponSys.TARGETING_BEAM_LINE,
		"area_parameters": {"length": 100.0, "width": 4.0}
	}

	# 1. While UNKNOWN
	var val_unknown := SpecialWeaponSys.validate_special_activation(special_wp)
	_check(not bool(val_unknown.get("can_activate", false)), "[H1] Activation rejected while UNKNOWN")
	_check(val_unknown.get("reason") == "technology_locked", "[H2] Reason is technology_locked")

	# 2. While SALVAGED
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.SALVAGED
	var val_salvaged := SpecialWeaponSys.validate_special_activation(special_wp)
	_check(not bool(val_salvaged.get("can_activate", false)), "[H3] Activation rejected while SALVAGED (SALVAGED != IDENTIFIED)")

	# 3. While IDENTIFIED
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.IDENTIFIED
	var val_identified := SpecialWeaponSys.validate_special_activation(special_wp)
	_check(not bool(val_identified.get("can_activate", false)), "[H4] Activation rejected while IDENTIFIED (IDENTIFIED != USABLE)")

	# 4. While RESEARCHED
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.RESEARCHED
	var val_researched := SpecialWeaponSys.validate_special_activation(special_wp)
	_check(not bool(val_researched.get("can_activate", false)), "[H5] Activation rejected while RESEARCHED (RESEARCHED != USABLE)")

	# 5. When USABLE
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE
	var val_usable := SpecialWeaponSys.validate_special_activation(special_wp)
	_check(bool(val_usable.get("can_activate", false)), "[H6] Activation allowed once technology is USABLE")


# -----------------------------------------------------------------------------
# TEST I: EQUIPMENT AUTHORIZATION REGRESSION
# -----------------------------------------------------------------------------
func _test_equipment_authorization_regression() -> void:
	print("\n-- [Test I] Equipment Authorization Regression --")
	TechSys.reset_discovery_states()
	GlobalData.reset_run_data()

	var tech_id := "tech_beam_weaponry"
	TechSys._player_discovery[tech_id] = TechSys.DiscoveryState.USABLE

	var special_wp := {
		"uid": "uid_special_gun",
		"name": "Advanced Beam Weapon",
		"tech_id": tech_id,
		"path": "res://resources/mech/stock/weapon_beam_rifle.tres",
		"special_capability": {
			"capability_type": SpecialWeaponSys.CAPABILITY_STRATEGIC_STRIKE,
			"targeting_mode": SpecialWeaponSys.TARGETING_BEAM_LINE
		}
	}

	# Incompatible Gen 1 ballistic frame
	var gen1_frame: Dictionary = {
		"id": "frame_basic_arm",
		"native_generation": 1,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_BALLISTIC]
	}
	GlobalData.weapons.equipped_frames["arm_right"] = gen1_frame

	var val_incomp := LoadoutSys.validate_equip_request("weapon_right", special_wp)
	_check(not bool(val_incomp.get("can_equip", false)), "[I1] LoadoutSystem rejects weapon on incompatible frame")
	_check(val_incomp.get("reason") == "physically_incompatible", "[I2] Rejection reason is physically_incompatible")

	var val_act_incomp := SpecialWeaponSys.validate_special_activation(special_wp, {"frame_data": gen1_frame})
	_check(not bool(val_act_incomp.get("can_activate", false)), "[I3] SpecialWeaponSystem activation rejects incompatible frame")
	_check(val_act_incomp.get("reason") == "physically_incompatible", "[I4] Activation rejection reason is physically_incompatible")

	# Compatible Gen 2 energy frame
	var gen2_frame: Dictionary = {
		"id": "frame_energy_arm",
		"native_generation": 2,
		"technology_lineage": "valkren",
		"supported_families": [TechSys.FAMILY_ENERGY]
	}
	GlobalData.weapons.equipped_frames["arm_right"] = gen2_frame

	var val_comp := LoadoutSys.validate_equip_request("weapon_right", special_wp)
	_check(bool(val_comp.get("can_equip", false)), "[I5] LoadoutSystem allows weapon on compatible frame")

	var val_act_comp := SpecialWeaponSys.validate_special_activation(special_wp, {"frame_data": gen2_frame})
	_check(bool(val_act_comp.get("can_activate", false)), "[I6] SpecialWeaponSystem allows activation on compatible frame")
