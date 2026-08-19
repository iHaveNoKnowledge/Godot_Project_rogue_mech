# 📋 Session Progress Tracker

> ไฟล์นี้ใช้ติดตามความคืบหน้าระหว่าง session พัฒนา
> อัปเดตทุกครั้งที่ทำเสร็จแต่ละขั้น

---

## Phase ที่กำลังทำ: GDD Section 3.2 — Roller Dash + Energy Pool

### สถานะปัจจุบัน: ✅ เสร็จแล้ว — Energy Persistence + Board Integration

---

### Sub-tasks

| # | รายการ | สถานะ | หมายเหตุ |
|---|--------|--------|----------|
| 1 | เอา dash_cooldown ออก — ให้กด Dash ได้อิสระตาม Reflex | ✅ | `mecha_controller.gd` |
| 2 | เพิ่ม `mech_energy` / `mech_max_energy` ใน GlobalData | ✅ | ค่าเริ่ม 100.0 |
| 3 | เพิ่ม energy ใน save_run() + restore_from_dict() | ✅ | `save_game_io.gd` |
| 4 | mecha_controller.gd โหลด energy จาก GlobalData เมื่อ _ready | ✅ | ข้าม scene ได้ |
| 5 | mecha_controller.gd บันทึก energy กลับ GlobalData เมื่อ _exit_tree | ✅ | ข้าม scene ได้ |
| 6 | Board movement ดึงพลังงาน 2.0 ต่อก้าว | ✅ | `board_manager.gd` |
| 7 | Energy regen ต่อวันบน board (+15.0) | ✅ | `_end_day()` |
| 8 | Safehouse refuel (+30.0) | ✅ | `_process_tile_effect("safehouse")` |
| 9 | Energy depletion → หุ่นเดินไม่ได้บน board | ✅ | FUEL EMERGENCY popup |

---

### บันทึกการทำงาน (Work Log)

| วันที่ | สิ่งที่ทำ | ไฟล์ที่แก้ | หมายเหตุ |
|--------|-----------|------------|----------|
| 2026-08-19 | ลบ dash_cooldown — เปลี่ยนเป็น pure energy-based dash | `mecha_controller.gd` | ลบ `dash_cooldown`, `dash_cooldown_timer` |
| 2026-08-19 | เพิ่ม mech_energy state ใน GlobalData | `autoload/global_data.gd` | + `BOARD_ENERGY_COST_PER_STEP`, `BOARD_ENERGY_REGEN_PER_DAY`, `SAFEHOUSE_ENERGY_REGEN` |
| 2026-08-19 | เพิ่ม energy ใน save/load | `scripts/systems/save_game_io.gd` | save + restore |
| 2026-08-19 | mecha_controller โหลด/บันทึก energy จาก GlobalData | `scripts/mecha/mecha_controller.gd` | `_ready()` + `_exit_tree()` |
| 2026-08-19 | Board movement ดึงพลังงาน + depletion check | `scripts/board/board_manager.gd` | FUEL EMERGENCY popup เมื่อ energy = 0 |
| 2026-08-19 | Energy regen ต่อวัน + Safehouse refuel | `scripts/board/board_manager.gd` | +15/day, +30 at safehouse |

---

### Blockers / ปัญหา

| ปัญหา | สถานะ | วิธีแก้ |
|--------|--------|---------|
| — | — | — |

---

### ค่าคงที่ (Constants)

| ค่า | ค่าเริ่ม | หมายเหตุ |
|-----|---------|----------|
| `mech_max_energy` | 100.0 | GlobalData |
| `BOARD_ENERGY_COST_PER_STEP` | 2.0 | ดึงจาก GlobalData |
| `BOARD_ENERGY_REGEN_PER_DAY` | 15.0 | ทุกครั้งที่ End Day |
| `SAFEHOUSE_ENERGY_REGEN` | 30.0 | เมื่อเดินเข้า safehouse |
| `DASH_ENERGY_COST` | 12.0 | ต่อ dash 1 ครั้ง (mecha_controller) |
| `ROLLER_BASE_DRAIN` | 4.0/วินาที | ค้าง roller (mecha_controller) |
| `ROLLER_RAMP_DRAIN` | 7.0/วินาที² | ramp ยิ่งกดนานยิ่งแรง |

---

*Last updated: 2026-08-19*
