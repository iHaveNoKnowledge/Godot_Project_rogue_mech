extends Node

# --- Damage Pipeline ---
signal damage_received(slot_name: String, raw_damage: float, damage_type: String)
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
signal tile_entered(tile_pos: Vector2i, tile_data: Resource)
signal event_triggered(event_data: Resource)
signal heat_changed(new_heat: int)
signal wanted_changed(new_wanted: int)
signal combat_ended(victory: bool)

# --- Game State ---
signal game_state_changed(old_state: String, new_state: String)
signal run_ended(victory: bool)

# --- Safehouse ---
signal heal_requested(amount: float)
signal repair_requested()

# --- Combat Rewards ---
signal combat_rewards_shown(rewards: Dictionary)
