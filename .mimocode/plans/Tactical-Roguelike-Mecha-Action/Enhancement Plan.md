# Rogue Mech Enhancement Plan — Arena, AI, Sound, Balance

## สรุป

โปรเจค Godot 4.3+ ที่ `C:\Users\Satawad_Ta\Documents\GitHub\Godot_Project_rogue_mech`
ต้องการปรับปรุง 4 ด้าน: Game World, Enemy AI, Sound System, Balance

---

## สถานะปัจจุบัน

| ด้าน | สถานะ |
|------|-------|
| Game World | 200x200 flat green box, 1 DirectionalLight, procedural sky gradient, ไม่มี arena/walls/cover |
| Enemy AI | มีแค่ melee rusher (chase + attack), ไม่มี state machine, ไม่มี ranged, ไม่มี pathfinding |
| Sound | ไม่มีเสียงเลย — ไม่มีไฟล์ audio, ไม่มี AudioStreamPlayer, ไม่มี audio directory |
| Balance | Weapon DPS 53-120, Player 690HP, Enemy 450HP, Heat max 15 |

---

## Phase 1: Arena Boundary + Ground Tiles (M)

**เป้าหมาย**: แทนที่ flat green box ด้วย arena ที่มีกำแพง + พื้นหลากสี

**สร้างไฟล์**:
- `scripts/arena/arena_generator.gd` — สร้างกำแพง + พื้น tile อัตโนมัติ
- `scenes/arena/arena_boundary.tscn` — กำแพง 4 ด้าน + เสา 4 มุม

**แก้ไขไฟล์**:
- `scenes/game_world.tscn` — ลบ Ground เดิม, เพิ่ม arena_boundary
- `autoload/event_bus.gd` — เพิ่ม signal `arena_generated`

**รายละเอียด**:
- กำแพง 120x120 สูง 8m (BoxMesh 4×10×4 ที่มุม)
- พื้น tile 10x10 (แต่ละ tile 12x12 หน่วย) สีเทา/เขียว vary ±5%
- Collision บน physics layer 2 (Environment)

**Complexity**: M | **Dependencies**: ไม่มี

---

## Phase 2: Cover Objects + Obstacles (M)

**เป้าหมาย**: เพิ่ม cover สำหรับ tactical gameplay

**สร้างไฟล์**:
- `scripts/arena/cover_object.gd` — StaticBody3D ที่มี HP, armor_class, ทำลายได้
- `scripts/arena/obstacle_spawner.gd` — วาง cover ตาม pattern
- `resources/arena/arena_layout.gd` — Resource class สำหรับ arena layout
- `resources/arena/stock_arena.tres` — Default layout

**Cover Types**:
| Type | Mesh | HP | ขนาด |
|------|------|----|------|
| Concrete Barrier | BoxMesh(3×1.5×0.5) | 200 | สั้น กว้าง |
| Crate Stack | BoxMesh(2×3×2) | 150 | สูง |
| Pillar | CylinderMesh(r=0.8, h=6) | 300 | กลม |
| Destroyable Crate | BoxMesh(1.5×1.5×1.5) | 80 | เล็ก |

**แก้ไขไฟล์**:
- `scenes/game_world.tscn` — เพิ่ม obstacle_spawner
- `autoload/event_bus.gd` — เพิ่ม signal `cover_destroyed`

**Complexity**: M | **Dependencies**: Phase 1

---

## Phase 3: Atmosphere (S)

**เป้าหมาย**: เพิ่ม fog, แสง, ambient particles

**สร้างไฟล์**:
- `scripts/arena/atmosphere_manager.gd` — จัดการ WorldEnvironment

**แก้ไขไฟล์**:
- `scenes/game_world.tscn` — เปิด volumetric fog, เปลี่ยน sky สีเข้ม, เพิ่ม OmniLight3D 2 ดวง, เพิ่ม GPUParticles3D (dust motes)

**Atmosphere**:
- Fog: density 0.02, สีเทาเข้ม
- Sky: top #1a1a3e, horizon #3a3a4a
- Light: DirectionalLight สี #e8dcc8 energy 0.8 + OmniLight สีส้ม 2 ดวง
- Particles: 200 dust motes เล็กๆ ลอยช้าๆ

**Complexity**: S | **Dependencies**: Phase 1

---

## Phase 4: Enemy State Machine (M)

**เป้าหมาย**: แทนที่ linear chase ด้วย proper FSM

**สร้างไฟล์**:
- `scripts/mecha/ai/enemy_state_machine.gd` — จัดการ current state
- `scripts/mecha/ai/enemy_state.gd` — Base class (enter/exit/physics_process)
- `scripts/mecha/ai/states/state_idle.gd` — ยืนนิ่ง, scan target
- `scripts/mecha/ai/states/state_chase.gd` — เดินเข้าหา target
- `scripts/mecha/ai/states/state_attack.gd` — โจมตี (melee/ranged)
- `scripts/mecha/ai/states/state_flee.gd` — หนีเมื่อ HP ต่ำ

**แก้ไขไฟล์**:
- `scripts/mecha/enemy_dummy.gd` — ใช้ state machine แทน inline chase
- `scripts/mecha/enemy_health.gd` — เพิ่ม `reached_low_hp` signal
- `scripts/mecha/enemy_health_full.gd` — เหมือนกัน

**State Flow**:
```
Idle → (target detected) → Chase → (in range) → Attack
  Chase → (low HP) → Flee → (cover reached) → Idle
  Attack → (target out of range) → Chase
```

**Complexity**: M | **Dependencies**: ไม่มี (ทำคู่กับ Phase 1-3 ได้)

---

## Phase 5: Enemy Archetypes (L)

**เป้าหมาย**: เพิ่ม 4 enemy types ที่มี behavior ต่างกัน

**สร้างไฟล์**:
- `scripts/mecha/ai/states/state_strafe.gd` — Ranged enemy circle-strafe
- `scripts/mecha/ai/states/state_charge.gd` — Heavy enemy charge attack
- `scripts/mecha/ai/enemy_attack_templates.gd` — Attack patterns per archetype
- `scenes/mecha/enemy_ranged.tscn` — Ranged enemy (60-300 HP, ยิง projectile)
- `scenes/mecha/enemy_heavy.tscn` — Heavy enemy (200-800 HP, charge)
- `scenes/mecha/enemy_support.tscn` — Support enemy (40-150 HP, heal allies)

**Enemy Archetypes**:
| Archetype | HP (simple/full) | Speed | Attack | Range | Special |
|-----------|-------------------|-------|--------|-------|---------|
| Rusher | 100/450 | 3.0 | Melee 20dmg/2s | 15m | Chase + melee |
| Ranged | 60/300 | 4.0 | Projectile 15dmg/0.5s | 60m | Strafe + shoot |
| Heavy | 200/800 | 1.5 | Charge 50dmg AoE | 10m | Charge + stun self |
| Support | 40/150 | 5.0 | Heal 5dps allies | 40m | Heal + flee |

**แก้ไขไฟล์**:
- `scripts/mecha/enemy_dummy.gd` — เพิ่ม `archetype` enum
- `scripts/mecha/enemy_health.gd` — เพิ่ม `take_heal(amount)`
- `scripts/systems/projectile.gd` — เพิ่ม `fired_by_enemy` flag

**Complexity**: L | **Dependencies**: Phase 4

---

## Phase 6: NavMesh Pathfinding (M)

**เป้าหมาย**: Enemy เดินอ้อม obstacle แทนเดินชน

**สร้างไฟล์**:
- `scripts/arena/arena_nav_setup.gd` — สร้าง NavigationRegion3D + NavigationMesh

**แก้ไขไฟล์**:
- `scenes/game_world.tscn` — เพิ่ม NavigationRegion3D เป็น root container
- `scripts/arena/arena_generator.gd` — เรียก nav setup หลังสร้าง obstacle
- `scripts/mecha/ai/states/state_chase.gd` — ใช้ NavigationServer3D.map_get_path()
- `scripts/mecha/ai/states/state_flee.gd` — ใช้ pathfinding หนี

**NavigationMesh**: cell_size=0.5, agent_radius=2.0, agent_height=6.0

**Complexity**: M | **Dependencies**: Phase 2 (obstacles), Phase 4 (state machine)

---

## Phase 7: Spawn System + Waves (L)

**เป้าหมาย**: แทนที่ hardcoded enemies ด้วย wave-based spawning

**สร้างไฟล์**:
- `scripts/systems/spawn_manager.gd` — จัดการ spawning, wave timing, death tracking
- `scripts/systems/spawn_point.gd` — Marker3D spawn points
- `resources/enemy/wave_data.gd` — Resource class สำหรับ wave definitions
- `resources/enemy/stock_waves.tres` — 5 waves ของ escalating difficulty

**Wave Definitions**:
| Wave | Enemies | Notes |
|------|---------|-------|
| 1 | 3x Rusher (simple) | Tutorial feel |
| 2 | 2x Rusher + 1x Ranged | เพิ่ม ranged |
| 3 | 1x Rusher (full) + 2x Ranged + 1x Support | เริ่มมี support |
| 4 | 2x Rusher (full) + 1x Heavy + 1x Ranged | Heavy ตัวแรก |
| 5 | 1x Heavy (1.5x HP) + 2x Support + 2x Ranged | Boss wave |

**แก้ไขไฟล์**:
- `scenes/game_world.tscn` — ลบ 2 EnemyDummyHardcoded, เพิ่ม SpawnManager + 8 SpawnPoints
- `autoload/global_data.gd` — เพิ่ม current_wave, total_waves
- `autoload/event_bus.gd` — เพิ่ม wave_started, wave_completed, all_waves_cleared
- `scripts/game_manager.gd` — เริ่ม spawn system ใน enter_combat()

**Complexity**: L | **Dependencies**: Phase 1, 4, 5

---

## Phase 8: Enemy Visual Differentiation (S)

**เป้าหมาย**: แต่ละ archetype มีสี/ทรงต่างกัน

**สีที่ใช้**:
| Archetype | Primary | Accent |
|-----------|---------|--------|
| Rusher | Dark orange #8B4513 | Yellow |
| Ranged | Steel blue #4682B4 | Cyan |
| Heavy | Dark red #8B0000 | Orange glow |
| Support | Olive green #556B2F | White cross |

**แก้ไขไฟล์**:
- `scripts/mecha/enemy_dummy.gd` — ใช้สีตาม archetype ใน `_ready()`

**Complexity**: S | **Dependencies**: Phase 5

---

## Phase 9: Audio Bus + AudioManager (M)

**เป้าหมาย**: สร้าง audio infrastructure

**สร้างไฟล์**:
- `scripts/autoload/audio_manager.gd` — Autoload singleton, SFX pool 16 ตัว, music crossfade
- `scripts/autoload/audio_manager.tscn`

**Audio Bus Layout**:
```
Master
├── SFX
│   ├── Weapons
│   ├── Impacts
│   ├── Movement
│   └── UI
├── Music
└── Ambient
```

**แก้ไขไฟล์**:
- `project.godot` — เพิ่ม AudioManager autoload

**Complexity**: M | **Dependencies**: ไม่มี

---

## Phase 10: Weapon SFX (S)

**เป้าหมาย**: ทุก weapon fire มีเสียง

**สร้างไฟล์**:
- `scripts/audio/weapon_sounds.gd` — สร้าง AudioStreamWAV จาก waveform
- `scripts/audio/sound_templates.gd` — weapon_type → {stream, volume, bus}

**Procedural Sounds** (ไม่ต้องมีไฟล์ audio):
- Beam Rifle: sine sweep 200→800Hz 0.15s
- Machine Gun: white noise burst 0.05s
- Missile: deep sine 100Hz + noise 0.3s
- Shotgun: noise burst 0.1s
- Melee: sine chop 0.08s

**แก้ไขไฟล์**:
- `scripts/mecha/weapon_manager.gd` — เรียก AudioManager.play_sfx() หลัง fire

**Complexity**: S | **Dependencies**: Phase 9

---

## Phase 11: Impact + Movement Sounds (S)

**เป้าหมาย**: Hit, destroy, footstep, ambient sounds

**สร้างไฟล์**:
- `scripts/audio/impact_sounds.gd` — metal ping, armor break, explosion
- `scripts/audio/movement_sounds.gd` — footstep rhythm
- `scripts/audio/ambient_generator.gd` — low drone + wind

**Sound Events**:
| Event | Sound | Location |
|-------|-------|----------|
| Projectile hit armor | Metallic ping | projectile.gd |
| Armor break | Sharp crack | mecha_health_base.gd |
| Frame hit | Dull thud | mecha_health_base.gd |
| Part destroyed | Heavy crunch | mecha_health_base.gd |
| Footstep | Alternating pitch | mecha_animation.gd |

**แก้ไขไฟล์**:
- `scripts/mecha/mecha_health_base.gd` — เรียก sound ทุก damage milestone
- `scripts/systems/projectile.gd` — เล่น impact sound
- `scripts/mecha/enemy_dummy.gd` — เล่น footstep ทุก 0.5s ขณะเดิน

**Complexity**: S | **Dependencies**: Phase 9

---

## Phase 12: Music + UI Sounds (M)

**เป้าหมาย**: Background music, UI sounds, ambient loop

**สร้างไฟล์**:
- `scripts/audio/music_generator.gd` — Procedural music ด้วย AudioStreamGenerator (120 BPM, bass/mid/hi layers)
- `scripts/audio/ui_sounds.gd` — Click, hover, confirm sounds
- `scripts/audio/audio_settings.gd` — Save/load volume preferences

**แก้ไขไฟล์**:
- `autoload/event_bus.gd` — เพิ่ม `combat_intensity_changed`
- `scripts/game_manager.gd` — Emit intensity 1.0/0.0
- `scripts/ui/main_menu_controller.gd` — เล่น UI sounds

**Complexity**: M | **Dependencies**: Phase 9

---

## Phase 13: Weapon Balance Pass (M)

**เป้าหมาย**: ปรับ weapon stats ให้มี meaningful tradeoffs

**Rebalanced Weapon Stats**:
| Weapon | Damage | Fire Rate | DPS | Ammo | Weight | Range |
|--------|--------|-----------|-----|------|--------|-------|
| Beam Rifle | 25 | 0.35s | **71** | 40 | 8 | 55m |
| Machine Gun | 6 | 0.08s | **75** | 250 | 5 | 80m |
| Missile | 100 | 2.0s | **50** | 8 | 14 | 85m |
| Shotgun | 12×7 | 1.0s | **84** | 30 | 12 | 20m |
| Heat Blade | 50 | 0.4s | **125** | ∞ | 4 | 3m |
| Pile Bunker | 120 | 2.0s | **60** | ∞ | 15 | 4m |

**DPS Tiers**:
- Close risk/reward: Heat Blade (125) > Shotgun (84)
- Mid sustained: Machine Gun (75) > Beam Rifle (71)
- Heavy melee: Pile Bunker (60, but 120 per hit breaks armor fast)

**แก้ไขไฟล์**:
- `resources/mech/stock/weapon_*.tres` (6 files) — แก้ค่า stats
- `scripts/systems/damage_calculator.gd` — เพิ่ม weapon_type modifiers

**Complexity**: M | **Dependencies**: ไม่มี

---

## Phase 14: Enemy HP + Difficulty Curve (M)

**เป้าหมาย**: ปรับ enemy HP ให้ difficulty ramp smooth

**Rebalanced Enemy HP**:
| Enemy | Armor HP | Frame HP | Total EHP |
|-------|----------|----------|-----------|
| Simple Rusher | 40 | 60 | 100 |
| Simple Ranged | 30 | 40 | 70 |
| Simple Support | 20 | 30 | 50 |
| Full Rusher | 80/part | 100/part | 1080 |
| Full Heavy | 150/part | 200/part | 2100 |

**Wanted Level Scaling (revised)**:
| Wanted | HP Multi | Speed Multi | Extra Enemies |
|--------|----------|-------------|---------------|
| 0 | ×1.0 | ×1.0 | 0 |
| 1 | ×1.1 | ×1.05 | 0 |
| 2 | ×1.2 | ×1.1 | 1 |
| 3 | ×1.3 | ×1.1 | 2 |
| 4 | ×1.5 | ×1.15 | 2 |
| 5+ | ×1.7 | ×1.2 | 3 |

**แก้ไขไฟล์**:
- `resources/mech/stock/*_standard.tres` (6 files) — ลด player armor/frame HP
- `scripts/systems/heat_wanted_system.gd` — แก้ scaling formula
- `scripts/mecha/enemy_health.gd` — รับ `hp_multiplier` parameter

**Complexity**: M | **Dependencies**: Phase 5, 13

---

## Phase 15: Cover Interaction Polish (S)

**เป้าหมาย**: Cover ทำลายได้ + visual feedback

**แก้ไขไฟล์**:
- `scripts/arena/cover_object.gd` — visual damage states (50% crack, 25% particles, 0% debris)
- `scripts/systems/projectile.gd` — raycast check cover ก่อนถึง target
- `scripts/mecha/enemy_dummy.gd` — ranged enemy flank เมื่อ target อยู่หลัง cover

**Complexity**: S | **Dependencies**: Phase 2, 11

---

## Phase 16: Game Flow Polish (M)

**เป้าหมาย**: Smooth transition, wave counter, heat tuning

**แก้ไขไฟล์**:
- `scripts/systems/heat_wanted_system.gd` — heat thresholds [4,7,11], +1 per kill, +3 per wave clear
- `scripts/game_manager.gd` — Fade transition 0.5s ระหว่าง board ↔ combat
- `scenes/game_world.tscn` — เพิ่ม CanvasLayer + ColorRect สำหรับ fade
- `scripts/ui/hud_controller.gd` — เพิ่ม wave counter "Wave X/Y"
- `scripts/ui/combat_rewards_ui.gd` — แสดง wave breakdown
- `scripts/systems/loot_system.gd` — Scale loot ตาม wave number
- `scripts/systems/safehouse_system.gd` — Scale cost ตาม wanted level

**Complexity**: M | **Dependencies**: Phase 7, 12, 14

---

## ลำดับการทำงาน

ทำ 4 tracks คู่กันได้:

**Track A (Arena)**: 1 → 2 → 3 → 15 → 16
**Track B (AI)**: 4 → 5 → 6 → 7 → 8
**Track C (Sound)**: 9 → 10 → 11 → 12
**Track D (Balance)**: 13 → 14 → 16

**Critical Path**: Phase 4 → 5 → 7 → 16 (AI tracks + final polish)

**Estimated Total**: ~51 ชั่วโมง across 16 phases

---

## New Files (41 files)

**Scripts (34)**:
```
scripts/arena/arena_generator.gd
scripts/arena/cover_object.gd
scripts/arena/obstacle_spawner.gd
scripts/arena/arena_nav_setup.gd
scripts/arena/atmosphere_manager.gd
scripts/arena/arena_seed_system.gd
scripts/mecha/ai/enemy_state_machine.gd
scripts/mecha/ai/enemy_state.gd
scripts/mecha/ai/enemy_attack_templates.gd
scripts/mecha/ai/states/state_idle.gd
scripts/mecha/ai/states/state_chase.gd
scripts/mecha/ai/states/state_attack.gd
scripts/mecha/ai/states/state_flee.gd
scripts/mecha/ai/states/state_strafe.gd
scripts/mecha/ai/states/state_charge.gd
scripts/systems/spawn_manager.gd
scripts/systems/spawn_point.gd
scripts/autoload/audio_manager.gd
scripts/audio/weapon_sounds.gd
scripts/audio/impact_sounds.gd
scripts/audio/movement_sounds.gd
scripts/audio/ambient_generator.gd
scripts/audio/music_generator.gd
scripts/audio/ui_sounds.gd
scripts/audio/audio_settings.gd
scripts/audio/sound_templates.gd
resources/arena/arena_layout.gd
resources/enemy/wave_data.gd
```

**Scenes (6)**:
```
scenes/arena/arena_boundary.tscn
scenes/mecha/enemy_ranged.tscn
scenes/mecha/enemy_heavy.tscn
scenes/mecha/enemy_support.tscn
scripts/autoload/audio_manager.tscn
```

**Resources (5)**:
```
resources/arena/stock_arena.tres
resources/arena/arena_variants/open_field.tres
resources/arena/arena_variants/corridor.tres
resources/arena/arena_variants/central_fortress.tres
resources/enemy/stock_waves.tres
```

---

## แก้ไขไฟล์เดิม (20 files)

```
project.godot
scenes/game_world.tscn
scripts/autoload/event_bus.gd
scripts/autoload/global_data.gd
scripts/game_manager.gd
scripts/mecha/enemy_dummy.gd
scripts/mecha/mecha_health_base.gd
scripts/mecha/enemy_health.gd
scripts/mecha/enemy_health_full.gd
scripts/mecha/weapon_manager.gd
scripts/mecha/mecha_animation.gd
scripts/systems/projectile.gd
scripts/systems/heat_wanted_system.gd
scripts/systems/loot_system.gd
scripts/systems/damage_calculator.gd
scripts/systems/safehouse_system.gd
scripts/ui/combat_rewards_ui.gd
scripts/ui/hud_controller.gd
scripts/ui/main_menu_controller.gd
resources/mech/stock/weapon_*.tres (6 files)
```

---

## Verification

หลังแต่ละ Phase ต้อง test:
1. Game ยัง run ได้ไม่ crash
2. Flow เดิมยังทำงาน: Main Menu → Board → Combat → Board
3. Player ยังควบคุมได้ (WASD, mouse, dash, jump)
4. Weapons ยิงได้ + hit detection ทำงาน
5. Enemy ยัง chase + attack ได้
6. Wave system ทำงาน (Phase 7+): ศัตรู spawn ตาม wave, หมด wave แล้ว combat จบ
7. Sound ทำงาน (Phase 9+): มีเสียง fire, hit, footstep
8. Cover ทำลายได้ (Phase 15): ยิง cover แล้วแตก + debris
