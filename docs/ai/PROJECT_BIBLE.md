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
