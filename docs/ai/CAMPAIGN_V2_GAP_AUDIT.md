# Valkren Campaign V2 — Architecture Gap Audit

> **Audit identifier:** `VAL-CAMPAIGN-V2-GAP-AUDIT-01`
> **Baseline commit:** `f98a52b9` (`main`, after C6-A supply ledger and C6-B supply consumption wiring)
> **Master spec:** `docs/ai/CAMPAIGN_DESIGN_V2_MASTER_SPEC.md` (§0–§47)
> **Scope:** Read-only audit of the existing codebase against every V2 section. No production behaviour was changed by this audit.
> **Status legend:**
> - `EXISTING` — implemented and carry a verified test or documented contract; **do not rebuild**.
> - `PARTIAL` — the authority exists but the spec's behaviour is only partly covered.
> - `MISSING` — no owner in the codebase.
> - `DRIFT` — canonical documentation no longer matches the code.
> **Action legend:** `REUSE` / `EXTEND` / `NEW` / `VERIFY` / `NO ACTION`.

---

## 1. Method & Evidence Base

1. Read the canonical docs: `PROJECT_BIBLE.md`, `ARCHITECTURE_AUTHORITY_MAP.md`, `PHASE_STATUS.md`, `OPEN_ISSUES.md`, `WORK_HANDOFF.md`, `CAMPAIGN_DESIGN_V2_MASTER_SPEC.md`, `C4_HEAT_DETECTION_THREAT_DESIGN.md`, `C5_CAMPAIGN_TERRITORY_TURFWAR_PLAN.md`.
2. Enumerated every `class_name` in `scripts/` + `autoload/` (1 class registry pass) to find real owners rather than assumed ones.
3. Grepped for spec keywords that would prove or disprove ownership: `supply`, `upkeep`, `cargo`, `defect`, `betray`, `prisoner`, `decoy`, `drone`, `field_assembly`, `commander`, `intervention`, `in_combat`, `data_cores`, `world_technology_diffusion`.
4. Booted the game headlessly (`res://scenes/main_menu/main_menu.tscn`, exit 0) and ran the campaign suites (`campaign_canonical_scenario_verify` 96/96, `campaign_playability_acceptance_audit_verify` 46/46, `campaign_auto_resolve_verify`, `campaign_battle_resolution_lifecycle_verify`, `campaign_supply_verify` 93/93, `run_tests.sh` exit 0) to separate "documented but dead" from "actually running".

---

## 2. Section-by-Section Map (§0–§47)

| § | Spec content | Status | Evidence in code | Action |
|---|---|---|---|---|
| 0 | Design north star (living war, pilot-centric) | EXISTING (doc) | `CAMPAIGN_DESIGN_V2_MASTER_SPEC.md` §0 | REUSE |
| 1 | Run identity: pilot → mecha → frame → parts → weapons; mecha loss ≠ game over | EXISTING | `MechaEject`, `BackupMechSpawner` (`scripts/systems/backup_mech_spawner.gd`), `FleetSystem`, `ArmorSystem`, `WeaponManager`; `GlobalData.reset_run_data()` | REUSE |
| 2 | Campaign loop PLAN→MOVE→OBSERVE→DECIDE→ACT→CONSEQUENCE→WORLD ADVANCES | PARTIAL | `CampaignTurnExecutive.advance_campaign_turn`, `CampaignPlayerMovement`, `CampaignNodeInspection`, `CampaignPlayerDispatch`, `CampaignNodeMap` | EXTEND (CONSEQUENCE / world memory, see §38) |
| 3 | Campaign turn advances the world | EXISTING | `scripts/systems/campaign_turn_executive.gd` `PHASE_ORDER` (12 phases incl. `campaign_supply`) | REUSE |
| 4 | Node = place/opportunity (patrol, data center, hangar, depot, research facility, base, rescue, convoy, battlefield, prison transport, boss) | PARTIAL | `CampaignNodeRegistry.STRATEGIC_TILE_TYPES` — 12 types: `START, EXIT, SAFEHOUSE, CITY, FUEL_DEPOT, RESEARCH_LAB, ENEMY_BASE, COMMS_RELAY, PROTOTYPE_VAULT, DATA_NODE, SALVAGE_CACHE, SUPPLY_DEPOT` | EXTEND (no `RESCUE_SITE`, `PRISON_TRANSPORT`, `PRISON_FACILITY`, `BATTLEFIELD`, `BLACK_MARKET`, `BOSS`) |
| 5 | Route = movement/frontier/contact space with activity states (safe/patrol/ambush/blocked…) | MISSING | `campaign_node_registry.gd`: route model is exactly `{id, a, b}`, undirected, "no cost fields, no movement semantics" (quoted in `campaign_force_movement.gd` header) | NEW (`CampaignRouteState`) |
| 6 | Multi-faction: PLAYER, AUTHORITY, MILITIA, SCAVENGERS, MERCENARIES, SPECIAL + 4 relation states | PARTIAL / DRIFT | `faction_system.gd:306` `enum Relation {HOSTILE, NEUTRAL, COOPERATIVE, ALLIED}`; faction defs are `federation`, `zeon`, `outland` only. `SCAVENGER` exists only as a `CampaignForce` type, not a faction | EXTEND or map spec names onto existing IDs |
| 7 | Multi-sided war (3+ forces, player may abstain) | PARTIAL | `CampaignBattle` model `{id, state, node_id, participants: [force ids], session_ref}` — N participants supported; tactical layer still resolves two sides | EXTEND combat participants |
| 8 | Faction movement (patrols, convoys, base attacks, node capture, withdrawal, inter-faction war) | PARTIAL | `campaign_force_movement.gd` (one-hop validated move action). Header states cross-domain orchestration is **not modelled**; nothing decides moves autonomously | NEW (strategic AI/order producer) |
| 9 | Player faction starting state A (lone pilot) vs B (small resistance) | CONFLICT (undecided) | `run_start_system.gd:137` seeds ally units from scenario data; `frontier_skirmish.tres` gives a starting force via scenario specs | VERIFY with design decision |
| 10 | Supply as campaign resource (SUPPLY/MATERIALS/DATA/SALVAGE) | EXISTING | `campaign_supply.gd` (`SUPPLY` 42/100 capped, `MATERIALS`, `SALVAGE`; DATA intentionally delegated to `GlobalData.currency.data_cores`) | REUSE |
| 11 | Supply over time: income, crisis instead of game over | PARTIAL | `CampaignSupply.process_turn_income()` (+4/turn), `is_supply_crisis()`, `PHASE_CAMPAIGN_SUPPLY` upkeep shortfall receipt; board upkeep never disables a base (by design) | EXTEND (crisis escalation) |
| 12 | Base as capability hub (logistics, arsenal, factory, intelligence, research, force) | MISSING (capabilities) | `campaign_base.gd`: model is `{id, node_id, base_type, state, controller, territory_id}` only | NEW (`CampaignBaseCapability`) |
| 13 | Base upgrades unlock capability, not +5% damage | MISSING | same as §12; no upgrade level field anywhere | NEW |
| 14 | Base can be attacked, go critical, captured, recovered; player can intervene | EXISTING | `campaign_base_defense.gd` (`start_base_attack`, `is_base_under_attack`, `can_intervene`, `intervene`, `process_assault_turn`, `recover_pending_defense_from_records`) | REUSE |
| 15 | Auto battle spans multiple turns with attrition | PARTIAL → implemented for base defence (C8-A) | `CampaignBaseDefense._try_player_force_resolution` (5 rounds × 20% strength attrition) applies when a `CampaignPlayerForce` detachment defends; no detachment keeps the legacy Option D outcome. Field battles outside a base still lack an attrition policy | EXTEND (field battles) |
| 16 | Intervention → playable combat, withdrawal returns to world battle | EXISTING | `campaign_base_defense.intervene()` + `INTERVENTION_SESSION_PREFIX`; `campaign_attack_bridge.gd` for player attacks | REUSE |
| 17 | Heat = awareness/pursuit pressure | EXISTING | `campaign_strategic_heat.gd` (node-local 0..10, decay, serialize) | REUSE |
| 18 | Threat = willingness to attack our assets | EXISTING | `campaign_strategic_threat.gd` (pure derived query, never serialized) | REUSE |
| 19 | Detection → suspicion → response → engagement | PARTIAL | `campaign_strategic_detection.gd` (UNKNOWN/SUSPECTED/LOCATED, decay, anti-omniscience). No producer acts on `LOCATED` (no response/pursuit) | EXTEND (response step) |
| 20 | Stolen mecha / IFF / disguise ladder | MISSING | No IFF or disguise concept in `scripts/` (grep `iff`/`disguise` returns unrelated matches) | NEW |
| 21 | Research changes how you fight (improvement/specialized/advanced/unique) | PARTIAL | `technology_system.gd` (`DiscoveryState UNKNOWN..USABLE`), `research_progression_system.gd`, `FleetSystem` blueprint research (`data_cores`) | EXTEND (research tied to campaign facilities) |
| 22 | Unique technology (field assembly, salvage engineering, directed energy, drones, distributed control) | MISSING / PARTIAL | No `field_assembly` references; no drone gameplay system (`drone` only in audio/board/theme strings); `SpecialWeaponSystem` covers exotic weapon execution only | NEW (one tech at a time, spec §45 C13) |
| 23 | Technology discovery via facilities / salvage / faction sharing | PARTIAL | `TechnologySystem` discovery states + `research_progression_system.gd` dispatch; no campaign facility or faction-sharing source | EXTEND |
| 24 | Technology can be lost (theft/sabotage/prisoner) | MISSING | No code path models research loss (theft/sabotage/captured scientist); `research_unlocked` is a plain saved array listed in `SaveGameIO._ARRAY_FIELDS` | NEW |
| 25 | Technology proliferation to the world | PARTIAL | `TechnologySystem.serialize_world_diffusion_state()`, saved as `world_technology_diffusion` (`save_game_io.gd:28,242,535`) | EXTEND (no theft event drives it) |
| 26 | Battlefield persists after combat; salvage later | PARTIAL | `SalvageSystem` tags weapons → `LoadoutSystem`; `tile_wreckages` saved by `SaveGameIO`; no Battlefield **node** | EXTEND |
| 27 | Convoy carries varied cargo (supply, mecha, prisoners, scientists, prototypes…) | MISSING | `convoy_escort.gd` is a board encounter; `CampaignForce` type `CONVOY` has no cargo model; grep `cargo` in `scripts/systems/campaign_*.gd` = 0 hits | NEW |
| 28 | Personnel states (recruit/injure/capture/rescue/defect/die/leave/return) | PARTIAL | `PilotSystem`/`PilotState`/`PilotGenerator`, `HangarManager` roster, `RecruitSystem`, `FleetSystem` `wounded` flag | EXTEND (capture/defect/rescue) |
| 29 | Defection levels (individual/commander/unit/faction/split) | MISSING | grep `defect`/`betray` in `scripts/` = 0 gameplay hits | NEW (spec §45 C12) |
| 30 | Defection needs causes + warnings, not RNG | MISSING | No trust/loyalty/payment/fear model | NEW |
| 31 | Capture / prisoner / prison transport / exchange | MISSING | `CampaignCaptureAction` captures **bases and territory** (`CampaignBase.set_controller`, `CampaignTerritory.set_controlled`), never personnel | NEW |
| 32 | Faction requests (intercept, defend, rescue, deliver, steal) | MISSING | `CampaignPlayerDispatch` supports `investigate`, `resupply`, `trade`, `capture`, `attack`, `recover`, `defend` — all player-initiated | NEW |
| 33 | Reputation changes events/trust/prices/recruitment/tech sharing | PARTIAL | `FactionSystem.get_relation/set_relation/serialize_relations/reset_relations` + `faction_relations` save key; no reputation magnitude or downstream effects | EXTEND |
| 34 | Intel is not always true (stale/wrong/decoy) | MISSING | Detection stores source/age but no falsity/decoy flag; `decoy` is only a board tile type | NEW |
| 35 | Scout / recon before committing | PARTIAL | `CampaignInvestigateAction` (read-only investigate) + `CampaignNodeInspection`; no recon-on-route or stealth objective | EXTEND |
| 36 | Black market node | MISSING (campaign) | `scripts/war/war_merchant_system.gd` is the **separate war mode**; no campaign trade node type (only `city`/`trade` action) | NEW (or scope `trade`) |
| 37 | Companion design reduced to preset loadouts; companions can be lost/captured/defect | PARTIAL | `FleetSystem` ally templates + `recruit_system.gd`; wounded/destroyed handled; no capture/defect | EXTEND |
| 38 | Player action → world memory | MISSING | No campaign event/history log; `PHASE_*` receipts are transient (`get_last_receipt`) | NEW (`CampaignWorldMemory`) |
| 39–40 | Event system driven by world state + relations + history + randomness | PARTIAL / MISSING | `EventBus` signals exist; `DynamicEncounterDirector` is board-scale; no campaign event engine reading world state | NEW (spec §45 C9) |
| 41 | Resource model, no resource sprawl | EXISTING | `CampaignSupply.RESOURCE_KEYS` = 3 owned keys; DATA stays `data_cores`; `CurrencyManager` = credits/scrap | REUSE + EXTEND sinks |
| 42 | Existing architecture must not be rebuilt | EXISTING | see §3 below | REUSE |
| 43 | Pre-implementation audit A–H | THIS DOC | see §2–§4 | COMPLETE |
| 44 | Feature status ledger | REPLACED BY THIS TABLE | — | REUSE this document |
| 45 | Implementation order C1–C13 | see §4 | `PHASE_STATUS.md` ledger | CONTINUE |
| 46 | Agent hard constraints (audit first, no speculative code) | HONOURED | this audit changes no production code | — |
| 47 | The 7 heart sentences | see §6 | — | CHECK |

---

## 3. Consolidated EXISTING → MODIFY → NEW → REMOVE

### 3.1 EXISTING — do not rebuild (authority + proof)

| Authority | Path | Proof |
|---|---|---|
| `CampaignNodeRegistry` | `scripts/systems/campaign_node_registry.gd` | node/route topology, 12 strategic tile types, tested by `campaign_node_route_verify`, `campaign_strategic_topology_decoupling_verify` |
| `CampaignPlayerMovement` | `scripts/systems/campaign_player_movement.gd` | 1-hop route movement, `campaign_player_route_movement_contract_verify` |
| `CampaignPlayerDispatch` + actions | `campaign_player_dispatch.gd`, `campaign_{attack,capture,resupply,trade,investigate,recover,defend}_action.gd` | `campaign_node_action_capability_contract_verify`, `campaign_action_exposure_verify` (81/81) |
| `CampaignTurnExecutive` | `campaign_turn_executive.gd` | 12 phases, re-entry guard, `campaign_turn_executive_verify`, `campaign_turn_c4_integration_verify` (45/45) |
| `CampaignStrategicHeat/Detection/Threat` | `campaign_strategic_{heat,detection,threat}.gd` | C4-B1..B6 ledger in `PHASE_STATUS.md`; suites 53/115/101 checks |
| `CampaignBase` | `campaign_base.gd` | `RESEARCH_BASE`/`OUTPOST`, ACTIVE→DISABLED→DESTROYED, occupancy; `campaign_base_defense_verify` |
| `CampaignBaseDefense` | `campaign_base_defense.gd` | attack/intervene/assault/auto-resolve lifecycle |
| `CampaignForce` + movement | `campaign_force.gd`, `campaign_force_movement.gd` | types `PATROL/CONVOY/SCAVENGER/RIVAL`, one-hop move; 10+ boundary suites |
| `CampaignTerritory` | `campaign_territory.gd` | `UNCONTROLLED/CONTROLLED/CONTESTED`; `campaign_territory_geometry_verify` |
| `CampaignBattle` | `campaign_battle.gd` | `PLANNED/ACTIVE/RESOLVED/CANCELLED`, N participants; `campaign_battle_resolution_lifecycle_verify` |
| `CampaignSupply` | `campaign_supply.gd` | C6-A/C6-B; `campaign_supply_verify` 93/93 |
| `FactionSystem` | `faction_system.gd` | 3 factions, 4 relation states, `faction_relations` save key, C3 suite 49/49 |
| `SaveGameIO` | `save_game_io.gd` | schema 1, `_DICT_FIELDS` incl. `forces`, `bases`, `territories`, `campaign_battles`, `campaign_supply`, `campaign_assaults`; `campaign_strategic_persistence_verify` 62/62 |
| Scenario layer | `campaign_scenario_*`, `run_start_system.gd`, `scenario_schema_validator.gd` | `campaign_canonical_scenario_verify` 96/96 |
| Tactical layer | `MechaController`, `WeaponManager`, `HangarManager`, `BoardManager`, `SalvageSystem` | existing suites; `PROJECT_BIBLE.md` §5 |

### 3.2 MODIFY — extend an existing owner

| Target | Change | Why (spec) |
|---|---|---|
| `CampaignNodeRegistry.STRATEGIC_TILE_TYPES` | add `RESCUE_SITE`, `PRISON_TRANSPORT`, `PRISON_FACILITY`, `BATTLEFIELD`, `BLACK_MARKET`, `BOSS` | §4, §26, §31, §36 |
| `CampaignStrategicDetection` | add a response/pursuit producer that acts on `LOCATED` | §19 |
| `CampaignBaseDefense` | multi-turn attrition policy (replace `DEFERRED awaiting_policy`) | §15 |
| `CampaignBase` | capability/upgrade records (arsenal/factory/logistics/intel/research/force) | §12, §13 |
| `FactionSystem` | reputation magnitude + downstream effects on top of existing relations | §6, §33 |
| `TechnologySystem` | discovery sources from facilities/salvage/faction sharing; loss paths | §23, §24 |
| `CampaignSupply` | MATERIALS/SALVAGE sinks; crisis escalation policy | §41, §11 |
| `SalvageSystem` / `tile_wreckages` | promote wreck sites to persistent Battlefield nodes | §26 |
| `FleetSystem` | companion capture/defection hooks | §37 |
| `CampaignPlayerDispatch` | faction-request intents alongside player-initiated actions | §32 |

### 3.3 NEW — no owner exists today

| New authority | Deliverable | Spec |
|---|---|---|
| `CampaignRouteState` | per-route activity/safety/blocked state | §5 |
| Strategic force AI/order producer | autonomous faction movement, convoy dispatch, base assault orders, inter-faction war | §8 |
| `CampaignBaseCapability` | capability unlocks replacing flat bonuses | §12, §13 |
| `CampaignConvoyCargo` | manifest model on convoy forces | §27 |
| `CampaignIFF` | stolen-mecha disguise/suspicion ladder | §20 |
| `CampaignPrisoner` | personnel custody + prison nodes + exchange | §28, §31 |
| `CampaignDefection` | trust/loyalty drivers, warning ladder, faction split | §29, §30 |
| `CampaignWorldMemory` | action → state change log consumed by events | §38 |
| `CampaignEventSystem` | world-state + relations + history driven events | §39, §40 |
| `CampaignIntelReliability` | stale/false/decoy intel provenance | §34 |
| `CampaignBlackMarket` | campaign-node trade with risk | §36 |
| Advanced tech slice | `FieldAssembly`, drone platforms, distributed control | §22 (C13) |

### 3.4 REMOVE / RETIRE

Nothing in production is safe to delete on current evidence. The audit found **no dead authority** that a V2 system supersedes. Items to verify rather than remove:

| Candidate | Finding | Action |
|---|---|---|
| `ARCHITECTURE_AUTHORITY_MAP.md` §2 row "`PilotData` / `scripts/pilot/pilot_data.gd`" | `scripts/pilot/` contains only `pilot_controller.gd` and `pilot_interaction.gd`; the registered classes are `PilotSystem`, `PilotState`, `PilotGenerator`, `PilotSkillSystem` | DRIFT — fix the map, do not delete code |
| `CampaignForce` type `PATROL` vs `BoardState.board_patrols` / `PatrolSystem` | Two patrol truths by documented design (`campaign_force.gd` header: "PATROL REMAINS SEPARATE in 5A") | VERIFY before any bridge; do not merge speculatively |
| `FactionSystem` "Tier 1-3 by real time (board_day + time_hour)" | Time-based progression predates `CampaignTurnExecutive`; may conflict with campaign-turn semantics | VERIFY (possible obsolete assumption) |
| `scripts/war/*` (WarManager, WarMerchantSystem, WarLogisticSystem…) | Parallel war-mode implementation, not campaign | NO ACTION — must not be duplicated into campaign |
| `data_cores` vs spec `DATA` | Already reconciled: DATA stays `GlobalData.currency.data_cores` | NO ACTION |

---

## 4. Phase Ledger vs Spec §45

| Spec phase | State | Evidence / blocker |
|---|---|---|
| C1 State foundation | CLOSED | `PHASE_STATUS.md` C1 (`bd2bafe`) |
| C2 Node/Route/Turn | CLOSED | C2/C2.6/C2.7/C2.8 |
| C3 Faction/Relationship | CLOSED | C3 49/49 |
| C4 Detection/Heat/Threat | CLOSED | C4-B1..B6 |
| C5 Base/Ownership/Force | PARTIAL | base/force/territory/battle/assault exist; **capability upgrades (§13) and player-side force/manpower (C5 plan §3) do not** |
| C6 Supply/Logistics | PARTIAL → mostly done | C6-A ledger + C6-B consumption; **no logistics capacity, no crisis escalation, MATERIALS/SALVAGE have no sinks** |
| C7 Dynamic world movement | NOT STARTED | `CampaignForceMovement` is a validated action with zero autonomous producers |
| C8 Auto battle / intervention | PARTIAL | intervention EXISTING; auto-battle lacks attrition policy |
| C9 Event system | NOT STARTED | depends on C7 + world memory |
| C10 Research/Technology | PARTIAL | tactical tech tree + discovery + diffusion storage exist; no campaign facility/theft loop |
| C11 Salvage/Prototype | PARTIAL | tactical salvage + wreckage persistence; no Battlefield node |
| C12 Defection/Betrayal | NOT STARTED | zero code |
| C13 Advanced systems | NOT STARTED | no field assembly, no drones |

**Blocking order (evidence-based):** C7 needs a decision on who issues force orders; C9 needs `CampaignWorldMemory` first; C12 needs personnel states (§28) and reputation effects (§33) first. Therefore the next three phases should be:

1. **C7-A Strategic order queue** — a single authority that records intents (move/assault/withdraw) and lets `CampaignTurnExecutive` execute them one hop per turn; still no new clock.
2. **C11-A Battlefield persistence** — promote a resolved battle's node to a `BATTLEFIELD` node with a salvage manifest (reuses `SalvageSystem` + `tile_wreckages`).
3. **C6-C Logistics capacity** — MATERIALS/SALVAGE sinks (salvage → supply conversion) so C7's forces have something to consume.

---

## 5. Documentation Drift Found

1. `ARCHITECTURE_AUTHORITY_MAP.md` §2 cites `PilotData` at `scripts/pilot/pilot_data.gd` — file absent; real classes are `PilotSystem`/`PilotState`/`PilotGenerator`.
2. `OPEN_ISSUES.md` Issue 3 ("`PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP` undefined") is stale — the constants exist at `autoload/global_data.gd:174-175`; the repair suite now passes (exit 0).
3. `OPEN_ISSUES.md` Issue 4 lists campaign action-contract failures; the suites were re-run in this audit and now exit 0 (`campaign_attack_action_verify`, `campaign_playability_acceptance_audit_verify` 46/46).
4. `C4_HEAT_DETECTION_THREAT_DESIGN.md` §6 documents 9 turn phases; the code has 12 (`strategic_assault`, `campaign_supply` added since).
5. `CAMPAIGN_DESIGN_V2_MASTER_SPEC.md` §31 contains a stray typo ("Spieler") — cosmetic only.

---

## 6. Heart-Sentence Check (§47)

| # | Sentence | Status | Evidence |
|---|---|---|---|
| 1 | Pilot คือ Run | EXISTING | `GlobalData.reset_run_data()` + `HangarManager.ensure_roster()`; pilot ejection/boarding in `MechaEject`/`BackupMechSpawner` |
| 2 | Mecha คือสิ่งที่ Pilot ใช้ | EXISTING | `FleetSystem`, `HangarManager`, `MechaController`; mecha loss handled without run end |
| 3 | โลกเดินต่อแม้ผู้เล่นไม่อยู่ | PARTIAL | turn phases run economy/spy/enemy-base/rival/era/scavenger autonomously; **faction forces do not move on their own** (C7) |
| 4 | Node คือสถานที่/โอกาส ไม่ใช่ช่องที่ต้องยึด | EXISTING | `CampaignNodeRegistry` node types vs `CampaignTerritory` control are separate authorities; capture action is per-node, not per-board |
| 5 | Faction มีเป้าหมายและเปลี่ยนความสัมพันธ์ได้ | PARTIAL | relations EXISTING (`set_relation`), goals/autonomy MISSING |
| 6 | Technology เปลี่ยนวิธีทำสงคราม | PARTIAL | `TechnologySystem` discovery + `FleetSystem` blueprints; no gameplay-changing tech slice yet |
| 7 | การกระทำของผู้เล่นทิ้งร่องรอยในโลก | PARTIAL | heat/detection/assault/territory persist; **no memory/history consumed by events** (§38) |
