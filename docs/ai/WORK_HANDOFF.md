# Work Handoff & Session State

## 1. Current State Summary
- **Current Task:** C4 Documentation Closure (status/handoff/issues sync for verified B1–B6).
- **Current Branch:** `main`
- **Current HEAD:** `e7b99529c445fe1ec2fef387ab8e60ab960f9713`
- **Origin Status:** Up to date with `origin/main`.
- **Uncommitted-work caveat:** All C4 B1–B6 implementation and tests exist in the working tree only (per-phase instructions forbade commit/push). Nothing under C4 is committed; `git status` also carries pre-existing `.tscn` UID churn and unrelated untracked artifacts — all preserved as found.
- **Latest Completed Phase:** **Phase C4 (Strategic Heat / Detection / Threat / Turn / Persistence / Action Hooks)** — B1, B2/B2.1, B3/B3.1, B4, B5, B6 implemented and green (see table below).

---

## 2. Test Verification Summary (Freshly Run & Verified in Godot 4.6.2.stable)

| Test Suite | Scene File | Tests / Assertions | Exit Code | Result |
|---|---|:---:|:---:|:---:|
| **C4-B1 Strategic Heat** | `res://test/unit/campaign_strategic_heat_verify.tscn` | 53 assertions | 0 | PASSED |
| **C4-B2/B2.1 Strategic Detection** | `res://test/unit/campaign_strategic_detection_verify.tscn` | 115 assertions | 0 | PASSED |
| **C4-B3 Strategic Threat** | `res://test/unit/campaign_strategic_threat_verify.tscn` | 101 assertions | 0 | PASSED |
| **C4-B4 Turn Integration** | `res://test/unit/campaign_turn_c4_integration_verify.tscn` | 45 assertions | 0 | PASSED |
| **C4-B5 Strategic Persistence** | `res://test/unit/campaign_strategic_persistence_verify.tscn` | 62 assertions | 0 | PASSED |
| **C4-B6 Action Exposure** | `res://test/unit/campaign_action_exposure_verify.tscn` | 81 assertions | 0 | PASSED |
| **Campaign Turn Executive** | `res://test/unit/campaign_turn_executive_verify.tscn` | 46 assertions | 0 | PASSED |
| **C2.8 Playability Acceptance** | `res://test/unit/campaign_playability_acceptance_audit_verify.tscn` | 46 assertions | 0 | PASSED |
| **C2.7 Strategic Node Map UI** | `res://test/unit/campaign_strategic_node_map_ui_verify.tscn` | 62 assertions | 0 | PASSED |
| **Save Hardening (2H-02)** | `res://test/unit/phase_2h_02_save_hardening_verify.tscn` | 30 assertions | 0 | PASSED |

Adjacent dispatch/movement/action suites carry pre-existing failures (attack TEST-J, dispatch Q1, movement route B2/cluster, capture E4/E6, resupply G4/G5, trade C9, investigate J/L, coexistence J1, node-capability T4, repair professional-repair constant) — all classified with baseline evidence in `OPEN_ISSUES.md`; none caused by C4 work.

---

## 3. C4 Architecture Snapshot (Implemented Behavior Only)

- **Strategic Heat** (`CampaignStrategicHeat`): node-local integer traces, bounded 0–10, clamped storage; dissipates −1 per node in the established `strategic_heat` turn phase (day-boundary only). Fully isolated from tactical `HeatWantedSystem.heat` and board patrols.
- **Strategic Detection** (`CampaignStrategicDetection`): faction-specific intelligence; `SUSPECTED` (traces/stale records) stays distinct from confirmed `LOCATED`; freshness rule LOCATED iff age < 1, SUSPECTED iff age < 3, else UNKNOWN; suspicion refresh bumps the clock without moving node/source (pinned); stale/out-of-order/future-dated inputs handled deterministically; never reads player position.
- **Strategic Threat** (`CampaignStrategicThreat.get_node_threat`): stateless derived query (no state, signals, persistence, or orders). CRITICAL only for co-located hostile force + fresh LOCATED intel; pressure vs. knowledge reported separately (`threat_level` vs `confidence` + reason-coded contributors).
- **Turn Executive** (`CampaignTurnExecutive`): remains the sole campaign turn-advancement authority (counter, re-entry guard, receipt contract unchanged); new day-gated phases run detection aging then heat dissipation between enemy-base and compatibility fan-out. Counter-only turns skip both.
- **Persistence** (`SaveGameIO`): persists Heat (`campaign_strategic_heat`) and Detection (`campaign_strategic_detection`) via each authority's own serializer; schema stays 1; legacy/malformed payloads follow the established preflight + sanitize policy. Threat is never persisted (re-derived on demand).
- **Action hooks** (dispatch post-success per design matrix; movement post-success into hostile territory only): attack +3/LOCATED defending faction; capture +2/SUSPECTED dislodged controller; resupply/trade +1 unless allied cover (+threshold-gated suspicion); investigate zero; movement trace only, never detection. Failures/rejections/retries of uncommitted work record nothing; each committed success exposes once. No combat-resolution hook exists because no connected production `resolve_battle` caller exists.
- **Tactical separation**: Heat/Wanted/Patrol remain entirely separate from strategic evidence in both directions.

### Known limitations (implemented as documented, not as defects)
1. Dispatch has no submit-in-flight guard: two rapid successful submissions are two committed actions by contract. Recommend a separate UI-layer task (button discipline); no generic event ledger is warranted.
2. Overlapping multi-controller territories use deterministic id-sorted enumeration with conservative ANY-rules (ANY-hostile traces movement; ANY-allied suppresses resupply/trade heat; suspicion targets the first non-empty controller). No redesign performed.
3. Combat-resolution hooks were not added: audit found no connected production `resolve_battle` caller; attack-time LOCATED already covers player-initiated intel.
4. All balance values (heat amounts, threat ladder, DISABLED-counts-as-present) remain provisional as documented in code, not tuned game design.

---

## 4. Immediate Next Actions
1. Decide commit/push of the uncommitted C4 working tree (implementation + tests + these docs were all held per no-commit phase instructions).
2. Triage the pre-existing failures listed in `OPEN_ISSUES.md` as separate work (not C4 scope).
3. Future strategic work (if ordered): UI double-submit guard; Threat consumers (AI/UI) reading the query; B7+ only per an explicit new phase plan — none designed here.
