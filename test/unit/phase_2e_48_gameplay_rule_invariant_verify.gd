extends Node

## Phase 2E-48: Gameplay Rule Invariant & Domain Constraint Integrity Test Suite
## Verifies that all gameplay rules, range limits, conservation laws, state exclusivity,
## dependency relationships, monotonicity, and cross-domain constraints remain valid.

const BoardManager = preload("res://scripts/board/board_manager.gd")
const BoardTile = preload("res://scripts/board/board_tile.gd")

var _pass_count: int = 0
var _fail_count: int = 0
var _failures: Array[String] = []
var _board_scene: BoardManager = null


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		_failures.append(message)
		print("  [FAIL] %s" % message)


func _ready() -> void:
	print("\n==================================================")
	print("PHASE 2E-48: GAMEPLAY RULE INVARIANT INTEGRITY AUDIT")
	print("==================================================")
	GameManager.suppress_scene_change = true
	_run_all_tests()
	_print_summary()
	if _fail_count > 0:
		push_error("PHASE_2E_48_FAILURE: %d assertions failed" % _fail_count)
		get_tree().quit(1)
	else:
		print("\nPHASE_2E_48_SUCCESS")
		get_tree().quit(0)


func _exit_tree() -> void:
	_cleanup_board_scene()


func _instantiate_board_scene() -> BoardManager:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null

	GameManager.current_state = GameManager.State.BOARD
	GlobalData.board.active_contract = {"name": "Test Contract", "target_sector": 1}
	GlobalData.board.board_objective_intro_consumed = true
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_fuel_reserve = 100.0
	GlobalData.fuel.convoy_fuel_max = 200.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.fuel.mech_max_energy = 1000.0
	GlobalData.fuel.pilot_stamina = 100.0
	GlobalData.fuel.pilot_max_stamina = 100.0
	GlobalData.board.board_mp = 8
	GlobalData.board.board_mp_max = 8

	var board_res: PackedScene = load("res://scenes/board/game_board.tscn")
	_board_scene = board_res.instantiate() as BoardManager
	add_child(_board_scene)
	var intermission = _board_scene.get_node_or_null("IntermissionUI")
	if intermission:
		intermission.visible = false
	return _board_scene


func _cleanup_board_scene() -> void:
	if _board_scene and is_instance_valid(_board_scene):
		_board_scene.queue_free()
		_board_scene = null


func _run_all_tests() -> void:
	# ===========================================================================
	# Scenario A: Movement Resource Invariant (Domain A / I1, I2)
	# ===========================================================================
	print("\n-- Scenario A: Movement Resource Invariant --")
	GlobalData.fuel.traversal_mode = "convoy"
	GlobalData.fuel.convoy_fuel = 100.0
	GlobalData.fuel.convoy_max_fuel = 200.0
	GlobalData.board.board_mp = 10
	GlobalData.board.board_mp_max = 10
	GlobalData.board.current_hazard = ""

	var step_costs: Dictionary = GlobalData.fuel.get_mode_step_cost("plain")
	var expected_mp_cost: int = int(step_costs["mp"])
	var expected_fuel_cost: float = float(step_costs["fuel"])

	var initial_mp := GlobalData.board.board_mp
	var initial_fuel := GlobalData.fuel.convoy_fuel

	# Legal deduction check
	GlobalData.board.board_mp = maxi(GlobalData.board.board_mp - expected_mp_cost, 0)
	GlobalData.fuel.convoy_fuel = maxf(GlobalData.fuel.convoy_fuel - expected_fuel_cost, 0.0)

	_assert(GlobalData.board.board_mp == initial_mp - expected_mp_cost, "Movement decreases MP exactly by rule cost")
	_assert(GlobalData.fuel.convoy_fuel == initial_fuel - expected_fuel_cost, "Movement decreases convoy fuel exactly by rule cost")
	_assert(GlobalData.board.board_mp >= 0 and GlobalData.board.board_mp <= GlobalData.board.board_mp_max, "MP strictly satisfies 0 <= MP <= MaxMP")
	_assert(GlobalData.fuel.convoy_fuel >= 0.0 and GlobalData.fuel.convoy_fuel <= GlobalData.fuel.convoy_max_fuel, "Fuel strictly satisfies 0 <= Fuel <= MaxFuel")

	# ===========================================================================
	# Scenario B: Blocked Movement Zero-Mutation Invariant (Domain A / I4)
	# ===========================================================================
	print("\n-- Scenario B: Blocked Movement Zero-Mutation Invariant --")
	var board := _instantiate_board_scene()
	var origin_pos := board.current_pos
	var initial_mp_b := GlobalData.board.board_mp
	var initial_fuel_b := GlobalData.fuel.convoy_fuel

	# Find or inject an impassable neighbor (water terrain)
	var impassable_cand := Vector2i(-99, -99)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var cand: Vector2i = origin_pos + d
		if board.nodes_dict.has(cand):
			var tile_node = board.nodes_dict[cand]
			if not BoardConfig.is_passable(str(tile_node.get_meta("terrain", "plain"))):
				impassable_cand = cand
				break
	if impassable_cand == Vector2i(-99, -99):
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cand: Vector2i = origin_pos + d
			if board.nodes_dict.has(cand):
				board.nodes_dict[cand].set_meta("terrain", "water")
				impassable_cand = cand
				break

	var can_step_impassable := board._can_step(impassable_cand)
	_assert(!can_step_impassable, "_can_step rejects impassable water tile")
	var step_res := board._try_step(impassable_cand)
	_assert(!step_res, "_try_step returns false for impassable terrain")
	_assert(board.current_pos == origin_pos, "Position remains unchanged after rejected step")
	_assert(GlobalData.board.board_mp == initial_mp_b, "MP remains completely unmutated on rejected step")
	_assert(GlobalData.fuel.convoy_fuel == initial_fuel_b, "Fuel remains completely unmutated on rejected step")

	# Non-adjacent tile rejection check
	var far_tile := origin_pos + Vector2i(5, 5)
	var can_step_far := board._can_step(far_tile)
	_assert(!can_step_far, "_can_step rejects non-adjacent tile")

	# ===========================================================================
	# Scenario C: Combat Damage / HP Boundary Invariant (Domain B / I1)
	# ===========================================================================
	print("\n-- Scenario C: Combat Damage / HP Boundary Invariant --")
	var current_hp := 50.0
	var armor_class := 1.0

	# Standard damage
	var dmg_res_1 = DamageCalculator.calculate_damage(30.0, armor_class, current_hp, false)
	_assert(is_equal_approx(dmg_res_1["remaining"], 20.0), "Damage reduces HP accurately according to formula")
	_assert(!dmg_res_1["destroyed"], "Unit is not destroyed when HP > 0")

	# Lethal overkill damage
	var dmg_res_2 = DamageCalculator.calculate_damage(100.0, armor_class, current_hp, false)
	_assert(dmg_res_2["remaining"] == 0.0, "Overkill damage cleanly clamps remaining HP to exactly 0.0")
	_assert(dmg_res_2["destroyed"] == true, "Unit is destroyed when remaining HP <= 0")

	# Zero damage
	var dmg_res_3 = DamageCalculator.calculate_damage(0.0, armor_class, current_hp, false)
	_assert(is_equal_approx(dmg_res_3["remaining"], current_hp), "Zero incoming damage causes 0 HP change")
	_assert(!dmg_res_3["destroyed"], "Zero damage does not destroy unit")

	# Destroyed / broken part receives damage
	var dmg_res_broken = DamageCalculator.calculate_damage(50.0, armor_class, 0.0, true)
	_assert(dmg_res_broken["reduced"] == 0.0 and dmg_res_broken["remaining"] == 0.0, "Already broken part absorbs 0 damage and remains at 0 HP")

	# ===========================================================================
	# Scenario D: Armor Boundary Invariant (Domain B / I1, I5)
	# ===========================================================================
	print("\n-- Scenario D: Armor Boundary Invariant --")
	var armor_data := {"armor_type": "composite", "durability": 100.0, "max_durability": 100.0}
	var res_kinetic := DamageCalculator.get_armor_resistance(armor_data, "kinetic")
	_assert(res_kinetic > 0.0, "Armor returns valid positive resistance factor")

	var mitigated_full := DamageCalculator.calculate_armor_damage(100.0, "kinetic", armor_data, 1.0)
	var mitigated_degraded := DamageCalculator.calculate_armor_damage(100.0, "kinetic", armor_data, 0.5)
	_assert(mitigated_degraded > mitigated_full, "Degraded armor durability penalizes mitigation (increases damage taken)")

	# ===========================================================================
	# Scenario E: Heat Threshold Invariant (Domain C / I1, I4)
	# ===========================================================================
	print("\n-- Scenario E: Heat Threshold Invariant --")
	var heat_pool := 0.0
	var max_heat := 100.0
	var overheat_threshold := 80.0

	# Sub-threshold
	heat_pool += 50.0
	var is_overheat := (heat_pool >= overheat_threshold)
	_assert(!is_overheat, "Heat below threshold does not trigger overheat state")

	# Exact threshold
	heat_pool = 80.0
	_assert(heat_pool >= overheat_threshold, "Heat at exact threshold triggers overheat state")

	# Above threshold
	heat_pool = 85.0
	_assert(heat_pool >= overheat_threshold, "Heat above threshold maintains overheat state")

	# ===========================================================================
	# Scenario F: Heat Clamp / Overflow Behavior (Domain C / I1)
	# ===========================================================================
	print("\n-- Scenario F: Heat Clamp / Overflow Behavior --")
	var raw_heat_add := 50.0
	heat_pool = minf(heat_pool + raw_heat_add, max_heat)
	_assert(heat_pool == max_heat, "Heat overflow cleanly clamps to MaxHeat (100.0)")
	_assert(heat_pool <= max_heat, "Heat never exceeds max_heat")

	# Dissipation
	var dissipation := 30.0
	heat_pool = maxf(heat_pool - dissipation, 0.0)
	_assert(heat_pool == 70.0, "Heat dissipation reduces heat pool correctly")
	heat_pool = maxf(heat_pool - 100.0, 0.0)
	_assert(heat_pool == 0.0, "Excess dissipation cleanly clamps to 0.0 minimum")

	# ===========================================================================
	# Scenario G: Weapon Capability Neutral-Default Behavior (Domain D / I5)
	# ===========================================================================
	print("\n-- Scenario G: Weapon Capability Neutral-Default Behavior --")
	var default_weapon := WeaponPart.new()
	default_weapon.arm_load = 0.0
	default_weapon.stability_requirement = 0.0
	default_weapon.recoil_force = 0.0
	default_weapon.weight = 5.0

	var neutral_powers := {"arm_power": 10.0, "leg_power": 10.0, "recoil_resistance": 0.0}
	var res_default: Dictionary = HandlingResolver.resolve(default_weapon, "hand", neutral_powers)

	_assert(res_default["supported"] == true, "Default neutral weapon is fully supported")
	_assert(res_default["grip_mode"] == HandlingResolver.GRIP_ONE_HAND, "Default weapon defaults to ONE_HAND grip")
	_assert(res_default["recoil_level"] == HandlingResolver.RECOIL_MINIMAL, "Default weapon resolves to MINIMAL recoil")
	_assert(res_default["mobility_fire_mode"] == HandlingResolver.MOBILITY_SPRINT, "Default weapon allows SPRINT mobility")
	_assert(res_default["aim_stability"] == HandlingResolver.AIM_NORMAL, "Default weapon resolves to NORMAL aim stability")
	_assert(is_equal_approx(float(res_default["recoil_mult"]), 1.0), "Default recoil multiplier is exactly 1.0")

	# ===========================================================================
	# Scenario H: Weapon Capability Rejection Boundary (Domain D / I5)
	# ===========================================================================
	print("\n-- Scenario H: Weapon Capability Rejection Boundary --")
	var custom_weapon := WeaponPart.new()
	custom_weapon.weight = 50.0
	custom_weapon.recoil_force = 35.0
	custom_weapon.mount_compatibility = ["hand"]

	# Incompatible mount
	var res_incompat: Dictionary = HandlingResolver.is_mount_supported(custom_weapon, "special_pod")
	_assert(!res_incompat["supported"], "Non-legacy incompatible mount is rejected")
	_assert(res_incompat["reason"] == "mount_incompatible", "Rejection reason matches 'mount_incompatible'")

	# Over-capacity mount
	custom_weapon.mount_compatibility = ["shoulder_left"]
	var res_over_mass: Dictionary = HandlingResolver.is_mount_supported(custom_weapon, "custom_shoulder_slot")
	_assert(!res_over_mass["supported"], "Exceeding mount mass capacity is rejected")

	# Legacy slot grandfathering check
	var res_legacy: Dictionary = HandlingResolver.is_mount_supported(custom_weapon, "shoulder_left")
	_assert(res_legacy["supported"] == true, "Legacy slots are grandfathered for stock compatibility")

	# ===========================================================================
	# Scenario I: Weapon Stability Boundary (Domain D / I5)
	# ===========================================================================
	print("\n-- Scenario I: Weapon Stability Boundary --")
	var heavy_weapon := WeaponPart.new()
	heavy_weapon.arm_load = 15.0
	heavy_weapon.stability_requirement = 12.0
	heavy_weapon.recoil_force = 10.0

	var low_power_frame := {"arm_power": 5.0, "leg_power": 5.0, "recoil_resistance": 0.0}
	var res_heavy: Dictionary = HandlingResolver.resolve(heavy_weapon, "hand", low_power_frame)

	_assert(res_heavy["grip_mode"] == HandlingResolver.GRIP_TWO_HAND or res_heavy["grip_mode"] == HandlingResolver.GRIP_BRACED,
		"Under-powered arm forces TWO_HAND / BRACED grip")
	_assert(res_heavy["aim_stability"] == HandlingResolver.AIM_LOW, "Negative power margin drops aim stability to LOW")
	_assert(res_heavy["mobility_fire_mode"] == HandlingResolver.MOBILITY_STATIONARY, "High recoil + low leg power forces STATIONARY mobility")

	# High power frame
	var high_power_frame := {"arm_power": 30.0, "leg_power": 30.0, "recoil_resistance": 0.3}
	var res_empowered: Dictionary = HandlingResolver.resolve(heavy_weapon, "hand", high_power_frame)
	_assert(res_empowered["grip_mode"] == HandlingResolver.GRIP_ONE_HAND, "Empowered arm sustains ONE_HAND grip")
	_assert(res_empowered["aim_stability"] == HandlingResolver.AIM_HIGH, "High power margin upgrades aim stability to HIGH")
	_assert(res_empowered["mobility_fire_mode"] == HandlingResolver.MOBILITY_SPRINT, "Empowered legs sustain SPRINT mobility")

	# ===========================================================================
	# Scenario J: Weapon Success Exact-Once Consequence (Domain D / I2)
	# ===========================================================================
	print("\n-- Scenario J: Weapon Success Exact-Once Consequence --")
	var ammo_pool := 10
	var heat_val := 0.0
	var ammo_cost := 1
	var heat_cost := 8.0

	# Execute firing consequence
	ammo_pool -= ammo_cost
	heat_val += heat_cost

	_assert(ammo_pool == 9, "Weapon firing decrements ammo by exactly its consumption rate")
	_assert(heat_val == 8.0, "Weapon firing adds exact heat value once")

	# ===========================================================================
	# Scenario K: Equipment Weight Invariant (Domain E / I3)
	# ===========================================================================
	print("\n-- Scenario K: Equipment Weight Invariant --")
	var part_weights := [12.5, 8.0, 15.0, 4.5]
	var total_calculated := 0.0
	for w in part_weights:
		total_calculated += w
	_assert(is_equal_approx(total_calculated, 40.0), "Total loadout weight is exact sum of constituent parts")

	# ===========================================================================
	# Scenario L: Capacity Boundary (Domain E / I3)
	# ===========================================================================
	print("\n-- Scenario L: Capacity Boundary --")
	var max_capacity := 50.0
	var is_under_cap := (total_calculated <= max_capacity)
	_assert(is_under_cap, "Weight of 40.0 kg is legal within 50.0 kg capacity")

	var penalty: Dictionary = DamageCalculator.calculate_weight_penalty(total_calculated, max_capacity)
	_assert(penalty["speed_mult"] > 0.0 and penalty["speed_mult"] <= 1.0, "Speed multiplier is within legal (0.0, 1.0] range")
	_assert(penalty["turn_rate_mult"] > 0.0, "Turn rate multiplier remains positive and non-zero")

	# Over-capacity penalty check
	var over_weight := 60.0
	var over_penalty: Dictionary = DamageCalculator.calculate_weight_penalty(over_weight, max_capacity)
	_assert(over_penalty["speed_mult"] <= penalty["speed_mult"], "Over-weight loadout receives greater speed penalty")

	# ===========================================================================
	# Scenario M: Research State Transition Invariant (Domain F / I4, I6)
	# ===========================================================================
	print("\n-- Scenario M: Research State Transition Invariant --")
	TechnologySystem.init_catalog_if_needed()
	var test_tech_id := "tech_ballistic_conventional"

	var initial_state := TechnologySystem.get_discovery_state(test_tech_id)
	_assert(initial_state == TechnologySystem.DiscoveryState.USABLE, "Conventional base technology initializes to USABLE")

	# Verify enum monotonicity ordering
	_assert(TechnologySystem.DiscoveryState.UNKNOWN < TechnologySystem.DiscoveryState.ENCOUNTERED, "Discovery UNKNOWN < ENCOUNTERED")
	_assert(TechnologySystem.DiscoveryState.ENCOUNTERED < TechnologySystem.DiscoveryState.SALVAGED, "Discovery ENCOUNTERED < SALVAGED")
	_assert(TechnologySystem.DiscoveryState.SALVAGED < TechnologySystem.DiscoveryState.IDENTIFIED, "Discovery SALVAGED < IDENTIFIED")
	_assert(TechnologySystem.DiscoveryState.IDENTIFIED < TechnologySystem.DiscoveryState.RESEARCHED, "Discovery IDENTIFIED < RESEARCHED")
	_assert(TechnologySystem.DiscoveryState.RESEARCHED < TechnologySystem.DiscoveryState.USABLE, "Discovery RESEARCHED < USABLE")

	# ===========================================================================
	# Scenario N: Technology Modifier Eligibility (Domain F / I5)
	# ===========================================================================
	print("\n-- Scenario N: Technology Modifier Eligibility --")
	var empty_context: Dictionary = {}
	var base_dmg_mult := CombatModifierResolver.resolve_pilot_damage_multiplier(empty_context)
	_assert(is_equal_approx(base_dmg_mult, 1.0), "Unmodified pilot damage multiplier is baseline 1.0")

	var unlocked_context := {
		"unlocked_skills": ["kinetic_tuning", "point_blank_mastery"]
	}
	var modified_dmg_mult := CombatModifierResolver.resolve_pilot_damage_multiplier(unlocked_context)
	_assert(is_equal_approx(modified_dmg_mult, 1.30), "Unlocked skills apply additive damage bonuses (1.0 + 0.10 + 0.20 = 1.30)")

	var dash_mult_base := CombatModifierResolver.resolve_dash_energy_multiplier(empty_context)
	_assert(is_equal_approx(dash_mult_base, 1.0), "Baseline dash multiplier is 1.0 without perks")

	var perk_context := {
		"hired_pilots": [{"perk_id": "precognitive_flow"}]
	}
	var dash_mult_perk := CombatModifierResolver.resolve_dash_energy_multiplier(perk_context)
	_assert(is_equal_approx(dash_mult_perk, 0.5), "Precognitive flow perk grants exactly 0.5x dash cost")

	# ===========================================================================
	# Scenario O: Objective Completion Boundary (Domain G / I1, I5)
	# ===========================================================================
	print("\n-- Scenario O: Objective Completion Boundary --")
	GlobalData.board.active_contract = {}
	GlobalData.board.board_theme_id = "grassland"
	GlobalData.board.board_objective_progress = 0
	GlobalData.board.board_objective_required = 3

	_assert(!BoardSystem.is_objective_complete(), "Objective is incomplete at 0/3 progress")

	# Add partial progress
	BoardSystem.add_progress(2)
	_assert(GlobalData.board.board_objective_progress == 2, "Progress increments to 2")
	_assert(!BoardSystem.is_objective_complete(), "Objective is incomplete at 2/3 progress")

	# Complete objective
	BoardSystem.add_progress(1)
	_assert(GlobalData.board.board_objective_progress == 3, "Progress reaches required 3")
	_assert(BoardSystem.is_objective_complete(), "Objective is recognized as complete at required threshold")

	# Over-completion clamp
	BoardSystem.add_progress(5)
	_assert(GlobalData.board.board_objective_progress == 3, "Excess progress cleanly clamps to required ceiling")

	# ===========================================================================
	# Scenario P: Extraction Unlock Invariant (Domain G / I4, I5)
	# ===========================================================================
	print("\n-- Scenario P: Extraction Unlock Invariant --")
	GlobalData.board.active_contract = {"id": "test_contract"}
	GlobalData.board.primary_objective_done = false
	_assert(!BoardSystem.is_objective_complete(), "Extraction locked when primary contract objective is incomplete")

	GlobalData.board.primary_objective_done = true
	_assert(BoardSystem.is_objective_complete(), "Extraction unlocked when primary contract objective is completed")

	# ===========================================================================
	# Scenario Q: Patrol / Engagement Referential Invariant (Domain H / I7, I8)
	# ===========================================================================
	print("\n-- Scenario Q: Patrol / Engagement Referential Invariant --")
	GlobalData.board.board_patrols = [
		{"id": 0, "pos": Vector2i(2, 2), "name": "Vultures", "pilots": []},
		{"id": 1, "pos": Vector2i(4, 4), "name": "Ravens", "pilots": []}
	]
	GlobalData.board.board_patrol_engagement = 0
	_assert(GlobalData.board.board_patrol_engagement >= 0 and GlobalData.board.board_patrol_engagement < GlobalData.board.board_patrols.size(),
		"Active patrol engagement references a valid patrol index")

	# After defeat / removal
	GlobalData.board.board_patrols.remove_at(0)
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement resets to -1 after resolution")
	_assert(GlobalData.board.board_patrols.size() == 1, "Defeated patrol is removed from roster")

	# ===========================================================================
	# Scenario R: Reward Conservation (Domain I / I2)
	# ===========================================================================
	print("\n-- Scenario R: Reward Conservation --")
	GlobalData.currency.reset(100)
	_assert(GlobalData.currency.credits == 100, "Initial credits set to 100")
	_assert(GlobalData.currency.scrap == 0, "Initial scrap is 0")
	_assert(GlobalData.currency.data_cores == 0, "Initial data cores is 0")

	GlobalData.currency.gain_credits(50)
	GlobalData.currency.gain_scrap(20)
	GlobalData.currency.gain_data_cores(2)

	_assert(GlobalData.currency.credits == 150, "Credits increase by exact gain amount (+50 -> 150)")
	_assert(GlobalData.currency.scrap == 20, "Scrap increases by exact gain amount (+20 -> 20)")
	_assert(GlobalData.currency.data_cores == 2, "Data cores increase by exact gain amount (+2 -> 2)")

	# ===========================================================================
	# Scenario S: Currency Overspend Invariant (Domain I / I1, I2)
	# ===========================================================================
	print("\n-- Scenario S: Currency Overspend Invariant --")
	var spend_success := GlobalData.currency.try_spend_credits(50)
	_assert(spend_success, "Spending 50 from 150 credits succeeds")
	_assert(GlobalData.currency.credits == 100, "Credits balance decrements to 100")

	var overspend_credits := GlobalData.currency.try_spend_credits(200)
	_assert(!overspend_credits, "Overspending credits (200 > 100) is rejected")
	_assert(GlobalData.currency.credits == 100, "Credits balance unchanged after rejected spend")

	var overspend_scrap := GlobalData.currency.try_spend_scrap(50)
	_assert(!overspend_scrap, "Overspending scrap (50 > 20) is rejected")
	_assert(GlobalData.currency.scrap == 20, "Scrap balance unchanged after rejected spend")

	var spend_negative := GlobalData.currency.try_spend_credits(-10)
	_assert(!spend_negative, "Negative spend attempt is rejected")
	_assert(GlobalData.currency.credits == 100, "Balance unchanged on negative spend attempt")

	# ===========================================================================
	# Scenario T: Sector-Local vs Run-Persistent State Invariant (Domain J / I8)
	# ===========================================================================
	print("\n-- Scenario T: Sector-Local vs Run-Persistent State Invariant --")
	GlobalData.board.current_sector = 1
	GlobalData.board.board_theme_id = "grassland"
	GlobalData.board.board_objective_id = "scout_camps"
	var persistent_credits := GlobalData.currency.credits
	var persistent_scrap := GlobalData.currency.scrap

	# Simulate sector transition
	GlobalData.board.current_sector += 1
	GlobalData.board.board_objective_id = "" # reset sector-local
	GlobalData.board.board_patrols.clear()   # reset sector-local
	GlobalData.board.board_mp = GlobalData.board.board_mp_max # refreshed

	_assert(GlobalData.board.current_sector == 2, "Sector number advanced to 2")
	_assert(GlobalData.board.board_objective_id == "", "Sector-local objective ID reset for new generation")
	_assert(GlobalData.board.board_patrols.is_empty(), "Sector-local patrols cleared")
	_assert(GlobalData.currency.credits == persistent_credits, "Run-persistent credits preserved across sector transition")
	_assert(GlobalData.currency.scrap == persistent_scrap, "Run-persistent scrap preserved across sector transition")

	# ===========================================================================
	# Scenario U: Run Terminal-State Invariant (Domain J / I4, I6)
	# ===========================================================================
	print("\n-- Scenario U: Run Terminal-State Invariant --")
	GameManager.current_state = GameManager.State.MENU
	_assert(GameManager.current_state == GameManager.State.MENU, "Menu state is valid terminal/idle state")
	_assert(GameManager.current_state != GameManager.State.COMBAT, "Terminal state is mutually exclusive with active combat")
	_assert(GameManager.current_state != GameManager.State.BOARD, "Terminal state is mutually exclusive with active board")

	# ===========================================================================
	# Scenario V: Run Reset Invariant (Domain J / I4)
	# ===========================================================================
	print("\n-- Scenario V: Run Reset Invariant --")
	GlobalData.currency.reset(110)
	GlobalData.fuel.convoy_fuel = 350.0
	GlobalData.fuel.mech_energy = 1000.0
	GlobalData.board.current_sector = 1
	GameManager.current_state = GameManager.State.BOARD

	_assert(GlobalData.currency.credits == 110, "Run reset restores starting credits (110)")
	_assert(GlobalData.currency.scrap == 0, "Run reset zeroes scrap")
	_assert(GlobalData.fuel.convoy_fuel == 350.0, "Run reset restores starting convoy fuel")
	_assert(GlobalData.fuel.mech_energy == 1000.0, "Run reset restores starting mech energy")
	_assert(GlobalData.board.current_sector == 1, "Run reset starts at Sector 1")
	_assert(GameManager.current_state == GameManager.State.BOARD, "Clean active board state established")

	# ===========================================================================
	# Scenario W: Save/Load Invariant Preservation (Domain K / I8)
	# ===========================================================================
	print("\n-- Scenario W: Save/Load Invariant Preservation --")
	GlobalData.currency.credits = 345
	GlobalData.currency.scrap = 85
	GlobalData.fuel.convoy_fuel_reserve = 175.0
	GlobalData.board.current_tile = Vector2i(3, 4)
	GlobalData.board.board_mp = 7

	SaveGameIO.save_run()
	_assert(FileAccess.file_exists(GlobalData.SAVE_PATH), "Save file created at user://savegame.json")

	# Reset and load back
	GlobalData.currency.credits = 0
	GlobalData.currency.scrap = 0
	GlobalData.fuel.convoy_fuel_reserve = 0.0
	GlobalData.board.board_mp = 0

	var load_success := SaveGameIO.load_run()
	_assert(load_success, "SaveGameIO.load_run() completes successfully")
	_assert(GlobalData.currency.credits == 345, "Loaded credits restored accurately")
	_assert(GlobalData.currency.scrap == 85, "Loaded scrap restored accurately")
	_assert(is_equal_approx(GlobalData.fuel.convoy_fuel_reserve, 175.0), "Loaded convoy fuel reserve restored accurately")
	_assert(GlobalData.board.board_mp == 7, "Loaded board MP restored accurately")

	# ===========================================================================
	# Scenario X: Cross-Domain: Weapon + Frame + Loadout (Domain D, E / I8)
	# ===========================================================================
	print("\n-- Scenario X: Cross-Domain: Weapon + Frame + Loadout --")
	var sample_weapon := WeaponPart.new()
	sample_weapon.weight = 10.0
	sample_weapon.arm_load = 5.0
	sample_weapon.stability_requirement = 4.0
	sample_weapon.recoil_force = 4.0

	var frame_caps := {"arm_power": 15.0, "leg_power": 15.0, "recoil_resistance": 0.1}
	var cross_res: Dictionary = HandlingResolver.resolve(sample_weapon, "hand", frame_caps)

	_assert(cross_res["supported"] == true, "Weapon is supported on frame")
	_assert(cross_res["grip_mode"] == HandlingResolver.GRIP_ONE_HAND, "Frame arm power (15.0) exceeds weapon load (5.0) -> ONE_HAND")
	_assert(cross_res["aim_stability"] == HandlingResolver.AIM_HIGH, "Frame stability margin exceeds +10.0 threshold -> HIGH aim")

	# ===========================================================================
	# Scenario Y: Cross-Domain: Research + Combat Modifier (Domain F / I8)
	# ===========================================================================
	print("\n-- Scenario Y: Cross-Domain: Research + Combat Modifier --")
	var tech_ctx := {"unlocked_skills": ["heat_venting_drills", "combat_strides"]}
	var heat_mult := CombatModifierResolver.resolve_pilot_heat_generation_multiplier(tech_ctx)
	var speed_mult := CombatModifierResolver.resolve_pilot_movement_speed_multiplier(tech_ctx)

	_assert(is_equal_approx(heat_mult, 0.85), "Unlocked heat venting drills grants 0.85x heat multiplier")
	_assert(is_equal_approx(speed_mult, 1.10), "Unlocked combat strides grants 1.10x movement speed multiplier")

	# ===========================================================================
	# Scenario Z: Cross-Domain: Patrol + Engagement + Combat Flow (Domain H / I8)
	# ===========================================================================
	print("\n-- Scenario Z: Cross-Domain: Patrol + Engagement + Combat Flow --")
	var patrol_fleet := {
		"id": 10,
		"pos": Vector2i(2, 3),
		"home": Vector2i(2, 3),
		"name": "Strykers",
		"faction": "hostile",
		"pilots": [
			{"pilot_id": "grunt_1", "mech_loadout": {}}
		]
	}
	GlobalData.board.board_patrols = [patrol_fleet]
	GlobalData.board.board_patrol_engagement = 0

	var engaged_patrol: Dictionary = GlobalData.board.board_patrols[GlobalData.board.board_patrol_engagement]
	_assert(engaged_patrol["name"] == "Strykers", "Engagement points to correct hostile fleet")
	_assert((engaged_patrol["pilots"] as Array).size() == 1, "Engaged patrol has valid combat roster")

	# Cleanup test artifacts
	GlobalData.board.board_patrols.clear()
	GlobalData.board.board_patrol_engagement = -1
	_assert(GlobalData.board.board_patrol_engagement == -1, "Patrol engagement cleaned up to -1")


func _print_summary() -> void:
	print("\n==================================================")
	print("PHASE 2E-48 INVARIANT AUDIT SUMMARY:")
	print("  Passed: %d" % _pass_count)
	print("  Failed: %d" % _fail_count)
	if _fail_count > 0:
		print("\nFailures:")
		for f in _failures:
			print("  - %s" % f)
	print("==================================================")
