# 📑 Game Design Document (GDD)

**Project Title:** (Working Title)  
**Genre:** Single-Player Hybrid (Tabletop Board + 3rd Person Action Mecha)  
**Engine Target:** Godot Engine  
**Core Theme:** Military Science Fiction / Tactical Mecha (Grounded, High-Stakes, Strategic Mechanics)  
**Core Concept:** เกมวางแผนยุทธศาสตร์สไตล์บอร์ดเกม ผสมผสานฉากต่อสู้ 3rd Person Action ที่เน้นความสมจริง การบริหารทรัพยากร ความผูกพันกับหุ่น และความรอดชีวิตของนักบิน  

---


## 🛠️ 1. Core Gameplay Loop
[ Strategic Board Phase ]
(เดินบอร์ด / บริหาร Convoy / วางแผนทรัพยากร / ตัดสินใจข้ามแผนที่)
│
▼  (ตกช่องศัตรู / โดนซุ่มโจมตี / บุกโรงงาน)
[ 3rd Person Action Combat Phase ]
(สู้แบบอิสระ / Roller Dash / สู้ หรือ ถอย / ปกป้อง Convoy)
│
▼  (จบการรบ / ถอยทัพ / Re-ignition)
[ Post-Battle & Garage Phase ]
(ซ่อมเกราะ Wear System / อัปเกรด Frame / จัดการ Pilot)

---

## 🚛 2. Strategic Layer (Tabletop Board Phase)

### 2.1 Convoy System (ขบวนรถบรรทุกส่งกำลังบำรุง)
* **มีรถบรรทุก (Convoy Enabled):** 
  * เดินทางไกลบนบอร์ดได้เร็ว ไม่เสียพลังงานถังหลักของตัวหุ่นก่อนเข้าสู้
  * **Backup Mecha:** สามารถเรียก "หุ่นสำรอง" ลงมาจากรถบรรทุกเพื่อสู้ต่อได้ทันทีเมื่อหุ่นหลักพัง
* **ไม่มีรถ / รถพัง / ลุยเดี่ยว:** 
  * หุ่นต้องใช้ขาเดินเท้าบนบอร์ดเอง เสียพลังงานระยะยาว (Global Energy) ตั้งแต่ก่อนเข้าฉากสู้
  * ไม่มีหุ่นสำรองสนับสนุน หากหุ่นพังจะต้องกดถอย (Flight) เท่านั้น

### 2.2 Pilot Survival Phase (โหมดนักบินเดินเท้า)
* **Emergency State:** เมื่อหุ่นพลังงานหมดหรือเกราะพังยับ เกมไม่ Game Over ทันที
* **Gameplay Change:** นักบินสามารถ **"ลงจากหุ่น"** เพื่อออกเดินเท้าบนบอร์ดเกม
* **Stealth & Mechanics:** ย่อขนาดตัวลงเพื่อใช้ช่องแคบ/ซอกตึก หรือใช้ความสามารถ Stealth แอบตัดผ่านศัตรู
* **Objective:** สวมบทนักบินหาถังพลังงาน/แบตเตอรี่ นำกลับมาสตาร์ทเครื่องยนต์ (Re-ignition) เพื่อชุบชีวิตหุ่นอีกครั้ง

### 2.3 Faction & Dynamic Enemy Board AI (ระบบกองทัพศัตรูบนบอร์ด)
* **Active Enemy Units:** ศัตรูมียูนิตเคลื่อนที่บน Tile บอร์ดจริง (หน่วยลาดตระเวน, ขบวนขนส่ง, หน่วยล่าสังหาร)
* **Alert & Escalation Level:** ยิ่งผู้เล่นใช้เวลานานบนบอร์ด ศัตรูจะยิ่งเพิ่มระดับการตื่นตัว ส่งยูนิตเกรดสูงลงมาปิดล้อม
* **Factory Nodes:** ฐานการผลิตศัตรูบนบอร์ดที่ผลิตกำลังพลเติมเข้ามาเรื่อยๆ บีบให้ผู้เล่นต้องเลือกว่าจะ "เสี่ยงบุกถล่มโรงงาน" หรือ "รีบตีแหกวงล้อมเพื่อไปต่อ"

### 2.4 Refueling & Supply Logistics (ระบบเติมเชื้อเพลิง)
#### Board-Level Refueling (การเติมบนบอร์ด)
* **Convoy Supply Transfer:** จอดประชิดรถบรรทุกเพื่อถ่ายโอนพลังงาน (กินค่า Supply Reserve ของรถ) — เสีย 1 Turn + Alert Level พุ่ง
* **Depot Seizure:** บุกยึดคลังน้ำมันศัตรู — เลือก Precise (อาวุธเบา ได้ fuel เต็ม 80) หรือ Heavy (ปืนใหญ่ ได้ fuel ครึ่ง 40 เพราะถังบางส่วนโดนทำลาย)
* **Time Trade-off:** การเติมพลังงานบนบอร์ดจะเสีย 1 Turn ซึ่งส่งผลให้ Alert Level ของศัตรูพุ่งสูงขึ้น

#### In-Combat Emergency Refueling (การเติมกลางสนามรบ)
* **External Drop Tanks:** ถังพลังงานสำรองภายนอก เพิ่มความจุแต่เป็นจุดอ่อน 如果โดนยิงจะสปาร์คระเบิด ต้องกด Purge สลัดทิ้งก่อนระเบิด
* **Pilot Siphon Protocol:** เมื่อหุ่นดับกลางฉากสู้ นักบินต้องลงเดินเท้าไปสูบเชื้อเพลิงจากซากหุ่นศัตรูนำกลับมารีบูตเครื่อง
* **Impure Fuel Penalty:** การสูบเชื้อเพลิงเถื่อน/ซากหุ่น จะทำให้ Torso Frame สะสมความร้อนไวขึ้น (Engine Dirt Penalty) ฟื้นฟูช้าลงระหว่างวัน

> 📌 **Current Implementation Status:**
> - [x] Board-Level: Fuel Depot Seizure tile + Convoy Supply Transfer tile
> - [x] Time Trade-off: refuel = end day + alert++
> - [x] External Drop Tanks: bolt-on fuel + vulnerable + purge + detonation
> - [x] External Drop Tank 3D visual model + HUD indicator + body damage intercept
> - [x] Drop Tank purchase at City Shop (80 credits, max 3, detach free)
> - [x] Engine Dirt Penalty: impure fuel slows energy regen
> - [x] Convoy fuel reserve: replenishes overnight
> - [x] Pilot Siphon Protocol: wreckage tile + siphon + re-ignition reboot

---

## 🤖 3. Combat Layer (3rd Person Action Phase)

### 3.1 Mobility System (Bipedal + Roller Dash)
* **Built-in Mechanism:** ตัวหุ่นเป็นสองขา (Bipedal) ที่มีกลไกล้อและไอพ่นพับเก็บไว้ในตัวตั้งแต่แรก
* **Bipedal Walk / Jump:** ใช้งานเมื่อเจอพื้นที่ชัน ขรุขระ บันได หรือซากตึก เพื่อก้าวข้ามสิ่งกีดขวาง
* **Roller Dash:** กางล้อกดจุดชนวนไอพ่นพุ่งตัวความเร็วสูงบนพื้นเรียบ 
  * *Trade-off:* พุ่งไวแต่เสียการควบคุมความเร็วและการเลี้ยว (Inertia/Drifting) และดึงพลังงานไปใช้มหาศาล

> 📌 **Current Implementation Status:**
> - [x] Bipedal Movement Logic
> - [x] Roller Dash Mechanics
> - [x] Integration with Global Energy Pool

### 3.2 Energy & Skill-Based System
* **No Cooldown & No Stamina:** ไม่มี Cooldown ในการ Dash ผู้เล่นสามารถกดหลบหลีกได้อิสระตาม Reflex
* **Global Energy Pool:** การ Dash ทุกครั้งจะดึงพลังงานมาจาก "ถังพลังงานหลัก"
  * *Precision Dash:* หลบถูกจังหวะ = ประหยัดพลังงาน
  * *Spam Dash:* กดรัวด้วยความตกใจ = เผาพลังงานถังใหญ่ หมดหลอดแล้วส่งผลกระทบย้อนกลับไปบนบอร์ดเกม

> 📌 **Current Implementation Status:**
> - [x] Bipedal Movement Logic
> - [x] Roller Dash Mechanics
> - [x] Integration with Global Energy Pool
> - [x] Precision Dash: near-miss detection + energy refund + HUD indicator

---

## 🦾 4. Maintenance & Wear Architecture (ระบบความสึกหรอ)

แยกโครงสร้างหุ่นออกเป็น 3 เลเยอร์: **เกราะ (Armor), โครงใน (Inner Frame), และ อาวุธ (Weapons)** พร้อมแยกค่า **HP** ออกจาก **Durability (Battery Health)**

### 4.1 Armor System (เกราะนอก)
* **Armor HP:** รับแรงปะทะก่อน เมื่อ HP = 0 เกราะจะแตกหลุดกระเด็น (Armor Purge)
* **Armor Durability:** สภาพความหนาและความสมบูรณ์ของเหล็ก 
  * ลดลงจากการถูกยิงหนัก หรือการ **"ซ่อมด่วนบนบอร์ด"**
  * ยิ่งซ่อมบ่อย ค่า Max HP ของเกราะชิ้นนั้นจะยิ่งลดลง จนถึงขั้นยับเยินเกินซ่อมและต้องซื้อเกราะใหม่มาเปลี่ยน

### 4.2 Inner Frame System (โครงสร้างด้านใน)
* **Inner Frame Tiers:** กระดูกสันหลังของหุ่น แบ่งตาม Tier ยุคสมัย
  * *Tier 1 (รุ่นเก๋า):* Socket น้อย ใส่ Property ได้แค่พื้นฐาน
  * *Tier 3 (รุ่นต้นแบบ / Freedom / 00 Level):* รองรับ High-Tech Properties ขั้นสูง (เช่น Overdrive, Anti-Beam Coating)

#### Part Penalties เมื่อ Frame Durability ต่ำ (ชำรุดหนัก)

| ชิ้นส่วน Inner Frame | หน้าที่หลัก | Penalty เมื่อ Durability ต่ำ / เสื่อมสภาพ |
| :--- | :--- | :--- |
| **หัว (Head)** | เซนเซอร์ / ล็อกเป้า | ล็อกเป้าช้า, HUD เกิด Glitch, ถ้าพังต้อง Free-aim เล็งเอง 100% |
| **แขน (Arms)** | คุมปืน / แบกน้ำหนัก | แรงดีดปืนสูง, ฟันดาบช้า, ถ้าพังไม่สามารถถืออาวุธหนักได้ |
| **ขา (Legs)** | การเคลื่อนที่ / ล้อ Roller | AP เดินบนบอร์ดลดลง, Speed ตก, ระบบ Roller Dash ล้อติดขัด/พัง |
| **ลำตัว (Torso)** | เตาปฏิกรณ์ / Core | Max Energy รวมลดลง, พลังงานสปาร์ค, Overheat ชัตดาวน์ตัวเองง่าย |

---

## 🔬 4A. Research & Blueprint System (ระบบวิจัยและพิมพ์เขียว)

### Board-Level Research (การวิจัยบนบอร์ด)
* **Research Lab Tile:** พบได้บนบอร์ด (สีน้ำเงิน) — เปิด UI เลือกโปรเจควิจัย
* **Data Cores:** ทรัพยากรสำหรับเริ่มวิจัย หาได้จาก data_node tiles, เอาชนะ enemy base, หรือซื้อใน city
* **Research Time:** แต่ละ board move = 1 แต้ม, แต่ละ combat = 2 แต้ม — รอจนครบจะ unlock reward
* **Rewards:** ปลดล็อก ally units (GM-II, Guncannon), gundam-tier armor/frames, หรือ special abilities

### Blueprint Catalog
* **Ally Unit Blueprints:** วิจัยเสร็จ = ได้ unit ใหม่เข้า fleet roster ลงสนามเป็น squadmate
* **Gear Blueprints:** วิจัยเสร็จ = ปลดล็อก crafting ส่วนเกราะ/โครงระดับ gundam-tier
* **Data Core Sink:** data_cores เป็น currency ที่ใช้ทั้งวิจัยและซื้อของ — ต้องเลือกว่าจะลงทุนด้านไหน

> 📌 **Current Implementation Status:**
> - [x] Research Lab tile on board (blue, spawns in generator)
> - [x] Research Lab UI: browse projects, start research, view progress
> - [x] Research progress: board move = 1pt, combat = 2pt
> - [x] Research completion: unlocks ally units from blueprint catalog
> - [x] Save/Load research state

---

## 🎯 5. Narrative & Emotional Design (ความผูกพันและการเปลี่ยนหุ่น)

* **Building Bond:** ผู้เล่นผูกพันกับหุ่นเครื่องเก่าผ่านรอยแผล การปะซ่อม และการฝ่าฟันอุปสรรค
* **Hitting the Ceiling:** เมื่อเล่นไปถึงจุดหนึ่ง ศัตรูรุ่นใหม่จะกดดันจนเห็นขีดจำกัดของหุ่นเก่าอย่างชัดเจน
* **The Sacrifice Event:** ภารกิจวิกฤตที่ผู้เล่นต้องเค้นพลังหุ่นเก่าจนพังยับเยินเพื่อปกป้องเป้าหมาย
* **The Grand Entry:** ตัดเข้าฉาก 3rd Person เปิดตัวหุ่นใหม่ mid-battle บินลงมาจากฟากฟ้าพร้อม BGM ใหม่ ปลดล็อกข้อจำกัดเดิมทันที (ให้ความรู้สึกทรงพลังแบบ Freedom หรือ 00 Gundam)

---

## ⏱️ 6. Pacing & Game Length Plan

* **1 Loop การเล่น (Single Session):** **20 - 45 นาที**
  * *Board Phase:* 10 - 15 นาที
  * *Action Combat Phase:* 5 - 10 นาที
  * *Post-Battle & Garage Phase:* 5 - 10 นาที
* **1 Era / ช่วงชีวิตของหุ่น (ต่อ 1 Tier):** **3 - 6 ชั่วโมง** (~5-8 Loops)
* **Total Campaign Length (สเกลสำหรับ Indie/Roguelite):** **10 - 15 ชั่วโมง** (แบ่งเป็น 3 Inner Frame Tiers)

---

## 🎲 7. Dynamic Event System (ระบบเหตุการณ์สุ่ม)

### 7.1 Military Environmental Hazards (ส่งผลจากบอร์ดลงฉากสู้)
* **พายุฝุ่น/ทราย (Dust Storm):** เศษฝุ่นเข้าอุดตันกลไกล้อ Roller Dash ทำให้สปีดตก และกินพลังงานถังหลักมากขึ้น
* **หมอกควันสารเคมี/แก๊สพิษ (Tactical Smog):** รั่วไหลจากคลังแสงที่ถูกถล่ม ทำให้อุณหภูมิเครื่องสูงขึ้น เตาปฏิกรณ์ (Torso) Overheat ง่ายขึ้น
* **EMP & Jamming Zone:** ช่องตัดสัญญาณเรดาร์ทางยุทธวิธีบนบอร์ด ทำให้ฉากสู้ล็อกเป้าไม่ได้ (บังคับ Free-aim) และห้ามเรียกหุ่นสำรองจาก Convoy

> 📌 **Current Implementation Status:**
> - [x] Board tile types: dust_storm / tactical_smog / emp_zone (spawn in generator)
> - [x] Dust Storm: Roller Drain x1.5 + Movement Speed x0.85
> - [x] Tactical Smog: Heat Cool Rate x0.5 (weapons overheat faster)
> - [x] EMP & Jamming: Disable lock-on targeting + Block reserve mech call
> - [x] Visual atmosphere overlay for all 3 hazard types
> - [x] Hazard clears after combat ends (one-shot per encounter)
> - [x] Save/Load hazard state

### 7.2 Strategic Dilemmas (เหตุการณ์ทางเลือกบนบอร์ด)
* **Distress Signals:** ยอมอ้อมไปช่วยเพื่อลุ้นรับ Inner Frame / ทรัพยากร หรือเสี่ยงพลังงานหมด
* **Scavenge Risk:** ส่ง Pilot ลงเดินเท้าสำรวจซากคลังแสง เสี่ยงเจอโดรนซุ่มโจมตี

> 📌 **Current Implementation Status:**
> - [x] Distress Signal tile on board (red, spawns in generator)
> - [x] Distress Signal choice: Respond (−30 energy, 60% loot reward) vs Ignore
> - [x] Scavenge Site tile on board (rusty brown, spawns in generator)
> - [x] Scavenge Site choice: Explore (50% loot, 30% drone ambush, 20% nothing) vs Leave
> - [x] Drone ambush triggers forced combat

### 7.3 Mid-Battle Injections (เหตุการณ์พลิกผันกลางฉากสู้)
* **Reinforcements / Third Party:** ศัตรูฝ่ายที่สามเข้าแทรกแซงกลางสมรภูมิ
* **Countdown Extraction:** พื้นที่สู้รบโดนถล่ม ต้องเค้น Roller Dash สู้แข่งกับเวลา

> 📌 **Current Implementation Status:**
> - [x] Mid-Battle Injection system (mid_battle_injection.gd)
> - [x] Reinforcements: third-party enemies spawn after 15-25s delay on ace/boss battles
> - [x] Countdown Extraction: 45s escape timer + 80 damage on expiry
> - [x] Countdown Extraction HUD: red pulsing banner with timer
> - [x] Event triggers: 50% reinforcements, 30% countdown, 20% none

### 7.4 Convoy Escort & Defense Events (ภารกิจปกป้องขบวนส่งกำลังบำรุง)
* **Convoy Ambush:** เมื่อรถบรรทุกโดนซุ่มโจมตีบนบอร์ด ฉากสู้ 3rd Person จะเปลี่ยนเป็นภารกิจตั้งรับ (Defense Mission) เพื่อป้องกันไม่ให้รถบรรทุกถูกทำลาย
* **Vehicle Breakdown:** รถบรรทุกเสียกลางสมรภูมิ ต้องปักหลักคุ้มกันท่ามกลางคลื่นศัตรู (Wave Defense) ตามจำนวน Turn ที่กำหนด
* **Failure Consequence:** หาก Convoy พัง ผู้เล่นจะสูญเสีย "หุ่นสำรอง" ทั้งหมด และบังคับเข้าสู่โหมดนักบินเดินเท้า (Pilot Survival) ทันที

> 📌 **Current Implementation Status:**
> - [x] Convoy Escort system (convoy_escort.gd)
> - [x] Convoy Ambush tile (red, spawns in generator)
> - [x] Convoy Ambush: 2-wave defense combat
> - [x] Vehicle Breakdown tile (dark orange, spawns in generator)
> - [x] Vehicle Breakdown: 3-wave defense combat
> - [x] Convoy HP system (100 HP, 10% damage spill from player)
> - [x] Failure Consequence: convoy destroyed → lose backups + pilot mode

---

## 🗺️ 8. Campaign Progression & Map Transition

### 8.1 Map Transition Dilemma (การตัดสินใจข้ามแผนที่)
* **Strategic Choices:** ผู้เล่นต้องชั่งน้ำหนักระหว่างการ "ยอมเสียเวลาถล่มโรงงาน/ฐานศัตรู" บนแผนที่ปัจจุบัน เพื่อตัดกำลังผลิต หรือ "รีบข้ามไปแผนที่ถัดไป" เพื่อประหยัดพลังงานถังหลัก (Global Energy) และถนอมค่า Durability ของหุ่น
* **Threat Escalation:** ยิ่งผู้เล่นใช้เวลาบนแผนที่เดิมนาน ศัตรูในแผนที่ถัดไปจะยิ่งตั้งรับแน่นหนา และมีโอกาสส่งหน่วยไล่ล่าลงมาขัดขวาง

---
*Document Version: 2.0 (Master Unified Blueprint)*  
*Last Updated: August 2026*
