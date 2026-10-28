# Phase C5 Architecture Design & Implementation Plan: Territory Ownership, Turf War, Grunt Economy & Node Missions

> **Plan Identifier:** `VAL-CAMPAIGN-TERRITORY-TURFWAR-PLAN-UPDATE-02`  
> **Predecessor Design Audit:** `VAL-CAMPAIGN-TERRITORY-TURFWAR-DESIGN-01`  
> **Canonical Target Engine:** `Godot 4.6.2.stable`  
> **Master Design Reference:** `docs/ai/CAMPAIGN_DESIGN_V2_MASTER_SPEC.md` (§45 Phase C5)  
> **Status:** `PROPOSED ARCHITECTURE PLAN — AWAITING EXPLICIT USER AUTHORIZATION`  
> **Code Modification / Implementation:** `FORBIDDEN IN THIS TASK`  
> **Git Commit / Push / Stage:** `FORBIDDEN IN THIS TASK`

---

## 1. Executive Summary & Architectural Scope

This document establishes the authoritative, dependency-ordered implementation plan for the **Valkren Campaign Territory, Turf War, Grunt Manpower Economy, and Strategic Node Mission System (Phase C5)**.

The design adheres strictly to the project rule **Reuse, Then Extend**:
- Zero duplicate clocks or parallel day counters (all progression uses `CampaignTurnExecutive`).
- Zero duplicate faction registries or relationship systems (all diplomacy uses `FactionSystem`).
- Zero competing territory ownership managers (all area control uses `CampaignTerritory`).
- Zero duplicate spendable-currency stores (all credit/scrap transactions use `CurrencyManager` via `GlobalData.currency`).
- Zero duplicate player mecha/pilot inventories (all mecha/pilots remain with `HangarManager`, `FleetSystem`, and `PilotData`).
- Zero misuse of `CampaignForce` for player units (`CampaignForce` remains strictly an NPC operational entity).
- Zero parallel save/load pipelines (all persistence extends `SaveGameIO` schema version 1).

---

## 2. Terminology & Core Concept Disambiguation

```
+-----------------------------------------------------------------------------------+
|                                STRATEGIC LEVEL                                    |
|                                                                                   |
|  +-------------------------------------+   +------------------------------------+ |
|  |           TERRITORY A               |   |            TERRITORY B             | |
|  |  (District / Geographic Area)       |   |   (District / Geographic Area)     | |
|  |  - Control: CONTROLLED (Player)     |   |   - Control: CONTROLLED (Enemy)    | |
|  |  - Yields: Passive Daily Income     |   |   - Target of Turf War             | |
|  |                                     |   |                                    | |
|  |    [Node 1] <==== Route ====> [Node 2] <====== Route ======> [Node 3]        | |
|  |    (Travel, Encounter,        (Travel)                       (Mission Node)  | |
|  |     Base, or Mission)               |                                        | |
|  +-------------------------------------+----------------------------------------+ |
|                     |                                      |                      |
|                     +============= Territory Adjacency ====+                      |
|                       (Independent of Node-to-Node Routes)                        |
+-----------------------------------------------------------------------------------+
```

### A. Territory vs. Node Separation `[CONFIRMED USER DECISION]`
1. **Node (`CampaignNodeRegistry`):** A discrete point location on the strategic map used for travel, encounters, physical board transitions, bases, and tactical missions.
2. **Route (`CampaignNodeRegistry`):** A 1-hop bidirectional topological link connecting two specific Nodes.
3. **Territory (`CampaignTerritory`):** A geographic district or municipal sector that may encompass multiple Nodes, a single Node, or zero Nodes.
4. **Territory Adjacency (`[PROPOSED IMPLEMENTATION]`):** An explicit district-to-district neighbor graph (`neighbors: Array[String]`) that exists **independently** of Node Routes. Two Territories may be geographically adjacent even if no direct Node Route connects their internal Nodes, and the existence of a cross-border Node Route does not automatically make non-border districts adjacent.
5. **District Geometry / Fills (`[PROPOSED IMPLEMENTATION]`):** Visual polygon or tile-cluster overlay on the strategic map indicating territory boundaries and faction ownership coloring, fully separated from the Route network lines.

### B. Ownership vs. Control vs. Diplomacy `[EXISTING SYSTEM / REUSE]`
- **Ownership / Control (`CampaignTerritory`):**
  - `UNCONTROLLED (0)`: Free / neutral territory. No faction controller.
  - `CONTROLLED (1)`: Held by exactly one registered faction (`controller`).
  - `CONTESTED (2)`: Active conflict zone or unresolved Turf War (`contesting: Array[String]`).
- **Diplomatic Relationship (`FactionSystem`):** `HOSTILE`, `NEUTRAL`, `COOPERATIVE`, `ALLY`. Faction attitudes govern whether an unowned claim or cross-border movement is considered an act of war or generates Strategic Heat/Detection (`C4_HEAT_DETECTION_THREAT_DESIGN.md`).

---

## 3. Subsystem Authority & Reuse Analysis

| Subsystem Responsibility | Existing Authority `[EXISTING SYSTEM / REUSE]` | Contract & Extension Path `[PROPOSED IMPLEMENTATION]` | Prohibited Architecture Violations |
| :--- | :--- | :--- | :--- |
| **Area Control & Boundaries** | `CampaignTerritory` (`scripts/systems/campaign_territory.gd`) | Add explicit `neighbors: Array[String]` adjacency, territory yields, and scenario initial foothold contract. | **PROHIBITED:** Treating Node Routes as Territory adjacency; storing ownership in Nodes or Board tiles. |
| **Topology & Routes** | `CampaignNodeRegistry` (`scripts/systems/campaign_node_registry.gd`) | Maintain node-to-territory membership references (`node.territory_id`). | **PROHIBITED:** Adding territory ownership or claim state to `CampaignNodeRegistry`. |
| **Faction Colors & Identity** | `FactionSystem` (`scripts/systems/faction_system.gd`) | Query faction colors and display names for district map fills and legends. | **PROHIBITED:** Duplicating faction IDs, colors, or diplomatic relations in territory objects. |
| **Spendable Currencies** | `CurrencyManager` (`scripts/systems/currency_manager.gd`) via `GlobalData.currency` | Execute atomic spending (`try_spend_credits`, `try_spend_scrap`) for claiming and hiring. | **PROHIBITED:** Creating a secondary credit/currency store or direct balance mutations outside `CurrencyManager`. |
| **Campaign Clock & Progression** | `CampaignTurnExecutive` (`scripts/systems/campaign_turn_executive.gd`) | Integrate day-boundary passive income settlement and ongoing Turf War day ticks into `advance_campaign_turn()`. | **PROHIBITED:** Introducing a second calendar, turn counter, or independent timer. |
| **Player Fleet & Mecha** | `HangarManager`, `FleetSystem`, `MechaController` | Provide player mecha assembly, loadout, durability, and pilot identity for tactical combat. | **PROHIBITED:** Abstracting player mecha into generic numeric strength when player enters combat. |
| **NPC Operational Forces** | `CampaignForce` (`scripts/systems/campaign_force.gd`) | NPC forces (Patrol, Convoy, Scavenger, Rival). | **PROHIBITED:** Repurposing `CampaignForce` for player Grunt pool (violates 5A entity invariant). |
| **Player Grunt Pool** | *None (Missing Responsibility)* | **New Component:** `CampaignPlayerManpowerPool` under `GlobalData` or `FleetSystem`. | **PROHIBITED:** Merging player manpower into NPC `CampaignForce` or faking infinite Grunts. |
| **Strategic Battle Lifecycle** | `CampaignBattle` (`scripts/systems/campaign_battle.gd`) | Track active Turf War battles, territory targets, committed Grunts, and resolution receipts. | **PROHIBITED:** Bypassing `CampaignBattle` lifecycle (`PLANNED -> ACTIVE -> RESOLVED`). |
| **Strategic Missions** | *None (Missing Responsibility)* | **New Component:** `CampaignMissionRegistry` tracking daily rotations and long-term milestones. | **PROHIBITED:** Mutating board generator randomly without day-boundary synchronization. |
| **Persistence** | `SaveGameIO` (`scripts/systems/save_game_io.gd`) | Add root keys (`"player_manpower"`, `"daily_missions"`, `"longterm_missions"`, `"turf_wars"`) under Schema Version 1. | **PROHIBITED:** Creating standalone save files outside `SaveGameIO.save_run()`. |

---

## 4. Detailed Feature Specifications

### 4.1 Initial Foothold `[CONFIRMED USER DECISION]`
- **Starting Territory Policy:** Scenario-driven initial footholds (defined via scenario resources such as `res://resources/campaign/scenarios/frontier_skirmish.tres` or scenario catalog).
- **Behavior:** When a new campaign launches, the scenario configuration initializes the player faction's starting territory (e.g. territory containing the starting base/node) as `CONTROLLED` by the player faction (`player_militia` / `player`).
- **Safety Invariant:** Zero hardcoded starting territory IDs or balance values in production scripts. Initial conditions load deterministically from the scenario payload.

### 4.2 Claiming Unowned Territory `[CONFIRMED USER DECISION]`
- **Eligibility Rule:** A player may claim an `UNCONTROLLED` Territory if and only if:
  1. The target Territory has `control == ControlState.UNCONTROLLED`.
  2. The target Territory is directly adjacent to at least one Territory currently `CONTROLLED` by the player faction (`neighbors.any(t => is_player_controlled(t))`).
  3. The player possesses sufficient resources in `GlobalData.currency`.
- **Atomic Transaction & Duplicate-Spend Protection:**
  ```text
  Claim Request -> Validate Adjacency -> Validate Uncontrolled -> Check Currency ->
  Atomically Deduct Currency via CurrencyManager -> Mutate Territory to CONTROLLED ->
  Emit territory_claimed Signal -> Generate Receipt
  ```
- **Cost Scaling:** Claim costs may vary by territory type (e.g. Industrial, Commercial, Residential, Wasteland) or strategic importance.
- **Enemy Territory Firewall:** Hostile or enemy-controlled territories (`control == CONTROLLED` by another faction) CANNOT be claimed via resource spending. They strictly require initiating a **Turf War**.
- **Balance Values:** Exact credit/scrap amounts remain `[UNRESOLVED DESIGN QUESTION]` and must be configured via data resources.

### 4.3 Turf War Lifecycle & Outcome-Driven Resolution `[CONFIRMED USER DECISION]`
- **Initiation:** The player initiates an attack on an enemy-controlled Territory adjacent to player-held territory.
- **Outcome-Driven Duration:** Turf Wars do NOT have a fixed or player-selected duration. The duration is entirely outcome-driven:
  - If the enemy force is defeated during the current day's tactical engagement, the Turf War resolves immediately on that day, and the Territory transfers to player control.
  - If the enemy force is NOT defeated, the battle remains unresolved and persists across campaign day boundaries as an active, contested conflict.
- **Campaign Clock Integration:** The Turf War does NOT use an independent clock. When `CampaignTurnExecutive.advance_campaign_turn()` advances the campaign day:
  - Active Turf Wars persist their state (`BattleState.ACTIVE`, committed forces, battle progress).
  - Daily attrition/upkeep or tactical follow-up opportunities are processed.
  - Territory remains in `ControlState.CONTESTED`.
- **Ownership Invariant:** A Territory is NEVER automatically awarded merely because a campaign day elapsed. Ownership changes only upon verified defeat of the defending force.
- **Save/Load Retention:** `SaveGameIO` serializes all active Turf Wars, committed participant IDs, elapsed days, and battle progress.
- **Withdrawal, Defeat & Surrender:** Withdrawal, tactical retreat, or complete force defeat behaviors are documented under Section 7 (`[UNRESOLVED DESIGN QUESTION]`).

### 4.4 Player Combat Participation: Customized Mecha vs. Grunt vs. Auto-Battle `[CONFIRMED USER DECISION]`
The campaign battle system supports three distinct engagement modes without conflation:

```
                          TURF WAR ENGAGEMENT MODES
                                      |
         +----------------------------+----------------------------+
         |                                                         |
         v                                                         v
[MODE 1: DIRECT MECHA COMBAT]                               [NON-MECHA COMBAT]
- Player deploys customized mecha                           (Player mecha not deployed)
- Uses actual frame, weapons, parts, tuning                                |
- Combat outcome governed by player skill                   +--------------+---------------+
  and actual mecha build capability                         |                              |
- High-spec mecha can dominate                              v                              v
- Grunt strength is NOT sole decider            [MODE 2: PLAYER AS GRUNT]       [MODE 3: AUTO-BATTLE]
                                                - Player pilots standard Grunt  - Fully delegated battle
                                                - Uses Grunt loadout / limits   - Resolved mathematically
                                                - Direct tactical play          - Based on force stats
```

1. **Mode 1: Direct Tactical Battle with Customized Player Mecha `[CONFIRMED USER DECISION]`:**
   - The player launches into combat piloting their actual customized mecha from `HangarManager`.
   - The battle takes full account of modular armor parts, equipped shoulder/hand weapons, frame variants, heat dissipation, and player movement/aiming skill.
   - A sufficiently advanced, well-tuned mecha and skilled execution can decisively defeat numerically superior enemy forces. Grunt numbers must NOT override or overwrite an authoritative tactical victory achieved in direct play.
2. **Mode 2: Player Participation as an Ordinary Grunt `[CONFIRMED USER DECISION]`:**
   - If the player chooses not to deploy their customized mecha (or if their main mecha is undergoing repair/hangar recovery), the player may directly enter combat as an individual frontline Grunt.
   - The player controls a standard mass-production Grunt unit with stock weapons and baseline durability.
3. **Mode 3: Fully Delegated Automatic Battle Resolution `[PROPOSED IMPLEMENTATION]`:**
   - If the player delegates the engagement entirely to their Grunt force without personal intervention, the battle resolves via an authoritative mathematical simulation based on unit counts, force tiers, and tactical matchups.
- *Crucial Clarification:* Mode 2 (Player as Grunt) and Mode 3 (Auto-Battle) are fundamentally different concepts and must never be silently merged. The exact triggering UI and delegation mechanics are tracked in Section 7 (`[UNRESOLVED DESIGN QUESTION]`).

### 4.5 Player Grunt Manpower Pool `[CONFIRMED USER DECISION]`
- **Single Source of Truth:** `CampaignPlayerManpowerPool` (managed under `GlobalData` and serialized by `SaveGameIO`).
- **Five-State Manpower Accounting Contract:**
  1. `total_grunts`: Absolute lifetime/current count of owned personnel (`available + committed`).
  2. `available_grunts`: Ready to be deployed to Turf Wars, defense garrisons, or missions.
  3. `committed_grunts`: Actively assigned to an ongoing Turf War, operation, or Node mission. Cannot be spent elsewhere.
  4. `surviving_grunts`: Return to `available_grunts` upon battle/mission conclusion.
  5. `lost_grunts`: Permanent casualties subtracted from `total_grunts` and discarded.
- **Accounting Invariants:**
  - `total_grunts == available_grunts + committed_grunts` at all times outside active resolution transactions.
  - Committing $N$ Grunts atomically decrements `available_grunts` by $N$ and increments `committed_grunts` by $N$.
  - Resolution of a battle with $S$ survivors and $C$ casualties atomically performs:
    - `committed_grunts -= (S + C)`
    - `available_grunts += S`
    - `total_grunts -= C`
- **Recruitment & Rewards:**
  - The player can hire additional Grunts by spending credits through `CurrencyManager` (`GlobalData.currency.try_spend_credits()`).
  - Successful tactical battles and territory captures can award bonus Grunts when specified in scenario or mission reward tables.
- **Forbidden Practice:** No arbitrary casualty formulas or hiring costs are hardcoded; pricing and attrition factors must be defined via configuration resources.

### 4.6 Daily Passive Territory Income `[CONFIRMED USER DECISION]`
- **Settlement Point:** Executed exclusively during `CampaignTurnExecutive.advance_campaign_turn()` at the calendar day boundary (`PHASE_FACTION_ECONOMY` or dedicated `PHASE_TERRITORY_ECONOMY`).
- **Yield Separation:** Territory passive income is completely distinct from Node mission rewards.
- **Idempotency & Duplicate-Payout Protection:**
  - The economy ledger records `last_income_settlement_turn: int`.
  - If `turn == last_income_settlement_turn`, settlement aborts immediately without adding funds.
  - Prevents double payouts during reloads, save restoration, or repeat turn calls.
- **Contested / Hostile Policy:**
  - Only territories with `control == ControlState.CONTROLLED` and `controller == player_faction` yield income.
  - Territories in `UNCONTROLLED` or `CONTESTED` status yield zero income.
  - If territory ownership changes during the day, income awards to the faction holding confirmed control at the time of settlement.

### 4.7 Daily Node Missions & Rotation `[CONFIRMED USER DECISION]`
- **Day-Boundary Rotation:** Strategic Node missions are assigned to specific Nodes based on the campaign day (`CampaignTurnExecutive._campaign_turn`).
- **Single-Claim Invariant:** Each daily mission reward can be claimed exactly once.
- **Map Disappearance:** Upon successful mission completion, the mission is marked completed in `CampaignMissionRegistry` and immediately disappears from the strategic map for the remainder of that daily cycle.
- **Next-Day Replenishment:** At the next day boundary, completed daily missions clear, and a newly generated or rotated set of daily missions appears across active strategic Nodes.
- **Receipt & Reload Safety:** Completed mission receipts are stored as `(campaign_turn, node_id, mission_id)`. Loading a save or retrying a node cannot reset a completed daily mission within the same day cycle.

### 4.8 Long-Term Missions `[CONFIRMED USER DECISION]`
- **Multi-Day Persistence:** Long-term missions persist across campaign days and do not disappear on daily turn boundaries.
- **Milestone & Progress Tracking:** Track incremental progress across multiple sorties, node captures, salvage collection, or boss confrontations (e.g. `current_progress / target_progress`).
- **One-Time Reward:** Upon final completion, rewards are disbursed once, and the mission is permanently flagged as `RESOLVED`.
- **Illustrative Examples (Not Mandatory Content):**
  - *Strategic Route Unlocking:* Capture 3 designated border Nodes to establish a supply line to an enemy logistics depot.
  - *Battlefield Salvage Recovery:* Accumulate 500 units of rare alloy across contested wreckage nodes.
  - *Ace Hunt:* Gather intelligence across 3 patrol encounters, then locate and defeat an elite enemy Ace mecha.
  - *District Resistance:* Liberate 2 adjacent industrial territories to unlock localized militia artillery fire support.

---

## 5. Revised 11-Phase Implementation Roadmap

The implementation plan is strictly ordered by architectural dependencies:

```
[Phase C5-A: Territory Schema & Adjacency]
        |
        +-----------------------------------+
        v                                   v
[Phase C5-B: Map Visualization]     [Phase C5-C: Adjacent Claim Action]
                                            |
                                            v
                                    [Phase C5-D: Passive Daily Income]
                                            |
                                            v
                                    [Phase C5-E: Player Grunt Pool]
                                            |
                                            v
                                    [Phase C5-F: Turf War Lifecycle]
                                            |
        +-----------------------------------+-----------------------------------+
        |                                                                       |
        v                                                                       v
[Phase C5-G: Grunt Combat Pacing]                               [Phase C5-H: Tactical Mecha Bridge]
        |                                                                       |
        +-----------------------------------+-----------------------------------+
                                            |
                                            v
                                    [Phase C5-I: Daily & Long-Term Missions]
                                            |
                                            v
                                    [Phase C5-J: Integrated Save/Load]
                                            |
                                            v
                                    [Phase C5-K: Acceptance & Regression Suite]
```

### Phase C5-A: Territory Schema, Explicit Adjacency & Scenario Foothold Contract
- **Scope:**
  - Extend `CampaignTerritory` with explicit `neighbors: Array[String]` adjacency data and validator (`validate_adjacency()`).
  - Implement bidirectional adjacency registration helpers (`register_adjacency(t1, t2)`).
  - Add territory classification / yields data fields (`category`, `income_credits`, `income_scrap`).
  - Implement scenario-driven foothold loader reading starting territory ownership from scenario definition.
- **Firewalls:** Zero map rendering, zero combat code, zero currency spending in this phase.
- **Target Verification:** `res://test/unit/campaign_c5_territory_schema_verify.tscn`.

### Phase C5-B: Strategic Territory Map Visualization & District Geometry Layer
- **Scope:**
  - Create `CampaignTerritoryVisualizer` node under `campaign_node_map.tscn`.
  - Draw geographic district polygon boundaries / mesh fills representing territories.
  - Query `FactionSystem` for faction colors; color-code player territories, enemy territories, and neutral outlines.
  - Ensure visual separation between district boundaries and Node Route connection lines.
- **Firewalls:** Pure visualization; zero mutation of territory ownership or turn state.
- **Target Verification:** `res://test/unit/campaign_c5_territory_visualizer_verify.tscn`.

### Phase C5-C: Adjacent Unowned Claim Action & Currency Authority Integration
- **Scope:**
  - Implement `CampaignTerritoryClaimAction` integrated with `CampaignPlayerDispatch`.
  - Enforce adjacency constraint (`target_territory.neighbors` must include a player-controlled territory).
  - Gate claim execution via `GlobalData.currency.try_spend_credits(cost)`.
  - Reject attempts to claim enemy-held territories (requires Turf War).
  - Generate atomic transaction receipt and emit `territory_claimed` signal.
- **Firewalls:** No Turf War resolution, no passive income generation.
- **Target Verification:** `res://test/unit/campaign_c5_territory_claim_verify.tscn`.

### Phase C5-D: Passive Territory Economy & Day-Boundary Settlement Ledger
- **Scope:**
  - Add `settle_territory_income()` step to `CampaignTurnExecutive` during calendar day advance (`PHASE_FACTION_ECONOMY`).
  - Calculate total yields across all verified player-controlled territories.
  - Credit player wallet via `GlobalData.currency.gain_credits()` / `gain_scrap()`.
  - Enforce idempotency: record `last_settlement_turn` to prevent duplicate payouts.
  - Enforce zero income for uncontrolled or contested territories.
- **Firewalls:** Zero mission rewards; strictly territory passive income.
- **Target Verification:** `res://test/unit/campaign_c5_territory_economy_verify.tscn`.

### Phase C5-E: Player Grunt Manpower Pool & Recruitment Authority
- **Scope:**
  - Implement `CampaignPlayerManpowerPool` under `GlobalData`.
  - Implement 5-state accounting (`total`, `available`, `committed`, `survivors`, `casualties`).
  - Implement recruitment method `hire_grunts(count, cost_per_grunt)` via `GlobalData.currency`.
  - Implement commitment and return methods with atomic bounds checking.
  - Connect combat reward listeners to disburse bonus Grunts upon territory capture.
- **Firewalls:** No changes to NPC `CampaignForce`.
- **Target Verification:** `res://test/unit/campaign_c5_player_manpower_verify.tscn`.

### Phase C5-F: Persistent Turf War Lifecycle & Day-Boundary State Tracking
- **Scope:**
  - Implement `CampaignTurfWarManager` managing active territory conflicts via `CampaignBattle`.
  - Enforce attack prerequisites: target territory must be enemy-controlled and adjacent to player territory.
  - Set territory state to `ControlState.CONTESTED`.
  - Retain ongoing wars across campaign day boundaries; advance battle day counter without automatic ownership flip.
  - Provide query APIs for UI inspection of active Turf Wars.
- **Firewalls:** No combat execution in this phase; purely lifecycle and state management.
- **Target Verification:** `res://test/unit/campaign_c5_turf_war_lifecycle_verify.tscn`.

### Phase C5-G: Grunt-Led Combat Resolution & Player-as-Grunt Participation
- **Scope:**
  - Implement mathematical resolution engine for delegated auto-battles based on Grunt counts and force tiers.
  - Calculate casualties and survivors atomically applying results to `CampaignPlayerManpowerPool`.
  - Establish contract for Mode 2 (Player participating as a standard Grunt).
  - Award territory control to player if enemy defending force is eliminated.
- **Firewalls:** Does not override player mecha combat results.
- **Target Verification:** `res://test/unit/campaign_c5_grunt_combat_verify.tscn`.

### Phase C5-H: Tactical Player Mecha Combat Integration Bridge
- **Scope:**
  - Connect strategic Turf War intent to `GameManager.enter_combat()` with full player mecha loadout.
  - Pass authoritative tactical combat results (`EventBus.combat_ended`) to `CampaignTurfWarManager`.
  - Guarantee that tactical victory achieved with player's customized mecha overrides numerical Grunt odds.
  - Handle player retreat or defeat without corrupting campaign state.
- **Firewalls:** Tactical combat remains in `game_world`; no tactical code placed in campaign systems.
- **Target Verification:** `res://test/unit/campaign_c5_mecha_combat_bridge_verify.tscn`.

### Phase C5-I: Daily & Long-Term Node Mission Engine & Claim Gating
- **Scope:**
  - Implement `CampaignMissionRegistry` tracking daily missions and long-term milestones.
  - Implement daily rotation hook in `CampaignTurnExecutive`.
  - Implement single-claim verification: completed daily missions disappear from map for current cycle.
  - Implement milestone tracking for multi-day long-term missions.
  - Isolate mission reward disbursement from territory passive income.
- **Firewalls:** Zero secondary clocks; generation keyed strictly to `CampaignTurnExecutive._campaign_turn`.
- **Target Verification:** `res://test/unit/campaign_c5_mission_system_verify.tscn`.

### Phase C5-J: Integrated Strategic Save/Load Serialization & Idempotency
- **Scope:**
  - Extend `SaveGameIO` to serialize and restore:
    - Territory adjacency, ownership, and controller state (`"territories"`).
    - Player manpower pool (`"player_manpower"`).
    - Active Turf Wars and committed forces (`"turf_wars"`).
    - Daily mission rotation state, completed receipts, and long-term progress (`"campaign_missions"`).
    - Economy settlement receipt timestamps.
  - Update `validate_save_payload()` and schema preflight checks under Schema Version 1.
- **Firewalls:** Atomic write-and-rename maintained; zero broken legacy save regressions.
- **Target Verification:** `res://test/unit/campaign_c5_persistence_verify.tscn`.

### Phase C5-K: Serial Acceptance & Regression Verification Test Suite
- **Scope:**
  - Create end-to-end integration test exercising the complete gameplay loop:
    1. Start scenario with canonical foothold.
    2. Claim adjacent unowned territory with credits.
    3. Advance day boundary and verify passive income payout and idempotency.
    4. Hire Grunts into manpower pool.
    5. Initiate Turf War on adjacent enemy territory.
    6. Resolve combat (via direct mecha or Grunts), capture territory, and update map visuals.
    7. Complete daily node mission, claim reward once, and verify disappearance.
    8. Advance turn and verify daily mission rotation.
    9. Save game, restart/reload, and verify 100% bit-for-bit state reconstruction.
  - Execute serial test runner to ensure zero state contention across singletons.
- **Target Verification:** `res://test/unit/campaign_c5_end_to_end_acceptance_verify.tscn`.

---

## 6. Confirmed Decisions & Architectural Principles

### 6.1 Confirmed User Decisions `[CONFIRMED USER DECISION]`
1. **Territory != Node:** Territories are geographic districts; Nodes are tactical map points. Node Routes do NOT define Territory adjacency.
2. **Explicit Adjacency:** Territories require an independent adjacency graph (`neighbors`).
3. **Scenario Foothold:** Initial player territory ownership is established by scenario configuration.
4. **Adjacent Claim Rule:** Player can only claim unowned territories adjacent to existing player-controlled territory.
5. **No Direct Claim on Enemy Lands:** Enemy-held territory requires a Turf War.
6. **Outcome-Driven Turf War:** War duration is outcome-driven, not fixed in days. Wars persist across day boundaries if unresolved.
7. **Customized Mecha Primacy:** Direct combat utilizes the player's actual customized mecha and tactical skill; a high-tier build and skilled execution can decisively defeat numerically superior enemy forces.
8. **Player as Grunt Option:** When not using their customized mecha, the player may fight directly as an individual Grunt.
9. **Authoritative Grunt Manpower Pool:** Real tracked counts for Total, Available, Committed, Survivors, and Lost Grunts.
10. **Passive Territory Income:** Daily income settled at campaign day boundary, separate from mission rewards, protected by idempotency receipts.
11. **Daily Mission Single-Claim & Disappearance:** Daily missions disappear from the map upon completion and rotate on the next day boundary.
12. **Long-Term Mission Support:** Missions persist across days, tracking multi-step milestones to single completion.

### 6.2 Existing Subsystems Reused `[EXISTING SYSTEM / REUSE]`
1. `CampaignTerritory`: Core area control state and controller identity.
2. `CampaignNodeRegistry`: Strategic Node inspection and Route topology.
3. `FactionSystem`: Faction IDs, colors, and diplomatic states.
4. `CurrencyManager` (`GlobalData.currency`): All credit and scrap transactions.
5. `CampaignTurnExecutive`: Authoritative campaign day progression and turn boundaries.
6. `HangarManager` & `FleetSystem`: Player mecha roster and build identity.
7. `SaveGameIO`: Atomic persistence and preflight schema verification.

### 6.3 Proposed Implementation Components `[PROPOSED IMPLEMENTATION]`
1. `CampaignTerritoryAdjacency`: Explicit neighbor mapping within `CampaignTerritory`.
2. `CampaignTerritoryVisualizer`: UI layer rendering colored district fills on `campaign_node_map.tscn`.
3. `CampaignTerritoryClaimAction`: Dispatch-compatible claim validator and currency spending hook.
4. `CampaignPlayerManpowerPool`: 5-state player Grunt tracking singleton under `GlobalData`.
5. `CampaignTurfWarManager`: Persistent multi-day conflict state machine.
6. `CampaignMissionRegistry`: Daily mission rotation, completion receipts, and long-term milestone tracker.

---

## 7. Decision Log: Unresolved Design Questions `[UNRESOLVED DESIGN QUESTION]`

The following design parameters require user clarification before implementation:

### Q1: Relationship Between Player-as-Grunt and Delegated Auto-Battle
- *Context:* The user confirmed that when the player does not deploy their customized mecha, they can participate as an ordinary Grunt. The earlier draft also described delegating battles entirely to Grunts (auto-resolution).
- *Question:* How does the player select between (a) entering the tactical battle directly piloting a standard Grunt vs. (b) fully delegating the battle to auto-resolution without entering 3D gameplay? Should the dispatch UI present a 3-way choice (`[Deploy Mecha]`, `[Deploy as Grunt]`, `[Delegate to Grunts]`), or is one mode a fallback for the other?

### Q2: Turf War Tactical Retreat and Defeat Policy
- *Context:* Turf Wars persist across days until resolved.
- *Question:* What happens if the player retreats or eights ejects/loses their mecha during an ongoing Turf War battle?
  - Does the battle remain active with defending enemy forces entrenched?
  - Does the Turf War immediately cancel, returning surviving Grunts to the ready pool?
  - Does retreat inflict a Strategic Heat penalty or risk an immediate enemy counter-assault on adjacent player territory?

### Q3: Resource Costs and Territory Yield Balance Values
- *Context:* Balance numbers must not be invented by coding agents.
- *Question:* What are the target baseline values for:
  - Unowned territory claim cost (e.g. credits / scrap)?
  - Grunt recruitment cost per unit?
  - Base daily passive income per controlled territory?
  - Daily mission reward baselines?

### Q4: Multi-Faction Contested Territory Conflicts
- *Context:* The Living War campaign supports multi-sided conflicts (Authority vs Militia vs Scavengers).
- *Question:* Can two NPC factions wage a Turf War over a Territory without player involvement, transitioning the territory to `CONTESTED` on the map and leaving behind a Battlefield node for salvage?

---

## 8. Safety & Compliance Confirmation `[NOT AUTHORIZED IN THIS TASK]`

- **No Code Modifications:** Zero gameplay scripts, scenes, resources, or tests were created or modified during this planning task.
- **No Git Mutations:** Zero Git commands modifying repository state (`commit`, `stage`, `push`, `reset`, `clean`, `stash`, `checkout`) were executed.
- **Preservation:** All pre-existing modified files (R20 retargeting changeset) and untracked diagnostic test artifacts remain 100% untouched.
- **Authorization Gate:** Implementation of Phase C5-A through C5-K will not commence until explicit user authorization is provided.
