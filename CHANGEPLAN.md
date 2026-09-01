
# CHANGEPLAN — งานที่เหลือทำต่อ (Resume Point)

> ย้ายเครื่องมาแล้วอ่านไฟล์นี้ก่อน ข้อมูลในนี้ตรงกับโค้ด commit `8ac026d` บน branch `main`
> วิธีรันเทสต์ headless (แก้ `<GODOT>` เป็น path เครื่องตัวเอง):
> `<GODOT>\Godot_v4.6.2-stable_win64.exe --headless --quit-after 5 res://tests/refactor_qa_test.tscn`
> ตัวอย่าง: `D:\godot\...`, `H:\hack\project\godot\...`, `C:\Tools\Godot\...` — ถ้าเพิ่ง clone ใหม่ต้องรัน `--import` ก่อนเพื่อ build class cache
> หลังแก้ทุกครั้ง: รันเทสต์หลายรอบ (test มี randomness ต้องรัน 8-15 รอบ) + `git commit` + `git push` ตาม AGENTS.md

---

## ✅ DONE — commit `165405f`

- **Item 1 (BUG tile reset):** `destroy_enemy_base()` / `_enemy_base_completed()` ตั้ง `pending_enemy_base_tile_reset` ก่อนล้าง tile pos → `board_manager` เรียก `_clear_enemy_base_tile()` ตอน `_ready` + `move_to_tile` (set meta กลับเป็น `"combat"` + `_update_visual()`). เพิ่ม guard ใน `_process_tile_effect` ให้ raid เฉพาะเมื่อ `enemy_base_active` + pos ตรง node จริง ไม่งั้น = combat
- **Item 2 (type_pool):** เอาออก `"enemy_base"` จาก `type_pool` ใน `board_generator.gd` → enemy_base เกิดจาก spy system อย่างเดียว
- **Item 3 (counter-unit identity):** `_trigger_stalking_ace_ambush` แยกตัวตน — `special_ace` = heavy_full (HP 2.2), `gundam_copy` = tank_full (HP 2.6); reset `stalking_chance` แทน `ambush_probability` ที่ตายแล้ว
- **Item 5 (tests):** เพิ่ม `_test_enemy_base_tile_reset` (destroy + completion reset), `_test_board_has_no_random_enemy_base`; เพิ่ม `_consume_enemy_special_unit()` ให้ consume `enemy_special_units` จริงหลังต่อสู้จบ — ผลเทสต์ 0 failed (106-107 passed ตาม outcome สุ่ม)

---

## ✅ Phase 4 (Research & Blueprint) — ส่วนคราฟหุ่น gundam

- เพิ่ม gundam-tier armor ใน `mech_catalogs.tres` (ทุก 6 slot) พร้อม flag `blueprint_only: true` + `blueprint_id: "bp_gundam_armor"` → ไม่ดรอป/ไม่ขึ้น random start (`roll_random_start` เลือก index 0 = standard เท่านั้น)
- เพิ่ม `GlobalData.entry_is_blueprint_locked(entry)` — ถ้า `blueprint_only` และ blueprint ยังไม่ได้ research → lock; ใช้ gate `try_craft_armor_from_catalog()` (ปฏิเสธตอน lock)
- Gate crafting/equip ใน hangar: craft window แสดง `[BLUEPRINT]` + ปุ่ม "RESEARCH TO UNLOCK" disabled; `_equip_part_to_slot` + `_craft_armor_from_template` ตรวจ blueprint ก่อน
- `_apply_research_reward` ครอบคลุม `armor/frame` = research unlock สะท้อนผ่าน `research_unlocked` → unlock freely
- Test ใหม่ `_test_blueprint_gated_gundam_armor`: lock เมื่อยังไม่ research, refuse craft, random start ไม่ให้ gundam part, research แล้ว craft ได้

---

## ⏳ REMAINING

## 4. BALANCE — ยังไม่ได้ playtest จริง (ตัวเลขตั้งไว้ตามเหตุผล)

ตัวเลขปัจจุบัน (หลัง commit `13d6c6d` + ปรับ balance รอบแรก):

- Spy attempt: soldier 0.20, scavenger 0.22, merc 0.25 + per tier 0.04-0.05 (บอร์ด 7 เลเยอร์ ~12-15 moves → เป้า ~3-5 event/board)
- Counter chance: `0.10 + security*0.008`, clamp 0.10-0.90 → security 25 = ~30%, 100 = 90%
- Security cost: 35/75/115/155/... (+40/level), +14 security/upgrade, max 100
- Research node: เกิดจาก 2 thefts, `enemy_base_required = 6` (จบใน 6 moves)
- Income: ปกติ 30-80/victory, boss +105, raid bonus +60/+10, spy caught bounty 20-50
- Grunt: hp/tier 0.22-0.30, grunt_upgrade +0.10/level, MKII grant +2

**สิ่งที่ควรเช็คตอน playtest (เทียบ baseline รอบแรก):**

- [ ] spy event เกิดบ่อยเกินไปไหม (รอบแรกตั้งให้มาได้ ~3-5 event แทนไม่พอจะเกิด node) → ปรับ `escalation_spy_base_chance`
- [ ] security upgrade 35 ครั้งแรก (ให้ +14 sec ~ +11% catch) "คุ้ม" ไหม → ปรับ `SECURITY_UPGRADE_BASE_COST`/`SECURITY_PER_UPGRADE`
- [ ] 6 moves พอจะลุยถึง node ได้จริงไหม (บอร์ด 7 ชั้น) → ปรับ `enemy_base_required` / placement layers
- [ ] enemy HP ตอนท้าย sector โหดไปไหม (hp_per_tier + wanted + grunt upgrade stack กัน) → ปรับ `escalation_hp_per_tier`
- [ ] raid bonus +60 คุ้มค่ากับความเสี่ยงไหม

---

## 5. TEST — เพิ่ม coverage ตาม feature ใหม่ ✅ (commit `165405f`)

- [X] Test: หลัง destroy node → node tile ถูก reset / guard ไม่ให้ raid ซ้ำตอน `enemy_base_active=false`
- [X] Test: `enemy_special_units` ถูก consume จริงใน combat (`_consume_enemy_special_unit` ใน spawn_manager)
- [X] Test: stalking ace ที่เกิดจาก node → ถูก pop ออกจาก `stalking_aces` ตอนเกิด ambush

---

## ไฟล์ที่เกี่ยวข้องหลัก

| ไฟล์                                   | บทบาท                                                 |
| ------------------------------------------ | ---------------------------------------------------------- |
| `autoload/global_data.gd`                | state + logic: fleet_security, spy, enemy_base, escalation |
| `scripts/board/board_manager.gd`         | วาง node, spy roll ต่อ move, ต่อสู้ enemy_base |
| `scripts/board/board_generator.gd`       | gen board + type_pool (item 2)                             |
| `scripts/systems/spawn_manager.gd`       | wave + stalking ace ambush (item 3)                        |
| `resources/data/run_theme_catalogs.tres` | ค่าตัวเลขต่อ theme (item 4)                    |
| `scripts/ui/combat_rewards_ui.gd`        | income/reward (item 4)                                     |
| `scripts/ui/intermission_controller.gd`  | status text: security, enemy base, stalking ace            |
| `tests/refactor_qa_test.gd`              | QA suite (item 5)                                          |
