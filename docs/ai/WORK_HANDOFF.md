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
