# CHANGEPLAN — งานที่เหลือทำต่อ (Resume Point)

> ย้ายเครื่องมาแล้วอ่านไฟล์นี้ก่อน ข้อมูลในนี้ตรงกับโค้ด commit `c249f34` บน branch `main`
> วิธีรันเทสต์ headless:
> `D:\godot\Godot_v4.6.2-stable_win64.exe --headless --quit-after 5 res://tests/refactor_qa_test.tscn`
> หลังแก้ทุกครั้ง: รันเทสต์หลายรอบ (test มี randomness ต้องรัน 8-15 รอบ) + `git commit` + `git push` ตาม AGENTS.md

---

## 1. BUG — tile `enemy_base` ไม่ถูก reset หลังจบ node (สำคัญ)

**ปัญหา:** เมื่อ node ถูกทำลาย (`destroy_enemy_base`) หรือสร้าง counter-unit เสร็จ (`_enemy_base_completed`)
tile บน board ยังคง meta `tile_type = "enemy_base"` อยู่ (ถูก set ใน `_place_enemy_base_node`)

**ผลกระทบ:** เดินเหยียบซ้ำ tile เดิม → `_process_tile_effect` ส่งเข้าต่อสู้ `enemy_base` อีก →
ชนะแล้วได้ grunt upgrade +1 ฟรีซ้ำๆ (exploit) และ node ที่จบไปแล้วยังโดน raid ได้ทั้งที่ `enemy_base_active = false`

**ไฟล์:**
- `scripts/board/board_manager.gd`
  - `_process_tile_effect` (บรรทัด ~157) — ป้องกันไว้ด้วย: กรณี `enemy_base` แต่ `not GlobalData.enemy_base_active` ให้ treat เป็น `combat` แทน
  - `_place_enemy_base_node` (บรรทัด ~285) — แจ้งให้ reset tile เดิมก่อนวางใหม่ (ถ้า node เดิมยังค้างบน board)
- `autoload/global_data.gd` — `destroy_enemy_base()` / `_enemy_base_completed()` อาจตั้ง flag ให้ board รู้ว่า tile ไหนต้องล้าง
- `scripts/board/board_tile.gd` — `_update_visual()` ต้องคืนสีปกติเมื่อ tile type เปลี่ยนกลับ

**วิธี fix ที่แนะนำ:** ให้ `board_manager` ตรวจ flag ตอน `_ready`/`move_to_tile`:
เมื่อ consume `pending_enemy_base_destroyed` หรือ `pending_enemy_base_outcome` → reset tile ตัวเก่า
(`GlobalData.enemy_base_tile_pos`) ให้เป็น `"combat"` + `_update_visual()`

---

## 2. DESIGN — enemy_base ติดอยู่ใน type_pool ตอน gen board

**ปัญหา:** `board_generator.gd` บรรทัด 64 มี `"enemy_base"` ใน type_pool (1/7) →
มี tile enemy_base เกิดแบบสุ่มโดยไม่เกี่ยวกับ spy system → เดินเข้าไปแล้ว raid ทั้งที่ยังไม่มี research node จริง

**ตัดสินใจได้:**
- (A) เอาออก `type_pool` ให้ enemy_base เกิดจาก spy system เท่านั้น ← **แนะนำ** (สอดคล้อง design)
- (B) เก็บไว้แต่เปลี่ยน `_process_tile_effect` ให้ raid เฉพาะเมื่อ `enemy_base_active` จริง (กรณีอื่น = combat)

---

## 3. POLISH — ambush ของ counter-unit ยังเหมือนกันหมด

**ปัจจุบัน:** `special_ace` กับ `gundam_copy` ambush เป็น `heavy_full` เหมือนกัน ต่างแค่ HP scale (1.8 vs 2.4)
ใน `scripts/systems/spawn_manager.gd` `_trigger_stalking_ace_ambush`

**ไอเดีย:** ทำให้แยกตัวตนชัดขึ้น เช่น special_ace → `heavy_full` เร็ว/โหด, gundam_copy → ใช้ enemy scene ที่เลียนแบบ player ตัวจริง (ถ้ามี), หรือเพิ่ม entry เฉพาะใน `enemy_scene_paths`

---

## 4. BALANCE — ยังไม่ได้ playtest จริง (ตัวเลขตั้งไว้ตามเหตุผล)

ตัวเลขปัจจุบัน (หลัง commit ล่าสุด):
- Spy attempt: soldier 0.12, scavenger 0.14, merc 0.16 + per tier 0.05-0.06
- Counter chance: `0.10 + security*0.008`, clamp 0.10-0.90 → security 25 = ~30%, 100 = 90%
- Security cost: 40/85/130/175/... (+45/cấp), +12 security/upgrade, max 100
- Research node: เกิดจาก 2 thefts, `enemy_base_required = 6` (จบใน 6 moves)
- Income: ปกติ 30-80/victory, boss +105, raid bonus +60/+10, spy caught bounty 20-50
- Grunt: hp/tier 0.22-0.30, grunt_upgrade +0.10/level, MKII grant +2

**สิ่งที่ควรเช็คตอน playtest:**
- [ ] รู้สึกถึง spy event กี่ครั้ง/board? (เป้า ~3-4 ครั้ง) → ปรับ `spy_base_chance` ใน `run_theme_catalogs.tres`
- [ ] security ตัวอ่อนเกินไปไหม (upgrade 40 ครั้งแรกควร "คุ้ม") → ปรับ `SECURITY_UPGRADE_BASE_COST`/`SECURITY_PER_UPGRADE`
- [ ] 6 moves พอจะลุยถึง node ได้จริงไหม (บอร์ด 7 ชั้น) → ปรับ `enemy_base_required` / placement layers
- [ ] enemy HP ตอนท้าย sector โหดไปไหม (hp_per_tier + wanted + grunt upgrade stack กัน) → ปรับ `escalation_hp_per_tier`
- [ ] raid bonus +60 คุ้มค่ากับความเสี่ยงไหม

---

## 5. TEST — เพิ่ม coverage ตาม feature ใหม่

- [ ] Test: หลัง destroy node → `_process_tile_effect("enemy_base")` ตอน `enemy_base_active=false` ต้องไม่เข้า raid (item 1)
- [ ] Test: `enemy_special_units` ถูก consume จริงใน combat (ตอนนี้ยังไม่มีโค้ด consume — เช็ค item 3 ว่าไม่ใช่ dead code)
- [ ] Test: stalking ace ที่เกิดจาก node เมื่อ player ชนะ → ถูก pop ออกจาก `stalking_aces`

---

## ไฟล์ที่เกี่ยวข้องหลัก

| ไฟล์ | บทบาท |
|---|---|
| `autoload/global_data.gd` | state + logic: fleet_security, spy, enemy_base, escalation |
| `scripts/board/board_manager.gd` | วาง node, spy roll ต่อ move, ต่อสู้ enemy_base |
| `scripts/board/board_generator.gd` | gen board + type_pool (item 2) |
| `scripts/systems/spawn_manager.gd` | wave + stalking ace ambush (item 3) |
| `resources/data/run_theme_catalogs.tres` | ค่าตัวเลขต่อ theme (item 4) |
| `scripts/ui/combat_rewards_ui.gd` | income/reward (item 4) |
| `scripts/ui/intermission_controller.gd` | status text: security, enemy base, stalking ace |
| `tests/refactor_qa_test.gd` | QA suite (item 5) |
