# Work Handoff & Session State

## 1. Current State Summary
- **Current Task:** R24 Full 3D Torso Yaw Twist & Diagonal Arm Swing Retargeting (COMPLETE); R23 Live Blender 30-Frame Run-Cycle Integration (COMPLETE); R22 Run-Cycle Loop Closure (COMPLETE).
- **Current Branch:** `main`
- **Published Remote & Local Baseline:** `2100cb889a7fb3a1e0eb7c56e300959f6d4ae791` (`feat(mecha): integrate live Blender 30-frame run animation and sync loop verify`, verified synchronized with `origin/main` on remote GitHub).
- **Working-Tree Inventory & Status:**
  - Production code modified:
    - `scripts/mecha/mecha_clip_retarget.gd` (Upgraded from sagittal-only to 3D: `_apply_torso` transfers Yaw twist and Roll bank; `_apply_arm` transfers full 3D diagonal pump via Quaternion shortest arc).
  - Test suites & runners:
    - `test/unit/clip_retarget_verify.gd` (Added 3 checks for torso yaw range > 10.0°, torso roll range > 3.0°, and arm diagonal lateral range > 10.0°; 19/19 checks PASS, Exit 0).
    - `run_tests.sh` / Standalone Runner (15/15 standalone suites executed and passed, Exit 0).
  - Modified documentation: `docs/ai/WORK_HANDOFF.md`.
- **Latest Completed Audits / Phases:**
  - **C8-A (Player Strategic Force & Auto-Battle Defence, 2026-10-30):** The player finally owns a strategic force. `CampaignPlayerForce` (`scripts/systems/campaign_player_force.gd`) stores detachments `{id, node_id, base_id, unit_count, strength, state}` with proportional casualty application; it is deliberately separate from the NPC `CampaignForce` (5A invariant). `RunStartSystem.seed_player_garrison()` seeds a provisional home garrison (`START_GARRISON_STRENGTH` 10 / 1 unit) at the campaign start node, idempotently. `CampaignBaseDefense._try_player_force_resolution()` runs when an expired assault has a single verified ACTIVE attacker **and** a player detachment at the base: up to 5 rounds of 20% strength attrition decide the outcome, casualties hit both sides, the battle resolves, and a held defence keeps the base ACTIVE while a lost one DISABLES it (controller preserved). With no detachment the legacy Option D outcome is untouched. Persisted as `campaign_player_forces`; reset in `reset_run_data()`. Evidence: `campaign_player_force_verify.tscn` plus the pre-existing assault/auto-resolve/defence suites and `run_tests.sh` all Exit 0.
  - **C6-B (Supply Consumption Wiring, 2026-10-30):** The C6-A pool now gates real play. (1) `RepairSystem.apply_professional_repair` validates credits **and** `SUPPLY` before mutating, spending both only on success; the safehouse button shows `(credits, SUPPLY)` and disables when either is short. (2) `CampaignBase.get_player_upkeep()` quotes `SUPPLY_UPKEEP_PER_BASE` (2) per live player base; `PHASE_CAMPAIGN_SUPPLY` collects income then pays upkeep, reporting a `shortfall` in the receipt without destroying/disabling the base. (3) `FleetSystem.set_unit_fielded` now returns bool and charges `REINFORCEMENT_SUPPLY_COST` (3) when deploying an additional unit (standing down and re-confirming stay free); hangar sortie and deploy-team UIs revert the toggle and explain the refusal. Evidence: `campaign_supply_verify.tscn` 93/93 Exit 0; `repair_persistence_cycle_verify.tscn` Exit 0; `damage_integrity_closure_verify.tscn` 25 checks/0 failures; `campaign_turn_executive_verify.tscn` and `campaign_turn_c4_integration_verify.tscn` (45/45) Exit 0; `run_tests.sh` Exit 0.
  - **C6-A (Campaign Resource Ledger, 2026-10-30):** Added `CampaignSupply` (`scripts/systems/campaign_supply.gd`) as the campaign-level resource authority — `SUPPLY` (start 42, cap 100, +4/turn), `MATERIALS`, `SALVAGE`, atomic `try_spend`, supply-crisis flag, `serialize`/`deserialize` under save key `campaign_supply` (schema 1). `DATA` deliberately stays with `GlobalData.currency.data_cores` (FleetSystem research) to avoid a second research pool. New day-boundary phase `PHASE_CAMPAIGN_SUPPLY` runs right after `PHASE_FACTION_ECONOMY`; `CampaignTurnPanel` shows `Supply: n/100 (+4/turn)` and a `[SUPPLY CRISIS]` marker. Evidence: `campaign_supply_verify.tscn` 64/64 Exit 0; `campaign_turn_executive_verify.tscn` and `campaign_turn_c4_integration_verify.tscn` (45/45) updated for the new documented phase order (Exit 0); `campaign_strategic_persistence_verify.tscn` 62/62; `campaign_canonical_scenario_verify.tscn` 96/96; `run_tests.sh` Exit 0.
  - **R24 (Full 3D Torso Yaw Twist & Diagonal Arm Swing Retargeting, 2026-10-29):** Resolved missing body twist and flat 1D arm swing reported by user. Upgraded `MechaClipRetarget` to transfer Torso Yaw twist (21.5° range) and Roll bank (7.5° range), and Arm 3D diagonal swing (145.1° lateral range); `clip_retarget_verify` 19/19 PASS, `clip_ingame_verify` 14/14 PASS, 15/15 standalone suites exit 0. See §19.
  - **R23 (Live Blender 30-Frame Run-Cycle Integration, 2026-10-29):** Integrated live Blender 30-frame run animation (frames 0-29, 1.25s at 24fps) into canonical GLB; `innerframe_rig_verify` 10/10 PASS, `clip_retarget_verify` 16/16 PASS (hip bob 0.474m), `clip_ingame_verify` 14/14 PASS, 15/15 standalone suites exit 0. See §18.
  - **R22 (Run-Cycle Loop Closure, 2026-10-29):** Removed the unauthored f38–f40 tail and closed the loop (`f38 := f1`); final GLB 4,201,360 B / 38 keys / 1.541667 s; `innerframe_rig_verify` 10/10, `clip_retarget_verify` 16/16, `clip_ingame_verify` 14/14, `run_tests.sh` exit 0. See §17.
  - **Phase R21 (Melee Combat Pacing & Telegraph Redesign):** Resolved player feedback regarding enemies sticking and orbiting around the player. Replaced point-blank melee chaos with high-clarity Action RPG pacing:
    1. **Pacing Standoff (6.0–8.5m):** Circle-strafes and actively back-pedals away if player advances (< 5.5m).
    2. **Wind-up & Direction Lock:** Wind-up telegraph at distance (0.6s Rusher / 0.8s Shield Melee) displaying `GroundTelegraphIndicator` danger zone on the ground and rising audio cue. Direction locks 0.2s before strike.
    3. **Lunge Strike:** Dashes forward 4.5–6.0m along locked vector.
    4. **Recovery Punish Window:** 0.55s (Rusher) / 0.70s (Shield Melee) stationary opening with shield dropped on Shield Melee.
    5. **Disengage:** Backward dash on Rusher / step back with shield re-raised on Shield Melee.
    6. **Squad Attacker Tokens:** Limits concurrent melee attacks to 1 (or 2 for squads >= 5).

---

## 2. Test Verification Summary (Godot 4.6.2.stable)

| Test Suite / Fixture | Target Path | Tests / Checks | Exit Code | Result |
|---|---|:---:|:---:|:---:|
| **Primary Runner (10 Unit Suites)** | `./run_tests.sh` | 10 suites sequential + GUT | 0 | PASSED |
| **Melee Combat Pacing & Telegraph** | `res://test/unit/melee_combat_pacing_and_telegraph_verify.tscn` | 37 passed / 0 failed | 0 | PASSED |
| **Enemy Melee Animation Verify** | `res://tests/enemy_melee_anim_verify.tscn` | 6 passed / 0 failed | 0 | PASSED |
| **Enemy Ammo & Tactical Melee** | `res://tests/enemy_ammo_and_tactical_melee_verify.tscn` | 23 passed / 0 failed | 0 | PASSED |
| **Corrected In-Game Locomotion** | `res://test/unit/clip_ingame_verify.tscn` | 14 passed / 0 failed | 0 | PASSED |
| **Innerframe Rig & Loop Seam** | `res://test/unit/innerframe_rig_verify.tscn` | 10 passed / 0 failed | 0 | PASSED |
| **Exploratory Locomotion Fixture** | `res://test/unit/clip_ingame_drive_verify.tscn` | 14 passed / 2 failed | 1 | DIAGNOSTIC ARTIFACT |
| **Isolated Clip Retarget Verify** | `res://test/unit/clip_retarget_verify.tscn` | 16 passed / 0 failed | 0 | PASSED |
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

*Scope & Verification Note:* In `run_tests.sh`, GUT reported `Nothing was run` because unit suites under `res://test/unit/` are standalone scene runners rather than GUT scripts; all 10 standalone scenes executed and passed with exit code 0.
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
1. **In-Game Locomotion Fixture Alignment Verified (R20-I3 Complete):**
   - `test/unit/clip_ingame_verify.gd` was corrected to drive movement via `mecha.set_drive_commands(Vector3(0, 0, -1), Vector3.ZERO)`.
   - All 14 checks passed under Godot 4.6.2 headless execution (exit code 0): 80.9° leg swing, 7 cadence crossings, speed scaling (7 vs 2 crossings), and stop-to-idle transition.
   - Canonical regression runner `bash ./run_tests.sh` passed with exit code 0.
   - Issue 1 fixture degradation is marked resolved in `docs/ai/OPEN_ISSUES.md`.
2. **Retarget Fixture & Asset Verification Resolved (Issue 6 Closed — R20-I10 Complete):**
   - In commit `6011fa43`, `innerframe_run_cycle_clean.glb` was re-exported with generic 37-bone Blender names, action name `"RunCycle"`, and static keyframes.
   - In R20-I8/I9, the canonical 24-bone GLB asset with active animated skeletal channels was restored from historical commit `af08c13d` and reimported by Godot 4.6.2.
   - In R20-I10, `test/unit/clip_retarget_verify.gd` aligned its assertion to accept canonical `"run"` or legacy alias `"RunCycle"`.
   - All verification suites pass with exit code 0:
     - `innerframe_rig_verify.tscn`: 8/8 PASS
     - `clip_retarget_verify.tscn`: 16/16 PASS (leg swing L 105.6° / R 103.7°, antiphase correlation -0.78, knee flex 65.4°, arm pump 70.0°, hip bob 0.021m)
     - `clip_ingame_verify.tscn`: 14/14 PASS
   - Issue 6 is marked RESOLVED in `docs/ai/OPEN_ISSUES.md`.
3. **Preserved Untracked Diagnostic Artifacts:**
   - Two files from R20-I2 (`test/unit/clip_ingame_drive_verify.gd`, `test/unit/clip_ingame_drive_verify.tscn`) remain untracked in the worktree. They are preserved pending an explicit user keep/remove/integrate decision.
4. **Authority Invariant & Next Recommended Phase:**
   - Skeletal retargeting pipeline is fully verified and functional.
   - Remaining limitation: visual parity with 78-mesh model (Round 3 thigh cylinder resculpt) is unverified in interactive window (meshes are freed at runtime by `_free_meshes(inst)` for skeletal pose driving).
   - Awaiting user instruction for next phase.

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

---

## 11. Asset Session Note (2026-10-27): Leg Piston Rig — Left Built + Right Mirrored

- **Asset:** `scratch/innerframe_animation_handmade.blend` (gitignored; saved 2026-10-27, frame 15, all edits on disk). Backups: `innerframe_animation_handmade_pre_piston_2026-10-27.blend`, `_pre_bonebind_…`, `_pre_basepivot_…`, `innerframe_handmade_pre_lengthen_2026-10-27.blend`, `innerframe_handmade_pre_mirrorR_2026-10-27.blend` (all `copy=True`, verified).
- **Mechanism (per side, 8 bones):** `piston_barrel_{out,in}` → DAMPED_TRACK `TRACK_NEGATIVE_Y` at `piston_socket_{out,in}`; `piston_guide_{out,in}` → `TRACK_Y` at `piston_anchor_{out,in}`; socket/guide parented to the shin bone, anchor/barrel to the thigh bone. Left side uses `Bone.007.R`/`Bone.006.R`, right side mirrors to `.L` (rig naming is inverted vs user L/R: `.L` = +X = character right).
- **Left geometry:** `Leg_L_Thigh_piston_barrel`/`_b` (820 v each, vgroups `piston_barrel_out/in`) and `Leg_L_Shin_upper_piston`/`_b` (522 v each, vgroups `piston_guide_out/in`); rigid single-bone skin, parent Armature, collection `Legs`, actions None. Tube lengths out 0.62 / in 0.57 after the lengthen pass (was 0.4185/0.3585); anchors +0.2015/+0.2115; min |QB| 0.7724 → 0.9195.
- **Left verification (37 frames):** worst min-margin at the barrel base **4.55 cm (out) / 3.74 cm (in)**; max pull-out margin 1.90 cm (out) / −0.24 cm (in, rod tip still inside the dome cap, hidden); coaxial 0.0000° (f0/11/19/32/33/36); rod tip 0.7 cm short of the dome base at max penetration.
- **Bind offset accepted:** bone rest y 0.034 vs piston object y −0.1299 (offset 0.1639) — the offset rotates with the aim axis, evaluated meshes stay coaxial with the barrel and the assembly renders attached at f0–36; deliberately NOT re-anchored. Pending disclosure: the rod mesh was moved +0.286 y from its original bind A′.
- **Right mirror:** duplicated the 4 left objects (independent mesh data, not linked), `location.x *= −1` (rotationally symmetric meshes → no normal flip needed), vgroups renamed with `.L`, new 8 mirrored bones at x +1.322/+1.02 (default roll 0), mirrored Damped Track constraints. The old static `Leg_R_Shin_upper_piston` was renamed `Leg_R_Shin_upper_piston_static` and put on `hide_render`/`hide_viewport`; both legs' lower pistons remain static (out of scope).
- **Right verification (37 frames, mirror is phase-shifted, not symmetric):** min |QB| 0.8523 @f15 → base margin **−2.17 cm**; this is a real overrun of the rod tip past the barrel's base ball, but it is fully enclosed by the thigh at the joint (verified in f15/f27/f32 close-ups — no visible poke), accepted as hidden. Max |QB| 1.4824 @f27 → pull-out margin 1.16 cm (rod still inside); in-side min 0.8867 (+1.27 cm), max 1.4466 (−0.26 cm, tip inside the dome). Full-body f15 render shows both piston pairs attached and symmetric-looking.
- **Cleanup:** cleared 26 leftover object-level actions (all constant — animated values identical at f0/f15/f27; nothing changed after removal), removed 2 empty Armature modifiers (`body_WaistRollSocket`, `body_WaistRollSpindle`), kept `Armature/RunCycle`, moved the 4 new objects from `Scene Collection` into `Legs`.
- **Tooling lessons:** the frame drifted 33→22 between execute calls while `is_animation_playing` read False — re-set the frame before every measurement/render and read the look framing (it reports the actually evaluated frame). Setting `animation_data.action = None` leaves the last-evaluated transform in place, so bbox equality does not prove an action is inert — compare animated channel values across frames instead. `modifiers.remove(m)` invalidates `m` — capture the name before removal.
- **Not done / deferred:** GLB `scenes/mecha/animations/innerframe_run_cycle_clean.glb` is still the stale pre-piston export; in-game retarget suites not re-run for this asset change.

### 11a. Addendum (2026-10-27): Rod-End Pivot Rings (user-requested detail)

- **Ask:** the rod mesh had no pivot ring/eyelet (original rod = 522 v plain cylinder r 0.047, local z 0↔0.874, flat fan caps; barrel 820 v, no ring either). User asked for one and approved with "จัดมาเลย".
- **Geometry:** torus R=0.065, tube r=0.012, 48×12 segs, centred at rod-local (0,0,0) (visible lower/socket end), hole axis local X = world X (object rotation identity, scale 1). Joined into all 4 rod meshes (`Leg_L_Shin_upper_piston`, `_b`, `Leg_R_Shin_upper_piston`, `_b`) → **1098 v / 1344 polys** each; ring verts = indices 522..1097 (trailing 576), polygons 768..1343; every vert keeps weight 1.0 in its single piston vgroup; ring polys assigned **`DarkFrameSteel`** (slot 1) to match the shoulder/hip joint-socket language.
- **Provisional placement (SUPERSEDED by §11b):** the ring was initially left at rod-local (0,0,0), flush with the rod's cap end and reading as a socket boss on the shin plate. That was cosmetic only — the true guide-bone pivot sits 0.1639 m up the rod — and was corrected the same day: both outboard rings were shifted onto the pivot and given a machined link bar + clevis (see §11b).
- **Verification:** material-shaded close-ups of the left rod end at f15 (ring clear, no stray geo), plus a 3.4 m 4-rod view at f15 (rings read as dark loops at both rod ends, nothing floating). Right-side close-ups at f15/f27 framed inside the thigh/shin (all-black tiles) and were discarded; the right rods are exact data copies with identical modifier/weights and were verified numerically.
- **Backup/save:** `scratch/innerframe_handmade_pre_rodring_2026-10-27.blend` (1,458,512 B) before the edit; master re-saved at frame 15 after the ring + material pass.
- **Still deferred:** GLB export and in-game suites (unchanged from §11).

### 11b. Addendum (2026-10-27): Rod-End Link Bars + Pivot Clevises — Both Outboard Rods COMPLETE

- **Ask:** the §11a ring had nothing holding it and sat at the rod cap instead of the rod's rotation point. User asked for a real link bar / physical holder. Scope: the two outboard rods; inner rods deliberately untouched (last bullet).
- **Anchor math:** the ring must ride the guide-bone head `piston_guide_out`. In every rod's local space that joint is **(0, 0.16391, 0)** — measured on all four rods (all rings were still at the local origin). Ring shift Δ = R_D⁻¹ @ (joint_world − ring_center_world); multiplying Δ by the skinning matrix M (first attempt) produces garbage — use R_D only.
- **Left outboard (`Leg_L_Shin_upper_piston`):** ring + bar shifted Δ = (−0.035, 0.16391, 0) → eye world f15 (−1.38653, −1.27948, 1.75247). Link bar 8 v / 6 quads: root p0 = (−0.030, 0.024, 0.024), dir = normalize(eye_c − p0), tip = eye_c − 0.070·dir (tip sinks 12 mm into the ring annulus); ±0.011 thick along X, ±0.024 wide along w = dir × X; `DarkFrameSteel` (slot 1); every bar vert weight 1.0 in `piston_guide_out` (unweighted verts ignore the rod's pose). Mesh → 1106 v / 1350 polys.
- **Right outboard (`Leg_R_Shin_upper_piston`):** identical bar mirrored in mesh data only (x' = −x, all six face windings reversed, normals recalculated; object transform stays identity — no negative-scale rendering hazard), weights 1.0 in `piston_guide_out.L`; ring + bar shift Δ = (+0.035, 0.16391, 0) → eye world f15 (1.6322, 0.4646, 2.2379); 1106 v / 1350 polys.
- **Pivot clevis (both sides):** `Leg_{L,R}_Shin_upper_piston_pivot`, mesh data `Leg_{L,R}_UpperPistonPivot` (204 v; collection `Legs`), stacked along the plate's outboard normal a: hex boss r 0.0599 z −0.0392..−0.0147 (sunk ~1.3 cm into the plate), pin r 0.0358 z −0.0319..0.0320, washer r 0.0469 z 0.0160..0.0210, hex head r 0.048 z 0.0210..0.0330. Slots ['DarkFrameSteel', 'Material_2']: boss/washer/head dark, pin body colour. The ring tube (z ±0.0158) never intersects the stack; the head sits just inside the 0.053 ring hole, reading as a pin through an eyelet.
- **Bone parenting (the hard part):** the effective parent matrix for `parent_type='BONE'` is **`arm.matrix_world @ pose_bone.matrix @ Matrix.Translation((0, pose_bone.length, 0))`** — origin at the bone *tail*. Candidates using `rest.matrix_local.inverted()` or `arm.matrix_world @ pose.matrix` alone missed by 1.25–1.50 m. With the tail-offset P, `matrix_basis = P⁻¹ @ target_at_eye` landed both pivots to 0.001 mm at f15. Left parent `Bone.007.R`, right `Bone.007.L`, `matrix_parent_inverse` identity.
- **Verification (37 frames):** left ring↔pin radial drift 0.6–3.3 mm; right radial drift max **9.1 mm at f0** (pin r 0.0358 vs ring hole r 0.053 → 17.2 mm annular clearance, 8.1 mm still spare; axial ~0), 3.3 mm elsewhere. f15 close-ups (4 views) show ring, pin, washer, hex head and bar concentric with no gaps or poke-through; full-body f15 render clean.
- **Inner rods deliberately untouched:** the `_b` rings on both legs still sit at the rod's local origin, buried inside the shin (left inner ring world f15 (−1.0557, −1.4256, 1.8492) vs joint (−1.0499, −1.295, 1.7505), inside the plate volume) — invisible, so a clevis there would be hidden geometry. Note for any future outboard/inboard symmetry pass.
- **Backups/save:** `scratch/innerframe_handmade_pre_pivotlink_2026-10-27.blend` before the link + pivot work; master re-saved at frame 15 after the right side + final sanity pass (both rods 1106 v / 1350 p, both pivots parented to the correct bones).
- **Still deferred:** GLB export and the three in-game suites (unchanged from §11).

---

## 12. Asset Session Note (2026-10-27): Hip-Joint Bridges — Both Sides COMPLETE

- **Ask:** "เติมมันลงไปซะ" — add the hip-joint bridge both sides, connecting each hip puck to the pelvis (schema `|ขา|=สะพานข้อต่อ=|pelvis|=สะพานข้อต่อ=|ขา|`). Build followed the §10 note: pelvis-side audience only, guide arm from the pelvis collar down to a bearing pad on the puck's inboard face, plus a brass retainer ring.
- **Objects (collection `Pelvis_New`, parented to `Armature`):** `Leg_R_hip_bridge` / `Leg_L_hip_bridge` (180 v, `DarkFrameSteel`, mods [BEVEL (0.01, 2 seg, 40°), ARMATURE]) and `Leg_R_hip_bridge_trim` / `Leg_L_hip_bridge_trim` (128 v, `AccentBrass`, ARMATURE only). Every vert weight **1.0** in `Bone.003.L` (R bridge) / `Bone.003.R` (L bridge); object matrices identity, mesh authored in world coords at **frame 15 + pose_position='REST'** (armature object z 0.0424 then). Geometry: beam + collar box x 0.30..0.47, pad cylinder r 0.23 x 0.8215..0.8801, trim ring inner 0.225 / outer 0.255 x 0.835..0.875, 4 bolt heads.
- **Root cause found (the offset was not geometry):** the `RunCycle` action animates the **Armature object itself** (z −0.15 @f10/f28 … +0.18 @f0/f19); the pucks are parented to it, the new bridges were not, so the pad stayed at its authored world z while the puck rode the bob by ±0.18 (REST-neutral radial 173–175 mm at f0). Fix: parent all four bridge objects to `Armature` (`parent_type='OBJECT'`, `matrix_parent_inverse = arm.matrix_world⁻¹` at f15, basis unchanged) — exactly the puck arrangement; bridge world z now moves +0.1376 @f0 / −0.1924 @f28 with the legs.
- **Pad/puck numbers after parenting** (`Leg_R_hip_joint` / `Leg_L_hip_joint`; inner cap at world x 0.8818 / −0.8818, r 0.3754, vgroup `Bone.006.L`/`.R`): f15 R gap **+0.70 mm**, radial **75.94 mm**, tilt **1.48°**; f15 L gap −4.24, radial 96.68, tilt 22.40°; worst radial **106.72 mm (L f20)**, worst tilt **23.28° (L f20)**, gap stays **−9.54…+6.46 mm** across f0–34. Because ring r 0.255 + max radial 107 mm = 362 mm < puck r 375 mm, the collars never leave the white cap footprint; the tilt-driven rim penetration (sin23° × 0.23 ≈ 90 mm) is fully enclosed inside the white puck volume, so it is invisible. Accepted as an articulating bearing collar (renders: f15 R front/3q, f0 R front/3q, f20 L front/3q all read attached; front view shows dark beam → brass ring → white puck).
- **Measurement pitfall (repeat avoidance):** the bridge's BEVEL modifier changes evaluated vertex count/order — using base-mesh vertex indices on the evaluated mesh produced garbage (gap −320 mm). Measure on base verts with the rigid-skin matrix `M = arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ arm.matrix_world.inverted()`, applied to `obj.matrix_world @ v.co` (all four objects are single-bone weight 1.0). The pucks are rigid too — same formula. Blender 5.2: `Action.fcurves` no longer exists; read the armature object motion with `frame_set` + `arm.location`.
- **Saved/verified:** master re-saved at **frame 15 POSE**. Fresh headless reopen (`--factory-startup`) confirms parent + `matrix_parent_inverse` (0.00113, 0, −0.04239), verts/materials/modifiers/vgroups unchanged, f15 measurements identical (R +0.70 / 75.94 / 1.48; L −4.24 / 96.68 / 22.40), and the prior authoring visibility restored from `innerframe_handmade_pre_hipbridge_2026-10-27.blend` (13 eye-hidden: `Armature` + 12 `JNT_*`; `Leg_R_Shin_upper_piston_static` back on `hide_viewport`).
- **Deferred Resolution:** Resolved in §13 (re-exported to `scenes/mecha/animations/innerframe_run_cycle_clean.glb` with canonical bone names and baked bob).

---

## 13. Asset Session Note (2026-10-28): Innerframe GLB Re-Export from Latest Blender — COMPLETE

- **Asset:** `scratch/innerframe_animation_handmade.blend` (active in Blender 5.2.0 LTS).
- **Target Export:** `scenes/mecha/animations/innerframe_run_cycle_clean.glb` (3,974,108 bytes).
- **Tooling Added:** `tools/export_innerframe_glb.py` (canonical glTF patcher and exporter).
- **Pipeline Remapping & Bob Transfer:**
  - In Blender, the innerframe uses 55 bones with names (`Bone.006.R`, `Bone.019.R`, etc.) and object-level `Armature` translation bob (z = +0.18 to -0.15).
  - Patcher maps the 24 canonical `MechaRig` bones (`Bone_Hip`, `Bone_Torso`, `Bone_Thigh_L`, `Bone_Shin_L`, etc.) onto the skin joint nodes while preserving all piston/bridge bones.
  - Patcher transfers the Armature object-level Z-bob into `Bone_Hip` (`pelvis`) translation curves, resetting Armature object translation to 0 so Godot's retargeter reads the hip bob cleanly without double-bobbing.
  - Normalizes animation action name to `"run"`.
- **Test Verification (Godot 4.6.2.stable, Headless):**
  - `res://test/unit/innerframe_rig_verify.tscn`: **8/8 checks PASS (Exit 0)** (16/16 MechaRig bones present, 55 total bones, head scale 5.60m, "run" clip valid).
  - `res://test/unit/clip_retarget_verify.tscn`: **16/16 checks PASS (Exit 0)** (Leg swing L 113.2° / R 113.0°, antiphase corr -0.99, knee flex 122.3°, arm pump 132.7°, hip bob 0.323m, torso pitch -24.0°).
  - `res://test/unit/clip_ingame_verify.tscn`: **14/14 checks PASS (Exit 0)** (Clean locomotion, speed scaling, arm loss resilience, stop-to-idle transition).
  - **Regression Suite:** All 10 standalone unit suites executed and passed with exit code 0.

---

## 14. Runtime Session Note (2026-10-28): Prioritize Blender `CLIP_RUN` over Kimodo Sprint — COMPLETE

- **User Report:** "ท่าวิ่งยังเปนแบบเดิมอยู่เลยไม่เปนแบบที่ฉันทำใน blender นี้" (The running animation was still the old one).
- **Root Cause:**
  - In `scripts/mecha/mecha_animation.gd` (L174-178), clip selection initialized `clip_name := MechaRig.CLIP_RUN` but then unconditionally checked `if clip_retarget.has_clip(MechaRig.CLIP_SPRINT_KIMODO): clip_name = MechaRig.CLIP_SPRINT_KIMODO`.
  - Because `MechaClipRetarget._ready()` always registers `res://tools/kimodo/samples/valkren_sprint_run.json` as `CLIP_SPRINT_KIMODO`, `clip_retarget.has_clip(...)` was always true.
  - The live mecha in gameplay was unconditionally running `clip_sprint_kimodo` (Kimodo motion diffusion JSON), completely bypassing the re-exported Blender GLB asset `innerframe_run_cycle_clean.glb` (`CLIP_RUN`).
- **Fix:**
  - Modified `scripts/mecha/mecha_animation.gd` to prioritize `MechaRig.CLIP_RUN` first, only falling back to `CLIP_SPRINT_KIMODO` or `CLIP_AI_RUN` if `CLIP_RUN` is missing.
  - Aligned `test/unit/clip_ingame_verify.gd` to accept `clip_run` branch (measured 113.2° leg swing vs 80.9° on Kimodo).
- **Verification:**
  - `res://test/unit/clip_ingame_verify.tscn`: **14/14 PASS (Exit 0)** (enters `clip_run` branch).
  - `res://test/unit/innerframe_rig_verify.tscn`: **8/8 PASS (Exit 0)**.
  - `res://test/unit/clip_retarget_verify.tscn`: **16/16 PASS (Exit 0)**.
  - Regression suite (10 unit suites): **ALL 10 SUITES PASSED (Exit 0)**.

---

## 15. Asset Session Note (2026-10-29): Hip Hinge Barrel + Yoke (Outer, Both Sides) — BUILT, INNER BLOCKED

- **Ask:** replace the placeholder `Leg_L_hip_bridge_hinge` with a proper hinge for the schema `pelvis | hinge >> bridge << hinge | hip joint`; outer hinge (bridge ↔ hip-joint puck) first, mirror right.
- **Authoring frame:** evaluated **f15 world coords** (`frame_set(15)` + `evaluated_depsgraph_get()`); the file had been left at f32, which makes every rigidly bone-parented part look displaced — always set f15 before comparing/authoring.
- **Placement (raycast on the puck's flat inner face):** L plane n=(0.994, −0.093, −0.049), n·p0=−0.9586, face y −0.42..−0.18 / z 2.80..3.48; R plane n=(−0.987, 0.163, 0.005), c=−0.8581, face y −0.20..0.10 / z 2.80..3.48. The R face is **not a mirror of L** (different normal + y span) — never mirror this hinge across X blindly.
- **Objects (collection `Pelvis_New`):**
  - `Leg_L_hip_bridge_hinge` / `Leg_R_hip_bridge_hinge` — 320 v, `AccentBrass`: vertical pin r 0.0775 z 2.70..3.50 at the pad centre (L x −0.8032, R x 0.8517); brass rings r 0.095 × 0.012 at z 3.372 / 2.862; caps r 0.100 × 0.016 at z 3.494 / 2.706.
  - `Leg_L_hip_bridge_hinge_yoke` / `_yoke` R — 128 v, `DarkFrameSteel` + `AccentBrass` bolt heads: top arm 0.165 (L) / 0.237 (R) × 0.22 × 0.06 at z 3.39..3.45 running into the bridge; diagonal bottom brace from pad-bottom (L x −0.845 / R 0.887, z 2.73) up to bridge bottom (∓0.65, z 2.945) — the brace underside already merges with the bottom brass cap at the centreline (verified surface samples inside the cap volume), so it does not float; straps 0.02 × 0.20 × 0.09 at z 3.435 / 2.785 with hex bolts (shank r 0.012, head r 0.020).
  - Both meshes BEVEL 0.003, 2 seg, 40°.
- **Parenting:** all four `parent_type='BONE'` → `Bone.003.R` (L) / `Bone.003.L` (R), `matrix_world = Identity` at f15 (verified 0.0 error). `Leg_{L,R}_hip_bridge_trim` and `Leg_{L,R}_hip_bridge` are skinned 100% to the **same** bones, so the hinge is rigid with the pad/bridge and cannot drift; the only relative mover is the white puck (`Bone.006`). The top arm overlaps the pin body above the pad; the straps sit just above/below the pad's top/bottom faces and read as bolted flanges; the pin's inboard half is intentionally embedded in the pad/puck (only the D-shaped inboard face + brass caps are visible).
- **Inner (pelvis-side) hinge — BLOCKED:** a fixed pin on the pelvis collar cannot work: the collar point (−0.45, 0.016, 3.13) in pelvis space travels ~0.20 m across f0–34 (f0 Δ(0.048, −0.132, 0.146), f28 Δ(0.017, 0.194, 0.042)). Options: (a) static decorative mount bracket, (b) leave the inner side as-is, (c) redesign the rig pivot — awaiting user decision.
- **Open design questions:** the pin is vertical (yaw) matching the placeholder, not on the puck's rotation axis; the hinge is currently a static detail (pin + yoke on `Bone.003`). If it must articulate, the pin has to follow `Bone.006` — but the pin sits ~0.33 m from the ball centre, so it would translate during puck rotation.
- **Save/backup:** backup `scratch/innerframe_animation_handmade_pre_hiphinge_2026-10-29.blend` before the build; master re-saved at **frame 15 POSE** (`save_as_mainfile(copy=True)`).
- **Deferred:** GLB re-export and in-game suites (asset changed; unrelated GDScript edits are in progress in the working tree).

## 16. Asset Session Note (2026-10-29): Inner Hip-Bridge Hinge (Rig Pivot Redesign) — COMPLETE

- **Decision:** user chose **(c) redesign the rig pivot** for the pelvis side. The hip-bridge collar is now driven by two dedicated deform bones parented to `pelvis`, so the collar follows the bridge while the beam telescopes inside it; the outer hinge (§15) is untouched.
- **Rig:**
  - `Bone.008.R` (L side) head/tail armature `(−0.3944,−0.1212,3.0867)` / `(−0.798,−0.2791,3.0785)`; `Bone.008.L` (R side) `(0.4199,−0.0131,3.0876)` / `(0.8509,−0.0589,3.0805)`. Parent `pelvis`, `use_connect=False`, `use_deform=True`.
  - Hidden empties `CTRL_hip_bridge_collar.L` (`Bone.003.R`) / `.R` (`Bone.003.L`), PLAIN_AXES 0.05, `hide_render`, `hide_set(True)`, MPI identity; Damped Track `Track bridge pad`, `TRACK_Y`.
  - Weights: bridge re-split L `Bone.003.R` 76 / `Bone.008.R` 104; R `Bone.003.L` 76 / `Bone.008.L` 104. Collar pitches with the bridge step (~16.7° up at f0, ~23.6° down at f10); the Damped Track keeps the pad aim flush.
- **Collar clamp (collection `Pelvis_New`):** `Leg_{L,R}_hip_bridge_collar_bracket` (16 v, `DarkFrameSteel`) with top arm z 3.360..3.410 / bottom arm z 2.845..2.895, x inner ±0.325 (inside pelvis shell ±0.368), x outer = pad x ± 0.015; `Leg_{L,R}_hip_bridge_collar_pin` (256 v, `AccentBrass`) r 0.030 stubs + r 0.048 × 0.014 caps (top 3.410..3.424, bottom 2.831..2.845). Both BEVEL 0.003/2/40°, flat shading. The pin is embedded into the collar and carries the bracket plates; no vertical outer plate.
- **Parenting:** all four parts OBJECT-parented to `Armature`, `parent_type='BONE'` → `pelvis`, full `matrix_parent_inverse = (A @ pb.matrix @ Translation(0,len,0))⁻¹`, basis identity. At f0/15/34 `matrix_world` differs from the bridge by ≤1.34e-07 (f15 5.96e-08). Note: reading `matrix_world` immediately after parenting is stale until `view_layer.update()`; the first identity check was a false pass.
- **Clearance proof (f0–40 BVH, real objects at f0/5/15/20/34):** worst arm-vs-bridge **+39.34 mm** (R f2 top) / **+42.88 mm** (L f1 bottom); worst pin-vs-beam **+26.10 mm** (R f5 top) / **+26.18 mm** (L f33 bottom); pin–beam min distance 26.2–27.7 mm with `overlap=0`; bracket–beam (beam-only) 79.4–83.9 mm; pelvis pose rotation **0.0000° f0–40** (so no pelvis-driven drift). Method: world-space BVH `FromPolygons`; arm band grid 4 mm, stub disc 2.5 mm via raycasts — never vertex-in-band tests.
- **Bake integrity:** f15 evaluated components match `scratch/innerframe_animation_handmade_pre_collarbake_2026-10-29.blend` to 5 decimals both sides (pad 192, bolts 4×72, beam 68, collar 56 verts).
- **Save:** master `scratch/innerframe_animation_handmade.blend` re-saved at **f15 POSE**. Fresh headless reopen: 57 bones, frame 15, POSE, bracket/pin parent BONE `pelvis`, basis identity, world diff ≤1.34e-07, 15 eye-hidden objects (13 former + 2 new CTRL empties), `Leg_R_Shin_upper_piston_static.hide_viewport=True` preserved.
- **Render review:** both sides rendered at distance 2.0 m from outside front/left diagonals (tight 0.85–1.15 m puts the camera inside the pelvis/thigh; top-down sits inside the torso at z≈4.97). Bracket clamps the pin, caps seat on the arms, pin anchors into the collar, brass trim ring sits flush on the puck — accepted.
- **GLB re-export:** `scenes/mecha/animations/innerframe_run_cycle_clean.glb` rebuilt via Blender GLB + `tools/export_innerframe_glb.py` — **57 joints**, 103 meshes, 176 nodes, animation `run`, Armature translation zeroed and the Z-bob transferred into `Bone_Hip` (Z 3.1995..3.5295, 41 samples). Hidden CTL/JNT empties remain exported exactly as before.
- **Godot verification (after `--headless --import`; without reimport Godot serves the cached 55-bone scene):**
  - `innerframe_rig_verify` **8/8** (`>=16 bones (got 57)`, 16 canonical bones present, head 5.60 m)
  - `clip_retarget_verify` **16/16** (leg range 113.2°/113.1°, shin 122.4°, bob 0.325 m)
  - `clip_ingame_verify` **14/14** (clip_run, leg 113.3°, cadence 2 crossings, airtime/grace and idle return intact)
  - `run_tests.sh` exit 0; all standalone verifies pass; GUT reports "Nothing was run" (pre-existing configuration quirk, unrelated).
- **Remaining caveats:** outer hinge remains a static detail (§15); the GLB carries the hidden control empties as before. No production GDScript changed.

## 17. Asset Session Note (2026-10-29): Run-Cycle End-of-Loop Hitch Fix — COMPLETE

- **Symptom:** user reported the mecha run "freezes/hitches at the end of the loop" (ท่าวิ่งเหมือนค้างตอนท้าย loop).
- **Root cause:** the authored action carried an unauthored 3-frame tail (`f38–f40`). The cycle wrapped `f38 -> f1` with a **16.15°** shin snap (and a held torso), producing the visible hitch; there was no true cycle closure (`f38 != f1`). The closed seam now steps `f37 -> f1` at max **8.0°**, within normal motion.
- **Fix (Blender 5.2, headless):** closure rule = keep authored `f37`, set **only `f38 := f1`** on every transform curve, export frames **1..38**. Critical: insert a key at frame 1 (`1 = v1`) **before** removing modifiers/trimming; otherwise curves without a key exactly at f1 (object `location` x/z) evaluate differently and corrupt the first frame. Then trim `<1`/`>37`, ensure `37 = v37`, insert `38 = v1`.
- **Script/backup:** `C:\Users\hackd\AppData\Local\Temp\opencode\loopfix.py`; pre-fix backup `scratch/innerframe_animation_handmade_pre_loopfix_2026-10-29.blend` (1,610,091 B). The first attempt had already saved the broken master; it was restored from this backup before the corrected rerun.
- **Master result:** action/scene range `(1.0, 38.0)`; `REMOVED_META` 3, `KEPT` 370, `BAD []`; `CHECK` confirms `f38 == f1` for every checked transform.
- **GLB:** `scenes/mecha/animations/innerframe_run_cycle_clean.glb` rebuilt via Blender GLB + `tools/export_innerframe_glb.py` — **4,201,360 B**, 176 nodes, 103 meshes, 57 joints, animation `run`, 174 channels / 175 samplers, **38 keys per channel**, length **1.541667 s (37/24)**. First/last values are identical on every channel; the seam checker's 0.0125–0.056° flags are float32 quaternion-norm noise, not a delta. `Bone_Hip` bob preserved: Godot **Y** range **0.33 m**, first/last `(0.005471, 3.511501, -0.009502)` (Blender Z maps to Godot Y under `export_yup=True`; §16's "Z-bob" wording is Blender space).
- **Speed decision:** `MechaClipRetarget.NATURAL_SPEED` stays **8.5** (not 9.189). The pose sequence and frame rate are unchanged; only the extrapolated tail was removed. All retarget/ingame checks pass at 8.5, so no recalibration or `STEP_FRACS` change was justified.
- **Godot verification (after `--headless --path . --import`):**
  - `test/unit/innerframe_rig_verify.tscn` — **10/10** (added clip-length + first==last seam regression; the original 8 checks still pass).
  - `test/unit/clip_retarget_verify.tscn` — **16/16** (leg 113.2°/113.1°, shin 122.4°, bob 0.325 m).
  - `test/unit/clip_ingame_verify.tscn` — **14/14** (clip_run, leg 113.3°, cadence/airtime/idle return intact).
  - `./run_tests.sh` — exit **0**; GUT still reports "Nothing was run" (standalone-scene configuration quirk).
- **Caveats:** headless verification only; interactive-window visual check of the seam remains outstanding. The stale live MCP Blender session was not saved (disk master is authoritative). Raw export cleanup: `scratch/innerframe_run_loopfix_raw.glb` and its `.import` deleted after post-processing.

---

## 18. Asset Session Note (2026-10-29): Live Blender 30-Frame Run-Cycle Integration — COMPLETE

- **Context & User Request:** User asked to replace the game's run animation with the active cycle playing in Blender (`RunCycle`, frames 0-29, 30 frames at 24 fps = 1.25s), inquiring whether bone adjustments were needed in Godot and whether model "blobbing" (squash/bob/stride bounce) carried over.
- **Architecture Invariants Confirmed:**
  - **No Rig Adjustments in Godot:** `MechaClipRetarget` uses modular Node3D kinematic retargeting; external meshes are freed at load (`_free_meshes(inst)`), and joint motions are mapped rest-relatively from canonical `MechaRig` bones.
  - **Bob / Stride Bounce Preserved:** Blender Armature Z-bobbing (-0.18m to +0.27m) is mapped into `Bone_Hip` translation and transferred to `body.position.y` at runtime.
- **Verification & Test Evidence (Godot 4.6.2.stable):**
  - `scenes/mecha/animations/innerframe_run_cycle_clean.glb`: 4,185,832 B, 176 nodes, 103 meshes, 57 joints, animation `run`, 31 keys per channel (1.2500 s).
  - `test/unit/innerframe_rig_verify.tscn`: **10/10 checks PASS (Exit 0)** (16/16 MechaRig bones present, 57 total joints, head 5.60m, 1.25s length, all 33 animated tracks first==last closed).
  - `test/unit/clip_retarget_verify.tscn`: **16/16 checks PASS (Exit 0)** (leg range 113.2°/112.3°, antiphase -1.00, knee 122.5°, arm 132.0°, hip bob 0.474m).
  - `test/unit/clip_ingame_verify.tscn`: **14/14 checks PASS (Exit 0)** (enters `clip_run`, 113.2° swing, cadence scaling, arm destroy resilience, stop-to-idle).
  - **Full Regression Runner:** 15 standalone verification scenes executed and passed with Exit Code 0 (0 failures).

---

## 19. Runtime & Kinematics Session Note (2026-10-29): Full 3D Torso Yaw/Roll Twist & Diagonal Arm Swing Retargeting — COMPLETE

- **User Feedback & Problem Analysis:**
  - User reported: "ทำไมมันขยับไม่เหมือนใน blender เลย body ไม่มีหมุนเลย แต่ใน blender body มันมีการหมุนทำให้แขนไม่ได้เหวี่ยงตรงๆ แต่มันจะมีเหวียงแนวเฉียงหลังไหน้า"
  - Root cause in `scripts/mecha/mecha_clip_retarget.gd`:
    1. `_apply_pose` was strictly "sagittal-only" (v1): `body.rotation.y` (Yaw twist) was never set (0.0), and `pivot.rotation.y` and `pivot.rotation.z` on arms were hard-clamped to `0.0`.
    2. In Blender, `Bone.001` (`Bone_Torso`) has active Yaw rotation (-6.8° to +11.1°, range ~21.5°) and Roll bank (-2.4° to +3.7°, range ~7.5°).
    3. In Blender, the arms swing diagonally from back-flared (`X ≈ 0.52`, `Z ≈ 0.75`) to forward across the chest (`X ≈ -0.23`, `Z ≈ 0.33`), forming a dynamic 3D arc.
- **Implementation & Mathematical Solution:**
  - **Torso 3D Transfer (`_apply_torso`):**
    - Preserves `pivot.rotation.x = swing * BODY_PITCH_SCALE` (pitch lean).
    - Computes delta quaternion `delta_q := rest_q.inverse() * pose_q` from `Bone_Torso` in `Skeleton3D`.
    - Transposes Euler angles: `pivot.rotation.y = delta_q.get_euler().y` (Yaw twist), `pivot.rotation.z = delta_q.get_euler().z` (Roll bank).
  - **Arm 3D Diagonal Transfer (`_apply_arm`):**
    - Instead of projecting onto 1D sagittal pitch and zeroing Y/Z, calculates full 3D direction vectors in skeleton space: `r_dir := _rest_dir(bone, child)` and `p_dir := _pose_dir(bone, child)`.
    - Applies shortest arc quaternion: `pivot.quaternion = Quaternion(r_dir, p_dir)`.
    - Perfectly reproduces the diagonal outward-flare and chest-cross swing without gimbal lock.
- **Verification & Test Evidence (Godot 4.6.2.stable):**
  - `test/unit/clip_retarget_verify.tscn`: **19/19 checks PASS (Exit 0)**:
    - `torso twists with stride (yaw range=21.5 deg)`: PASS
    - `torso banks with stride (roll range=7.5 deg)`: PASS
    - `arms swing diagonally (lateral range=145.1 deg)`: PASS
    - `arms pump (range=96.3 deg)`: PASS
    - `hip bob moves body (bob=0.475m)`: PASS
  - `test/unit/clip_ingame_verify.tscn`: **14/14 checks PASS (Exit 0)** (full in-game locomotion pipeline clean).
  - `test/unit/innerframe_rig_verify.tscn`: **10/10 checks PASS (Exit 0)**.
  - **Full Regression Runner:** 15/15 standalone verification scenes passed with Exit Code 0 (0 failures).

