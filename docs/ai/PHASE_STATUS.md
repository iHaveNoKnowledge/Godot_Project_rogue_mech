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
| **C4** | Heat / Detection / Threat Progression | OPEN (Pending) | N/A | To be created in Phase C4 | Next scheduled phase. Requires explicit user command to start. |

---

## 2. Reopening Conditions
A CLOSED phase must **NEVER** be reopened or redesigned unless one of the following is proven:
1. A reproducible regression is demonstrated with a failing test case in `test/unit/`.
2. A proven violation of the Architecture Authority Map occurs in production code.
3. Explicit user requirements mandate a redesign.

---

## 3. Historical Reference Ledger
- `5AQ`: Base/Territory Entity Boundary (`77335a6`)
- `5AR`: Territory Ownership Boundary (`5ab4e22`)
- `5AS`: Force Lifecycle Boundary (`5ab4e22`)
- `5AT`: Strategic Player Movement Boundary (`5ab4e22`)
- `5AU`: Attack Combat Boundary (`29cee9e`)
- `5AV`: Base Defense Intervention Boundary (`77335a6`)
- `5AW`: World State Foundation Boundary (`5ab4e22`)
- `Canonical Scenario`: Canonical Scenario Execution (`campaign_canonical_scenario_verify.tscn`, freshly verified 96/96 passed, Exit 0)
