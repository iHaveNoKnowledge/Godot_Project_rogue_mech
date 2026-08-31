# WAR MODE — Battlefield + Red Alert Hybrid — Master Plan (โหมดใหม่ คู่กับโหมดเดิม)

> **ระบบเดิมเก็บไว้ทั้งหมด** — `Board` (Roguelike Convoy 25x25) ยังอยู่เหมือนเดิม `board_system.gd` / `game_manager.gd:State.BOARD`
> `War Mode` เป็นโหมดใหม่เลือกที่ Main Menu → เปิดเป็น `War Map` ใหญ่ 2 ฝั่ง — หุ่นธรรมดาเริ่ม → เก็บ Data/แร่ → วิจัย → สร้างหุ่นเทพ/Mass Product
> Engine: Godot 4.6.2.stable, reuse ระบบเดิม 70% (Hangar/Assembly/Repair/Pilot/Faction)

---

## 1. วิสัยทัศน์

**Battlefield Conquest + Red Alert Harvest** ไม่ใช่ Dota lane

* **2 โหมดคู่กัน:** `Campaign (Board)` เดิมยังเล่นได้ปกติ + `War Mode` แมพเดียว 2000x2000 กึ่ง open world หลายระดับ (ที่สูง/พื้น/อุโมงค์ใต้ดิน) ซ่อนทรัพยากร
* ต้อง **ขนส่ง (Logistic)** แร่/น้ำมันกลับ Storage ไม่ได้เข้าคลังทันที
* หา **Data** ตาม Event Area แบกกลับฐานวิจัย → สุ่มได้ Part เทพ / Frame เทพ / Module / สูตรเต็มตัว / หุ่นทั้งคัน
* มี **Module/Backpack/อาวุธไหล่ Q/E** ถอดได้ ตกให้ชิงได้ — หุ่นเทพตายกลางสนามกลายเป็นศึกชิงซาก
* รถ **Humvee / Truck / Tank / Carrier 2 หุ่น** + คลังอาวุธเคลื่อนที่ เปลี่ยนปืนกลางสนามได้
* กด **Tab ดูทรัพยากร / I ดู Inventory** (ใช้ได้ทั้ง 2 โหมด แต่ War Mode มีทรัพยากรเพิ่ม)

---

## 2. แมพ — ซับซ้อน ซ่อนของ

### 2.1 โครงสร้าง
* `scenes/war/war_world.tscn` แผ่นเดียว (เพิ่มใหม่ ไม่แทน `board/game_board.tscn` เดิม)
* Terrain เดียวด้วย `arena_generator.gd:333 _add_terrain_mesh()` + `HeightMapShape3D` `arena_generator.gd:755`
* แบ่ง 3 โซนตาม GDD Sub-Zone: `HIGHLAND` (เนินสูง sniper) / `GROUND` (crossroads) / `UNDERGROUND` (อุโมงค์ BoxMesh เพดาน + SpotLight)
* ซ่อน `Ore Node` 6-8 จุด + `Oil Well` 3 จุด + `Weapon Cache` 2 จุด ในซอกหุบ/ใต้ดิน — มองจากที่สูงไม่เห็น ต้องลาดตระเวนด้วย Humvee

### 2.2 ฐาน
* `Main Base` ฝั่งละ 1 (reuse `ForwardBase.spawn_base("fortified")` `forward_base.gd:39` HQ 220HP) มี `Storage Depot` + `Refinery` + `War Factory (Hangar)` + `Reactor Bay`
* ฐานย่อยไม่มี — ยึดด้วยทรัพยากร ไม่ใช่ capture point แบบเดิม

---

## 3. ทรัพยากร + Logistic

| ทรัพยากร | ได้จาก | เก็บยังไง | ใช้ทำอะไร |
|---|---|---|---|
| **Credits** | ขายแร่ที่ Depot, ฆ่าศัตรู | Auto เข้า `CurrencyManager` `global_data.gd:240` | คราฟท์ Part/อาวุธ, อัพฐาน |
| **Scrap** | แร่ Ore Node, ซากหุ่น | ต้องขนด้วย Truck → Depot | คราฟท์เกราะ/เฟรม |
| **Oil/Fuel** | Oil Well, ถังพก | ถัง `FuelContainerInventory` `fuel_container_inventory.gd` พกเติมกลางสนาม หรือขับกลับ Hangar เติม | พลังงานหุ่น `PowerCoreSystem` `GDD.md:152` |
| **Data** | Event Area | แบกกลับฐานวิจัย (CTF ช้าลง 20%) | สุ่ม Part/Module/สูตรเทพ |
| **Energy (หุ่นใหม่)** | เตาพิเศษในฐาน | สร้าง `Ancient Reactor` ที่ฐาน Lv3 ถึงผลิตได้ | เติมหุ่น Legendary ไม่กินน้ำมัน |

**Logistic Rule:** เก็บแร่/น้ำมันแล้วไม่เข้าคลัง — ต้องขับ `Truck` / `Carrier` กลับ `Storage Depot` กด `F` ถ่ายของ (reuse `convoy_escort.gd` + `FuelContainerInventory` ถังพก) ถูกดักปล้นระหว่างทางได้

---

## 4. ยานพาหนะ

| รถ | บทบาท | ขับยังไง |
|---|---|---|
| **Humvee** | ลาดตระเวนเร็ว หา Data/แร่ซ่อน | `pilot_controller.gd` สลับขึ้นลง `F` เหมือน `mecha_eject.gd` |
| **Truck** | ขนแร่/น้ำมัน จุเยอะ ช้า | มี `Storage` 200 scrap / 3 ถังน้ำมัน |
| **Tank** | ยิงแรง เกราะหนา ช้า | ปืนหลัก + ปืนรอง |
| **Carrier (ใหญ่)** | บรรทุกหุ่น 2 ตัว + คลังอาวุธเคลื่อนที่ | 2 ช่องจอดหลังกระบะ `Area3D` หุ่นกระโดดขึ้นล็อค → `HangarState` park, มี `Weapon Rack` 6 ช่อง + `Ammo Crate` ให้หุ่นโดดลงมาเปลี่ยนปืนกลางสนามได้, นักบินดีดจากหุ่น → ขึ้นขับ Carrier ได้ |

หุ่นคืออาวุธหลัก รถเป็น support/logistic

---

## 5. Data — 6 แบบ + คลังอาวุธ

**Event Area** สุ่มเกิด 2-3 จุด/5 นาที ขึ้น HUD "DATA ลึกลับ" → เข้าไปกด `F` เก็บ → แบกกลับฐาน (ถือแล้ววิ่งช้า) → กดวิจัยที่ `War Factory`

Roll Table (วิจัย 1 Data):

| ผล | โอกาส | ได้อะไร | หมายเหตุ |
|---|---|---|---|
| Part เทพ | 30% | เกราะแขน/ขา/หัว HP สูง | คราฟท์ไม่ได้ ต้องหา Data |
| Frame เทพ | 20% | เฟรมเบา/ถึกพิเศษ | ใส่แล้วเพิ่ม `carry_bonus` |
| Module เทพ | 20% | `frame_property_catalog` `global_data.gd:327` (Fission Core, FCS, Gyro, Roller Overdrive) ถอดได้ | ตกให้ชิงได้ |
| Data อาวุธ | 15% | `WeaponPart` `weapon_part.gd:4` เทพ (Railgun, Beam) |  |
| สูตรหุ่นเต็มตัว | 8% | Blueprint หุ่นเทพทั้งตัว | ต้องใช้แรร์ถึงคราฟท์ |
| หุ่นทั้งคัน | 2% | หุ่นเทพจอดกลางแมพ กดขึ้นขับได้เลย | เอากลับฐานวิจัยต่อได้ |

**Weapon Cache** จุดซ่อนถาวร 2 จุด เปิดแล้วได้อาวุธ/โล่สุ่ม (reuse `LootSystem`)

---

## 6. Module / Backpack / อาวุธไหล่ — ถอดได้ ตกชิงได้

* **Module** = `frame_property_catalog` 20 รายการเดิม ติด Slot `head/body/arm/leg` ถอดได้ใน Hangar ยิงตก → เป็น `LootPickup` ให้เก็บ (reuse `ScavengerSystem` + `salvage_system.gd`)
* **Backpack** = `Attachment` ใหม่ต่อยอด `hangar_state.gd`
  * `Cargo` +จุ 40kg
  * `Booster` +Roller Dash 30%
  * `Combat` +เกราะ/ระบายความร้อน
* **อาวุธไหล่** = Slot ใหม่ `shoulder_left` / `shoulder_right` `weapon_part.gd:4` กด `Q` ไหล่ซ้าย / `E` ไหล่ขวา (เพิ่ม Input `project.godot:46` แยกจาก `fire_left/right` เมาส์) ใส่โล่ไหล่หรือ Missile Pod ได้

หุ่นเทพตาย → ซากไม่หาย + Module/Backpack/Part เทพหล่น → ใครเก็บได้เอาเข้า Hangar ติดตัวอื่นได้ → ศึกชิงซาก

---

## 7. สูตรเต็มตัว vs Mass Product (รวม Stunt/EMP เฉพาะ Reactor)

* ได้ **หุ่นทั้งคัน** หรือ **สูตร** → เอากลับฐานวิจัย → ปลด 2 ทาง:
  * **Original** 100% — ต้องใช้ `Ancient Core` + Data + scrap 200 + credits 800 แพง/แรร์
  * **Mass Product** 75% — ใช้ scrap 80 + credits 400 คราฟท์ได้เรื่อยๆ ใน `craft_panel.gd` สเปคต่ำกว่า 20% แต่ทุนถูก
* Mass Product ตายก็ตกให้ชิงได้เหมือนกัน

---

## 7.5 นักบินสำคัญ + 6 Part เดิม + Stunt/EMP เฉพาะ Reactor

* **หุ่น = 6 Part เดิม** `head/body/arm_left/arm_right/leg_left/leg_right` `global_data.gd:90` + `part_mesh_manager.gd:335` — War Mode ไม่เปลี่ยนโครงสร้างนี้
* **นักบินสำคัญ:** หุ่นพัง (`HP 0`) → ระเบิดใน 3-4 วิ ถ้าดีด `G` (`mecha_eject.gd` `GameManager.State.EJECT` `game_manager.gd:162`) ไม่ทัน = นักบินตาย → `Respawn` เลือกฐานฝั่งเราได้ (`Main Base` หรือ `Carrier` ที่จอดในเขตเรา) — reuse `pilot_state.gd` + `hangar_state.gd` เลือกจุดเกิด
* ถ้าตายแต่หุ่นยังอยู่ → หุ่นจอดที่เดิมเป็นซาก `ScavengerSystem` ไม่หาย ใครยึดได้เอาไปขับ/วิจัยต่อ — ยิ่งหุ่นเทพ Tech สูงยิ่งเสี่ยงโดนขโมย (ถ่วงดุล)
* **Stunt Weapon:** อาวุธประเภท `STUNT` ใหม่ `weapon_part.gd:4` ยิงแล้วติด `stunned` 2-4 วิ ขยับไม่ได้ (reuse `ewar_system.gd` + `heat_wanted_system.gd` EMP เดิม `GDD.md:188` แต่แยกเป็นดีบัฟ Stunt)
  * **เฉพาะ Reactor:** `Direct Combustion` โดน Stunt นานสุด / `Overclocked Hybrid` กลาง / `Ancient/Legendary` ทน Stunt สูง (หรือกัน 100%) — `power_core_system.gd` + `WeaponPart.damage_type="stunt"` เช็ค `target.reactor_type` ก่อนติดสถานะ ไม่ใช่ยิงใส่ทุกหุ่นแล้วติดหมด

---

## 8. UI — Tab / I

* เพิ่ม Input `project.godot:46` `resource_view` = Tab (hold) / `inventory` = I
* **Tab** → Overlay `WarResourceHUD` โชว์ Credits/Scrap/Fuel/Ore/Oil/Data/Energy (ดึงจาก `CurrencyManager` + `FuelManager`)
* **I** → `WarInventory` เต็มจอ โชว์ Part/Frame/Module/Backpack/อาวุธมือ+ไหล่ ที่ถือ/ติดอยู่ ถอด/ติดได้

---

## 9. สถาปัตยกรรมใหม่ (เพิ่ม Pilot/Stunt)

```
GameManager.State.BOARD (เดิม) + GameManager.State.WAR (ใหม่คู่กัน)
  Main Menu → [CAMPAIGN (Board)] / [WAR MODE]  → เลือกโหมด
  enter_board() → game_board.tscn (เดิม)
  enter_war()   → war_world.tscn (ใหม่)
  Hangar/Repair/Pilot/Faction ใช้ร่วมกันทั้ง 2 โหมด

scenes/war/
  war_world.tscn              แมพใหญ่ + Main Base 2 ฝั่ง
  war_resource_hud.tscn       Tab overlay
  war_inventory.tscn          I inventory

scripts/war/
  war_manager.gd              ควบคุมรอบ, ชนะ/แพ้ (ทำลาย HQ 220HP)
  war_map_generator.gd        ต่อยอด arena_generator สร้าง Terrain + วาง Ore/Oil/Cache
  war_resource_system.gd      tick รายได้, Refinery Lv
  war_logistic_system.gd      Truck/Carrier ขนของ → Depot
  data_event_system.gd        สุ่ม Event Area + แบกกลับ + roll table
  capture_wreckage_system.gd  ซากหุ่นเทพชิงได้ (ต่อยอด scavenger_system.gd)
  war_respawn_system.gd       ตายเลือกฐานเกิด + หุ่นจอดที่เดิม + โดนขโมยได้
  pilot_survival_system.gd    หุ่นระเบิด 3วิ ต้องดีดทัน / EMP เฉพาะ Reactor
  stunt_weapon_system.gd      อาวุธ Stunt 2-4วิ เฉพาะ Reactor (ต่อยอด ewar_system.gd)
  vehicle_controller.gd       Humvee/Truck/Tank/Carrier (ต่อยอด pilot_controller.gd)
  carrier_dock.gd             2 ช่องจอด + Weapon Rack
  backpack_system.gd          ต่อยอด hangar_state.gd
  shoulder_weapon_system.gd   Q/E (6 Part เดิมไม่เปลี่ยน)
  war_hud.gd                  Tab/I
```

Reuse 100%: `PartMeshManager`, `RepairSystem`, `Hangar`, `PilotSystem`, `FactionSystem`, `PowerCoreSystem`, `WeaponInventoryState`

---

## 10. เฟสทำ

**Phase 1 — MVP 2 สัปดาห์ (เล่นได้)**
* [ ] `GameManager.State.WAR` + `war_world.tscn` โล่ง + Main Base 2 ฝั่ง (เก็บ Board เดิมไว้)
* [ ] Ore Node 4 จุด + Truck ขนกลับ Depot + Tab HUD
* [ ] Data Event 1 แบบ (Part เทพ) แบกกลับวิจัย
* [ ] Carrier 1 คัน บรรทุก 2 หุ่น + Weapon Rack เปลี่ยนปืนกลางสนาม
* [ ] Module ถอดได้ 3 ตัว + ตกชิงได้
* [ ] Pilot ดีด 3วิ + Respawn เลือกฐาน + หุ่น 6 Part เดิม + Stunt เฉพาะ Reactor (Combustion โดนนาน / Ancient กัน)

**Phase 2 — เต็ม 4 สัปดาห์**
* [ ] แมพซับซ้อน HIGHLAND/UNDERGROUND ซ่อนของ + Weapon Cache
* [ ] Data ครบ 6 แบบ + สูตรเต็มตัว/Mass Product + หุ่นทั้งคัน 2%
* [ ] Backpack 3 แบบ + อาวุธไหล่ Q/E + โล่ไหล่
* [ ] เตาพิเศษ Ancient Reactor + น้ำมันถังพกเติมกลางสนาม
* [ ] I Inventory เต็ม + ระบบชิงซากหุ่นเทพ

**Phase 3 — Polish**
* [ ] Minimap + Fog of War + Convoy ถูกปล้นระหว่างขน
* [ ] Balance ราคา Original vs Mass, เรทดรอป, ความจุ Carrier

---

## 11. หมายเหตุ

* Godot 4.6.2 path: `D:\godot\Godot_v4.6.2-stable_win64.exe` — validate ด้วย `--headless --import`
* ทุกเฟสจบ commit + push ตาม `AGENTS.md`
* สูตรหุ่นเทพใช้ทรัพยากรแรร์จริง แต่ Mass Product ให้ผู้เล่นทุนน้อยก็เล่นได้ — ไม่ pay-to-win
