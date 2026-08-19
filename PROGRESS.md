# 📋 Session Progress Tracker

> ไฟล์นี้ใช้ติดตามความคืบหน้าระหว่าง session พัฒนา
> อัปเดตทุกครั้งที่ทำเสร็จแต่ละขั้น

---

## Session: 2026-08-19 — GDD Section 2.4 (Refueling & Supply Logistics)

### ✅ เสร็จแล้วทั้งหมด

| # | รายการ | สถานะ | ไฟล์ |
|---|--------|:------:|------|
| 1 | Fuel system state ใน GlobalData (convoy_fuel, drop_tanks, engine_dirt, constants) | ✅ | `global_data.gd` |
| 2 | Board tile "fuel_depot" — บุกยึดคลังน้ำมันศัตรู | ✅ | `board_tile.gd`, `board_manager.gd`, `board_generator.gd` |
| 3 | Board tile "supply_truck" — Convoy Supply Transfer (เสีย 1 turn + alert++) | ✅ | `board_manager.gd` |
| 4 | Fuel depot combat victory → grant fuel bonus | ✅ | `global_data.gd` |
| 5 | External Drop Tank system (เพิ่ม capacity + vulnerable + purge + detonation) | ✅ | `mecha_controller.gd` |
| 6 | Engine Dirt Penalty — impure fuel slows energy regen | ✅ | `mecha_controller.gd` |
| 7 | Convoy fuel reserve overnight regen + engine dirt cleanup + depot reset | ✅ | `board_manager.gd` |
| 8 | Save/Load support | ✅ | `save_game_io.gd` |
| 9 | GDD.md Section 2.4 | ✅ | `GDD.md` |
| 10 | Drop Tank 3D visual model — procedural cylinders on backpack | ✅ | `drop_tank_visuals.gd`, `mecha_base.tscn` |
| 11 | Drop Tank HUD indicator — HP bar + fuel + purge warning | ✅ | `core_hud.gd` |
| 12 | Body damage intercept — 30% absorbed by drop tanks | ✅ | `mecha_health_base.gd` |
| 13 | Pilot Siphon Protocol — wreckage tile + siphon + re-ignition reboot | ✅ | `global_data.gd`, `board_manager.gd`, `board_tile.gd`, `mecha_health_base.gd`, `theme_system.gd`, `save_game_io.gd` |

---

### ค่าคงที่ — Final

| ค่า | ค่า | ผลลัพธ์ |
|-----|-----|---------|
| `CONVOY_TRANSFER_AMOUNT` | **60.0** | เติมได้ 60 หน่วยต่อครั้ง |
| `CONVOY_TRANSFER_ALERT_GAIN` | **2** | เติมที Alert++2 |
| `CONVOY_DAILY_FUEL_REGEN` | **30.0** | ขบวนรถเติม 30/วัน |
| `DROP_TANK_CAPACITY_PER` | **40.0** | ถังละ 40 หน่วย (สูงสุด 3 ถัง = 120) |
| `DROP_TANK_HP_PER_TANK` | **30.0** | ถังละ 30 HP ก่อนระเบิด |
| `DROP_TANK_DET_DELAY` | **1.5** | 1.5 วินาทีก่อนระเบิด |
| `DROP_TANK_PURGE_DAMAGE` | **15.0** | ระเบิดทำ DMG ตัวเอง 15 |
| `FUEL_DEPOT_BONUS` | **80.0** | ชนะ depot = +80 fuel |
| `ENGINE_DIRT_PER_SIPHON` | **0.25** | dirt +0.25 ต่อ siphon |
| `ENGINE_DIRT_CLEANUP_PER_DAY` | **0.1** | clean 0.1/วัน |
| `ENGINE_DIRT_HEAT_MULTIPLIER` | **1.5** | heat rate x1.5 ที่ max dirt |
| `WRECKAGE_SIPHON_AMOUNT` | **30.0** | siphon 30 หน่วยต่อครั้ง |
| `WRECKAGE_MAX_SIPHONS` | **3** | siphon ได้สูงสุด 3 ครั้ง |
| `REIGNITION_FUEL_COST` | **60.0** | เติม 60 fuel เพื่อ reboot |
| `REIGNITION_ENGINE_DIRT_COST` | **0.15** | dirt +0.15 ตอน reboot |

---

### Work Log

| วันที่ | สิ่งที่ทำ | ไฟล์ที่แก้ |
|--------|-----------|------------|
| 2026-08-19 | Fuel system state + constants + reset | `global_data.gd` |
| 2026-08-19 | Board tile fuel_depot + supply_truck visual | `board_tile.gd` |
| 2026-08-19 | Fuel depot seizure + convoy supply transfer | `board_manager.gd` |
| 2026-08-19 | Fuel depot tile spawn in board generator | `board_generator.gd` |
| 2026-08-19 | Fuel depot combat victory → fuel bonus | `global_data.gd` |
| 2026-08-19 | External Drop Tank system + purge + detonation | `mecha_controller.gd` |
| 2026-08-19 | Engine dirt penalty on energy regen | `mecha_controller.gd` |
| 2026-08-19 | Convoy regen + dirt cleanup + depot reset on day end | `board_manager.gd` |
| 2026-08-19 | Save/Load fuel state | `save_game_io.gd` |
| 2026-08-19 | GDD.md Section 2.4 | `GDD.md` |
| 2026-08-19 | Drop Tank 3D visual model + body damage intercept | `drop_tank_visuals.gd`, `mecha_base.tscn`, `mecha_health_base.gd`, `mecha_controller.gd` |
| 2026-08-19 | Drop Tank HUD indicator (HP + fuel + purge warning) | `core_hud.gd` |
| 2026-08-19 | Pilot Siphon Protocol — wreckage tile + siphon + re-ignition | `global_data.gd`, `board_manager.gd`, `board_tile.gd`, `mecha_health_base.gd`, `theme_system.gd`, `save_game_io.gd` |

---

### สิ่งที่เหลือทำ Session หน้า

| รายการ | หมายเหตุ |
|--------|----------|
| ~~❌ Fuel depot choice popup~~ | ✅ ทำแล้ว (Precise vs Heavy approach + reward) |
| ❌ Precision Dash — หลบถูกจังหวะคืนพลังงาน | gameplay depth |
| ❌ Phase 4: Research & Blueprint | feature ใหญ่ถัดไป |

---

### Commits (Session 2026-08-19)

| hash | ข้อความ |
|------|---------|
| `61f0bed` | feat(siphon): implement Pilot Siphon Protocol — wreckage + re-ignition |
| `a3fe044` | feat(drop_tanks): add HUD indicator for drop tank HP, fuel, and purge warning |
| `eb8687c` | feat(drop_tanks): add 3D visual model for external fuel canisters |
| `e0486bf` | feat(fuel): implement Refueling & Supply Logistics system (GDD §2.4) |

---

*Last updated: 2026-08-19*
