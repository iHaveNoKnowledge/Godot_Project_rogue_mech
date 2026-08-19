# 📋 Session Progress Tracker

> ไฟล์นี้ใช้ติดตามความคืบหน้าระหว่าง session พัฒนา
> อัปเดตทุกครั้งที่ทำเสร็จแต่ละขั้น

---

## Session: 2026-08-19 — GDD Section 3.2 (Roller Dash + Energy Pool)

### ✅ เสร็จแล้วทั้งหมด

| # | รายการ | สถานะ | ไฟล์ |
|---|--------|:------:|------|
| 1 | เอา dash_cooldown ออก — Dash อิสระตาม Reflex | ✅ | `mecha_controller.gd` |
| 2 | เพิ่ม `mech_energy` / `mech_max_energy` ใน GlobalData | ✅ | `global_data.gd` |
| 3 | Energy ใน save_run() + restore_from_dict() | ✅ | `save_game_io.gd` |
| 4 | mecha_controller โหลด/บันทึก energy จาก GlobalData | ✅ | `mecha_controller.gd` |
| 5 | Board movement ดึงพลังงาน + depletion check | ✅ | `board_manager.gd` |
| 6 | Energy regen ต่อวัน + Safehouse refuel | ✅ | `board_manager.gd` |
| 7 | ปรับค่า Energy ให้ใช้ได้นานขึ้น | ✅ | ทั้ง 2 ไฟล์ |

---

### ค่าคงที่ — Final

| ค่า | ค่าใหม่ | ผลลัพธ์ |
|-----|---------|---------|
| `mech_max_energy` | **200.0** | ถังใหญ่ขึ้น 2 เท่า |
| `DASH_ENERGY_COST` | **6.0** | dash ได้ ~33 ครั้ง |
| `ROLLER_BASE_DRAIN` | **2.0/วิ** | roller ได้ ~100 วิ |
| `ROLLER_RAMP_DRAIN` | **3.0/วิ²** | ramp ช้าลง 2 เท่า |
| `ROLLER_MAX_DRAIN` | **20.0** | ceiling ลดลง |
| `BOARD_ENERGY_COST_PER_STEP` | **1.0** | เดินได้ ~200 ก้าว |
| `BOARD_ENERGY_REGEN_PER_DAY` | **25.0** | regen เร็วขึ้น |
| `SAFEHOUSE_ENERGY_REGEN` | **50.0** | เติมเร็วขึ้น |

---

### Work Log

| วันที่ | สิ่งที่ทำ | ไฟล์ที่แก้ |
|--------|-----------|------------|
| 2026-08-19 | ลบ dash_cooldown — pure energy-based dash | `mecha_controller.gd` |
| 2026-08-19 | เพิ่ม mech_energy state ใน GlobalData | `global_data.gd` |
| 2026-08-19 | เพิ่ม energy ใน save/load | `save_game_io.gd` |
| 2026-08-19 | mecha_controller โหลด/บันทึก energy จาก GlobalData | `mecha_controller.gd` |
| 2026-08-19 | Board movement ดึงพลังงาน + depletion check | `board_manager.gd` |
| 2026-08-19 | Energy regen ต่อวัน + Safehouse refuel | `board_manager.gd` |
| 2026-08-19 | ปรับค่า Energy ให้ใช้ได้นานขึ้น (ทุกค่า) | `global_data.gd` + `mecha_controller.gd` |

---

### Commits

| hash | ข้อความ |
|------|---------|
| `7e50238` | feat(combat): remove dash cooldown — energy is the only gate |
| `a873657` | feat(energy): persist mech energy across combat/board + board fuel drain |
| `e117d28` | tune(energy): increase pool size and reduce drain rates for longer gameplay |

---

### สิ่งที่เหลือทำ Session หน้า

| รายการ | หมายเหตุ |
|--------|----------|
| ❌ Precision Dash — หลบถูกจังหวะคืนพลังงาน | gameplay depth |
| ❌ Energy depletion → board consequence จริงจัง | ตอนนี้แค่ popup |
| ❌ Phase 4: Research & Blueprint | feature ใหญ่ถัดไป |

---

*Last updated: 2026-08-19*
