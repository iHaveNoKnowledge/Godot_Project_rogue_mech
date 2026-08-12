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
signal part_destroyed(slot_name: String)
signal mecha_destroyed()

# --- Weight / Mobility ---
signal weight_changed(total_weight: float)
signal speed_modified(new_speed: float)

# --- Camera ---
signal camera_mode_changed(new_mode: String)
signal lock_on_target_acquired(target: Node3D)
signal lock_on_target_lost()

# --- Combat ---
signal weapon_fired(target_position: Vector3)

# --- Eject / Pilot ---
signal eject_initiated()
signal pilot_spawned(pilot_node: Node3D)
signal pilot_boarded_backup(backup_mech: Node3D)
signal backup_mech_destroyed()

# --- Board ---
signal tile_entered(tile_pos: Vector2i, tile_data: Node)
signal event_triggered(event_data: Dictionary)
signal heat_changed(new_heat: int)
signal wanted_changed(new_wanted: int)
signal combat_ended(victory: bool)
## Fired when the player completes a retreat: held position inside an escape
## zone long enough to abandon the battle without destroying every enemy.
signal combat_escaped()
signal enemy_tech_escalated(new_tier: int)

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
