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
| **Campaign Resources** | `CampaignSupply` | `scripts/systems/campaign_supply.gd` | Owns the campaign resource ledger (`SUPPLY` capped 0..100, `MATERIALS`, `SALVAGE`) with atomic spend and per-turn income. Consumed by `RepairSystem` (professional rebuild), `CampaignBase` upkeep via the turn phase, and `FleetSystem` (reinforcement/fielding). Stored under `campaign_supply`, applied only through the turn phase. | Must not own `DATA` (that is `GlobalData.currency.data_cores`), must not read/write `CurrencyManager`, `FactionEconomySystem`, `CampaignForce`, or research state, and must not advance turns or gate actions itself. |
| **Player Strategic Force** | `CampaignPlayerForce` | `scripts/systems/campaign_player_force.gd` | Owns the player's own strategic detachments (`{id, node_id, base_id, unit_count, strength, state}`, ACTIVE/DISABLED) plus casualty application. Read by `CampaignBaseDefense` for the auto-battle resolution. Stored under `campaign_player_forces`. | Must not create or mutate `CampaignForce` (NPC authority), must not capture bases or territory, and must not advance turns, spend supply, or resolve battles itself. |
| **Player Detachment Orders** | `CampaignPlayerForceAction` | `scripts/systems/campaign_player_force_action.gd` | Validates and executes the three player orders on a detachment: raise (credits via `CurrencyManager`, rolled back on payment failure), one-hop route move, and station/unstation at a player-owned base. Stateless. | Must not create state, advance turns, resolve battles, mutate base/territory ownership, or move a detachment more than one registered route hop. |
| **Player Detachment Assault** | `CampaignPlayerForceAssault` | `scripts/systems/campaign_player_force_assault.gd` | Resolves a player detachment attacking one HOSTILE `CampaignForce` at the same node: validation (`can_attack`, `get_hostile_targets_at`) then a deterministic attrition auto-battle reusing `CampaignBaseDefense` constants. Stateless. | Must not fabricate `CampaignBattle` records or `CampaignForce` records for the player, must not target non-HOSTILE factions, must not capture bases/territory, and must not enter tactical combat. |
| **Auto-Battle Formula** | `CampaignAutoBattle` | `scripts/systems/campaign_auto_battle.gd` | Single source of the strategic attrition resolver (`simulate`, `unit_loss`) plus the tuned constants (`ATTRITION_RATIO`, `MAX_ROUNDS`). Pure: no state, no signals, no mutation. | Must stay stateless and deterministic, and must not apply casualties itself — callers own mutation through `CampaignPlayerForce`/`CampaignForce`. |
| **Save / Load Persistence** | `SaveGameIO` | `scripts/systems/save_game_io.gd` | Serializes/deserializes run state with atomic write-and-rename and preflight schema verification (`save_run`, `load_run`). | Never write directly to save file path without schema validation. |

---

## 2. Tactical & Execution Subsystems

| Subsystem | Authoritative Class / Singleton | Script Path | Responsibilities & Invariants |
|---|---|---|---|
| **Scene & Mode Transitions** | `GameManager` | `autoload/game_manager.gd` | High-level state transitions (`enter_node_map`, `return_to_board`, `return_to_node_map`, `enter_combat`, `enter_safehouse`, `enter_hangar`). |
| **Tactical Board & Grid** | `BoardManager`, `BoardTile` | `scripts/board/board_manager.gd`, `scripts/board/board_tile.gd` | Physical 35x35 cell grid, micro-encounters, tactical hazard state, and tile rendering. Decoupled from strategic node graph. |
| **Mecha Controller & Slots** | `MechaController`, `PartSlot` | `scripts/mecha/mecha_controller.gd`, `scripts/mecha/part_slot.gd` | 3D locomotion, physics, weapon firing, modular damage distribution, and part detachment. |
| **Pilot Lifecycle & Eject** | `PilotData`, `MechaEject`, `BackupMechSpawner` | `scripts/pilot/pilot_data.gd`, `scripts/mecha/mecha_eject.gd`, `scripts/systems/backup_mech_spawner.gd` | Pilot dismount, emergency eject, dynamic boarding of secondary/unoccupied mechas. |
