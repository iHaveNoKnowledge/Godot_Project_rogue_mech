# Architecture Authority Map

This document establishes the authoritative subsystem owners, contracts, public entry points, and prohibited bypasses across the Valkren codebase.

---

## 1. Strategic Campaign Subsystems

| Subsystem | Authoritative Class / Storage | Script Path | Responsibilities & Invariants | Prohibited Bypasses |
|---|---|---|---|---|
| **Strategic Player Position** | `GlobalData.current_campaign_player_node_id` | `autoload/global_data.gd` | Holds current active strategic node ID. | UI must NEVER set this variable directly to bypass route movement validation. |
| **Strategic Topology & Routes** | `CampaignNodeRegistry` | `scripts/systems/campaign_node_registry.gd` | Owns all strategic Nodes (`id`, `name`, `node_type`, `map_position`, `tile`, `sector`) and Routes (`id`, `a`, `b`). | Must not perform movement, turn advancement, or combat triggers. |
| **Player Movement** | `CampaignPlayerMovement` | `scripts/systems/campaign_player_movement.gd` | Validates and executes 1-hop strategic movement along registered routes (`can_move_to_node`, `move_to_node`). Synchronizes physical board tile when available. | Must not perform tactical pathfinding or deduct tactical fuel/MP. |
| **Node Inspection** | `CampaignNodeInspection` | `scripts/systems/campaign_node_inspection.gd` | Read-only situation query (`inspect_node`). Returns forces, bases, territory control, available actions. | Zero state mutation. Must not trigger combat or modify campaign objects. |
| **Action Intent Dispatch** | `CampaignPlayerDispatch` | `scripts/systems/campaign_player_dispatch.gd` | Validates action capability and routes intent (`create_intent`, `dispatch_intent`). Supports `investigate`, `resupply`, `trade`, `capture`, `attack`. | Must not act as domain executor directly; returns deterministic failure if executor not present. |
| **Campaign Turn** | `CampaignTurnExecutive` | `scripts/systems/campaign_turn_executive.gd` | Authoritative single entry point for world turn advancement (`advance_campaign_turn`). Re-entry guarded. | Must not be confused with Board Day, Player Step, MP Enemy Turn, or Tactical Combat Turn. |
| **Campaign Base** | `CampaignBase` | `scripts/systems/campaign_base.gd` | Owns installation records and lifecycle states (`RESEARCH_BASE`, `OUTPOST`). | Base != Node; Base != Territory; Base != Force. |
| **Campaign Territory** | `CampaignTerritory` | `scripts/systems/campaign_territory.gd` | Owns area control state (`UNCONTROLLED`, `CONTROLLED`, `CONTESTED`) and node membership references. | Does not duplicate faction data or node data. |
| **Campaign Battle** | `CampaignBattle` | `scripts/systems/campaign_battle.gd` | Strategic battle lifecycle tracking (`PLANNED`, `ACTIVE`, `RESOLVED`, `CANCELLED`) and participant force IDs. | Battle != Force; Battle != Tactical Combat Session. |
| **Save / Load Persistence** | `SaveGameIO` | `scripts/systems/save_game_io.gd` | Serializes/deserializes run state with atomic write-and-rename and preflight schema verification (`save_run`, `load_run`). | Never write directly to save file path without schema validation. |

---

## 2. Tactical & Execution Subsystems

| Subsystem | Authoritative Class / Singleton | Script Path | Responsibilities & Invariants |
|---|---|---|---|
| **Scene & Mode Transitions** | `GameManager` | `autoload/game_manager.gd` | High-level state transitions (`enter_node_map`, `return_to_board`, `return_to_node_map`, `enter_combat`, `enter_safehouse`, `enter_hangar`). |
| **Tactical Board & Grid** | `BoardManager`, `BoardTile` | `scripts/board/board_manager.gd`, `scripts/board/board_tile.gd` | Physical 35x35 cell grid, micro-encounters, tactical hazard state, and tile rendering. Decoupled from strategic node graph. |
| **Mecha Controller & Slots** | `MechaController`, `PartSlot` | `scripts/mecha/mecha_controller.gd`, `scripts/mecha/part_slot.gd` | 3D locomotion, physics, weapon firing, modular damage distribution, and part detachment. |
| **Pilot Lifecycle & Eject** | `PilotData`, `MechaEject`, `BackupMechSpawner` | `scripts/pilot/pilot_data.gd`, `scripts/mecha/mecha_eject.gd`, `scripts/systems/backup_mech_spawner.gd` | Pilot dismount, emergency eject, dynamic boarding of secondary/unoccupied mechas. |
