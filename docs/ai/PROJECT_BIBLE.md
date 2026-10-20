# Valkren Project Bible & Core Development Rules

## 1. Project Overview & Identity
- **Project Name:** Valkren (Godot Project: `Godot_Project_rogue_mech`)
- **Engine Version:** **Godot 4.6.2.stable** (All GDScript, `.tscn`, `.tres` must strictly target Godot 4.6.2.stable).
- **Core Genre & Mechanics:** Modular 3rd-Person Roguelike Mecha Action with a Dual Strategic/Tactical Architecture.
  - **Strategic Layer:** Connected Node/Route Campaign Map inspired by *Crime Boss: Rockay City* and *FTL*. Decoupled from tactical cell grids.
  - **Tactical Layer:** 3D Combat Arena and tactical encounter grid (35x35 `BoardManager` / `BoardTile`).
- **Core Tenet & Survival Invariant:**
  - **Pilot Survival = Run Survival.**
  - Destruction of a mecha does NOT terminate the campaign run.
  - Pilots can eject or dismount, salvage, and dynamically board backup, fleet, or captured mechas.
  - Replacement mechas and frames must always remain accessible.

---

## 2. 3D Coordinate & Axis Standards (Godot & Blender)
- **Godot 4.6.2 Coordinate System (Right-Handed):**
  - **Forward:** `-Z` (`Vector3(0, 0, -1)`)
  - **Backward:** `+Z` (`Vector3(0, 0, 1)`)
  - **Up:** `+Y` (`Vector3(0, 1, 0)`)
  - **Right:** `+X` (`Vector3(1, 0, 0)`)
- **Blender 3D Authoring & Export:**
  - Forward-facing features (chest armor, visor, HUD, controls) must face **`+Y`** in Blender.
  - Rear features (bulkheads, backpack mounts) must face **`-Y`** in Blender.
  - Export to glTF/GLB with `export_yup=True` (maps Blender `+Y` to Godot `-Z`).

---

## 3. Engineering & Workflow Discipline
1. **Never Invent Features or Status:** Only report verified implementation and runtime facts.
2. **Never Confuse Headless Tests with Playability:** Automated test passing is a prerequisite, not proof of complete UX playability.
3. **Strict Authority Boundaries:** Never bypass subsystem managers or mutate global data directly to skip validation.
4. **Git Discipline:**
   - Commit changes with descriptive messages and push immediately when working on feature phases per `AGENTS.md`.
   - Never force push or revert uncommitted user work.
5. **Testing Harness:**
   - Every modification to `res://scripts/` requires a unit test in `res://test/unit/`.
   - Execute tests using Godot 4.6.2 console (`& 'D:\godot\Godot_v4.6.2-stable_win64_console.exe' --headless ...`).

---

## 4. Canonical Blender Assets & Mirror Discipline
- **Innerframe animation source:** `scratch/innerframe_animation_handmade.blend` (intentionally gitignored; the deployed copy lives in `scratch/`). The left side (`_L`) is the Master Reference; the right side (`_R`) is a strict X=0 mirror of it — no complex matrix-inversion tricks, only manual operational copies.
- **Mirror rule:** For every `_L`/`_R` pair, the world matrix must satisfy Q = Rw⁻¹·M4W·Lw ≈ identity with M4W = `Matrix.Diagonal((-1,1,1,1))` at every frame, and `_R`'s local mesh must equal the x-flip of `_L`'s local mesh vertex-for-vertex. Per-side accent materials (sage L / amber R) are by-design.
- **Verification discipline (lessons from the 2026-10-19 fix9 session):**
  - Use brute-force vertex comparison only: `mathutils.kdtree.KDTree.find()` returns `(co, index, dist)` and must never be read positionally as a distance.
  - Headless render symmetry checks must explicitly assign `sc.camera` and place the camera exactly on the mirror plane (x=0), not at the assembly center.
  - Read the `Machine snapshot`/canonical docs before Blender sessions: mirror plane is world x=0; the by-design f0 loop clearance of JointElbow/LinkLower/LinkUpper is not a defect.

---

## 5. Mecha Combat & Weapon Systems Architecture

### 5.1 Missile Lock-On System & Contention Resolution (Option A)
The missile targeting pipeline operates under a single active lock session authority managed by `MissileLockOnSystem` (`scripts/systems/missile_lock_on_system.gd`), referenced and coordinated through `WeaponManager` (`scripts/mecha/weapon_manager.gd`):
- **Single Active Session Authority:** Only one weapon slot may actively acquire or hold missile target locks at any time (`is_locking == true`, tracking `active_slot` and `active_weapon`).
- **Option A Contention Semantics:**
  - If a primary missile slot is actively acquiring/holding locks, triggering an independent secondary missile slot does not abort, cancel, or reset the active primary lock session.
  - Instead, the secondary slot attempts an immediate single dumbfire round via `_fire_dumbfire_missile(slot, weapon)` while the primary lock session continues undisturbed.
- **Same-Slot Debounce Protection:**
  - Triggering the *same* slot that is already actively locking is debounced and ignored (`return`), ensuring active lock states, targets, and elapsed hold durations are never accidentally reset or cleared by repeated trigger inputs.
- **Secondary Rejection Gate Isolation:**
  - If the secondary trigger attempt fails any standard weapon gating condition (e.g. empty magazine/salvo ammo exhaustion, ongoing reload cycle, fire cooldown, destroyed arm mounting, or capability restriction), the secondary firing is safely rejected without corrupting or cancelling the primary active lock session.
- **Lock-On Cancellation & Session Interruption Contracts:**
  - **Direct Cancellation Paths:** `cancel_locking()` explicitly resets lock session state (`is_locking = false`, clears `locked_targets` and `target_lock_progress`, and emits `lock_cleared`). Verified direct call sites in `WeaponManager` are:
    1. Weapon swap / slot-switch commit (`_cancel_lock_on_swap_commit`).
    2. Weapon drop from inventory selection (`_cancel_lock_if_dropped`).
    3. Destroyed-arm weapon drop (`drop_weapon_from_destroyed_arm` via `_cancel_lock_if_dropped`).
  - **Interruption & Rejection Gates:** Other session termination or firing suppression occurs via capability and lifecycle guards rather than direct `cancel_locking()` calls: ongoing reload cycles suppress firing via `_is_reloading(slot)` checks, and mecha destruction or pilot ejection invalidates node instances and fails pre-fire `is_instance_valid(mecha)` guards.

### 5.2 Missile Salvo & Ammunition Pricing Contracts
- **1:1 Salvo Ammunition Pricing:**
  - In `_fire_missile_salvo(slot, weapon)`, the weapon's core definition `ammo_per_shot` is temporarily overridden to `1` prior to salvo dispatch and restored immediately upon salvo cycle completion.
  - This ensures that multi-missile salvo pods (e.g. Swarm Missile arrays) consume exactly one unit of ammunition per launched missile round rather than draining full salvo ammo chunks per sub-projectile.
- **Mount Routing & Visual Muzzles:**
  - Left and right shoulder missile mountings are resolved through `_get_shoulder_muzzle_world_pos(slot)` with fallback to `FrameVariantResolver` socket positions.
  - Mount aliases (`shoulder_left` / `left_shoulder`, `shoulder_right` / `right_shoulder`) are normalized during weapon slot resolution.
  - Shoulder weapon firing updates state and triggers `shoulder_ammo_changed`.
- **Target Lock Capacity Bounds:**
  - Maximum acquired locks are strictly bounded by `min(weapon.max_locks, available_ammo)`.
  - Acquisition respects per-target saturation thresholds (max locks per target entity).
- **Trigger Hold Release Contracts:**
  - Short holds below the tap duration threshold trigger a single forward-projected dumbfire missile and reset lock tracking.
  - Sustained holds meeting or exceeding the threshold launch a guided homing missile salvo targeting all currently locked entities.

### 5.3 Arm Destruction & Weapon Drop Semantics
- **Slot Drop Isolation:**
  - When an arm suffers critical structural failure or destruction, `drop_weapon_from_destroyed_arm(hand)` is invoked on `WeaponManager`.
  - The affected hand slot (`left_arm` or `right_arm`) is unequipped, associated triggers and visual nodes are disconnected/cleaned up, and the weapon instance is dropped into the world.
- **Signal Sequencing & State Synchronization:**
  - Loadout data is synchronized, and the `weapon_switched` notification is emitted prior to `weapon_dropped` to maintain valid active weapon state across HUD and input listeners.
- **Opposite Slot Preservation:**
  - Destruction and weapon release on one arm never alters, drops, or interrupts the functional state of the opposite arm or mounted shoulder systems.

### 5.4 Weapon Subsystem Verification Standards
- **Targeted Regression & Unit Test Suites:**
  - Salvo execution and ammunition pricing: `test/unit/missile_salvo_execution_verify.tscn`
  - Cone sweep acquisition geometry and occlusion: `test/unit/missile_lock_cone_sweep_verify.tscn`
  - Dual-trigger contention and input rejection gates: `test/unit/missile_dual_trigger_contention_verify.tscn`
  - Tap versus sustained release mechanics: `test/unit/missile_lock_release_verify.tscn`
  - Target lock capacity limits: `test/unit/missile_lock_cap_verify.tscn`
  - Arm destruction and weapon drop side effects: `tests/mecha/weapon_drop_side_effects_verify.tscn`
- **Runner Registration:**
  - Verified regression test scenes are registered in `run_tests.sh` and run sequentially under Godot 4.6.2 headless mode to prevent test-order side effects and ensure strict zero-exit code validation.
