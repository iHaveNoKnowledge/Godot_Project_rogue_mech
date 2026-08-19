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
| 16 | Research Lab tile + UI | ✅ | `research_lab_ui.gd`, `research_lab_ui.tscn`, etc |
| 17 | 6 new blueprint projects in catalog | ✅ | `research_catalogs.tres` |
| 18 | Research completion notification popup | ✅ | `global_data.gd` |

---

### ค่าคงที่ — Final

| ค่า | ค่า | ผลลัพธ์ |
|-----|-----|---------|
| `CONVOY_TRANSFER_AMOUNT` | **60.0** | เติมได้ 60 หน่วยต่อครั้ง |
| `DROP_TANK_CAPACITY_PER` | **40.0** | ถังละ 40 หน่วย (สูงสุด 3 ถัง = 120) |
| `DROP_TANK_COST_CREDITS` | **80** | ราคาซื้อถังละ 80 credits |
| `FUEL_DEPOT_PRECISE_BONUS` | **80.0** | ชนะ depot precise = +80 fuel |
| `FUEL_DEPOT_HEAVY_BONUS` | **40.0** | ชนะ depot heavy = +40 fuel |
| `ENGINE_DIRT_PER_SIPHON` | **0.25** | dirt +0.25 ต่อ siphon |
| `WRECKAGE_SIPHON_AMOUNT` | **30.0** | siphon 30 หน่วยต่อครั้ง |
| `REIGNITION_FUEL_COST` | **60.0** | เติม 60 fuel เพื่อ reboot |

---

### สิ่งที่เหลือทำ Session หน้า

| รายการ | หมายเหตุ |
|--------|----------|
| ❌ Precision Dash — หลบถูกจังหวะคืนพลังงาน | gameplay depth |
| ❌ Environmental Hazards (Dust Storm, EMP, Tactical Smog) | Dynamic Event System §7.1 |

---

### Commits (Session 2026-08-19)

| hash | ข้อความ |
|------|---------|
| `0201044` | docs: update PROGRESS.md — 18 items complete |
| `79c8781` | feat(research): add completion notification popup |
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
