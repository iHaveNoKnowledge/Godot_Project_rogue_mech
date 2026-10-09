# Architecture Authority Map

## Strategic Subsystem Authorities
- `GlobalData.current_campaign_player_node_id`: Authoritative strategic player position. UI must not bypass movement validation.
- `CampaignNodeRegistry` (`scripts/systems/campaign_node_registry.gd`): Owns strategic Nodes and Routes.
- `CampaignPlayerMovement` (`scripts/systems/campaign_player_movement.gd`): Single authority for 1-hop route movement.
- `CampaignNodeInspection` (`scripts/systems/campaign_node_inspection.gd`): Read-only situation query. Zero state mutation.
- `CampaignPlayerDispatch` (`scripts/systems/campaign_player_dispatch.gd`): Action intent routing boundary (`investigate`, `resupply`, `trade`, `capture`, `attack`).
- `CampaignTurnExecutive` (`scripts/systems/campaign_turn_executive.gd`): Single turn progression authority.
- `CampaignBase` vs `CampaignTerritory`: Distinct responsibilities. `CampaignBase` owns installations (`RESEARCH_BASE`, `OUTPOST`); `CampaignTerritory` owns area control state.
- `CampaignBattle`: Strategic battle identity & participant force IDs.
- `SaveGameIO` (`scripts/systems/save_game_io.gd`): Persistence authority with schema validation and atomic rename.

## Tactical Subsystems
- `BoardManager` / `BoardTile`: 35x35 cell grid, micro-encounters, tactical hazards.
- `GameManager`: State transitions (`enter_node_map`, `return_to_board`, `return_to_node_map`, `enter_combat`).
- `PilotData` / `MechaEject` / `BackupMechSpawner`: Pilot survival and mech ejection/boarding lifecycle.

Canonical doc: `docs/ai/ARCHITECTURE_AUTHORITY_MAP.md`
