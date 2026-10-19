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
