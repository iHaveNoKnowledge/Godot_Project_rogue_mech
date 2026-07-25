# Tactical Roguelike Mecha Action 3rd-Person — Implementation Plan

## 0. Current State

- **Engine**: Godot 4.3+ (GDScript)
- **Assets**: Placeholder meshes only (Primitives: Capsule, Box, Sphere)
- **Approach**: Phase 1 first, then continue phase-by-phase
- **Repository**: Empty — no Godot project exists yet

---

## 1. Architecture Overview

### Folder Structure
```
res://
├── project.godot
├── autoload/
│   ├── global_data.gd          # Persistent cross-scene state
│   ├── event_bus.gd            # Centralized signal hub
│   └── game_manager.gd         # Top-level state machine
├── resources/
│   ├── mech/
│   │   ├── armor_part.gd       # Resource: armor stats
│   │   ├── weapon_part.gd      # Resource: weapon stats
│   │   ├── chassis_data.gd     # Resource: base chassis
│   │   └── stock/              # .tres instances
│   ├── board/
│   │   ├── tile_data.gd        # Resource: tile type/info
│   │   └── stock/
│   └── events/
│       ├── random_event.gd
│       └── stock/
├── scenes/
│   ├── main_menu/main_menu.tscn
│   ├── game_world.tscn          # Persistent root
│   ├── board/
│   │   ├── game_board.tscn
│   │   └── board_tile.tscn
│   ├── mecha/
│   │   ├── mecha_base.tscn     # Full mecha assembly
│   │   └── effects/
│   ├── pilot/pilot.tscn
│   ├── camera/mecha_camera.tscn
│   ├── ui/
│   │   ├── hud.tscn
│   │   ├── hangar_ui.tscn
│   │   ├── board_ui.tscn
│   │   └── components/
│   └── world/
│       ├── combat_arena.tscn
│       └── safehouse_interior.tscn
├── scripts/
│   ├── mecha/ (controller, combat, damage, eject, part_slot, part_mesh_manager)
│   ├── camera/ (camera_rig, camera_state)
│   ├── pilot/ (pilot_controller, pilot_interaction)
│   ├── board/ (board_generator, board_tile, board_manager)
│   ├── ui/ (hud_controller, hangar_controller, board_ui_controller)
│   └── systems/ (damage_calculator, heat_wanted_system, safehouse_system, backup_mech_spawner)
└── shaders/
```

### Core Autoloads

1. **`global_data.gd`** — Pure data container. Stores `equipped_parts` (slot → ArmorPart resource), `part_damage` (slot → float 0-1), board state, inventory, heat. JSON save/load for debuggability.

2. **`event_bus.gd`** — All cross-system signals. Damage pipeline (`damage_received`, `armor_degraded`, `part_destroyed`), weight (`weight_changed`), camera (`camera_mode_changed`, `lock_on_target_acquired`), eject (`eject_initiated`, `pilot_spawned`), board (`tile_entered`, `heat_changed`).

3. **`game_manager.gd`** — State enum: `MENU, BOARD, COMBAT, SAFEHOUSE, HANGAR, EJECT, PILOT`. Transitions emit `game_state_changed`.

### Key Design Decisions

- **Weight is emergent**: Computed from equipped parts minus broken parts. Breaking armor immediately makes the mecha faster (risk/reward).
- **EventBus decoupling**: All cross-system communication through signals. Never poll.
- **Resource-driven data**: All part stats, tile types, events in `.tres` files. Enables hangar UI and weighted random pools.
- **Composition over inheritance**: MechaBase composes PartSlot nodes. Parts are Resources, not subclasses.
- **Camera state machine**: 4 modes (exploration, combat, eject, board) via `CameraState` node hierarchy.

---

## 2. Input Map (project.godot)

| Action | Key |
|--------|-----|
| move_forward | W |
| move_back | S |
| move_left | A |
| move_right | D |
| strafe | Left Shift |
| aim | Right Mouse Button |
| jump | Space |
| interact | E |
| eject | X |
| pause | Escape |
| camera_unlock | Tab (toggle mouse capture) |

---

## 3. Scene Hierarchies

### mecha_base.tscn
```
MechaBase (CharacterBody3D) — mecha_controller, mecha_combat, mecha_damage, mecha_eject
├── CollisionShape3D (CapsuleShape3D)
├── MeshInstance3D (placeholder)
├── Skeleton3D
│   ├── BoneAttachment3D_Head [part_slot] "head"
│   │   └── Area3D + CollisionShape3D
│   ├── BoneAttachment3D_Body [part_slot] "body"
│   │   └── Area3D
│   ├── BoneAttachment3D_ArmLeft / ArmRight / LegLeft / LegRight
│   │   └── Area3D each
├── PartMeshManager (Node3D) — 6x MeshInstance3D (armor + inner frame per slot)
├── AimRay (RayCast3D, distance=50)
├── WeaponMount (Node3D)
└── EjectPoint (Node3D, position ahead of cockpit)
```

### mecha_camera.tscn
```
CameraRig (Node3D) — camera_rig, camera_state
├── CameraPivot (Node3D)
│   ├── SpringArm3D (spring_length=5, collision_mask=1)
│   │   └── Camera3D
│   └── AimOffset (Node3D)
└── LockOnRay (RayCast3D, distance=100)
```

### pilot.tscn
```
Pilot (CharacterBody3D) — pilot_controller, pilot_interaction
├── CollisionShape3D (CapsuleShape3D, h=1.8, r=0.3)
├── MeshInstance3D (placeholder capsule)
└── InteractArea (Area3D, SphereShape3D r=2.0)
```

---

## 4. Implementation Plan — Phase 1: 3rd Person Mecha Controller

### Step 1: Project Setup
- Create `project.godot` with Godot 4.x, set main scene, configure input map
- **File**: `project.godot` — Complexity: S

### Step 2: Autoloads (Stubs)
- `global_data.gd` — Basic dict storage, save/load skeleton
- `event_bus.gd` — All signal declarations
- `game_manager.gd` — State enum, transition_to()
- **Files**: 3x `.gd` — Complexity: S each

### Step 3: Resource Classes
- `armor_part.gd` — class_name ArmorPart, exports: part_name, slot_id, mesh_scene, inner_frame_scene, max_hp, weight, armor_class, break_threshold, icon
- `chassis_data.gd` — class_name ChassisData, exports: chassis_name, base_speed, base_turn_rate, weight_capacity, slot_layout, eject_pilot_scene, chassis_mesh
- **Files**: 2x `.gd` — Complexity: S each

### Step 4: Mecha Base Scene + Movement
- Create `mecha_base.tscn` with CharacterBody3D, CollisionShape3D, placeholder MeshInstance3D
- `mecha_controller.gd` — Movement input, weight calculation, `lerp_angle` rotation for inertia, strafe mode
- Weight formula: `speed = base_speed * (1.0 - clamp(weight/capacity, 0, 0.6))`
- Turn formula: `turn_rate = base_turn_rate * (capacity / max(weight, 1.0))`
- **Files**: 1x `.tscn` + 1x `.gd` — Complexity: M

### Step 5: Camera System
- Create `mecha_camera.tscn` — Node3D > CameraPivot > SpringArm3D > Camera3D
- `camera_rig.gd` — Mouse input (captured mode), yaw/pitch with `lerp_angle`, pitch clamping
- `camera_state.gd` — Base class + ExplorationState (free look) + CombatState (lock-on raycast)
- SpringArm3D handles camera collision automatically
- **Files**: 1x `.tscn` + 2x `.gd` — Complexity: M

### Step 6: Combat (Aim + Lock-on)
- `mecha_combat.gd` — Aim from camera via RayCast3D, soft lock-on to enemies, force strafe when aiming, `lerp_angle` to face aim direction
- **Files**: 1x `.gd` — Complexity: M

### Step 7: World Scene
- `game_world.tscn` — Root Node3D with WorldEnvironment, DirectionalLight3D, MechaCamera instance
- `damage_calculator.gd` — Static functions for damage/weight calculations
- **Files**: 1x `.tscn` + 1x `.gd` — Complexity: S

### Phase 1 Milestone: Mecha moves in 3D, mouse controls camera, weight affects speed, aim ray + lock-on works.

---

## 5. Implementation Plan — Phase 2: 3D Part Break & Persistent Damage

### Step 8: Part Slot System
- `part_slot.gd` — Extends BoneAttachment3D, owns Area3D hitbox, `take_damage()` with armor_class reduction, break detection, emits EventBus signals
- Update `mecha_base.tscn` with Skeleton3D + 6 BoneAttachment3D + Area3D hitboxes
- **Files**: 1x `.gd` + 1x `.tscn` update — Complexity: M

### Step 9: Mesh Manager
- `part_mesh_manager.gd` — Manages armor + inner frame meshes per slot, swaps on break, spawns break VFX
- `vfx_armor_break.tscn` — GPUParticles3D for armor break effect
- `vfx_spark.tscn` — Hit spark particles
- **Files**: 1x `.gd` + 2x `.tscn` — Complexity: M

### Step 10: Damage Pipeline
- `mecha_damage.gd` — Orchestrates signal flow from part_slot through EventBus
- Update `global_data.gd` with full `part_damage` persistence (save/load)
- Create 6x ArmorPart `.tres` files with varying stats
- `weapon_part.gd` — Weapon resource class
- **Files**: 1x `.gd` + 1x `.gd` update + 6x `.tres` + 1x `.gd` — Complexity: M

### Step 11: Damage Visuals
- `damage_overlay.gdshader` — Screen-space damage vignette
- `armor_crack.gdshader` — Albedo darkening on damaged parts
- **Files**: 2x `.gdshader` — Complexity: S

### Phase 2 Milestone: Shoot individual parts, HP per slot, armor breaks revealing inner frame, weight drops, damage persists.

---

## 6. Implementation Plan — Phase 3: Eject & Drop Mechanics

### Step 12: Eject System
- `mecha_eject.gd` — Eject sequence: disable mecha, spawn pilot, camera transition
- `backup_mech_spawner.gd` — Team logic: nearby spawn vs edge spawn, `RigidBody3D` falling capsule
- **Files**: 2x `.gd` — Complexity: M

### Step 13: Pilot Controller
- `pilot.tscn` + `pilot_controller.gd` — 3rd person movement, gravity, jump
- `pilot_interaction.gd` — Area3D proximity for backup mech detection, interact input
- **Files**: 1x `.tscn` + 2x `.gd` — Complexity: M

### Step 14: Camera Eject State
- Update `camera_state.gd` with EjectState — Fixed follow camera for pilot, smooth transition
- **Files**: 1x `.gd` update — Complexity: M

### Step 15: Escape Zone
- `safehouse_system.gd` — Area3D border detection, save data, return to board
- **Files**: 1x `.gd` — Complexity: M

### Phase 3 Milestone: Press eject → pilot spawns, walk to backup mecha, board it, escape zone works.

---

## 7. Implementation Plan — Phase 4: Procedural 3D Board & Management

### Step 16: Board Resources
- `tile_data.gd` — TileData resource (EMPTY/COMBAT/EVENT/SAFEHOUSE)
- `random_event.gd` — RandomEvent resource (name, type, weight, choices)
- 3x tile `.tres` + 3x event `.tres`
- **Files**: 2x `.gd` + 6x `.tres` — Complexity: S

### Step 17: Board Generation
- `board_generator.gd` — Grid-based random generation, type distribution (40% combat, 30% event, 15% safehouse, 15% empty), shuffle
- `board_tile.gd` — Click handling, adjacency highlight, visual state
- **Files**: 2x `.gd` — Complexity: L

### Step 18: Board Manager
- `board_manager.gd` — Token movement, tile processing, event dispatch
- `game_board.tscn` + `board_tile.tscn` — Board scene with camera, tiles, token
- **Files**: 1x `.gd` + 2x `.tscn` — Complexity: M

### Step 19: Heat & Wanted System
- `heat_wanted_system.gd` — Heat decay per move, wanted thresholds, signal emission
- **Files**: 1x `.gd` — Complexity: M

### Step 20: Hangar UI
- `hangar_ui.tscn` + `hangar_controller.gd` — Part grid, stats panel, repair buttons, assembly validation, weight display
- **Files**: 1x `.tscn` + 1x `.gd` — Complexity: L

### Step 21: Board UI + HUD
- `board_ui.tscn` + `board_ui_controller.gd` — Click-to-move, adjacency validation
- `hud.tscn` + `hud_controller.gd` — HP bars per slot, heat gauge, wanted stars
- `main_menu.tscn` — New game, continue, quit
- **Files**: 3x `.tscn` + 3x `.gd` — Complexity: M

### Phase 4 Milestone: Random board, click to move, combat/event/safehouse tiles trigger scenes, heat rises, hangar for repair/assembly.

---

## 8. Key Godot 4 API Notes

| Feature | API |
|---------|-----|
| 3rd person movement | `CharacterBody3D.move_and_slide()` (no delta arg in Godot 4) |
| Camera collision | `SpringArm3D` (set spring_length, collision_mask) |
| Bone attachment | `BoneAttachment3D` (set bone_name property) |
| Hitbox detection | `Area3D.area_entered` signal |
| Angle interpolation | `lerp_angle(from, to, weight)` global function |
| Mouse capture | `Input.MOUSE_MODE_CAPTURED` / `MOUSE_MODE_VISIBLE` |
| JSON persistence | `FileAccess.open()` + `JSON.stringify/parse_string` |
| Raycast | `RayCast3D.is_colliding()` / `get_collider()` |
| Scene loading | `ResourceLoader.load_threaded_request(path)` |

---

## 9. Verification Plan

### Phase 1 Verification
1. Open project in Godot 4, run main scene
2. WASD movement works, mecha moves on ground
3. Mouse rotates camera 360 degrees, SpringArm3D prevents wall clipping
4. Heavy armor (equip heavy parts) → slower turn, slower movement
5. Light armor → fast turn, fast movement
6. Right-click aim → mecha faces camera direction, strafe mode activates
7. Lock-on ray detects enemies in scene

### Phase 2 Verification
1. Shoot different body parts → separate HP bars decrease
2. Armor at 0 HP → mesh hides, inner frame shows, break VFX plays
3. Weight drops after armor break → mecha moves faster
4. Reload scene → damage persists from GlobalData
5. Armor crack shader darkens damaged surfaces

### Phase 3 Verification
1. Press X → mecha vanishes, pilot spawns at EjectPoint
2. Camera follows pilot in 3rd person
3. Pilot walks to backup mecha (falling capsule), presses E → boards mecha
4. New mecha activates, camera returns to combat mode
5. Walk to red border → save triggers, return to board

### Phase 4 Verification
1. Board generates random 8x8 grid with mixed tile types
2. Click adjacent tile → token moves, tile effect triggers
3. Combat tile → loads combat arena
4. Safehouse tile → heat decreases
5. Combat victories → heat increases → wanted level rises
6. Hangar UI → swap parts, repair broken parts, weight updates in real-time
7. Save/load persists board state across sessions
