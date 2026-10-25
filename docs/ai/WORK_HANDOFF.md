# Work Handoff & Session State

## 1. Current State Summary
- **Current Task:** R19-D Series Documentation Closure & Handoff (R19-D Series CLOSED).
- **Current Branch:** `main`
- **Published Remote & Local Baseline:** `87478eccc692944928e1fda75a6eb3d24d91082e` (verified synchronized with `origin/main` on remote GitHub via live `git ls-remote` query at R19-D8 audit time).
- **Published Commit Chain for R19-D:**
  1. `1c776fa6b1302d55c3cd63306d6511cbe846102a` — `fix(core): resolve melee sfx enum collision and main menu boolean syntax` (Group A: 2 production files)
  2. `87478eccc692944928e1fda75a6eb3d24d91082e` — `test(verify): harmonize standalone verification fixtures with production contracts and add exit codes` (Group B: 14 test fixtures)
- **Historical Inventory & Working-Tree State:**
  - Working-tree state: clean at baseline (0 modified, 0 staged, 0 untracked).
- **Latest Completed Audits / Phases:**
  - **Phase R19-D4 (Group A Production Commit):** `1c776fa6b1302d55c3cd63306d6511cbe846102a`
  - **Phase R19-D6 (Group B Test Fixtures Commit):** `87478eccc692944928e1fda75a6eb3d24d91082e`
  - **Phase R19-D7 (Post-Commit Regression Verification):** PASS WITH WARNINGS (`87478ecc`). 9 primary unit regression suites in `run_tests.sh` + 14 standalone verification scenes exited 0. Non-fatal dummy renderer shutdown leaks and expected geometry warnings documented.
  - **Phase R19-D8 (Push / Remote Synchronization Audit):** SYNCHRONIZED (`87478ecc`). Live GitHub `refs/heads/main` confirmed matching local `HEAD` and `origin/main` (0 ahead / 0 behind). Neutral reflog `update by push` recorded without actor attribution; no further push required.
  - **Phase R19-D9 (Documentation Closure):** Completed.

---

## 2. Test Verification Summary (Reported by R19-D7 in Godot 4.6.2.stable)

| Test Suite / Fixture | Target Path | Tests / Checks | Exit Code | Result |
|---|---|:---:|:---:|:---:|
| **Primary Runner (9 Unit Suites)** | `./run_tests.sh` | 9 suites sequential + GUT | 0 | PASSED |
| **Aim Pose & Muzzle Verify** | `res://tests/aim_pose_muzzle_verify.tscn` | Explicit marker | 0 | PASSED |
| **Armor Damage Visuals Live** | `res://tests/damage_visuals_live_verify.tscn` | 11 passed / 0 failed | 0 | PASSED |
| **Directional Damage & Durability** | `res://tests/directional_damage_and_durability_verify.tscn` | 13 passed / 0 failed | 0 | PASSED |
| **Dual Segment Mesh Hierarchy** | `res://tests/dual_segment_mesh_verify.tscn` | 5 passed / 0 failed | 0 | PASSED |
| **Durability Degradation / Permadeath** | `res://tests/durability_degradation_verify.tscn` | 9 passed / 0 failed | 0 | PASSED |
| **Hangar Weapon Persistence** | `res://tests/hangar_weapon_persistence_verify.tscn` | 7 passed / 0 failed | 0 | PASSED |
| **Weapon Hold Stance** | `res://tests/hold_stance_verify.tscn` | 8 passed / 0 failed | 0 | PASSED |
| **Mecha Combat Refinements** | `res://tests/mecha_combat_refinements_verify.tscn` | 5 passed / 0 failed | 0 | PASSED |
| **Mecha Foot IK Slope** | `res://tests/mecha_foot_ik_verify.tscn` | 7 passed / 0 failed | 0 | PASSED |
| **Melee SFX & Jitter Routing** | `res://tests/melee_sfx_verify.tscn` | 35 passed / 0 failed | 0 | PASSED |
| **Missile Projectile & Arc Detonation** | `res://tests/missile_projectile_verify.tscn` | 16 passed / 0 failed | 0 | PASSED |
| **Procedural Damage Shader Overlay** | `res://tests/procedural_damage_shader_verify.tscn` | 10 passed / 0 failed | 0 | PASSED |
| **Sacrifice Bond Mission Wiring** | `res://tests/sacrifice_bond_verify.tscn` | 19 passed / 0 failed | 0 | PASSED |
| **User Feedback Fixes** | `res://tests/user_feedback_fixes_verify.tscn` | 5 passed / 0 failed | 0 | PASSED |

*Scope & Verification Note:* In `run_tests.sh`, GUT reported `Nothing was run` because unit suites under `res://test/unit/` are standalone scene runners rather than GUT scripts; all 9 standalone scenes executed and passed with exit code 0.
*Known Headless Limitations:* Tests executed in `--headless` mode using `AudioServerDummy` and `RendererDummy`. Perceptual acoustic quality, actual framebuffer rendered fragments, OS-level window mouse-capture events, and full multi-mission campaign playthroughs remain to be verified in interactive gameplay sessions.

---

## 3. Missile Subsystem Architecture & Implemented Contracts

- **Option A Dual-Trigger Contention:**
  - Single active missile lock session globally in `MissileLockOnSystem` (`is_locking`, `active_slot`, `active_weapon`).
  - When one slot is actively locking, pressing another missile slot immediately fires one dumbfire missile from the secondary slot via `_fire_dumbfire_missile(slot, weapon)` without interrupting, resetting, or cancelling the primary lock session.
  - Same-Slot Debounce: Repeated trigger press on the currently locking slot is ignored (`return`) to prevent resetting `hold_duration` or clearing accumulated locks.
  - Secondary Rejection Safety: Secondary dumbfire rejections (empty ammo, reloading, cooldown, destroyed arm, gate capability denial) safely abort without disturbing the active primary lock session.
- **Salvo Ammunition Pricing:**
  - `_fire_missile_salvo` sets `core.ammo_per_shot = 1` temporarily so multi-missile pods (such as Swarm Missile) consume exactly 1 round per launched missile (1:1), restoring original `ammo_per_shot` upon salvo completion.
- **Shoulder Weapon Mounting & Routing:**
  - Physical muzzle world positions resolved via `_get_shoulder_muzzle_world_pos()` with fallback to `FrameVariantResolver.shoulder_fallback_for()`.
  - Normalizes slot aliases (`shoulder_left`/`left_shoulder` and `shoulder_right`/`right_shoulder`).
  - Emits `shoulder_ammo_changed(side, current, max)`.
- **Lock Capacity & Magazine Bounds:**
  - `max_total_locks` is strictly bounded by `min(weapon.max_locks, available_ammo)` and enforces per-target magazine caps.
- **Cone Geometry & Progress Retention:**
  - Direct space state raycasts enforce line-of-sight and reject occluded targets.
  - Off-cone targets are rejected by angular threshold.
  - Progress retention across transient cone exits during active hold is characterization-tested and pinned in `missile_lock_cone_sweep_verify.tscn`.
- **Tap vs. Sustained Release:**
  - Short holds (< tap threshold) launch 1 dumbfire projectile and clear lock state.
  - Sustained holds (>= tap threshold) launch guided homing salvos matching accumulated lock count.
- **`cancel_locking()` & Session Interruption Contracts:**
  - **Direct Cancellation:** `cancel_locking()` clears `is_locking`, `locked_targets`, and `target_lock_progress`, and emits `lock_cleared()`. Direct call sites exist for weapon swap / slot switching commit (`_cancel_lock_on_swap_commit`), weapon drop (`_cancel_lock_if_dropped`), and destroyed-arm drop (`drop_weapon_from_destroyed_arm`).
  - **Gated / Lifecycle Interruption:** Reload suppresses firing via `_is_reloading` checks; mecha core destruction and pilot ejection suppress firing via node invalidation (`is_instance_valid(mecha)` guards) rather than direct cancellation calls.
- **Destroyed-Arm Weapon Drop:**
  - `drop_weapon_from_destroyed_arm(hand)` returns armed instance, clears slot/visual/triggers, re-syncs loadout, emits `weapon_switched` before `weapon_dropped`, and preserves the opposite arm.
- **Runner Integration:**
  - `run_tests.sh` lines 9 & 10 register `missile_lock_cone_sweep_verify.tscn` and `missile_dual_trigger_contention_verify.tscn`.

---

## 4. Immediate Next Actions & Handoff Recommendations
1. **R19-D Series Closed & Synchronized:**
   - Group A production commit `1c776fa6b1302d55c3cd63306d6511cbe846102a` and Group B test fixture commit `87478eccc692944928e1fda75a6eb3d24d91082e` are verified and committed on `main`.
   - Local `HEAD`, local `origin/main`, and live GitHub `refs/heads/main` were observed fully synchronized at `87478eccc692944928e1fda75a6eb3d24d91082e` (0 ahead / 0 behind) during the R19-D8 audit.
   - Reflog recorded an `update by push` event without an identified actor. No further push is required for these commits.
2. **Authority Invariant:**
   - Contracts across audio management (`sfx_manager.gd`), UI campaign flow (`main_menu_controller.gd`), missile dual-trigger contention, permadeath armor mechanics, and test fixtures are verified and closed.
   - Never reopen or redesign closed phases without a reproducible regression test or proven architectural violation.
3. **Subsequent Project Action:**
   - With the R19-D series fully audited, regression-verified, synchronized, and documented, the repository is at a stable baseline.
   - The recommended next project action is to authorize new feature, content, or interactive playtest phases under a separate, narrowly scoped plan.

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

### Addendum (same day, 2026-10-19): Root cause of visible double freeze, fixed and verified

- **User report:** the _R shoulder links did not move at all. Two stacked defects, both remediated and saved into the blend:
  1. Armature.data.pose_position had been left at 'REST' by an earlier session. In Blender 5.2 this silently suspends the whole pose-consumption pipeline: channels still evaluate, read APIs (even pb.matrix in a live session) return live values, but bone-parented children do not consume the pose and armature-modifier deformers do not consume the pose. Fresh headless truth on the saved REST state: pb019.L dev f1-vs-f20 = 0.0; after setting 'POSE' in memory = 214.96 deg, while bone children stayed frozen (probe empty parented to Bone.019.L rode only the object bob z 0.162 to -0.108).
  2. The _R links were created with parent + parent_bone set but parent_type left 'OBJECT'; Blender ignores parent_bone unless parent_type == 'BONE'.
- **Fix:** pose_position = 'POSE'; _R links set to parent_type='BONE' with matrix_basis=I and matrix_parent_inverse=(armM26@pbm26)^-1, then re-anchored empirically in a second pass (basis = world26_observed^-1 @ world26_designed) because the evaluated bone-parenting product carries a constant right-composed offset not exposed by read APIs. Placement preserved exactly at f26 (drift 0.0 vs designed origins (1.977, 1.199, 4.096) for all three pieces).
- **Honest verification (fresh headless on the saved file, --factory-startup):** pose_position=POSE persisted; action RunCycle slot OBArmature; pb019.L world dev f1-vs-f20 = 1.5502 m / 214.96 deg; rigid-rel invariance across frames {1, 6, 12, 20, 26, 34, 40}: spreadT = 8.3e-07 m, Rdeg = 0.0 deg for all three _R pieces; _L pieces untouched (|f1-f26| = 1.4478 m, keys 0-36 intact).
- **With POSE restored the skinned deforms animate as well:** max vertex deviation across f1/f12/f26: Leg_L_Thigh 2.04 m, Leg_R_Thigh 1.93 m, Arm_L_UpperArm 2.63 m, Arm_R_Forearm 3.73 m. The earlier interim belief that skinned deformation was dead was an artifact of sampling only AbsInner, which is itself near-rigid (maxDev 0.0).
- **Retraction:** the "rigid-follow <= 4.8e-07" claim in the parent section was measured while the pose was frozen (pose_position='REST'), so the invariant passed as a false positive (constant matrices trivially constant). The addendum numbers replace it, and the earlier pb.matrix-reads-frozen correction is likewise superseded: pose matrices read correctly in ordinary sessions once the flag is fixed.
- **New tooling lessons:** Object.parent_bone is inert unless parent_type='BONE' (no warning). bpy.ops.ed.undo()/file reload invalidate held StructRNA references (re-resolve bpy.context.scene after them). Blender 5.2: Action.fcurves no longer exists; iterate act.layers[].strips[].channelbags[].fcurves. Frame-dependent checks must run after returning to the anchor frame (a save-gate almost failed by measuring drift at frame 40).

---

## 7. Session Note (2026-10-19): In-Game Run-Clip Verification (read-only, no code/asset change)

- Asked: "can you put this run animation into the game?" — already there. `scratch/innerframe_animation_handmade.blend` is the source of the standing `res://scenes/mecha/animations/innerframe_run_cycle_clean.glb` (2026-09-25 export), consumed as `MechaRig.CLIP_RUN` via `MechaClipRetarget` on every mech.
- Fresh headless runs (Godot 4.6.2.stable): `innerframe_rig_verify` 8/8 PASS; `clip_retarget_verify` 14/14 PASS (legs ~104° antiphase, knees 65.6°, arms 70.6°, hip bob); `clip_ingame_verify` 6/10 (clip live on mech OK; 4 behavioral FAILs — leg swing 5.0° in-scene, stride lost after arm destroy, cadence crossings 0, slow stride 0). Evidence logged on OPEN_ISSUES Issue 1; triage separately.
- Today's blend changes (bone-parent mirror via `Bone.001` + constant C conjugation; deletion of 6 shoulder-rod pieces `LinkUpper/LinkLower/JointElbow` `_L/R` + 2 orphan actions) are mesh-level only: no action curves were touched since 2026-09-25, so a fresh GLB export would yield an effectively identical clip. Scene meshes in-game come from the game's modular meshes — blend meshes are stripped (`_free_meshes`) in the clip path.
- 12 off-scene stray objects (`.002/.003` copies: BodyMountPlate_L/R, Bridge_HingeBarrel_L/R, JointBallBody_L/R) remain in the blend, untouched; `ShoulderBall_R` (origin-parented, no action) still awaits a user decision (mirror-move vs delete).

---

## 8. Asset Session Note (2026-10-19): Innerframe Torso Raise +0.40 (Option B, mesh data) — COMPLETE

- **Asset:** `scratch/innerframe_animation_handmade.blend` (gitignored; **saved in-session at frame 26**). Backup of the pre-session state: `C:\Users\hackd\AppData\Local\Temp\opencode\innerframe_before_jointfixR_20261019_184938.blend`.
- **Goal:** open a coherent pelvis zone (thigh tops 2.743 → torso bottom now 2.896) for the build-your-own pelvis-on-legs + bridge phase. The game never sees bones: in-game piece position = mesh data + skeleton weights, so the raise must live in mesh data (Option B).
- **Result (all verified on evaluated-depsgraph fresh measurements):** exactly 65 raise-set pieces lifted **+0.400**: Body → 2.896..4.974, Head pieces → 5.317..5.384, CockpitSeat → 3.799..5.200, monitor → 4.396..5.150, all arm pieces, Socket/Stub L=R post=4.981 (skeleton symmetric), all Bridge L/R pieces, JointBallBody/Bracket, BodyMountPlate L/R mains, ShoulderBall_L → 4.972..5.202, Head set 23/23 inside the raised band. Intentionally untouched: legs (14 pieces), AbsInner (2.172..2.911, grazes the plan), 2 waist rolls (re-weighted to root Bone in an earlier step), R-side strays. Note: verify-table pre-tops were estimated targets, not history — one apparent mismatch (`Arm_R_Hand`, delta +0.838) was a false alarm, see below.
- **Strategy (final):** mesh data transform (+0.40 z) on all 65 pieces. The interim pose-LOC-channel experiment is REVERTED — `Bone.001` local location fcurves = 0.0 on every key; monitor object z = 4.373 with the raise living in data. That pose-loc keys never reach deformed vertices (while quaternion channels do) is now an open tooling question: see `OPEN_ISSUES.md` Issue 5.
- **monitor negative-scale lesson (important):** matrices with det < 0 expose decompose sign artifacts — `to_scale()` reads (-0.4721, -0.0462, -0.3774) while the measured world mapping is `world_z = obj_z + 0.377 × local_z` (**positive** coefficient). The robust method for any such object is adaptive: apply a small known local delta, solve k = world-per-local from the observed world delta, then apply remainder = (target − w1)/k. monitor final 3.996..4.750 → 4.396..5.150 (+0.400 exact, k measured 0.377).
- **Crashes can partially apply:** one adaptive-loop run died with `TypeError: 'float' object is not subscriptable` **after** already writing a −1.06 data transform — transient measurement states (4.396..5.15 vs 3.996..4.75) were artifacts of that partial write, not alternate geometry. Re-measure fresh after every script; never diagnose by script intent.
- **Bone-parented strays (`.002/.003`):** editing `obj.location` has **no world effect** on these pieces (their `matrix_world.translation` reads ~0.000); the interim −0.404 location edits were reverted and originals restored (BodyMountPlate_L .002/.003 = 0.877, Bridge_HingeBarrel_L .002/.003 = 4.459, JointBallBody_L .002/.003 = 4.210). Left-side strays share mesh data with their `_L` mains → they **ride the raise** (+0.4 via shared data, user-accepted as "ride the raise"); right-side strays do not share data with the `_R` mains → untouched.
- **Arm_R_Hand false alarm:** the pre-batch top used in the verify table (2.292, mirrored from the L side) was a wrong guess; true pre = **2.730** (matching the earlier inventory's "Arm 2.73"). Evidence: identical local data z-span 0.917 on both hands (L 0.3497..1.2671 vs R 0.0938..1.0112 — R sits 0.2559 lower in local), a constant visible top-gap +0.438 at rest frames 60/80, and Socket/Stub L/R post worlds equal ⇒ the +0.438 is a **pre-existing L/R hand placement offset** (R higher), not an animation or raise artifact. The raise itself is exact (+0.400).
- **Accepted intentional state:** L strays ×6 ride the raise via shared data; R strays never lifted; `ShoulderBall_R` (origin, parentless, no action) still awaits the user decision (mirror of L vs delete).
- Section 7's "bone-parent mirror via Bone.001" description of today's changes is superseded by this final state (those keys are back at 0.0; only mesh data changed since).

---

## 9. Asset Session Note (2026-10-19): ShoulderBall_R Mirrored (resolve of the pending user decision)

- **User decision (2026-10-19, via session question):** mirror of `_L` — not delete.
- **Implementation:** the leftover parentless `ShoulderBall_R` object at the origin was repurposed in place. Its mesh data was replaced with an exact per-vertex x-flip + normal flip of `ShoulderBall_L`'s data (reflection lives in the data; the object transform stays pure identity — det +1, no negative-scale rendering hazards). The object was then parented to `Bridge_HingeBarrel_R` (`parent_type='OBJECT'`, identity `matrix_parent_inverse`, identity basis) — the same simple arrangement `ShoulderBall_L` has under `Bridge_HingeBarrel_L`. Material (`LINK_Ball_Brass`) comes with the data copy.
- **Rest verification (frame 26, evaluated):** object world equals the mirror conjugate `M @ wL @ M` with `M = diag(−1,1,1)` to ≤5.5e-07 m; mesh world extents exactly mirrored (L x −1.7194..−1.4894 vs R +1.4894..+1.7194, both y 0.278..0.508, z 4.9718..5.2018 — the raised shoulder band).
- **Clip invariant (sampled frames 0/1/6/12/20/26/34/40):** world-mirror drift is exact (≤5.5e-07 m) at f0/f20/f26/f34 and rises to ≤2.8e-03 m at mid-cycle frames (f6/f12). Root cause: both barrels ride the SAME root bone (`Bone.001`), whose baked pose carries mid-cycle Y/Z twist — a shared rotation cannot satisfy the per-frame mirror conjugation when that twist is non-zero. Magnitude ≤2.8 mm on a 0.23 m ball at 4.6 m shoulder height: accepted (root baked motion untouched per standing mandate; rest state is the exactness anchor).
- **Saved** to the blend at frame 26 in the same session.

---

## 10. Asset Session Note (2026-10-19): Innerframe Raise Round-2 (+0.45) + Thigh/Arm Extensions — COMPLETE (+ Round-3 addendum 2026-10-20: thigh cylinder resculpt + thigh pivot raised to 2.9926)

- **Asset:** `scratch/innerframe_animation_handmade.blend` (gitignored; **saved in-session at frame 26**, 1.58 MB). Backup still the pre-fix9 one from §8.
- **User-cascade numbers (locked via session questions):** ΔH = 0.45 (raise round 2), ΔL = 0.25 (thigh top extension), arm extension = "ยืดเท่า ΔH" (hands hold their rest world height).
- **Raise round 2 (verified fresh, +0.450 exact on 70 data blocks):** the 65-set from §8 + AbsInner (2.172..2.911 → 2.622..3.361) + 2 waist rolls (3.255..3.590) + `_pelvis` guide (2.011..2.906) + `ShoulderBall_R` (5.422..5.652, mirror-consistent with L). L-side strays were **separate data blocks this round** (§8's "share mesh data" does not hold for the .002/.003 copies — each carried its own data and was raised individually); legs (14), `Cube`, and the 6 R-side strays untouched. Method: per-vertex world + (0,0,0.45) mapped back via `matrix_world.inverted()` — exact for rotated/scaled bone-parented pieces, supersedes §8's monitor adaptive-k note as the default pattern.
- **Pelvis zone after raise:** free gap = thigh tops .. torso bottom, computed `0.062 + ΔH − ΔL`; actuals — thigh collars grade-stretch to **2.9926**, guide top 2.906, collar tips poke 0.087 above the guide (that protrusion is the hip-bridge junction point), torso bottom 3.3463.
- **Thigh top extension (graded, both sides, 325 verts each):** the top is a 6-ring dome (65 verts/ring, 2.6978→2.7426). Direct "extend top face" creates a spike; instead the five rings above base 2.6978 were stretch-scaled about the base ring: z' = 2.6978 + (z − 2.6978) × **6.5804** (= 0.2948/0.0448; landing the top exactly at +0.25 on 2.9926). Grade avoids a spike AND keeps topology. A first per-op top-plate theory (extend only the flat face like a box) would have distorted the 6-ring crown. — **SUPERSEDED by the Round-3 resculpt (below): the dome was replaced by a short straight + flat-capped cylinder.**
- **Arm extension chain (per side, keeping the original interlocks):** UpperArm bottom ring (12 verts at 4.2928 post-raise) −0.225 → bottom 4.0678; Forearm two-tier — wrist-end face (131 verts at 3.4242) −0.45, everything else −0.225 → span 2.9742..4.2576; Hand all-verts −0.45 → rests back at the **original** L 1.775..2.692 / R 2.213..3.130. Interlock deltas preserved by construction: forearm-top over upperarm-bottom = 0.1898 (was 0.19), forearm-wrist to hand-gap 0.2818 (was 0.282).
- **Look check:** ported image confirms raised torso, guide box under abs, collar tips past the guide border, forearms/hand hanging to mid-thigh.
- **Tooling lessons (repeat avoidance):** verify-table expectations sourced per-line from earlier prints still drowned in tolerance noise — a tolerance typo (>0.4995 vs expected ~0.45) flagged 19 false "BAD"s; always print the measured delta itself for eyeball verification. R-side naming asymmetry: `Leg_L_Shin.002` exists but the right twin is bare `Leg_R_Shin` (no suffix). `mesh.data.users` is already an int — do not `len()` it. Forearm two-tier cutline must sit mid-gap between measured facial levels (3.4242 / 3.4444 → cut 3.434), not at the face plane.
- **Round-3 (2026-10-20) — thigh cylinder resculpt (both sides):** replaced the grade-stretch dome with a short straight cylinder + flat cap. Thigh span now **1.1315..2.9926** (top block height 0.0929); 8 remapped z-levels from the 2.8997 ring (r 0.2492 constant, straight wall — 455 verts/side remapped) up to 2.9926, capped by a single flat **65-vert ngon** (poly 5016, normal +Z exact, no dome curvature). Counts stay 2780 verts / 5017 polys per leg; visual check confirmed clean flat caps.
- **Round-3 — thigh bone pivot raised to the cylinder top (user decision "ย้ายหัวกระดูกขึ้น 2.99"):** targets (world) **L (−1.1711, −0.0038, 2.9926), R (1.2598, −0.0038, 2.9926)** (each leg's ring-0 axis center); executed as same-delta head+tail edits (bone length 1.2111 and direction preserved). Landed in 2 passes: **L head (−1.1713, −0.0029, 2.9930) err 0.00097, R (1.2600, −0.0029, 2.9930) err 0.00106** (tol 0.002). Bone.003/004 and every other bone untouched; thigh meshes stay single-bone rigid-bound (w 1.0 × 2780 verts) so the rest pose is identity — only the **animation pivot** moved.
- **Round-3 — edit↔data coordinate anomaly (MEMORY-CRITICAL):** `edit_bones` coords are **not** the same basis as `data.bones` head on the same datablock (edit (0.875, 0.009, 2.657) vs data-world (0.0022, 0.180, −0.113)); absolute coords do not map affinely. But **edit-space deltas → data-space deltas run through a bone-local frame ≈ Rz(+90°) for L and Rz(−90°) for R** (bone rolls read ±1.65 rad). Working pattern: compute the wanted data delta, convert via `ed = (∆y, −∆x, ∆z)` (L) / `(−∆y, ∆x, ∆z)` (R), apply to head+tail, verify world, then a corrective 2nd pass with the same rule — converged in 2 passes. Never save a session whose verification mismatched; one wrong save had shipped first (recovered by reload + rebuild).
- **Round-3 — tooling lessons:** `wm.open_mainfile` invalidates the in-call ops context ("Context missing active object") — do the reload in one execute call and the edit/mode_set work in the NEXT one; scene attribute is `frame_current` (not `current_frame`); vgroup iteration uses `e.group`/`e.weight` (no tuple unpack); probe matrices must store **deltas**, not absolute positions; only one armature object now exists (`Armature` — the .002/.003 armature objects are gone).
- **Round-3 — artefacts & suites:** blend re-saved at frame 26 (1.475 MB); `scenes/mecha/animations/innerframe_run_cycle_clean.glb` re-exported (GLB + export_yup, 3,159,620 bytes). Suites: `innerframe_rig_verify` **8/8**, `clip_retarget_verify` **14/14** (legs swing L 105.6° / R 103.9°, antiphase corr −0.83; one OK message leaks a raw `mean=%.1f` via a format-string bug at clip_retarget_verify.gd:68 — cosmetic), `clip_ingame_verify` **6/10** — identical to the pre-pivot baseline, no regression (OPEN_ISSUES #1 still open: leg swing 5.0°, cadence 0 crossings, slow-speed 0.0°).
- **Remaining for this workstream:** ask the user to decide `_pelvis` finalize (guide → real piece), then author the hip-bridge mesh (collar tips ↔ guide/abs junction, 2.9926 ↔ torso bottom 3.3463, ground at 0.087), then re-run the 3 suites.
