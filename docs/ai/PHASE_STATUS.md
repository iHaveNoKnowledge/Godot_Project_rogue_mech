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
| **C6-A** | Campaign resource ledger (`CampaignSupply`: SUPPLY/MATERIALS/SALVAGE, SUPPLY 42/100 capped at 100, +4/turn day-boundary income, atomic spend, supply-crisis flag; DATA remains `GlobalData.currency.data_cores`) | CLOSED | Current Implementation | `campaign_supply_verify.tscn` (64/64 Passed, Exit 0); `campaign_turn_executive_verify.tscn`, `campaign_turn_c4_integration_verify.tscn`, `campaign_strategic_persistence_verify.tscn` (62/62), `campaign_canonical_scenario_verify.tscn` (96/96) all Exit 0 | Closed; new day-boundary phase `PHASE_CAMPAIGN_SUPPLY` runs immediately after `PHASE_FACTION_ECONOMY`; save key `campaign_supply` under schema 1; ledger performs no gating/crisis enforcement (consumers decide). |
| **C6-B** | Campaign supply consumption: professional repair gate (`RepairSystem.get_professional_repair_supply_cost`, validated before any mutation), base upkeep per live player base (`CampaignBase.SUPPLY_UPKEEP_PER_BASE`, charged in `PHASE_CAMPAIGN_SUPPLY`, shortfall reported not enforced), reinforcement gate (`FleetSystem.REINFORCEMENT_SUPPLY_COST`, `set_unit_fielded` now returns bool) | CLOSED | Current Implementation | `campaign_supply_verify.tscn` (93/93 Passed, Exit 0); `repair_persistence_cycle_verify.tscn` Exit 0; `damage_integrity_closure_verify.tscn` (25 checks, 0 failures, Exit 0); `campaign_turn_executive_verify.tscn` / `campaign_turn_c4_integration_verify.tscn` (45/45) Exit 0; `run_tests.sh` Exit 0 | Closed; no resource can be spent twice (validation precedes every mutation), destroyed bases cost no upkeep, and a shortfall never destroys/disables a base. |
| **C8-A** | Player strategic force + base-defence auto-battle (`CampaignPlayerForce` detachments, `CampaignBaseDefense` strength resolution when a detachment is present, run-start home garrison, save key `campaign_player_forces`) | CLOSED | Current Implementation | `campaign_player_force_verify.tscn`; `campaign_base_defense_verify.tscn`, `campaign_auto_resolve_verify.tscn`, `campaign_assault_scheduling_verify.tscn`, `campaign_assault_visibility_verify.tscn`, `campaign_battle_resolution_lifecycle_verify.tscn`, `run_tests.sh` | Closed; with no player detachment the legacy Option D expiry outcome is unchanged, so no previously CLOSED behaviour was redefined. Attrition ratio/rounds are provisional balance values. |
| **C8-B** | Player detachment UI + orders (`CampaignPlayerForceAction` raise/move/station domain, `CampaignPlayerForcePanel` embedded in the campaign node map sidebar) | CLOSED | Current Implementation | `campaign_player_force_action_verify.tscn`; `campaign_player_force_verify.tscn` (68/68); `campaign_strategic_node_map_ui_verify.tscn`; `run_tests.sh` Exit 0 | Closed; raise costs credits through `CurrencyManager` and rolls the record back when payment fails; move is one strategic route hop; station requires a player-owned base on the detachment's node. Panel owns transient UI state only. |
| **C8-C** | Player detachment strategic assault (`CampaignPlayerForceAssault.attack` resolves a HOSTILE `CampaignForce` at the detachment's node by the shared attrition auto-battle; panel gains target picker + ATTACK) | CLOSED | Current Implementation | `campaign_player_force_assault_verify.tscn`; `campaign_player_force_action_verify.tscn` (57/57); `campaign_player_force_verify.tscn` (68/68); `campaign_strategic_node_map_ui_verify.tscn` | Closed; targets must be HOSTILE via `FactionSystem`, no battle record is faked (detachments are not `CampaignForce`), and base/territory ownership is never mutated. Deterministic, no RNG. |
| **C8-D** | Auto-battle single source + balance tuning (`CampaignAutoBattle.simulate`/`unit_loss`; defence and assault delegate; measured with `tools/campaign_balance_sim` against `frontier_skirmish`; garrison 20/2 units seeded at the player BASE node; raise 12 strength for 120 credits) | CLOSED | Current Implementation | `campaign_auto_battle_verify.tscn`; `tools/campaign_balance_sim.tscn` (real scenario playthrough); C8-A/B/C suites; `run_tests.sh` | Closed; a 20 garrison still loses to a 30 push but now through the player-force path (attacker takes attrition), and garrison + one raise (32) holds. Numbers remain PROVISIONAL per spec §44. |
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

## 3. Core Combat, Audio & Test Harness Modernization Phase Ledger (R19-D Series)

Published Remote & Local Baseline: `87478eccc692944928e1fda75a6eb3d24d91082e` (`main`, verified synchronized with `origin/main` via live `git ls-remote` query at R19-D8 audit time)

| Phase | Description | Status | Verified Commit / Ref | Test Verification Suite | Notes & Reopening Conditions |
|---|---|---|---|---|---|
| **R19-D4** | Group A Production Fixes (Melee SFX enum collision & null safety, Main Menu scenario start boolean syntax) | CLOSED | `1c776fa6b1302d55c3cd63306d6511cbe846102a` | `tests/melee_sfx_verify.tscn`, `test/unit/campaign_scenario_selection_verify.tscn` | Closed; fixes `sfx_manager.gd` enum 4/5/6 collision via substring matching (`"fist"`, `"knife"`, `"blade"`) with pitch jitter (`0.06` swing, `0.05` hit/enemy) and resolves GDScript `False` -> `false` in `main_menu_controller.gd`. |
| **R19-D6** | Group B Test Fixture Modernization (14 standalone test fixtures synchronized with production contracts & exit codes) | CLOSED | `87478eccc692944928e1fda75a6eb3d24d91082e` | 14 standalone verification scenes (Exit 0) | Closed; adds deterministic exit codes (`get_tree().quit(0/1)`), resolves headless mouse capture gate, updates assertions to match 0.0 permadeath shattering, DEF damage scaling, archetype mesh heights, multi-channel action animators, and projectile isolation. |
| **R19-D7** | Post-Commit Serial Regression Verification | CLOSED | `87478eccc692944928e1fda75a6eb3d24d91082e` | `run_tests.sh` (9 suites Exit 0; GUT: "Nothing was run"); 14 standalone verification scenes (Exit 0) | Closed; verified PASS WITH WARNINGS. Non-fatal warnings documented (dummy renderer/allocator teardown, colinear up vector in vertical missile launch, auto-split child reparenting). Known headless limitations documented. |
| **R19-D8** | Push / Remote Synchronization Audit | CLOSED | `87478eccc692944928e1fda75a6eb3d24d91082e` | Read-only audit & `git ls-remote origin refs/heads/main` (Exit 0) | Closed; verified 0 ahead / 0 behind divergence. Remote GitHub server and local references confirmed matching at `87478ecc` at observation time. Neutral reflog `update by push` record noted without actor attribution; no further push required. |
| **R19-D9** | Canonical Documentation Synchronization | CLOSED | Current Phase (`87478ecc`) | Pre- and post-documentation git diff checks | Closed; canonical tracking synchronization across `PHASE_STATUS.md` and `WORK_HANDOFF.md`. |

## 4. Locomotion & Retargeting Integration Phase Ledger (R20 Series)

Published Remote & Local Baseline: `e0ef179c0c942d63ce8da791ddfa8bd7eaf44eae` (`main`, verified synchronized with `origin/main`)

| Phase | Description | Status | Verified Commit / Ref | Test Verification Suite | Notes & Reopening Conditions |
|---|---|---|---|---|---|
| **R20-I1** | In-Game Locomotion Stride Investigation (Read-Only Diagnostic) | CLOSED | Uncommitted analysis at `e0ef179c` | Static analysis & preflight | Closed; established that `clip_ingame_verify.gd` bypassed controller movement authority by writing `mecha.velocity` directly; `MechaController._apply_movement()` overwrote velocity with 0.0, trapping the mech in `procedural_idle`. |
| **R20-I2** | Controlled Locomotion Verification (Exploratory Fixture) | CLOSED | Uncommitted exploratory fixture (`clip_ingame_drive_verify.gd`/`.tscn`) | `clip_ingame_drive_verify.tscn` (14/16 passed), `run_tests.sh` (Exit 0) | Closed; empirically proved that driving via `set_drive_commands()` achieves 80.9° leg swing, 7 cadence crossings, and engages `clip_sprint_kimodo`. Confirmed `clip_retarget_verify.tscn` fails independently on `CLIP_RUN`. Two diagnostic files preserved untracked. |
| **R20-I3** | In-Game Locomotion Fixture Alignment | CLOSED | Uncommitted fixture fix (`test/unit/clip_ingame_verify.gd`) | `clip_ingame_verify.tscn` (14/14 passed, Exit 0), `run_tests.sh` (9 suites Exit 0) | Closed; aligned existing in-game fixture with canonical controller interface `set_drive_commands()` and `clip_sprint_kimodo`. Measured 80.9° swing, 7 cadence crossings, fast=7 vs slow=2 speed scaling, 78.0° post-arm-loss swing, 32.3° airtime grace, clean stop-to-idle. Zero production code modified. |
| **R20-I4** | Issue Ledger Update & Retarget Failure Triage | CLOSED | Current Documentation Phase | Documentation diff review | Closed; documented Issue 1 fixture resolution, opened Issue 6 for isolated retarget GLB clip failure, preserved untracked diagnostic artifacts, updated handoff. |
| **R20-I5** | Isolated Retarget Verification Triage (Read-Only) | CLOSED | Read-only audit at `14246e5e` | Asset & script analysis | Closed; identified animation name mismatch (`"run"` vs `"RunCycle"`) and missing `ai_mech_run.glb` asset. |
| **R20-I6** | Minimal Explicit Animation Alias Fix & Regression Verification | CLOSED | Current Implementation | `clip_retarget_verify.tscn` (1/7 checks), `clip_ingame_verify.tscn` (14/14 Exit 0) | Closed; added `CLIP_ALIASES` in `MechaClipRetarget` mapping `"run"` -> `"RunCycle"`; exposed follow-up zero-swing failure. |
| **R20-I7** | Read-Only Bone Mapping & Retarget Pipeline Audit | CLOSED | Read-only audit at `14246e5e` | Asset binary & keyframe analysis | Closed; proved dual root causes in 37-bone GLB: generic bone names (`Bone.*`) and 113/114 static animation channels in `RunCycle`. Proved historical commit `af08c13d` contained canonical 24-bone rig and active animated channels. |
| **R20-I8** | Controlled GLB Asset Restoration & Verification | CLOSED | Restored `innerframe_run_cycle_clean.glb` | Asset SHA-256 comparison & external backup | Closed; restored canonical 24-bone GLB asset from `af08c13d` (1,092,400 bytes, SHA256 `3627ceaa...`); preserved original in external backup. |
| **R20-I9** | Controlled Godot GLB Reimport & Runtime Verification | CLOSED | Reimported `.godot/imported/...scn` | `innerframe_rig_verify.tscn` (8/8 Exit 0), `clip_ingame_verify.tscn` (14/14 Exit 0) | Closed; executed controlled `--import`, updating `.godot/imported/...scn` to 530,189 bytes. Rig verify 8/8 pass; all 7 retarget motion checks passed (105.6°/103.6° leg swing, -0.82 antiphase correlation). |
| **R20-I10** | Retarget Fixture Alignment & Evidence-Based Issue Closure | CLOSED | Current Implementation | `innerframe_rig_verify.tscn` (8/8 Exit 0), `clip_retarget_verify.tscn` (16/16 Exit 0), `clip_ingame_verify.tscn` (14/14 Exit 0) | Closed; updated `clip_retarget_verify.gd` assertion to accept canonical `"run"` or alias `"RunCycle"`. All 16 checks pass (Exit 0). Closed Issue 6 in `OPEN_ISSUES.md`. |
| **R20-I11** | Run-Cycle Loop Closure & Seam Regression | CLOSED | Current Implementation | `innerframe_rig_verify.tscn` (10/10 Exit 0), `clip_retarget_verify.tscn` (16/16 Exit 0), `clip_ingame_verify.tscn` (14/14 Exit 0), `run_tests.sh` (Exit 0) | Closed; removed the unauthored f38–f40 tail and set `f38 := f1` (38 keys, 1.541667 s). Final GLB 4,201,360 B; first==last on all channels; `Bone_Hip` bob preserved. Added clip-length/seam regression to `innerframe_rig_verify.gd`. |

---

## 5. Melee Combat Standoff, Telegraph & Action Pacing Phase Ledger (R21 Series)

| Phase | Description | Status | Verified Commit / Ref | Test Verification Suite | Notes & Reopening Conditions |
|---|---|---|---|---|---|
| **R21-A** | Melee Combat Pacing & Standoff Distance (6.0–8.5m circle-strafe + back-pedal) | CLOSED | Current Implementation | `melee_combat_pacing_and_telegraph_verify.tscn` (37/37 Passed, Exit 0), `run_tests.sh` (10/10 suites Exit 0) | Closed; prevents enemy from sticking/orbiting at point-blank range. Back-pedals when < 5.5m; circle-strafes in sweet spot. |
| **R21-B** | Direction Lock & Ground Telegraph Indicator (Action RPG danger corridor) | CLOSED | Current Implementation | `melee_combat_pacing_and_telegraph_verify.tscn` (37/37 Passed, Exit 0) | Closed; displays red danger corridor on ground during windup (0.6s Rusher / 0.8s Shield Melee). Direction Lock engages 0.2s before strike. |
| **R21-C** | Attacker Token Management & Multi-Enemy Anti-Swarm Coordination | CLOSED | Current Implementation | `melee_combat_pacing_and_telegraph_verify.tscn` (37/37 Passed, Exit 0) | Closed; limits simultaneous melee attacks to 1 (or 2 for squads >= 5) via `EnemySquadCoordinator`. Other members hold circle-strafe formation. |
| **R21-D** | Punish Window Recovery & Back-dash Disengage | CLOSED | Current Implementation | `melee_combat_pacing_and_telegraph_verify.tscn` (37/37 Passed, Exit 0) | Closed; 0.55s–0.70s stationary recovery window, shield dropped on Shield Melee during windup and restored on disengage, agile back-dash on Rusher. |

---

## 6. Reopening Conditions
A CLOSED phase must **NEVER** be reopened or redesigned unless one of the following is proven:
1. A reproducible regression is demonstrated with a failing test case in `test/unit/`.
2. A proven violation of the Architecture Authority Map occurs in production code.
3. Explicit user requirements mandate a redesign.

---

## 7. Historical Reference Ledger
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
