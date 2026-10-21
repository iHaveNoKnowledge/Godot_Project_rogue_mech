# Phase Status & Evidence Ledger

This document tracks all campaign architecture phases, verified commits, implementation scope, and regression test records.

---

## 1. Phase Ledger

| Phase | Description | Status | Verified Commit / Ref | Test Verification Suite | Notes & Reopening Conditions |
|---|---|---|---|---|---|
| **C1** | Campaign State Foundation | CLOSED | `bd2bafe` | `campaign_state_foundation_verify.tscn` | Closed; establishes campaign scenario, faction ID, and core data structures. |
| **C2** | Node Route Turn Progression | CLOSED | `769641c` | `campaign_node_route_turn_progression_verify.tscn` | Closed; establishes base turn progression and route connection primitives. |
| **C3** | Faction Relationship Foundation | CLOSED | `191ea04` | `campaign_c3_faction_relationship_verify.tscn` (49/49 Passed, Exit 0) | Closed; establishes symmetric and asymmetric faction attitudes and thresholds. |
| **C2.6** | Strategic Topology Decoupling & Explicit Route Schema | CLOSED | `cc49d46` | `campaign_strategic_topology_decoupling_verify.tscn` (50/50 Passed, Exit 0) | Closed; decouples strategic node map from 35x35 tactical grid. |
| **C2.7** | Strategic Node Map UI & Navigation | CLOSED | `0cadaef` | `campaign_strategic_node_map_ui_verify.tscn` (62/62 Passed, Exit 0) | Closed; interactive node graph UI, route rendering, node selection, inspection, dispatch. |
| **C2.8** | Runtime Integration & Playability Acceptance Audit | CLOSED | `c67f8b1` | `campaign_playability_acceptance_audit_verify.tscn` (46/46 Passed, Exit 0) | Closed; verified New Campaign launch, scene transition continuity (`GameManager.return_to_board`), save/load persistence, and action contracts. |
| **C4-B1** | Strategic Heat foundation (`CampaignStrategicHeat`: node-local 0–10 traces, clamp/decay/reset/serialize) | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_strategic_heat_verify.tscn` (53/53 Passed, Exit 0) | Closed; isolated from tactical Heat/Wanted/Patrol. |
| **C4-B2/B2.1** | Strategic Detection state machine + boundary semantics (`CampaignStrategicDetection`: UNKNOWN/SUSPECTED/LOCATED, staleness, decay, anti-omniscience) | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_strategic_detection_verify.tscn` (115/115 Passed, Exit 0; incl. 29 B2.1 idempotency/ordering/recovery assertions) | Closed; LOCATED holds iff age < 1, SUSPECTED iff age < 3, else UNKNOWN; suspicion-refresh clock pin documented. |
| **C4-B3/B3.1** | Read-only Strategic Threat query + authority audit (`CampaignStrategicThreat.get_node_threat`) | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_strategic_threat_verify.tscn` (101/101 Passed, Exit 0) | Closed; pure derived query (no state/signals/persistence); CRITICAL strictly conjunctive; B3.1 audit found no production defect (test-only additions). |
| **C4-B4** | Turn Executive integration (detection aging + heat dissipation phases) | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_turn_c4_integration_verify.tscn` (45/45 Passed, Exit 0); `campaign_turn_executive_verify.tscn` (46/46 Passed, Exit 0) | Closed; phases run day-boundary only between enemy-base and compatibility fan-out; re-entry guard unchanged; no Threat phase (nothing to execute). |
| **C4-B5** | Save/Load persistence (`campaign_strategic_heat`, `campaign_strategic_detection` keys; schema stays 1) | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_strategic_persistence_verify.tscn` (62/62 Passed, Exit 0) | Closed; legacy/malformed/partial payloads handled per established preflight policy; Threat never serialized. |
| **C4-B6** | Dispatch/movement/combat action exposure hooks | CLOSED | N/A (verified uncommitted at `e7b99529`) | `campaign_action_exposure_verify.tscn` (81/81 Passed, Exit 0) | Closed; post-success hooks only (design matrix values); combat-resolution path has no connected producer by evidence, so no hook was invented. Adjacent dispatch/movement/action suites carry pre-existing failures documented in OPEN_ISSUES.md (reproduced without C4 changes where re-verified). |

---

## 2. Mecha Combat Subsystems: Missile System Phase Ledger (R2 Series)

Published Remote & Local Baseline: `eb6aa48b1740ad11e8e364be9c10c258445ec145` (`main`, up to date with `origin/main`)

| Phase | Description | Status | Verified Commit / Ref | Test Verification Suite | Notes & Reopening Conditions |
|---|---|---|---|---|---|
| **R2-BX** | Missile Salvo Harness Extension (Swarm salvo pricing, shoulder salvo execution & gate denial) | CLOSED | `f13b90d3` | `missile_salvo_execution_verify.tscn` (34/34 Passed, Exit 0) | Closed; verifies 1-per-missile pricing for swarm salvos, shoulder transform resolution, `shoulder_ammo_changed` signal order, and unarmed shoulder denial. |
| **R2-BZ / R2-CB** | Missile Lock Cone-Sweep Geometric Verification & Runner Registration | CLOSED | `2065bc12` | `missile_lock_cone_sweep_verify.tscn` (59/59 Passed, Exit 0) | Closed; verifies on-axis acquisition, off-cone rejection, multi-target stacking, occlusion raycasts, out-of-cone progress retention, and target freeing cleanup. |
| **R2-CC / R2-CD / R2-CE / R2-CH / R2-CI** | Missile Trigger Contention (Option A: Mutual Exclusion + Immediate Dumbfire Fallback) & Runner Integration | CLOSED | `e5fd6724` | `missile_dual_trigger_contention_verify.tscn` (130/130 Passed, Exit 0) | Closed; secondary missile trigger fires immediate dumbfire without disturbing active lock; same-slot debouncing; 4 secondary rejection gates; mouse mode guard restored identical to `HEAD`. |
| **R2-CJ / R2-CK** | Missile Changeset Consolidation & Commit Boundary Dry-Run Audits | CLOSED | Read-Only Audits | N/A | Closed; established exact 3-commit sequence without modifying repository state; resolved single-feature ownership of `weapon_manager.gd`. |
| **R2-CL / R2-CM / R2-CN** | Exact-Scope Commit Execution (Commits A, B, C) | CLOSED | `f13b90d3`, `2065bc12`, `e5fd6724` | Serial dry-run & staged diff verification | Closed; staged and committed strictly authorized paths without staging PNGs, campaign scene, or untracked work. |
| **R2-CO** | Serial Runtime Regression Verification | CLOSED | `e5fd6724` | 5 targeted suites (273/273 Passed, Exit 0); `run_tests.sh` (Exit 0) | Closed; serial verification of salvo, cone-sweep, contention, lock-release, and weapon-drop suites; full test runner executed with Exit 0. |
| **R2-CQ** | Authorized Fast-Forward Push of Commit Chain | CLOSED | `e5fd6724` (published to `origin/main`) | Post-push remote fetch & verification | Closed; fast-forward push published commits `f13b90d3..e5fd6724` to `origin/main` without force flags. |
| **R2-CR** | Post-Push Regression & Missile Integration Audit | CLOSED | `e5fd6724` | 5 targeted suites (273/273 Passed, Exit 0) | Closed; read-only verification confirming published remote hash, aggregate 8-file diff, 273 checks passing across 5 suites, and zero defects. |
| **R2-CS** | Canonical Documentation Synchronization | CLOSED | `ca071bcd` (closure verified: R2-CY-A at `eb6aa48b`) | Pre- and post-documentation git diff checks | Closed; synchronized `PHASE_STATUS.md`, `WORK_HANDOFF.md`, and `PROJECT_BIBLE.md` with published missile subsystem evidence. Closure verified by R2-CY-A at published baseline `eb6aa48b`. |

*Uncommitted Work Note:* Pre-existing working-tree modifications (8 reference PNG images under `imgs/valkren_hand_ref/` and `test/unit/campaign_pause_exit_wiring_verify.tscn`) alongside untracked working-tree files (with 48 untracked items verified at R2-CT baseline) are preserved and remain outside the missile subsystem commits.

---

## 3. Reopening Conditions
A CLOSED phase must **NEVER** be reopened or redesigned unless one of the following is proven:
1. A reproducible regression is demonstrated with a failing test case in `test/unit/`.
2. A proven violation of the Architecture Authority Map occurs in production code.
3. Explicit user requirements mandate a redesign.

---

## 4. Historical Reference Ledger
- `5AQ`: Base/Territory Entity Boundary (`77335a6`)
- `5AR`: Territory Ownership Boundary (`5ab4e22`)
- `5AS`: Force Lifecycle Boundary (`5ab4e22`)
- `5AT`: Strategic Player Movement Boundary (`5ab4e22`)
- `5AU`: Attack Combat Boundary (`29cee9e`)
- `5AV`: Base Defense Intervention Boundary (`77335a6`)
- `5AW`: World State Foundation Boundary (`5ab4e22`)
- `5AD`: Canonical Scenario #1 Contract (`campaign_canonical_scenario_purity_verify.tscn`, 28/28 passed, Exit 0) — locks singularity, determinism, and validation purity of `frontier_skirmish.tres` without new production code.
- `5AE`: Scenario Selection Contract and Entry Flow (`campaign_scenario_selection_verify.tscn`, 46/46 passed, Exit 0) — catalog enumeration by stable ID, validated pending selection, and handoff to `RunStartSystem.start_campaign_scenario`; main-menu call site routed through selection with no direct-start bypass.
- `5AF`: Scenario Runtime Initialization & Turn Simulation (`campaign_scenario_runtime_init_verify.tscn`, 47/47 passed, Exit 0) — selected-scenario start contract, run-identity publication, repeat-start stability, failure atomicity, turn boundaries, and save/load identity over existing authorities; no new runtime systems.
- `Canonical Scenario`: Canonical Scenario Execution (`campaign_canonical_scenario_verify.tscn`, freshly verified 96/96 passed, Exit 0)
