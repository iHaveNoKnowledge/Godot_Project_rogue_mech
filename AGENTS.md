# Agent Skills & Project Rules

## 🛠 Project Environment

* **Game Engine:** This project is developed using **Godot 4.6.2.stable**.
* All GDScript code, as well as `.tscn` and `.tres` configuration files, must be fully compatible with **Godot 4.6.2.stable** only.

## 🔄 Workflow & Git

* **Commit & Push:** Each time you modify code or add a new feature, create a **Git commit** with a clear and descriptive message, then **push the changes to GitHub immediately**.

## ✅ Quality Assurance

* **Testing:** Before considering any task complete, ensure that all implemented functions work as intended.
* Whenever possible, create and/or run appropriate test cases to validate the correctness of the implementation before delivering the work.

## 📐 3D Coordinate & Axis Standards (Blender & Godot)

* **Godot 4.6.2 Right-Handed System:**

  * **Forward:** `-Z` (Chest / Face / Forward Movement vector: `Vector3(0, 0, -1)`)
  * **Backward:** `+Z` (Backpack / Spine / Rear Wall: `Vector3(0, 0, 1)`)
  * **Up:** `+Y` (`Vector3(0, 1, 0)`)
  * **Right:** `+X` (`Vector3(1, 0, 0)`)
* **Blender 3D Authoring & Export Rules:**

  * In Blender, forward-facing features (chest armor, face visor, HUD, controls) must be authored facing **`+Y`**.
  * Rear features (bulkheads, backpack mounts, headrest) must be authored facing **`-Y`**.
  * When exporting to glTF/GLB from Blender, always use `export_yup=True`. Blender's exporter maps `+Y -> -Z` (Forward in Godot) and `-Y -> +Z` (Backward in Godot).
  * **CRITICAL RULE:** NEVER author front-facing features towards Blender `-Y`, as this will invert them in Godot, causing them to face backward towards the backpack!



  # OpenCode Harness Rules for Godot 4

  1. Whenever you write or modify GDScript in `res://scripts/`, always create or update a Unit Test in `res://test/unit/`.
  2. After completing code modifications, always run the command `./run_tests.sh` through the Terminal.
  3. If the tests fail (Exit code != 0), check the Error Log and revise the code until all tests pass.

## 🧠 Calibrated Judgment (jev)

* Use `jev` (TypeSafe System One) for judgments it is built for — never for generation, math, counting, or multi-hop reasoning, which stay in code/your own reasoning:
  * repeated classify/filter/rank/dedupe over many items (`jev rank` / `jev batch`),
  * a calibrated probability gate before acting on your own confidence (act/confirm/escalate),
  * an independent check of your own output (claim vs source, draft vs rule, tool call vs intent, untrusted text vs prompt injection),
  * any unattended judgment a script must make with no agent loop.
* One narrow judgment per question; state the exact condition literally; thresholds scale with risk (read-only ~0.6, destructive ~0.9).
* Invoke via `python "C:\Users\hackd\.local\bin\jev" <command>` (bare `jev` does not execute in PowerShell).
