# 📋 Session Progress Tracker

> ไฟล์นี้ใช้ติดตามความคืบหน้าระหว่าง session พัฒนา
> อัปเดตทุกครั้งที่ทำเสร็จแต่ละขั้น

---

## Session: 2026-08-19 — GDD Section 2.4 + Phase 4A Research & Blueprint

### ✅ เสร็จแล้วทั้งหมด

| # | รายการ | สถานะ | ไฟล์ |
|---|--------|:------:|------|
| 1 | Fuel system state ใน GlobalData | ✅ | `global_data.gd` |
| 2 | Board tile "fuel_depot" | ✅ | `board_tile.gd`, `board_manager.gd`, `board_generator.gd` |
| 3 | Board tile "supply_truck" | ✅ | `board_manager.gd` |
| 4 | Fuel depot combat victory | ✅ | `global_data.gd` |
| 5 | External Drop Tank system | ✅ | `mecha_controller.gd` |
| 6 | Engine Dirt Penalty | ✅ | `mecha_controller.gd` |
| 7 | Convoy fuel reserve overnight regen | ✅ | `board_manager.gd` |
| 8 | Save/Load support | ✅ | `save_game_io.gd` |
| 9 | GDD.md Section 2.4 + 4A | ✅ | `GDD.md` |
| 10 | Drop Tank 3D visual model | ✅ | `drop_tank_visuals.gd`, `mecha_base.tscn` |
| 11 | Drop Tank HUD indicator | ✅ | `core_hud.gd` |
| 12 | Body damage intercept | ✅ | `mecha_health_base.gd` |
| 13 | Pilot Siphon Protocol | ✅ | `global_data.gd`, `board_manager.gd`, etc |
| 14 | Fuel depot choice popup | ✅ | `global_data.gd`, `board_manager.gd`, `theme_system.gd` |
| 15 | Drop Tank purchase/detach in City Shop | ✅ | `city_shop_ui.gd` |
| 16 | Research Lab tile + UI | ✅ | `research_lab_ui.gd`, `research_lab_ui.tscn`, `board_tile.gd`, `board_manager.gd`, `board_generator.gd`, `game_board.tscn` |
| 17 | 6 new blueprint projects (frames, armor, units, beam shield) | ✅ | `research_catalogs.tres` |

---

### Research Catalog — All Projects

| ID | Name | Cores | Time | Reward |
|----|------|:-----:|:----:|--------|
| `bp_ally_gm` | GM-II Blueprint | 1 | 6 | Ally unit: GM-II |
| `bp_ally_gunner` | GM Sniper Blueprint | 2 | 9 | Ally unit: GM Sniper |
| `bp_ally_blade` | GM Blade Blueprint | 3 | 12 | Ally unit: GM Blade |
| `bp_ally_cannon` | Guncannon Blueprint | 3 | 10 | Ally unit: Guncannon |
| `bp_head_armor` | Gundam Head Armor | 4 | 10 | Armor: Duo-visor Plating |
| `bp_leg_armor` | Gundam Leg Armor | 4 | 10 | Armor: Reactive Leg Guards |
| `bp_gundam_frame` | Gundam Frame Blueprint | 4 | 14 | Frame: Alaya-Vijnana Set |
| `bp_gundam_armor` | Advanced Reactive Armor | 5 | 16 | Armor: Reactive Armor MK-I |
| `bp_heavy_frame` | Heavy Siege Frame | 6 | 18 | Frame: Reinforced Siege Set |
| `bp_beam_shield` | Beam Shield Blueprint | 7 | 20 | Armor: Beam Shield Module |

---

### สิ่งที่เหลือทำ Session หน้า

| รายการ | หมายเหตุ |
|--------|----------|
| ❌ Precision Dash — หลบถูกจังหวะคืนพลังงาน | gameplay depth |
| ❌ Research completion popup notification on board | UX improvement |

---

### Commits (Session 2026-08-19)

| hash | ข้อความ |
|------|---------|
| `df4f2ff` | feat(research): add 6 new blueprint projects |
| `0752fa6` | feat(research): add Research Lab tile + UI |
| `b576015` | feat(drop_tanks): add purchase/detach in City Shop |
| `ffb05cb` | feat(depot): add fuel depot choice popup |
| `61f0bed` | feat(siphon): implement Pilot Siphon Protocol |
| `a3fe044` | feat(drop_tanks): add HUD indicator |
| `eb8687c` | feat(drop_tanks): add 3D visual model |
| `e0486bf` | feat(fuel): implement Refueling & Supply Logistics |

---

*Last updated: 2026-08-19*
