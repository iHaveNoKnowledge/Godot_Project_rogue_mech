extends Node

# --- Damage Pipeline ---
signal damage_received(slot_name: String, raw_damage: float, damage_type: String)
## Fired for every friendly unit (player mech + fielded allies) that takes
## damage, so combat can measure how "decisive" our victory was.
signal friendly_damage_received(raw_damage: float)
## Fired by each fielded ally whenever its live HP changes, so the squad HUD
## panel (pilot names + health bars) can update without polling every frame.
## Payload: {template_id, name, health (0..1), destroyed}.
signal ally_squad_updated(ally_data: Dictionary)
signal armor_degraded(slot_name: String, current_hp: float, max_hp: float)
signal armor_broken(slot_name: String)
signal part_destroyed(slot_name: String)
signal mecha_destroyed()

# --- Weight / Mobility ---
signal weight_changed(total_weight: float)
signal speed_modified(new_speed: float)

# --- Camera ---
signal camera_mode_changed(new_mode: String)
signal camera_target_changed(target: Node3D)
signal lock_on_target_acquired(target: Node3D)
signal lock_on_target_lost()

# --- Combat ---
signal weapon_fired(target_position: Vector3)
signal combat_mode_toggled(mode: String)
signal deflect_triggered(position: Vector3, is_perfect: bool)
signal guard_state_changed(is_guarding: bool)
signal pile_bunker_fired(is_loaded_blast: bool, target_pos: Vector3)

# --- Rival & Era Progression ---
signal rival_progression_updated(rival_data: Dictionary)
signal era_phase_advanced(new_era: String, phase_index: int)
signal prototype_encounter_triggered(prototype_data: Dictionary)

# --- Eject / Pilot ---
signal eject_initiated()
signal pilot_spawned(pilot_node: Node3D)
signal pilot_boarded_backup(backup_mech: Node3D)
signal backup_mech_destroyed()
## Fired whenever a mech gains or loses its pilot so its pose can react:
## occupied = true -> standing idle, false -> kneel while waiting for its pilot.
signal mecha_occupancy_changed(occupied: bool)
## Fired when on-foot pilot or player moves in/out of range of an interactive entity (e.g. boardable mech)
signal interaction_prompt_updated(prompt_text: String, is_visible: bool)

# --- Board ---
signal tile_entered(tile_pos: Vector2i, tile_data: Node)
## Fired at the end of a grid "day" (MP exhausted / End Day pressed), so
## research, heat decay, spy rolls, enemy research nodes, patrol fleets and
## other once-per-day systems all advance exactly once per day — even though the
## player may have stepped across many cells that day.
signal board_day_ended()
signal event_triggered(event_data: Dictionary)
signal heat_changed(new_heat: int)
signal wanted_changed(new_wanted: int)
signal combat_ended(victory: bool)
## Fired when the player completes a retreat: held position inside an escape
## zone long enough to abandon the battle without destroying every enemy.
signal combat_escaped()
signal combat_escaped_directional(escape_type: String, delta_tile: Vector2i)
signal enemy_tech_escalated(new_tier: int)
signal faction_research_started(faction: String, tier: int, reason: String)
signal faction_tier_upgraded(faction: String, new_tier: int)

# --- Game State ---
signal game_state_changed(old_state: String, new_state: String)
signal run_ended(victory: bool)

# --- Safehouse ---
signal heal_requested(amount: float)
signal repair_requested()

# --- Combat Rewards ---
signal combat_rewards_shown(rewards: Dictionary)

# --- Arena ---
signal arena_generated(arena_data: Dictionary)
signal cover_destroyed(pos: Vector3, type: String)
signal combat_intensity_changed(intensity: float)
