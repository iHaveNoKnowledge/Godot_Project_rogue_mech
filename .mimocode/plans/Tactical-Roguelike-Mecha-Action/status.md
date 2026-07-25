# Tactical Roguelike Mecha Action — สถานะปัจจุบัน

## สรุปภาพรวม

โปรเจคอยู่ที่ `C:\Users\Satawad_Ta\Documents\GitHub\Godot_Project_rogue_mech`
ใช้ **Godot 4.3+** (GDScript)

---

## โครงสร้างไฟล์ปัจจุบัน

```
Godot_Project_rogue_mech/
├── autoload/
│   ├── event_bus.gd          # Signal hub
│   ├── global_data.gd        # Persistent data + save/load
│   └── game_manager.gd       # State machine (MENU→BOARD→COMBAT→...)
├── scripts/
│   ├── arena/                # NEW - Arena generation
│   │   └── arena_generator.gd
│   ├── mecha/                # 16 files
│   │   ├── mecha_controller.gd   # Movement + weight calc + dash
│   │   ├── mecha_combat.gd       # Combat + lock-on
│   │   ├── mecha_eject.gd        # Eject sequence
│   │   ├── mecha_health.gd       # Health system
│   │   ├── weapon_manager.gd     # L/R/Carry weapon slots + sound
│   │   ├── weapon_mount.gd       # Weapon mounting
│   │   ├── weapon_pickup.gd      # Loot pickup
│   │   ├── part_slot.gd          # Hitbox per part
│   │   ├── part_mesh_manager.gd  # Visual damage
│   │   ├── melee_attack.gd       # Melee combat
│   │   ├── mecha_hitbox.gd       # Hitbox detection
│   │   ├── enemy_dummy.gd        # Enemy FSM + archetypes
│   │   ├── enemy_health.gd       # Simple enemy HP
│   │   ├── enemy_health_full.gd  # Full 6-part enemy HP
│   │   └── ai/                   # NEW - AI state machine
│   │       ├── enemy_state_machine.gd
│   │       ├── enemy_state.gd
│   │       ├── enemy_attack_templates.gd
│   │       └── states/
│   │           ├── state_idle.gd
│   │           ├── state_chase.gd
│   │           ├── state_attack.gd
│   │           ├── state_flee.gd
│   │           ├── state_strafe.gd
│   │           └── state_charge.gd
│   ├── camera/camera_rig.gd
│   ├── pilot/
│   │   ├── pilot_controller.gd
│   │   └── pilot_interaction.gd
│   ├── board/
│   │   ├── board_manager.gd      # Board movement + tile effects
│   │   ├── board_generator.gd    # Procedural grid
│   │   └── board_tile.gd
│   ├── ui/                       # 11 files
│   │   ├── main_menu_controller.gd
│   │   ├── intermission_controller.gd
│   │   ├── hangar_controller.gd
│   │   ├── hud_controller.gd
│   │   ├── health_hud.gd
│   │   ├── weapon_hud.gd
│   │   ├── crosshair.gd
│   │   ├── enemy_status_ui.gd
│   │   ├── event_ui.gd
│   │   ├── safehouse_ui.gd
│   │   ├── combat_rewards_ui.gd
│   │   └── salvage_ui.gd
│   ├── systems/
│   │   ├── damage_calculator.gd
│   │   ├── heat_wanted_system.gd
│   │   ├── loot_system.gd
│   │   ├── salvage_system.gd
│   │   ├── safehouse_system.gd
│   │   └── projectile.gd         # + fired_by_enemy
│   └── effects/
│       ├── effect_manager.gd
│       └── melee_trail.gd
├── scripts/autoload/            # NEW - Audio system
│   ├── audio_manager.gd
│   └── audio_manager.tscn
├── scenes/                      # 23+ .tscn files
├── resources/mech/
│   ├── armor_part.gd
│   ├── chassis_data.gd
│   └── weapon_part.gd
└── shaders/
```

---

## Game Flow ปัจจุบัน

```
Main Menu
  ├── New Game → Board
  └── Continue (load save) → Board

Board (game_board.tscn)
  ├── Intermission UI (pause menu)
  │   ├── Mech Status
  │   ├── Inventory
  │   ├── Hangar (repair parts)
  │   ├── Save/Load
  │   └── Exit to Menu
  └── Move on Board → select tile
      ├── Combat (40%) → enter_combat() → game_world.tscn
      ├── Event (30%) → random rewards/damage
      ├── Safehouse (15%) → rest/repair
      └── Empty (15%) → nothing

Combat (game_world.tscn)
  ├── Arena generated (walls, tiles, pillars)
  ├── Waves of enemies (FSM-based AI)
  │   ├── Rusher: chase + melee
  │   ├── Ranged: strafe + shoot
  │   ├── Heavy: charge attack
  │   └── Support: heal allies
  ├── Kill all waves → CombatRewardsUI → return_to_board()
  └── Die → Defeat screen → Main Menu

Eject (X key)
  ├── Pilot spawns at EjectPoint
  ├── Camera follows pilot
  └── Find backup mech → board_backup_mech() → return to combat
```

---

## สิ่งที่ทำงานได้แล้ว

- **Phase 1**: Movement (WASD + mouse look), weight system, dash (Shift)
- **Phase 2**: 6-slot armor system, damage pipeline, part break + visual, persistent damage
- **Phase 3**: Eject (X), pilot controller, backup mech spawning
- **Phase 4**: Procedural board, tile movement, intermission UI, hangar, save/load
- **Combat**: 6 weapons (Beam Rifle, Machine Gun, Missile, Shotgun, Heat Blade, Pile Bunker), projectiles, lock-on
- **Arena**: Programmatic walls (120x120), tiled ground, corner pillars
- **Enemy AI**: FSM with 6 states (idle/chase/attack/flee/strafe/charge), 4 archetypes
- **Audio**: AudioManager autoload, procedural SFX (weapons, impacts, explosions, footsteps, dash, UI)
- **Balance**: Rebalanced all weapons for meaningful tradeoffs
- **Loot/Salvage**: Enemy drops, weapon pickup, carry system, salvage between runs
- **Heat/Wanted**: Heat accumulates from combat, wanted level scales enemy difficulty
- **UI**: HUD, health bars, weapon HUD, enemy status, event UI, safehouse UI, combat rewards

---

## Weapon Stats (Rebalanced)

| Weapon | DPS | Ammo | Weight | Range | Role |
|--------|-----|------|--------|-------|------|
| Beam Rifle | 71 | 40 | 8 | 55m | Mid-range sustained |
| Machine Gun | 75 | 250 | 5 | 80m | Suppression, light |
| Missile | 50 | 8 | 14 | 85m | Heavy alpha strike |
| Shotgun | 84 | 30 | 12 | 20m | Close range burst |
| Heat Blade | 125 | ∞ | 4 | 3m | Top DPS, extreme risk |
| Pile Bunker | 60 | ∞ | 15 | 4m | Anti-armor, slow |

---

## Enemy Archetypes

| Archetype | HP (simple/full) | Speed | Attack | Range |
|-----------|-------------------|-------|--------|-------|
| Rusher | 100/450 | 3.0 | Melee 20dmg/2s | 15m |
| Ranged | 60/300 | 4.0 | Projectile 15dmg/0.5s | 60m |
| Heavy | 200/800 | 1.5 | Charge 50dmg AoE | 10m |
| Support | 40/150 | 5.0 | Heal 5dps allies | 40m |

---

## สิ่งที่ควรทำต่อ (Remaining Phases)

### Track A: Arena
- [x] Phase 2: Cover objects + obstacles (destructible)
- [x] Phase 3: Atmosphere (fog, sky, lighting, particles)
- [x] Phase 14: Procedural arena variation (seed-based: 4 layouts)
- [x] Phase 15: Cover interaction polish

### Track B: AI
- [x] Phase 5: Enemy archetypes scenes (enemy_ranged.tscn, enemy_heavy.tscn, enemy_support.tscn)
- [x] Phase 6: NavMesh pathfinding (NavigationServer3D)
- [x] Phase 7: Spawn system + waves (5 waves, wanted scaling)
- [x] Phase 8: Enemy visual differentiation (color per archetype)

### Track C: Sound
- [x] Phase 10: Weapon sound integration
- [x] Phase 11: Impact + movement sounds (footstep, armor break, explosion)
- [x] Phase 12: Music + UI sounds + ambient (procedural combat music)

### Track D: Balance
- [x] Phase 14: Enemy HP + difficulty curve (wanted scaling revised)
- [x] Phase 16: Game flow polish + heat tuning (thresholds [4,7,11])

### ALL PHASES COMPLETE

---

## Git History ล่าสุด

| Commit | Description |
|--------|-------------|
| `ecc40ff` | feat: NavMesh pathfinding, procedural arenas, music, UI sounds |
| `db9ddf1` | feat: cover objects, atmosphere, enemy archetypes, spawn system, balance |
| `768d33f` | feat: arena environment, enemy AI state machine, audio system, weapon rebalance |
