# Rogue Mech — Roadmap ระบบใหญ่

## เสร็จแล้ว (commits)
- [x] merge `spare_parts` → `credits` (รวมเป็นสกุลเงินเดียว, save เก่า migrate อัตโนมัติ) — `d5efd9e`
- [x] Frame Upgrade จ่าย `credits` อย่างเดียว (เอา data_cores ออกจากราคา/UI) — `d5efd9e`
- [x] `data_cores` เปลี่ยนเป็น research item (เก็บ count, พร้อมให้ระบบวิจัยใช้)

## การตัดสินใจที่ยืนยันแล้ว
1. `spare_parts` + `credits` merge → ใช้ `credits` อย่างเดียว
2. ระบบ Frame Upgrade เก็บไว้ แต่จ่ายด้วย `credits`
3. inventory เป็นแบบ **instance-based** (ทุก instance มี uid แยกกัน)

---

## เฟสที่เหลือ (ยังไม่ทำ)

### เฟส 2: Instance Inventory (ฐานของทั้งหมด — ควรทำก่อน)
- ยูนิฟาย inventory: ทุก instance = `{ uid, db_id, durability, upgrade_level }`
- เอา `salvaged_armor_inventory` ออก
  - `spawn_enemy_armor_salvage()` เป็น **dead code** (ไม่มี caller) — ลบได้ปลอดภัย
  - `salvaged_armor_inventory` **ไม่ถูก save** (ไม่มีใน `save_run()`) — เอาไม่มีผลกับ save เดิม
- `weapon_inventory` (count-based) → instance-based
  - `register_weapon()` ตอนนี้ dedupe + `count++` → เปลี่ยนเป็น append 1 instance/ครั้ง
  - caller: `weapon_manager.gd:491`, `weapon_pickup.gd:71`, `salvage_ui.gd` → `salvage_all()`
  - reader: `hangar_controller.gd:912,1021,1152`, `intermission_controller.gd:385`
- durability: เก็บหลักที่ instance, **`part_damage` ยังเป็น key-by-slot = cache runtime ของ instance ที่สวม** (sync ตอน equip/unequip) → ไม่ต้องแตะ 55 จุดคอมแบท (mecha_health/part_slot/hud/part_mesh/safehouse ฯลฯ)
- save schema: เพิ่ม armor instances + weapon instances (uid+durability+upgrade), migration จาก count เดิม

### เฟส 3: Scrap & Crafting
- เพิ่มสกุล "scrap" (วัสดุ) ใหม่
- ยูนิฟายคำว่า "scrap" ที่กำลังมี 3 แนวคิด:
  - `_spawn_scrap_wreckage()` (`mecha_health_base.gd:268`) — debris visual ตอนแขนหัก (group "scrap", layer 8)
  - `weapon_pickup.gd:58` — กด F "scrap" อาวุธ = ทิ้งอาวุธเอาอมโม (ตอนนี้ไม่มี material)
  - board event "Salvage Cache" (`board_manager.gd:185`) — ตอนนี้ให้ **credits** (เพิ่งสร้าง) ควรเปลี่ยนให้ scrap ตอนเฟสนี้ลง กันลืม
- `loot_system.gd` เพิ่ม pickup type "scrap" (แบบเดียวกับ ammo/repair)
- คราฟเกราะจาก scrap + credits ที่ hangar; เกราะที่คราฟ = instance ใหม่ (ต่อเข้ากับเฟส 2)

### เฟส 4: Research & Blueprint (Gundam-type)
- `data_cores` → ส่งเข้าสถานีวิจัย → ปลดล็อก blueprint ต่อ run
- เพิ่ม `GlobalData.unlocked_blueprints` (per-run, reset ใน `reset_run_data()`)
- `mech_catalogs.tres`: เพิ่ม item หุ่น gundam + flag `blueprint_only` (ไม่ขึ้นร้าน/ดรอปปกติ)
- Research UI ใหม่ + คราฟหุ่น gundam ด้วย blueprint + scrap

---

## Overlap ระหว่าง progress ปัจจุบัน กับระบบใหญ่
| จุด | ปัจจุบัน | ระบบใหญ่ | ผล | แนวทาง |
|---|---|---|---|---|
| `part_damage` (key-by-slot, 55 จุด) | ใช้กันทุกหน้าจอ | durability per-instance | **ชนหนัก** | bridge: instance = เก็บหลัก, part_damage = cache instance ที่สวม |
| `salvaged_armor_inventory` | dead code + ไม่ save | เอาออก | ชนน้อย | ลบได้เลย (รายการ UI + intermission) |
| `weapon_inventory` count | dedupe+count++ | instance | ชน | register_weapon → append instance; UI ตัด count |
| "scrap" 3 แนวคิด | visual / ทิ้งอาวุธ / event ให้ credits | scrap material | ชน | ยูนิฟายทั้งหมดเป็น material |
| `data_cores` | research item (ว่าง) | research/blueprint | ไม่ชน | ต่อยอดได้เลย |
| save schema | เก็บ weapon_inventory, part_damage | เพิ่ม instances | ชน | เพิ่ม field ใหม่ + migration |
| Docs | ARCHITECTURE.md:240,286, design.md | — | stale | อัปเดตทีหลัง |

## หมายเหตุ
- มี Godot binary: `D:\godot\Godot_v4.6.2-stable_win64.exe` → ใช้ headless validate ได้
- คำสั่งตรวจ: `--headless --import` (validate resources) + `--headless --quit-after 5 <scene.tscn>` (compile scripts/scene ที่ระบุ; รันผ่าน main scene เฉพาะเมนู ไม่ได้แตะหน้าในเกม)
- ข้อจำกัด: `--check-only --script` ให้ false positive (ไม่มี autoload) อย่าใช้ตัดสิน ต้องรันผ่าน scene แทน
- ทุกเฟสจบแล้ว commit + push (ตาม AGENTS.md)
