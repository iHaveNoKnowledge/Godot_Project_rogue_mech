class_name EraProgressionSystem
extends RefCounted

## ---------------------------------------------------------------------------
## ERA PROGRESSION SYSTEM (War Phase Evolution)
##
## As the planetary war prolongs, the technology, battlefield physics,
## and core gameplay mutate across 3 distinct Eras:
##
## Phase 1: Tactical Era (Turn 1 - 15)
##   - Heavy industrial physics, slow deliberate mechs, kinetic ballistics.
##   - Cover system provides high defense, single heavy Pile Bunker impacts.
##
## Phase 2: Energy Era (Turn 16 - 30)
##   - Beam/plasma weapons become standard, agile thrusters, Close Combat mode fully dominant.
##   - Burst mode thruster overcharge enabled.
##
## Phase 3: Singularity Era (Turn 31+)
##   - One-Mech Army prototypes, 360-degree omni barriers, destructive lasers.
##   - Hyper-fluid deflection & relativistic dash speeds.
## ---------------------------------------------------------------------------

enum EraPhase {
	PHASE_1_TACTICAL = 1,
	PHASE_2_ENERGY = 2,
	PHASE_3_SINGULARITY = 3
}

static var current_turn: int = 1
static var current_phase: EraPhase = EraPhase.PHASE_1_TACTICAL

const PHASE_2_TURN_THRESHOLD: int = 16
const PHASE_3_TURN_THRESHOLD: int = 31


static func reset() -> void:
	current_turn = 1
	current_phase = EraPhase.PHASE_1_TACTICAL


## Advances the war calendar turn and checks for Era evolution.
static func advance_war_turn(turn_count: int = 1) -> Dictionary:
	var old_phase = current_phase
	current_turn += turn_count
	
	if current_turn >= PHASE_3_TURN_THRESHOLD:
		current_phase = EraPhase.PHASE_3_SINGULARITY
	elif current_turn >= PHASE_2_TURN_THRESHOLD:
		current_phase = EraPhase.PHASE_2_ENERGY
	else:
		current_phase = EraPhase.PHASE_1_TACTICAL

	var phase_changed = (old_phase != current_phase)
	if phase_changed:
		EventBus.era_phase_advanced.emit(get_era_name(), int(current_phase))

	return {
		"current_turn": current_turn,
		"phase": current_phase,
		"phase_changed": phase_changed,
		"era_name": get_era_name()
	}


static func get_era_name() -> String:
	match current_phase:
		EraPhase.PHASE_1_TACTICAL:
			return "Tactical Era (Heavy Ballistics & Cover)"
		EraPhase.PHASE_2_ENERGY:
			return "Energy Era (Beam Warfare & Hack-and-Slash)"
		EraPhase.PHASE_3_SINGULARITY:
			return "Singularity Era (Infinite Energy & Omni-Shields)"
	return "Tactical Era"


## Gameplay modifiers derived from current Era phase.
static func get_era_modifiers() -> Dictionary:
	match current_phase:
		EraPhase.PHASE_1_TACTICAL:
			return {
				"ballistic_damage_mult": 1.25,
				"energy_damage_mult": 0.85,
				"speed_mult": 0.90,
				"dash_recharge_mult": 0.85,
				"cover_defense_bonus": 0.40,
				"pile_bunker_impact_mult": 1.5,
				"unlocked_burst_mode": false,
				"omni_barrier_active": false
			}
		EraPhase.PHASE_2_ENERGY:
			return {
				"ballistic_damage_mult": 1.0,
				"energy_damage_mult": 1.30,
				"speed_mult": 1.15,
				"dash_recharge_mult": 1.20,
				"cover_defense_bonus": 0.20,
				"pile_bunker_impact_mult": 1.2,
				"unlocked_burst_mode": true,
				"omni_barrier_active": false
			}
		EraPhase.PHASE_3_SINGULARITY:
			return {
				"ballistic_damage_mult": 1.10,
				"energy_damage_mult": 1.65,
				"speed_mult": 1.40,
				"dash_recharge_mult": 1.60,
				"cover_defense_bonus": 0.10,
				"pile_bunker_impact_mult": 1.8,
				"unlocked_burst_mode": true,
				"omni_barrier_active": true
			}
	return {}


static func serialize_era_state() -> Dictionary:
	return {
		"current_turn": current_turn,
		"current_phase": int(current_phase)
	}


static func deserialize_era_state(data: Variant) -> void:
	reset()
	if data is Dictionary:
		current_turn = maxi(1, int(data.get("current_turn", 1)))
		var phase_val := int(data.get("current_phase", EraPhase.PHASE_1_TACTICAL))
		if phase_val in [EraPhase.PHASE_1_TACTICAL, EraPhase.PHASE_2_ENERGY, EraPhase.PHASE_3_SINGULARITY]:
			current_phase = phase_val
		else:
			if current_turn >= PHASE_3_TURN_THRESHOLD:
				current_phase = EraPhase.PHASE_3_SINGULARITY
			elif current_turn >= PHASE_2_TURN_THRESHOLD:
				current_phase = EraPhase.PHASE_2_ENERGY
			else:
				current_phase = EraPhase.PHASE_1_TACTICAL

