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

---

## 5. Asset Session Note (2026-10-19): Innerframe Shoulder-Bridge Mirror — fix9

- **Asset:** `scratch/innerframe_animation_handmade.blend` (intentionally gitignored per `.gitignore:21`; deployed from the working blend and hash-stable after 90 s OneDrive debounce).
- **Root cause (proven, not suspected):** The right-side asymmetry of the 14-piece shoulder-bridge pair was NOT animation. All 14 pair matrices are exact X=0 mirrors (Q = Rw⁻¹·M4W·Lw, M4W = `Matrix.Diagonal((-1,1,1,1))`, nearM4W=0.0000, drift f0→f36 = 0.0000). Only `JointBallBody_R` and `JointBracket_R` carried local mesh vertices displaced by a uniform (+1.48, +0.65, +4.39) from the exact x-flip of their `_L` twins.
- **fix9 (deployed, hash `8BB9A1AADC43D57C`…):** Rewrote the two `_R` local meshes as the exact x-flip of the `_L` twins with index-correspondence pre-check (per-vertex delta uniformity). Verified: local x-flip match 222/222 and 8/8 (max err 0.000000); brute-force world mirror at f0/1/13/36 all pass; pair renders from a camera exactly on the mirror plane report symDiff 0.0000 in all 4 views. The residual f0 clearance for JointElbow/LinkLower/LinkUpper (max ~0.07–0.09) is by-design loop gap, gone from f13 onward.
- **Mandate decision (user, 2026-10-19):** Skip the destructive purge of `_R` object-level actions and the pinv restore — `_R` actions were proven mirror-exact before the decision; only mesh data was broken.
- **Tooling pitfalls (do not repeat):** `mathutils.kdtree.KDTree.find()` returns `(co, index, dist)` — earlier mirror checks false-passed by reading the first element as a distance; brute-force vertex comparison is the only trusted metric. Headless render symmetry checks must explicitly assign `sc.camera = cam` (an unassigned camera renders with the scene's default camera and can false-pass at diff 0.0000) and must sit exactly on the mirror plane (x=0), not at the assembly center (x≈0.197).

---

## 6. Asset Session Note (2026-10-19): Innerframe Shoulder-Link Mirror (Bone-Attachment)

- **Asset:** `scratch/innerframe_animation_handmade.blend` (same gitignored blend; live session, save point after fix9).
- **Task per user mandate (2026-10-19):** Mirror the 3-piece shoulder-link set (`LinkUpper`, `LinkLower`, `JointElbow` `_L` → `_R`) and attach to the arm bones so the pieces follow RunCycle. Armature naming flip: the user's right side is +X, which the rig names with the `.L` suffix.
- **What was replaced:** The three old `_R` pieces (objects + meshes `LinkUpper_R`/`LinkLower_R`/`JointElbow_R`, and their baked actions `LinkUpper_RAction`/`LinkLower_RAction`/`JointElbow_RAction`) were deleted. New `_R` meshes are the exact x-flip + `normal_flip()` of the `_L` meshes (32/32/222 verts, brute-force set-match exact missing=0 extra=0), materials re-assigned from the removed pieces (`LINK_R_Amber` upper/lower, `LINK_Elbow_Steel` elbow), parented to `Bone.019.L` (user choice: all three follow the swinging upper arm, ~90° swing range) with `matrix_parent_inverse = Identity(4)`, placed at the exact world x-flip of the `_L` pieces at rest frame 26.
- **Verification:** rest-world mirror sym ≤1.5e-07; rigid-follow vs the live parent chain across frames 1/20/40 ≤4.8e-07, with chain matrices recomposed from pose channel props and cross-checked against live object `matrix_world`. `_L` pieces and their baked actions untouched per mandate.
- **Correction (tooling, not scene):** An interim statement this session claimed the RunCycle does not move pose bones. That was a wrong read: `pb.matrix` (and evaluated-object pose matrices) return frozen constants in Blender 5.2 regardless of `view_layer.update()`/`evaluated_depsgraph_get()`, while `pb.rotation_quaternion` reads live and matches fcurve evaluation exactly. The action animates the arm/leg chains (Bone.018.L ±17.5°, Bone.019.L ~90° range, legs via Bone.006.L). Verification math in this build must use channel props, never pose matrices. Channel-composition checks also only predict correctly when intermediate chain `location` values read ~0 (e.g. Bone.001-children: don't use this method there).
- **Intentional asymmetry (by mandate, not a defect):** `_L` links keep their baked, non-rig-registered animation; the new `_R` links follow the arm. The sides mirror rest geometry only, not motion.
- **Backup:** `innerframe_before_linkR.blend` in the session temp dir (pre-deletion state of the `_R` links).
