# Rogue Mech — Roadmap ระบบใหญ่

## เสร็จแล้ว (commits)

- [X] merge `spare_parts` → `credits` (รวมเป็นสกุลเงินเดียว, save เก่า migrate อัตโนมัติ) — `d5efd9e`
- [X] Frame Upgrade จ่าย `credits` อย่างเดียว (เอา data_cores ออกจากราคา/UI) — `d5efd9e`
- [X] `data_cores` เปลี่ยนเป็น research item (เก็บ count, พร้อมให้ระบบวิจัยใช้)

## การตัดสินใจที่ยืนยันแล้ว

1. `spare_parts` + `credits` merge → ใช้ `credits` อย่างเดียว
2. ระบบ Frame Upgrade เก็บไว้ แต่จ่ายด้วย `credits`
3. inventory เป็นแบบ **instance-based** (ทุก instance มี uid แยกกัน)

---

## เฟสที่เหลือ (ยังไม่ทำ)

### เฟส 2: Instance Inventory (ฐานของทั้งหมด — ควรทำก่อน)

- [X] ยูนิฟาย inventory: ทุก instance = `{ uid, db_id, durability, upgrade_level }` — `aec40f0`
- [X] เอา `salvaged_armor_inventory` ออก (`spawn_enemy_armor_salvage()` ลบแล้ว) — `aec40f0`
- [X] `weapon_inventory` (count-based) → instance-based (`register_weapon()` append instance) — `aec40f0`
- [X] durability bridge: instance = เก็บหลัก, `part_damage` = cache instance ที่สวม (sync equip/unequip/save/combat end) — `aec40f0`
- [X] save schema: armor instances + weapon instances + migration จาก save เก่า — `aec40f0`

### เฟส 3: Scrap & Crafting

- [X] เพิ่มสกุล "scrap" (วัสดุ) ใหม่ — ประกาศ/reset/save/load ครบ (ค่าเริ่ม 0)
- [X] ยูนิฟายคำว่า "scrap" 3 แนวคิด:
  - [X] `_spawn_scrap_wreckage()` — debris visual ยังอยู่ + ตอนนี้**ทิ้ง scrap pickup** (เป็นวัสดุได้จริง, เก็บ auto-collect เหมือน ammo)
  - [X] `weapon_pickup.gd` — กด F "scrap" อาวุธ = ได้อมโม + scrap วัสดุ (weight + rarity)
  - [X] board event "Salvage Cache" — เปลี่ยนจาก credits → ให้ **scrap**
- [X] `loot_system.gd` เพิ่ม pickup type "scrap" + enemy drops scrap (ตาราง drop)
- [X] คราฟเกราะจาก scrap + credits ที่ hangar (ค่ายิงจาก stats: scrap = ceil((hp+1.5ac+2wt)/20), cr = ceil((hp+ac+wt)/15)); เกราะที่คราฟ = instance ใหม่ (ต่อเฟส 2); cost-gate ที่ equip template
- [X] UI แสดง scrap: hangar stats bar, intermission (status/mech/inventory), combat rewards

### เฟส 4: Research & Blueprint (Gundam-type)

- `data_cores` → ส่งเข้าสถานีวิจัย → ปลดล็อก blueprint ต่อ run
- เพิ่ม `GlobalData.unlocked_blueprints` (per-run, reset ใน `reset_run_data()`)
- `mech_catalogs.tres`: เพิ่ม item หุ่น gundam + flag `blueprint_only` (ไม่ขึ้นร้าน/ดรอปปกติ)
- Research UI ใหม่ + คราฟหุ่น gundam ด้วย blueprint + credit

---

## Overlap ระหว่าง progress ปัจจุบัน กับระบบใหญ่

| จุด                                   | ปัจจุบัน                                   | ระบบใหญ่        | ผล                   | แนวทาง                                                                   |
| ---------------------------------------- | -------------------------------------------------- | ----------------------- | ---------------------- | ------------------------------------------------------------------------------ |
| `part_damage` (key-by-slot, 55 จุด) | ใช้กันทุกหน้าจอ                     | durability per-instance | **ชนหนัก** | bridge: instance = เก็บหลัก, part_damage = cache instance ที่สวม |
| `salvaged_armor_inventory`             | dead code + ไม่ save                            | เอาออก            | ชนน้อย           | ลบได้เลย (รายการ UI + intermission)                              |
| `weapon_inventory` count               | dedupe+count++                                     | instance                | ชน                   | register_weapon → append instance; UI ตัด count                            |
| "scrap" 3 แนวคิด                   | visual / ทิ้งอาวุธ / event ให้ credits | scrap material          | ชน                   | ยูนิฟายทั้งหมดเป็น material                                  |
| `data_cores`                           | research item (ว่าง)                           | research/blueprint      | ไม่ชน             | ต่อยอดได้เลย                                                       |
| save schema                              | เก็บ weapon_inventory, part_damage             | เพิ่ม instances    | ชน                   | เพิ่ม field ใหม่ + migration                                          |
| Docs                                     | ARCHITECTURE.md:240,286, design.md                 | —                      | stale                  | อัปเดตทีหลัง                                                       |

## หมายเหตุ

- มี Godot binary: `D:\godot\Godot_v4.6.2-stable_win64.exe` → ใช้ headless validate ได้
- คำสั่งตรวจ: `--headless --import` (validate resources) + `--headless --quit-after 5 <scene.tscn>` (compile scripts/scene ที่ระบุ; รันผ่าน main scene เฉพาะเมนู ไม่ได้แตะหน้าในเกม)
- ข้อจำกัด: `--check-only --script` ให้ false positive (ไม่มี autoload) อย่าใช้ตัดสิน ต้องรันผ่าน scene แทน
- ทุกเฟสจบแล้ว commit + push (ตาม AGENTS.md)
