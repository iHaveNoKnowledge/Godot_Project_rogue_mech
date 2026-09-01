# WAR MODE — Battlefield + Red Alert Hybrid — Master Plan (โหมดใหม่ คู่กับโหมดเดิม)

> **ระบบเดิมเก็บไว้ทั้งหมด** — `Board` (Roguelike Convoy 25x25) ยังอยู่เหมือนเดิม `board_system.gd` / `game_manager.gd:State.BOARD`
> `War Mode` เป็นโหมดใหม่เลือกที่ Main Menu → เปิดเป็น `War Map` ใหญ่ 2 ฝั่ง — หุ่น `Valkren Class` ธรรมดาเริ่ม → เก็บ Data/แร่ → วิจัย → สร้าง Valkyrion/Mass Product
> Engine: Godot 4.6.2.stable, reuse ระบบเดิม 70% (Hangar/Assembly/Repair/Pilot/Faction)

---

## สารบัญ

1. [วิสัยทัศน์ & IP Naming](#1-วิสัยทัศน์--ip-naming-conventions)
2. [แมพ & จุดยึดส่งกำลังพล](#2-แมพ--จุดยึดส่งกำลังพล-spawn-locations)
3. [ทรัพยากร + Logistic](#3-ทรัพยากร--logistic)
4. [ยานพาหนะ & Carrier Physics](#4-ยานพาหนะ--carrier-physics-rules)
5. [Valkren Classification & Evolution Schema](#5-valkren-classification--evolution-schema-tech-tree)
6. [Combat Scale, Deploy Cap & Ace Right](#6-combat-scale-deploy-cap--ace-right-system)
7. [Dynamic Launch Setup, Realtime Hangar & System Details](#7-dynamic-launch-setup-realtime-hangar--system-details)
8. [สถาปัตยกรรมไฟล์](#8-สถาปัตยกรรมไฟล์-scripts--scenes)
9. [แผนการดำเนินงาน (Phases)](#9-แผนการดำเนินงาน-phases-progress)
10. [Performance & Engine (Godot 4.6 Specifics)](#10-performance--engine-godot-46-specifics)
11. [ระบบเซฟ & แยกโหมด](#11-ระบบเซฟ--แยกโหมด-save-system)
12. [Input Map & Controls (War Mode)](#12-input-map--controls-war-mode)
13. [Audio / VFX / UI Polish](#13-audio--vfx--ui-polish)
14. [Testing & QA Checklist](#14-testing--qa-checklist)
15. [Risks & Mitigations](#15-risks--mitigations)
16. [Glossary & หมายเหตุ](#16-glossary--หมายเหตุ)

---

## 1. วิสัยทัศน์ & IP Naming Conventions

**Battlefield Conquest + Red Alert Harvest (Valkren Tactical Combat)**

* **2 โหมดคู่กัน:** `Campaign (Board)` เดิมยังเล่นได้ปกติ + `War Mode` แมพเดียว 2000x2000 กึ่ง open world หลายระดับ (ที่สูง/พื้น/อุโมงค์ใต้ดิน) ซ่อนทรัพยากร
* **IP Classification — `Valkren` vs `Valkyrion`:**
  * **Valkren (วาลเครน):** ศัพท์เรียกสปีชีส์/ประเภทจักรกลรบหลักทั้งหมดในสนามรบ (เทียบเท่า Mobile Suit)
  * **Valkyrion (วาลคิริออน):** ชื่อเรียกหุ่นต้นแบบสเปกสุดยอด / Secret Frame ที่ขับเคลื่อนด้วย Ancient Core
  * **Combat Hierarchy:** `Valkyrion (Apex)` > `Valkren Class` > `Tank Class` > `Infantry / Pilot Class`
  * **จุดเด่น Valkren:** ความคล่องตัวสูง (High Mobility), ตอบสนองไว (High Response), และความต่อเนื่องในการโจมตีสูงมาก (Offensive Continuity / Seamless Fire-on-Move)
  * **วิวัฒนาการเกราะ:** ยุคแรกเกราะอาจเบากว่ารถถังเน้นหลบหลีก แต่เมื่ออัปเกรด (Upgraded Gen) เกราะจะแข็งแกร่งทนทานกว่ารถถังยุคเก่าอย่างเห็นได้ชัด
* **ระบบ ขนส่ง (Logistic):** แร่/น้ำมัน ต้องแบกกลับ Storage Depot ไม่ได้เข้าคลังทันที
* **หา Data:** ตาม Event Area แบกกลับฐานวิจัย → สุ่มได้ Valkren Part / Frame / Module / Blueprint / Valkyrion ทั้งคัน
* **อุปกรณ์ถอดได้/ตกชิงได้:** Module/Backpack/อาวุธไหล่ Q/E — เมื่อ Valkren/Valkyrion พังกลางสนามจะกลายเป็นศึกชิงซาก
* **ยานพาหนะ Support:** Humvee / Truck / Tank / Carrier (คลังอาวุธเคลื่อนที่ + จุด Spawn)
* **UI Input:** กด **Tab ดูทรัพยากร (`WarResourceHUD`) / I ดู Inventory (`WarInventory`)**

### Reuse 70% — แยกของใหม่ vs ของเดิม

| ระบบ | Reuse ของเดิม | ของใหม่ War Mode |
|------|---------------|-----------------|
| Hangar/Assembly/Repair | `hangar_state.gd`, `repair_system.gd`, `part_mesh_manager.gd` | `war_realtime_hangar.gd` (Overlay บนแมพจริง) |
| Combat/Weapon/Projectile | `spawn_manager.gd`, `weapon_core.gd`, `projectile.gd`, `loot_system.gd` | `stunt_weapon_system.gd`, `shoulder_weapon_system.gd` (Q/E) |
| Pilot/Eject | `mecha_eject.gd`, `pilot_controller.gd`, `pilot_state.gd` | `war_ai_jump_system.gd` + HQ Shield |
| Board/Faction | `PilotGenerator`, `RecruitSystem`, `FactionSystem` | `WarManager` + Barracks Lv 4/8/12 |
| Arena/Terrain | `arena_generator.gd` | `war_map_generator.gd` (HIGHLAND/UNDERGROUND) |

---

## 2. แมพ & จุดยึดส่งกำลังพล (Spawn Locations)

### 2.1 โครงสร้างแมพ

* `scenes/war/war_world.tscn` แผ่นเดียว (`war_world.gd`)
* Terrain เดียวด้วย `arena_generator.gd:333 _add_terrain_mesh()` + `HeightMapShape3D` `arena_generator.gd:755`
* แบ่ง 3 โซนตาม GDD Sub-Zone: `HIGHLAND` (เนินสูง sniper) / `GROUND` (crossroads) / `UNDERGROUND` (อุโมงค์ซ่อนของ + SpotLight)
* ซ่อน `Ore Node` 6-8 จุด + `Oil Well` 3 จุด + `Weapon Cache` 2 จุด ในซอกหุบ/ใต้ดิน — มองจากที่สูงไม่เห็น ต้องลาดตระเวนด้วย Humvee

### 2.2 ฐาน & จุด Spawn แนวหน้า

* **Main Base (War Factory):** ฐานหลักฝั่งละ 1 (`forward_base.gd:39` HQ 220HP) มี `Storage Depot` + `Refinery` + `War Factory (Hangar)` + `Reactor Bay` (เกิด Valkren ได้ทุก Class และ Valkyrion)
* **Mobile Carrier (Deploy Mode):** จุดเกิดยูนิต `Valkren Line-Issue` และ `Vehicles` แนวหน้า เคลื่อนที่ได้
* **Forward Storage Depot:** ยึดจุดยุทธศาสตร์เพื่อส่งกำลังบำรุง และเป็นจุดเกิด `Valkren Line-Issue` / `Truck` / `Humvee` (ห้ามเกิด Valkyrion)
* **Supply Beacon / Drop Pod:** ให้ Infantry เรียก Drop Pod ส่ง `Line-Valkren` ลงตำแหน่งแนวหน้า (จ่าย Resource เพิ่ม 2 เท่า)
* **กำลังคน:** ขึ้นกับ `Barracks Lv` ใน `Main Base/ForwardBase` (Lv1=4 คน, Lv2=8, Lv3=12) + `Pilot Pool` สุ่มจาก `PilotGenerator` + เงินจ้าง `RecruitSystem` เดิม — อัพ Barracks ถึงเพิ่มคนได้

---

## 3. ทรัพยากร + Logistic

| ทรัพยากร   | ได้จาก                               | เก็บยังไง                                                                                                               | ใช้ทำอะไร                                          |
| ------------------ | ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| **Credits**  | ขายแร่ที่ Depot, ฆ่าศัตรู | Auto เข้า`CurrencyManager` (`global_data.gd:240`)                                                                        | คราฟท์ Part/อาวุธ, อัพฐาน                  |
| **Scrap**    | แร่ Ore Node, ซาก Valkren            | ต้องขนด้วย Truck → Depot                                                                                              | คราฟท์เกราะ/เฟรม                             |
| **Oil/Fuel** | Oil Well, ถังพก                       | ถัง`FuelContainerInventory` (`fuel_container_inventory.gd`) พกเติมกลางสนาม หรือกลับ Hangar เติม | พลังงาน Valkren (`PowerCoreSystem` `GDD.md:152`) |
| **Data**     | Event Area                                 | แบกกลับฐานวิจัย (ถือแล้ววิ่งช้าลง 20%)                                                            | สุ่ม Part/Module/สูตรวิจัย Valkren             |
| **Energy**   | เตาพิเศษ Ancient Reactor           | สร้างที่ฐาน Lv3 ถึงผลิตได้                                                                                  | เติม Valkyrion สเปกล้ำ ไม่กินน้ำมัน  |

**Logistic Rule:** เก็บแร่/น้ำมันแล้วไม่เข้าคลัง — ต้องขับ `Truck` / `Carrier` กลับ `Storage Depot` กด `F` ถ่ายของ (`convoy_escort.gd` + `FuelContainerInventory` ถังพก) ถูกดักปล้นระหว่างทางได้

---

## 4. ยานพาหนะ & Carrier Physics Rules

| ยานพาหนะ             | บทบาท                                                           | ขับยังไง / สเปค                                                                                                                                                                                                                                                                        |
| ---------------------------- | -------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Humvee**             | ลาดตระเวนเร็ว หา Data/แร่ซ่อน                  | `pilot_controller.gd` สลับขึ้นลง `F` เหมือน `mecha_eject.gd`                                                                                                                                                                                                                 |
| **Truck**              | ขนแร่/น้ำมัน จุเยอะ ช้า                          | AI ขับอัตโนมัติ`NavigationAgent3D` บน Terrain (รวม UNDERGROUND) ส่งของ Depot→Depot / ผู้เล่นยึดขับเองได้ มี Storage 200 scrap / 3 ถังน้ำมัน                                                                                                |
| **Tank**               | ยิงแรง เกราะหนา ยิงนัดเดียวหนัก (Burst) | เคลื่อนที่ช้า หมุนป้อมช้า เป็นเหยื่อของ Valkren                                                                                                                                                                                                               |
| **Carrier (ใหญ่)** | บรรทุก Valkren 2 ตัว + คลังอาวุธ                   | **Physics Rule:** AI `Automated Logistic Track` วิ่งตามเส้นทาง Depot / ผู้เล่นยึดขับได้. 2 ช่องจอดหลังกระบะ `Area3D` กด Dock → สั่ง `FREEZE` Physics + `Reparent` เป็น Child ของ Carrier แก้ปัญหา Physics Jitter |

---

## 5. Valkren Classification & Evolution Schema (Tech Tree)

วิวัฒนาการสายการวิจัยแบ่งออกเป็น 4 Class หลัก:

1. **Valkren Line-Issue (Standard Frame):** Valkren รุ่นผลิตจำนวนมาก (Mass Product) อะไหล่หาง่าย คล่องตัว สมดุล
2. **Valkren Iron-Vanguard (Heavy Armored Walker):** อดีตสุดยอดป้อมปราการเดินได้ ติดตั้งป้อมปืนใหญ่และเกราะหนา รับแรงปะทะแนวหน้า (Walk-Tank)
3. **Valkren Strike-Apex (High-Mobility & EWAR):** อดีตหุ่นความเร็วสูงสุด เฟรมเบา ติดล้อสายพาน/Booster ก่อกวนและยึดพื้นที่ฉับไว
4. **Valkyrion Prime (Apex Secret Branch):** หุ่นต้นแบบสเปกสูง ปลดล็อกจากการวิจัย Data Event กลางสนามรบ ขับเคลื่อนด้วย Ancient Core

**Data Roll Table (วิจัย 1 Data):**

* Part เทพ (30%) / Frame เทพ (20%) / Module เทพ (20%) / Data อาวุธ (15%) / Blueprint หุ่นเต็มตัว (8%) / Valkyrion ทั้งคัน (2%)
* **Original (100% Spec):** ใช้ `Ancient Core` + Data + scrap 200 + credits 800 (แพง/แรร์)
* **Mass Product (75% Spec):** ใช้ scrap 80 + credits 400 คราฟท์ได้เรื่อยๆ ใน `craft_panel.gd`

---

## 6. Combat Scale, Deploy Cap & Ace Right System

### 6.1 Combat Scale (15-20 Active Units / Faction)

* **ผู้เล่น (Player):** 1-4 คน (Solo: ผู้เล่น 1 + AI Squad 3)
* **Ally Commander AI:** 3-5 ตัว (ขับ Valkren / Tank)
* **Logistic AI:** 2-3 ตัว (ขับ Truck / Carrier อัตโนมัติ)
* **Enemy AI:** 8-12 ตัว (คุม Valkren, Tank, และ Logistic)
* *Performance Note:* ใช้ Simplified AI Navigation สำหรับยูนิตระยะไกล เพื่อคุม Frame Rate ที่ 60+ FPS บน Godot 4.6

### 6.2 Deploy Cap & Stock Cooldown

* **จำกัดโควตาประจำการ (Deploy Cap):** ควบคุมเพดานยูนิตสนามรบ เช่น `Line-Valkren: 5/5`, `Strike/Iron: 3/3`, `Valkyrion: 1/1`
* **Stock Respawn Timer:** เมื่อ Valkren/Valkyrion พัง สต็อกยูนิตจะติดคูลดาวน์เติมสต็อก (3-5 นาทีสำหรับ Valkyrion)
* **การซ่อมบำรุงใน Hangar/Carrier:** ถอยกลับมาซ่อม ใช้เวลาเพียง 15-30 วินาที ไม่เสียคูลดาวน์สต็อก บังคับให้การถอยซ่อมคุ้มค่ากว่าปล่อยระเบิด

### 6.3 สิทธิ์การขับ Valkyrion (Apex Right System)

* **Single-Player:** ผู้เล่นได้สิทธิ์เด็ดขาดในการสั่ง Deploy ขับเอง หรือมอบหมายให้ AI Ace Pilot ในทีม
* **Multiplayer / Team Play (Hybrid Ace System):**
  * เมื่อ Valkyrion พร้อมใช้งาน ผู้เล่นที่มีคะแนน Merit / Score สูงสุดในทีม (Ace Pilot) จะได้รับสิทธิ์จองขับก่อน 30 วินาที
  * หาก Ace ไม่กดรับสิทธิ์ ระบบจะเปิด Public ให้ผู้เล่นคนอื่นในทีมกด Spawn ลงสนามแทนได้ทันที

---

## 7. Dynamic Launch Setup, Realtime Hangar & System Details

* **Dynamic Launch Setup Interface:** ก่อนกด Spawn Valkren/Valkyrion ลงสนาม เลือก Quick Launch หรือ Custom Fitting สลับ Main Hand, Off-Hand, Backpack, และอาวุธไหล่ Q/E ได้สดๆ
* **Realtime Hangar (War Mode):** Hangar ตั้งอยู่ที่ `Main Base`/`Carrier`/`ForwardBase` บนแมพจริง กด `F` เปิด Overlay UI ซ่อม/แต่งหุ่นได้ทันที ไม่ตัดฉาก
* **Module / Backpack / อาวุธไหล่ Q/E:**
  * Module = `frame_property_catalog` 20 รายการเดิม (ถอดได้/ตกชิงได้)
  * Backpack = `Cargo` (+40kg), `Booster` (+30% Dash), `Combat` (+เกราะ/ระบายความร้อน)
  * อาวุธไหล่ = Slot `shoulder_left` (Q) / `shoulder_right` (E) ใส่ Missile Pod หรือ Shield
* **Pilot & Ejection System:** หุ่นพัง (`HP 0`) → ระเบิดใน 3-4 วิ ดีดตัว `G` (`mecha_eject.gd`) ไม่ทัน = นักบินตาย. AI มีระบบ `war_ai_jump_system.gd` กระโดดข้ามสิ่งกีดขวาง
* **Stunt Weapon & Reactor Response:** อาวุธ Stunt ยิงติดชะงัก 2-4 วิ โดย `Direct Combustion` โดนผลหนักสุด ส่วน `Ancient Reactor (Valkyrion)` มีแรงต้านทาน Stunt สูงสุด

---

## 8. สถาปัตยกรรมไฟล์ (Scripts & Scenes)

```text
GameManager.State.BOARD (เดิม) + GameManager.State.WAR (ใหม่คู่กัน)
  enter_board() → game_board.tscn (เดิม)
  enter_war()   → war_world.tscn (ใหม่)

scenes/war/
  war_world.tscn              แมพใหญ่ + Main Base 2 ฝั่ง
  war_resource_hud.tscn       Tab overlay          ⏳ TODO — ปัจจุบันใช้ war_hud.gd แบบ CanvasLayer ชั่วคราว
  war_inventory.tscn          I inventory          ⏳ TODO — ปัจจุบัน logic อยู่ใน war_hud.gd
  war_launch_setup_ui.tscn    หน้าเลือก Fitting/Preset/Ace Right ก่อน Spawn  ⏳ TODO

scripts/war/ — สถานะปัจจุบัน (ตรวจสอบ 2026-09-01)
  ✅ war_world.gd              แมพใหญ่ + Ground + Bases + Spawn
  ✅ war_manager.gd            ควบคุมรอบ, ชนะ/แพ้ (HQ 220HP) — skeleton, SAVE_WAR_PATH = user://save_war.json
  ✅ war_map_generator.gd      HIGHLAND/UNDERGROUND + Weapon Cache + Occluder
  ✅ war_logistic_system.gd    Truck/Carrier ขนของ → Depot
  ✅ war_data_event.gd         สุ่ม Event Area + แบกกลับ + roll table (data_event_system.gd ตามแผน = ตัวเดียวกัน)
  ✅ war_production_queue.gd   คิวคราฟท์/ซ่อม 60-180วิ + เร่งได้
  ✅ war_merchant_system.gd    พ่อค้า Part พร้อมใช้ สุ่มเกิด 2-3นาที
  ✅ war_salvage_dispatch.gd   ศัตรูดรอป Part/อาวุธ + เรียกรถจากฐานสาขาไปเก็บ
  ✅ war_ore_node.gd           Ore/Oil Node + FuelContainer
  ✅ war_module_system.gd      Module ถอดได้/ตกชิงได้
  ✅ war_reactor_bay.gd        เตาพิเศษ Ancient Reactor
  ✅ war_valkyrion_system.gd    Roll 6 แบบ + Original/Mass craft
  ✅ war_balance.gd            ค่าคงที่สมดุล (Original/Mass, Drop, Barracks, Carrier, HQ)
  ✅ war_minimap.gd            Minimap + Fog of War
  ✅ war_convoy_ambush.gd      ระบบดักปล้น Convoy
  ✅ war_realtime_hangar.gd    Hangar Overlay บนแมพจริง
  ✅ war_hud.gd                Tab/I HUD
  ✅ war_ai_jump_system.gd     AI โดดข้ามสิ่งกีดขวาง (RayCast + Jump)
  ✅ carrier_dock.gd           2 ช่องจอด + Dock = FREEZE + Reparent
  ✅ backpack_system.gd        Cargo/Booster/Combat
  ✅ shoulder_weapon_system.gd Q/E (6 Part เดิมไม่เปลี่ยน)
  ✅ stunt_weapon_system.gd    อาวุธ Stunt 2-4วิ เฉพาะ Reactor
  ✅ war_camera_follow.gd      WarCamera follow (fallback, หลักใช้ mecha_camera.tscn)
  ⏳ war_deployment_manager.gd จัดการ Deploy Cap + Stock Cooldown — ยังไม่สร้าง (logic ชั่วคราวอยู่ใน war_valkyrion_system.gd)
  ⏳ development_node_resource.gd Resource โครงสร้าง Tech Tree — ยังไม่สร้าง (ใช้ Dictionary ใน war_valkyrion_system.gd)
  ⏳ war_resource_system.gd    tick รายได้, Refinery Lv — ยังไม่แยกไฟล์ (logic อยู่ใน war_logistic_system.gd + war_manager.gd)
  ⏳ capture_wreckage_system.gd ซาก Valkyrion ชิงได้ — ยังไม่แยกไฟล์ (อยู่ใน war_salvage_dispatch.gd)
  ⏳ war_respawn_system.gd     ตายเลือกฐานเกิด + หุ่นจอดที่เดิม — ยังไม่แยกไฟล์ (ใช้ pilot_state.gd + hangar_state.gd)
  ⏳ pilot_survival_system.gd  หุ่นระเบิด 3วิ ต้องดีดทัน — ยังไม่แยกไฟล์ (ใช้ mecha_eject.gd)
  ⏳ vehicle_controller.gd     Humvee/Truck/Tank/Carrier AI Track — ยังไม่แยกไฟล์ (ใช้ war_logistic_system.gd)
```

> Reuse 100%: `PartMeshManager`, `RepairSystem`, `Hangar`, `PilotSystem`, `FactionSystem`, `PowerCoreSystem`, `WeaponInventoryState`, `SpawnManager`, `EffectManager`, `LootSystem`, `ConvoyEscort`, `ArenaSeedSystem`

---

## 9. แผนการดำเนินงาน (Phases Progress)

### Phase 1 — MVP 2 สัปดาห์ (เล่นได้) — ✅ เสร็จหมดแล้ว (commit e711ac8 -> 609b2fa)

- [x] GameManager.State.WAR + war_world.tscn โล่ง + Main Base 2 ฝั่ง
- [x] Ore Node 4 จุด + Truck ขนกลับ Depot + Tab HUD
- [x] Deploy Cap skeleton + Stock Cooldown (ชั่วคราวใน war_valkyrion_system.gd — รอแยกเป็น war_deployment_manager.gd)
- [x] Data Event 1 แบบ (Part เทพ) แบกกลับวิจัย
- [x] Carrier 1 คัน + Docking Physics (Freeze & Reparent)
- [x] Module ถอดได้ 3 ตัว + ตกชิงได้
- [x] Pilot ดีด 3วิ + Respawn เลือกฐาน + หุ่น 6 Part เดิม + Stunt เฉพาะ Reactor
- [x] คราฟท์/ซ่อมใช้เวลา (คิว 60-180วิ) + พ่อค้า Part พร้อมใช้สุ่มเกิด

### Phase 2 — เต็ม 4 สัปดาห์ — ✅ เสร็จหมดแล้ว

- [x] แมพซับซ้อน HIGHLAND/UNDERGROUND ซ่อนของ + Weapon Cache (`war_map_generator.gd`)
- [x] Data ครบ 6 แบบ + สูตรเต็มตัว/Mass Product + หุ่นทั้งคัน 2% (`war_valkyrion_system.gd`)
- [x] Backpack 3 แบบ + อาวุธไหล่ Q/E + โล่ไหล่ (`backpack_system.gd` / `shoulder_weapon_system.gd`)
- [x] เตาพิเศษ Ancient Reactor + น้ำมันถังพกเติมกลางสนาม (`war_reactor_bay.gd`)
- [x] I Inventory เต็ม + ระบบชิงซากหุ่นเทพ + ระบบเรียกรถขนซากจากฐานสาขา (`war_salvage_dispatch.gd`)
- [x] Dynamic Launch Setup skeleton + Ace Right System (logic ใน `war_valkyrion_system.gd` — รอแยก UI เป็น `war_launch_setup_ui.tscn`)

### Phase 3 — Polish

- [x] Minimap + Fog of War + Convoy ถูกปล้นระหว่างขน (`war_minimap.gd`, `war_convoy_ambush.gd`)
- [ ] Balance ราคา Original vs Mass, เรทดรอป, ความจุ Carrier — (`war_balance.gd` ปรับจูนจริงระหว่าง Playtest) ⏳ รอ Playtest

---

## 10. Performance & Engine (Godot 4.6 Specifics)

### 10.1 Terrain & Occlusion — แมพ 2000x2000 + Ore/ซากหุ่น

**ปัญหา:** Object/Ore/ซากหุ่นจำนวนมาก + `SpotLight3D` หลายดวงใน UNDERGROUND → ไม่มี culling เฟรมตก

**แก้:**

* **Chunk Loader:** แบ่งแมพ 16x16 chunk (125m) — โหลด/ซ่อน `Ore Node`/`Scrap`/`Wreckage` ตาม `VisibilityNotifier3D` + ระยะผู้เล่น
* **OccluderInstance3D:** ใส่ `OccluderInstance3D` + `Occluder3D` Box ที่ปากอุโมงค์และผนังใต้ดิน → บัง UNDERGROUND ทั้งโซนเมื่อผู้เล่นอยู่บนพื้น ลด draw call `SpotLight3D`
* **Terrain LOD:** ใช้ `HeightMapShape3D` chunk เดียวกับ mesh, ปิด shadow ของ Ore ไกล >150m
* **MultiMeshInstance3D:** หิน/แร่ซ้ำๆ ใช้ MultiMesh แทน MeshInstance3D แยก

### 10.2 Navigation 2 ชั้น + Link

* `NavigationAgent3D` bake แยก `GROUND` vs `UNDERGROUND` (2 `NavigationRegion3D`)
* **ข้ามชั้น:** ใส่ `NavigationLink3D` ตรงปากอุโมงค์/ทางลง เชื่อม 2 Region ให้ Agent คำนวณ Path ข้ามไร้รอยต่อ

### 10.3 Micro Edge Cases

* **HQ Barrier Shield (Anti-Rush):** HQ 220HP มี barrier ลดดาเมจ 90% จนกว่าศัตรูบุกในรัศมี 100m ของฐาน หรือถึง Late Game นาที 10+ (`war_world.gd:118 _add_hq_shield()` + `SphereShape3D radius 100` + `Timer 600s`)
* **เซฟแยกโหมด:** War Mode กับ Campaign (Board) แยกเซฟคนละไฟล์ `user://save_war.json` vs `user://savegame.json` ไม่แชร์ Part/เงิน/Progress (`war_manager.gd:7 SAVE_WAR_PATH`)
* **Camera:** War Mode ใช้ `MechaCamera` เดียวกับ Campaign (`war_world.gd:159 _ensure_war_camera()` — PhantomCamera) ไม่ใช่ WarCamera แยก

---

## 11. ระบบเซฟ & แยกโหมด (Save System)

| โหมด | ไฟล์เซฟ | เนื้อหา | แชร์กันไหม |
|------|---------|---------|------------|
| Campaign (Board) | `user://savegame.json` | Board tiles, Day, Convoy, Hangar roster, Parts, Credits | ❌ แยก |
| War Mode | `user://save_war.json` | War HQ HP, Ore nodes, Data research, Carrier, Stock Cooldown | ❌ แยก |

* `GameManager.enter_war()` / `enter_board()` สลับโหมด — `HangarManager.save_active()` ก่อนเปลี่ยนฉากเสมอ (`game_manager.gd:166`)
* War save ยังเป็น skeleton (`war_manager.gd:7`) — ต้องเพิ่ม `WarSaveIO` (serialize: ore collected, depot stock, research unlocked, HQ HP, carrier pos) ก่อน Beta
* Validate: `godot --headless --import` + โหลด `war_world.tscn` ต้องไม่ error `load_steps`

---

## 12. Input Map & Controls (War Mode)

> Base จาก `project.godot:46` — War Mode เพิ่ม Q/E ไหล่ + Tab/I

| Action | ปุ่ม | ไฟล์ | หมายเหตุ |
|--------|------|------|----------|
| เดิน/Strafe/Jump/Dash | `WASD` / `Shift` / `Space` / `PageDown/Up` | `project.godot` | เหมือน Campaign |
| ยิงมือซ้าย/ขวา | `Mouse Left/Right` | `project.godot:fire_left/right` | `weapon_core.gd` |
| อาวุธไหล่ซ้าย/ขวา | `Q` / `E` (`guard` เดิมคือ Q — ต้องแยก) | `shoulder_weapon_system.gd` | ⏳ TODO: เพิ่ม `shoulder_left`/`shoulder_right` ใน `project.godot` แยกจาก `guard` |
| โต้ตอบ/ขึ้นรถ/Dock | `F` (`interact`) | `project.godot` | `carrier_dock.gd`, `war_realtime_hangar.gd` |
| ดีดตัว | `G` (`eject`) | `project.godot` | `mecha_eject.gd` |
| Tab ทรัพยากร | `Tab` (`camera_unlock` เดิม) | `war_hud.gd` | ⏳ TODO: เพิ่ม `war_resource_view` = Tab แยกจาก `camera_unlock` |
| Inventory | `I` | `war_hud.gd` | ⏳ TODO: เพิ่ม `war_inventory` = I ใน `project.godot` |
| Roller Dash | `PageUp` | `project.godot` | `mecha_controller.gd` |

---

## 13. Audio / VFX / UI Polish

* **Audio:** `AudioManager.play_combat_music("war")` ใน `game_manager.gd:171` — ต้องเพิ่ม war BGM แยกจาก combat ปกติ + SFX สำหรับ Ore drill, Dock clamp, Data pickup
* **VFX:** ใช้ `EffectManager` เดิม (reuse) — เพิ่ม HQ shield hit VFX, Ore spark, UNDERGROUND fog
* **UI:** `WarHUD` (Tab/I) ปัจจุบันเป็น CanvasLayer ชั่วคราว — ต้องแยกเป็น `war_resource_hud.tscn` + `war_inventory.tscn` + `war_launch_setup_ui.tscn` แบบ Figma ก่อน Beta
* **Minimap:** `war_minimap.gd` แสดง Friendly/Enemy/ Ore/Cache/Convoy — Fog of War ค่อยๆ เผยตามระยะ Humvee

---

## 14. Testing & QA Checklist

### Headless Validate (Godot 4.6.2)

> dev หลายเครื่อง — แก้ `<GODOT>` เป็น path เครื่องตัวเอง

```powershell
<GODOT>\Godot_v4.6.2-stable_win64.exe --headless --import
<GODOT>\Godot_v4.6.2-stable_win64.exe --headless --quit-after 5 res://scenes/war/war_world.tscn

# ตัวอย่าง path ที่ใช้จริง:
# H:\hack\project\godot\Godot_v4.6.2-stable_win64.exe --headless --import
# D:\godot\Godot_v4.6.2-stable_win64.exe --headless --import
# C:\Tools\Godot\Godot_v4.6.2-stable_win64.exe --headless --import
```

### War Mode Manual QA

- [ ] Main Menu → [WAR MODE] → โหลด `war_world.tscn` ไม่จอฟ้า/เทา (Ground mesh ครบ)
- [ ] Tab/I เปิด WarHUD/Inventory ได้, ปิดได้
- [ ] Ore Node ขุด → Truck ขน → Depot กด F รับ Scrap/Credits
- [ ] Data Event เก็บ → แบกช้าลง 20% → กลับฐานวิจัย → Roll 30/20/20/15/8/2
- [ ] Carrier Dock: ขับ Valkren เข้า Area → กด Dock → FREEZE + Reparent ไม่สั่น
- [ ] HIGHLAND มองลงมาไม่เห็น Ore ใต้หุบ, UNDERGROUND มี SpotLight + Occluder
- [ ] HQ Shield: ยิง HQ จากไกลลดดาเมจ 90%, เข้าใกล้ 100m หรือรอ 10 นาที ยิงเข้าเต็ม
- [ ] Eject G → Respawn เลือกฐาน → หุ่นเก่าจอดเป็นซากให้ชิงได้
- [ ] Stunt Weapon ยิงแล้วติด 2-4วิ — Direct Combustion นานสุด, Ancient กัน

### TODO ก่อน Beta

- [x] สร้าง `war_deployment_manager.gd` แยกจาก `war_valkyrion_system.gd` + test Deploy Cap 5/3/1 — `war_deployment_manager.gd:8 CAPS`, `WarBalance.DEPLOY_CAPS`
- [x] สร้าง `war_launch_setup_ui.tscn` + Ace Right 30วิ timeout — `war_launch_setup_ui.gd:WarBalance.ACE_RIGHT_TIMEOUT`
- [x] แยก `war_resource_hud.tscn` / `war_inventory.tscn` จาก `war_hud.gd` — `war_resource_hud.gd` + `war_inventory_ui.gd`
- [x] เพิ่ม Input `shoulder_left/right`, `war_resource_view`, `war_inventory` ใน `project.godot` — Q/E/Tab/I

---

## 15. Risks & Mitigations

| ความเสี่ยง | ผลกระทบ | แนวทางแก้ |
|------------|---------|-----------|
| แมพ 2000x2000 วัตถุเยอะเฟรมตก | FPS <30 บนเครื่องกลาง | Chunk Loader + Occluder + MultiMesh + ปิด shadow ไกล |
| Physics Jitter บน Carrier | หุ่นสั่น/หลุดกระบะ | FREEZE + Reparent เป็น Child (ทำแล้ว `carrier_dock.gd`) |
| Navigation 2 ชั้นไม่เชื่อม | Truck ติดปากอุโมงค์ | 2 NavigationRegion3D + NavigationLink3D |
| เซฟ War/Campaign ปนกัน | ของหาย/เงินปน | แยกไฟล์ `save_war.json` vs `savegame.json` + ไม่แชร์ GlobalData |
| สูตร Valkyrion โกง/เกลือ | Mass Product 75% ไม่คุ้ม | ปรับ `war_balance.gd` ระหว่าง Playtest (Phase 3) |
| Input Q/E ชน guard | กด Q แล้วกันแทนยิงไหล่ | แยก Input Map ใหม่ shoulder_left/right |

---

## 16. Glossary & หมายเหตุ

| คำ | ความหมาย |
|----|----------|
| **Valkren** | จักรกลรบหลักทุกตัวในสนาม (Mobile Suit) |
| **Valkyrion** | หุ่นต้นแบบ Apex ขับด้วย Ancient Core |
| **Line-Issue** | Valkren Mass Product มาตรฐาน |
| **Iron-Vanguard** | Valkren สายเกราะหนัก Walk-Tank |
| **Strike-Apex** | Valkren สายเร็วสูง EWAR |
| **Deploy Cap** | โควตาจำกัดจำนวนหุ่นประจำการ |
| **Stock Cooldown** | คูลดาวน์เติมสต็อกหลังหุ่นพัง |
| **Ace Right** | สิทธิ์จองขับ Valkyrion ของ Ace |
| **HQ Barrier** | โล่ลดดาเมจ 90% รอบ HQ 100m / 10 นาที |

* Godot 4.6.2 path: `<GODOT>\Godot_v4.6.2-stable_win64.exe` — dev หลายเครื่อง ให้แก้เป็น path เครื่องตัวเอง (เช่น `D:\godot\...`, `H:\hack\project\godot\...`, `C:\Tools\Godot\...`) แล้ว validate ด้วย `--headless --import`
* ทุกเฟสจบ commit + push ตาม `AGENTS.md`
* สูตรหุ่นเทพใช้ทรัพยากรแรร์จริง แต่ Mass Product ให้ผู้เล่นทุนน้อยก็เล่นได้ — ไม่ pay-to-win
* เอกสารนี้ตรงกับโค้ด commit หลัง War Phase3 — deploy + launch + hud split + Input 2026-09-01

