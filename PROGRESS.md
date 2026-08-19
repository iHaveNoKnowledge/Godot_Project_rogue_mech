# 📋 Session Progress Tracker

> ไฟล์นี้ใช้ติดตามความคืบหน้าระหว่าง session พัฒนา
> อัปเดตทุกครั้งที่ทำเสร็จแต่ละขั้น

---

## Phase ที่กำลังทำ: GDD Section 3.2 — Roller Dash + Energy Pool

### สถานะปัจจุบัน: ✅ เสร็จแล้ว — Energy Tuned

---

### Sub-tasks

| # | รายการ | สถานะ | หมายเหตุ |
|---|--------|--------|----------|
| 1 | เอา dash_cooldown ออก — ให้กด Dash ได้อิสระตาม Reflex | ✅ | `mecha_controller.gd` |
| 2 | เพิ่ม `mech_energy` / `mech_max_energy` ใน GlobalData | ✅ | ค่าเริ่ม 200.0 |
| 3 | เพิ่ม energy ใน save_run() + restore_from_dict() | ✅ | `save_game_io.gd` |
| 4 | mecha_controller.gd โหลด/บันทึก energy จาก GlobalData | ✅ | `_ready()` + `_exit_tree()` |
| 5 | Board movement ดึงพลังงาน + depletion check | ✅ | FUEL EMERGENCY popup |
| 6 | Energy regen ต่อวัน + Safehouse refuel | ✅ | +25/day, +50 safehouse |
| 7 | ปรับค่า Energy ให้ใช้ได้นานขึ้น | ✅ | ดูตารางด้านล่าง |

---

### บันทึกการทำงาน (Work Log)

| วันที่ | สิ่งที่ทำ | ไฟล์ที่แก้ | หมายเหตุ |
|--------|-----------|------------|----------|
| 2026-08-19 | ลบ dash_cooldown — เปลี่ยนเป็น pure energy-based dash | `mecha_controller.gd` | ลบ `dash_cooldown`, `dash_cooldown_timer` |
| 2026-08-19 | เพิ่ม mech_energy state ใน GlobalData | `autoload/global_data.gd` | + constants |
| 2026-08-19 | เพิ่ม energy ใน save/load | `save_game_io.gd` | save + restore |
| 2026-08-19 | mecha_controller โหลด/บันทึก energy จาก GlobalData | `mecha_controller.gd` | `_ready()` + `_exit_tree()` |
| 2026-08-19 | Board movement ดึงพลังงาน + depletion check | `board_manager.gd` | FUEL EMERGENCY popup |
| 2026-08-19 | Energy regen ต่อวัน + Safehouse refuel | `board_manager.gd` | +25/day, +50 safehouse |
| 2026-08-19 | ปรับค่า Energy ให้ใช้ได้นานขึ้น | `global_data.gd` + `mecha_controller.gd` | ทุกค่า |

---

### ค่าคงที่ — หลังปรับ (Final)

| ค่า | ค่าเดิม | ค่าใหม่ | ผลลัพธ์ |
|-----|---------|---------|---------|
| `mech_max_energy` | 100.0 | **200.0** | ถังใหญ่ขึ้น 2 เท่า |
| `DASH_ENERGY_COST` | 12.0 | **6.0** | dash ได้ ~33 ครั้ง |
| `ROLLER_BASE_DRAIN` | 4.0/วิ | **2.0/วิ** | roller ได้ ~100 วิ |
| `ROLLER_RAMP_DRAIN` | 7.0/วิ² | **3.0/วิ²** | ramp ช้าลง 2 เท่า |
| `ROLLER_MAX_DRAIN` | 40.0 | **20.0** | ceiling ลดลง |
| `BOARD_ENERGY_COST_PER_STEP` | 2.0 | **1.0** | เดินได้ ~200 ก้าว |
| `BOARD_ENERGY_REGEN_PER_DAY` | 15.0 | **25.0** | regen เร็วขึ้น |
| `SAFEHOUSE_ENERGY_REGEN` | 30.0 | **50.0** | เติมเร็วขึ้น |

---

*Last updated: 2026-08-19*
