# Open Issues & Known Limitations

This document tracks unresolved investigations, technical debt, and known runtime limitations with concrete evidence.

---

## 1. Active Investigations

### Issue 1: Animation & Combat Lunge Synchronization
- **Category:** Combat / Animation Pipeline
- **Status:** **PARTIALLY RESOLVED / IN-GAME FIXTURE VERIFIED** (Locomotion fixture resolved; live combat lunge unverified)
- **Symptom Description:**
  - Original symptom: Mecha attack logic may move or lunge the character before the imported attack animation visually plays. Full-body motion may not be visible; only certain body parts may appear animated during certain attacks.
  - Test fixture symptom (Resolved): `test/unit/clip_ingame_verify.tscn` exhibited 4/10 failures with leg swing limited to ~5.0° and 0 cadence crossings inside `mecha_base.tscn`.
- **Root Cause & Resolution (In-Game Locomotion Fixture — R20-I1..R20-I3):**
  - **Root Cause:** The original `clip_ingame_verify.gd` test fixture assigned `mecha.velocity` directly on `CharacterBody3D` without setting movement command buffers (`cmd_world_direction`). On every physics frame, `MechaController._apply_movement()` calculated `desired_velocity = Vector3.ZERO` and overwrote horizontal velocity to 0.0. Consequently, `MechaAnimation` observed `velocity.length() <= 0.8`, aborted clip retargeting, and fell back to `procedural_idle`. The observed 5.0° "swing" was merely the mecha's initial asymptotic lerp from 0.0° into its 8.0° standing combat idle crouch.
  - **Resolution:** In R20-I3, `test/unit/clip_ingame_verify.gd` was corrected to drive locomotion via the authoritative public controller interface: `mecha.set_drive_commands(Vector3(0, 0, -1), Vector3.ZERO)`.
  - **Verification Evidence (2026-10-27, Godot 4.6.2.stable, headless):**
    - `test/unit/clip_ingame_verify.tscn` — **14/14 PASS (Exit code 0)**:
      - Horizontal velocity sustained at ~10.5 m/s (above 0.8 m/s threshold).
      - Active animation branch: `clip_sprint_kimodo`.
      - Forward run leg swing: **80.9°** (exceeds 5.0° threshold).
      - Cadence crossings: **7 crossings** over 120 frames.
      - Arm loss robustness: **78.0°** leg swing persists after left arm destruction.
      - Speed scaling: fast speed (7.0 m/s) exhibits **7 crossings** vs slow speed (2.0 m/s) **2 crossings**; slow speed strides at **77.1°**.
      - Airtime grace: **32.3°** motion with `clip_sprint_kimodo` retained across brief airborne pulse.
      - Stop deceleration: returns cleanly to `procedural_idle`.
    - Canonical regression suite `./run_tests.sh` passed cleanly with exit code 0.
- **Remaining Open Limitations:**
  - Interactive-window visual and perceptual animation rendering was not performed (headless only).
  - Combat-attack lunge synchronization during active weapon/melee attacks remains to be verified in live combat scenes.

### Issue 6: Isolated Retarget Verification Missing "run" Clip on GLB Source
- **Category:** Animation Pipeline / Retargeting Verification
- **Status:** **RESOLVED / SKELETAL RETARGET VERIFIED** (Asset restored & retargeting fixture verified; visual parity unverified)
- **Symptom Description:**
  - Standalone verification scene `test/unit/clip_retarget_verify.tscn` originally failed with exit code 1:
    `CLIP_RETARGET FAIL: run clip present on retarget source`
- **Root Cause & Resolution (R20-I5..R20-I10):**
  - **Root Cause:** In commit `6011fa43`, `scenes/mecha/animations/innerframe_run_cycle_clean.glb` was re-exported from `innerframe_animation_handmade.blend` with unbaked bone channels, generic 37-bone Blender names (`Bone.*`), and action name `"RunCycle"` instead of `"run"`. Consequently, `MechaClipRetarget._build_source()` discarded the clip. Even when aliased, `_bone_idx()` lookups for `MechaRig` canonical bone names (`Bone_Thigh_L`, etc.) failed (`-1`), producing zero swing deltas across all body pivots.
  - **Resolution:**
    1. In R20-I6, `MechaClipRetarget` added `CLIP_ALIASES` to support `"RunCycle"` if present, and exposed `get_source_animation_name()`.
    2. In R20-I8, the canonical 24-bone GLB asset with active animated skeletal channels was restored from historical commit `af08c13da808cd670089fed029804b166e14a5a3`.
    3. In R20-I9, Godot 4.6.2 executed a controlled `--import` pass, recompiling `.godot/imported/...scn` to the restored 24-bone rig.
    4. In R20-I10, `test/unit/clip_retarget_verify.gd` aligned its assertion to accept either canonical `"run"` or legacy alias `"RunCycle"`.
- **Verification Evidence (2026-10-27, Godot 4.6.2.stable, headless):**
  - `res://test/unit/innerframe_rig_verify.tscn` — **8/8 PASS (Exit code 0)**:
    - All 16 `MechaRig` bones present, 24 bones total, head scale verified at 4.28m, `"run"` clip confirmed.
  - `res://test/unit/clip_retarget_verify.tscn` — **16/16 PASS (Exit code 0)**:
    - Run clip present, resolved animation valid (`"run"`), source skeleton valid, all pivots finite.
    - Leg swing: Left **105.6°**, Right **103.7°** (exceeds 10.0° threshold).
    - Antiphase correlation: **-0.78** (below -0.3 threshold).
    - Knee flexion: **65.4°** (exceeds 10.0° threshold).
    - Arm pump: **70.0°** (exceeds 5.0° threshold).
    - Hip bob: **0.021 m** (exceeds 0.005m threshold).
    - Torso pitch mean: **-33.3°** (within [-40°, -20°] window).
    - Speed rate scaling and missing-pivot robustness verified.
  - `res://test/unit/clip_ingame_verify.tscn` — **14/14 PASS (Exit code 0)**:
    - Zero regression to live mecha locomotion.
- **Remaining Open Limitations:**
  - Visual parity of the restored 45-mesh asset against the 78-mesh model (Round 3 thigh cylinder resculpt) remains unverified (note: meshes are freed at runtime by `_free_meshes(inst)` as it operates purely as a skeletal pose driver).
  - Interactive-window visual animation rendering remains outstanding (headless test only).

### Issue 2: Offline LSP Server Environment
- **Category:** Developer Tooling / Serena Semantic Analysis
- **Status:** **ACTIVE WORKAROUND**
- **Description:**
  - Serena's GDScript LSP language backend expects Godot Editor running with LSP enabled on port 6008.
  - When Godot is not running in editor mode, LSP-based tools (`find_symbol`, `get_symbols_overview`, `find_referencing_symbols`) return connection errors.
- **Remediation / Standard Operating Procedure:**
  - Use exact text pattern search (`search_for_pattern`), direct file inspection (`view_file`), and Godot headless CLI test runners (`& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless ...`) for symbol and architecture validation.

### Issue 5: Pose-Bone Local-Location Channels Do Not Deform Mesh (Blender 5.2, innerframe blend)
- **Category:** Asset Tooling / Blender 5.2 Animation Authoring (`scratch/innerframe_animation_handmade.blend`)
- **Status:** OPEN INVESTIGATION — root cause unknown; safe workaround proven in production. Do NOT retry pose-loc key authoring on skinned/bone-parented pieces without a reproducible probe.
- **Description:** Authoring pose-bone local `location` keyframes over the RunCycle action never reached deformed world vertices on skinned and bone-parented pieces, while quaternion channels from the same action evaluate live and pose correctly in the same build. Resolution path taken: revert all `Bone.001` local-location keys to 0.0 and carry piece motion in mesh data transforms instead (torso raise +0.40, session note §8 of `WORK_HANDOFF.md`) — verified coherent.
- **Evidence (2026-10-19):**
  - Same channelbag, same slot: `rotation_quaternion` fcurves read live per-frame; locally-added `location` fcurves on the same pose bone produced zero world-extent delta at every sampled frame (legs, thighs) regardless of `frame_set` flip (25→26) for re-evaluation.
  - Rigid-affirmation vs negation: typing values into the same channel verifies in the channel and predicted on a probe empty, yet measured deformed extents stayed identical — prediction and mesh measurement disagreed by a constant, independent of frame.
  - Quaternion path empirically healthy: legs read swinging across frames (channels + evaluated bone children), so this is not slot/bag staleness in general.
- **Open questions:** why local location is consumed differently from rot/quat on this rig build (5.2), whether `armature.data.pose_position`, slot handle binding, or a hidden parent-conjugation path is involved, and whether other Blender 5.2 files reproduce it.
- **Deliverable gate:** reopen only with a minimal repro blend showing a loc-only channel that DOES deform a vertex — or confirm by reversing the above. Ref authoring rule until then: pose quaternion only; positional changes in mesh data.

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
