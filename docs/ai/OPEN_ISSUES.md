# Open Issues & Known Limitations

This document tracks unresolved investigations, technical debt, and known runtime limitations with concrete evidence.

---

## 1. Active Investigations

### Issue 1: Animation & Combat Lunge Synchronization
- **Category:** Combat / Animation Pipeline
- **Status:** **UNVERIFIED / OPEN INVESTIGATION**
- **Symptom Description:**
  - Mecha attack logic may move or lunge the character before the imported attack animation visually plays.
  - Full-body motion may not be visible; only certain body parts may appear animated during certain attacks.
- **Investigation Plan:**
  - Inspect animation blend trees, pivot writers, attack timing, bone retargeting, and weapon-layer masks.
  - Must not mark as resolved without a dedicated, reproducible regression test and visual confirmation.

### Issue 2: Offline LSP Server Environment
- **Category:** Developer Tooling / Serena Semantic Analysis
- **Status:** **ACTIVE WORKAROUND**
- **Description:**
  - Serena's GDScript LSP language backend expects Godot Editor running with LSP enabled on port 6008.
  - When Godot is not running in editor mode, LSP-based tools (`find_symbol`, `get_symbols_overview`, `find_referencing_symbols`) return connection errors.
- **Remediation / Standard Operating Procedure:**
  - Use exact text pattern search (`search_for_pattern`), direct file inspection (`view_file`), and Godot headless CLI test runners (`& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless ...`) for symbol and architecture validation.

---

## 2. Resolved Issues (Reference)
- **Phase C2.8 Scene Transition Seam (Resolved in `c67f8b1`):**
  - Exiting Hangar or finishing tactical combat previously returned unconditionally to `res://scenes/board/game_board.tscn`.
  - Resolved by adding campaign state check to `GameManager.return_to_board()`: if `current_campaign_player_node_id`, scenario ID, or registered campaign nodes are present, route to `res://scenes/ui/campaign_node_map.tscn`.
- **Shoulder-Bridge Right-Side Floating Pieces (Resolved 2026-10-19, fix9):**
  - Symptom: `JointBallBody_R` / `JointBracket_R` rendered floating far off the mirror plane (world x≈3.0–3.25, z≈8.9–9.2 instead of x≈1.6, z≈4.6).
  - Root cause: their local mesh vertices were displaced by a uniform (+1.48, +0.65, +4.39) from the x-flip of the `_L` twins; the animation matrices were already exact X=0 mirrors and untouched.
  - Resolution: the two `_R` local meshes rewritten as exact x-flips of `_L` (fix9); brute-force world/local verification passes frames 0–36; deployed to `scratch/innerframe_animation_handmade.blend` (hash `8BB9A1AADC43D57C`…). User decision: no purge of `_R` actions / pinv restore (they were proven correct).
  - Lesson: `mathutils.kdtree.KDTree.find()` returns `(co, index, dist)` — vertex-mirror checks that read the first element as a distance false-pass; use brute-force comparison. Headless render checks must assign `sc.camera` explicitly and place the camera exactly on the mirror plane (x=0).

---

## 3. Known Pre-existing Test Failures (Unrelated to C4)

The following failures were observed during C4 regression runs and classified with baseline evidence. None is caused by C4 Heat/Detection/Threat/Turn/Persistence/Hook work (C4 hooks run strictly post-success and return receipts unmodified, so they cannot produce `ok:false` results). Do not fix them in a C4 task; triage separately.

### Issue 3: Repair Professional-Repair Constant Undefined
- **Category:** Hangar / Repair Persistence
- **Status:** PRE-EXISTING FAILURE (36 checks, 1 failure in `repair_persistence_cycle_verify.tscn`)
- **Symptom Description:**
  - `SCRIPT ERROR: Invalid access to property or key 'PROFESSIONAL_REPAIR_CREDITS_PER_ARMOR_HP' on a base object of type 'Node (global_data.gd)'` at `repair_system.gd:189`.
  - Failing assertion: professional repair cost is positive (0 credits).
- **Evidence:** The constant is referenced exactly once (`repair_system.gd:189`) and defined nowhere in the repository. Causally disjoint from all C4 files.
- **Recommended triage:** Define the constant or correct the lookup in a dedicated repair-system task with its own regression run.

### Issue 4: Dispatch / Movement / Action Contract Suite Drift
- **Category:** Campaign Action Contract Tests (setup/world drift, test bugs, missing globals)
- **Status:** PRE-EXISTING FAILURES (reproduced without C4 changes where re-verified)
- **Symptom Description:**
  - `campaign_player_action_intent_dispatch_contract_verify.tscn`: 39 passed, 1 failed (Q1 depot intent expects `action_not_implemented`). Reproduced identically on a pristine `e7b99529` worktree (39/1, same Q1).
  - `campaign_attack_action_verify.tscn`: TEST J Attack/Capture succeed (2 failures). Reproduced identically with C4 production edits stashed.
  - `campaign_action_resupply_contract_verify.tscn`: G4/G5 city-resupply success (59 passed, 2 failed). Reproduced identically on a pristine worktree; root cause class is test fuel/world setup (G4 expects success where setup yields rejection), not exposure hooks.
  - `campaign_player_route_movement_contract_verify.tscn`: B2/F1/G1/G2/H4/H5/H6/R1/R6 (position/source expectations) plus `GlobalData.in_combat` missing-member script error in the test path.
  - `campaign_capture_action_verify.tscn`: E4/E6 expect `node_cannot_capture`, got `player_not_at_node` (validation-order setup drift).
  - `campaign_trade_action_verify.tscn`: C9 expects `node_cannot_trade` (node-type/world setup drift).
  - `campaign_action_investigate_contract_verify.tscn`: J3/J4/L1/L2 plus invalid-cast script errors at test lines 349/391 (test-code cast bug).
  - `campaign_multi_action_coexistence_verify.tscn`: J1 plus the same test-file cast error at line 391.
  - `campaign_node_action_capability_contract_verify.tscn`: T4 ×4 (expected vs actual rejection reasons; setup drift).
- **Evidence:** Failures assert `ok:false`/setup-dependent values in validation paths that execute before any C4 hook; hooks cannot convert success to failure by construction. Pristine-baseline reproduction performed for the dispatch, attack, and resupply suites; remainder classified by failure-message causal analysis (missing globals, test cast bugs, fuel/world assumptions).
- **Recommended triage:** Per-suite setup alignment in dedicated tasks; do not bundle with C4 closure.
