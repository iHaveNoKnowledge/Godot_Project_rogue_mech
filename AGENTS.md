# Agent Skills & Project Rules

## 🛠 Project Environment

* **Game Engine:** This project is developed using  **Godot 4.6.2.stable** .
* All GDScript code, as well as `.tscn` and `.tres` configuration files, must be fully compatible with **Godot 4.6.2.stable** only.

## 🔄 Workflow & Git

* **Commit & Push:** Every time code is modified or a new feature is added, create a **Git commit** with a clear and descriptive commit message, then  **push the changes to GitHub immediately** .

## ✅ Quality Assurance

* **Testing:** Before considering any task complete, verify that all implemented functions work as intended.
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
  * **CRITICAL RULE:** NEVER author front-facing features towards Blender `-Y`, as it will invert in Godot and face backward towards the backpack!

