# 📑 Master Game Design Document (GDD)

**Project Title:** (Working Title)  
**Genre:** Single-Player Hybrid (Tabletop Board + 3rd Person Action Mecha)  
**Engine Target:** Godot Engine  
**Core Theme:** Military Science Fiction / Tactical Mecha (Grounded, High-Stakes, Strategic Mechanics)  
**Core Architecture:** Procedural Modular Assembly System (Catalog-Driven Parts & Enemies)  
**Core Concept:** เกมวางแผนยุทธศาสตร์ทางทหารสไตล์บอร์ดเกม ผสมผสานฉากต่อสู้ 3rd Person Action ที่เน้นความสมจริง การบริหารเชื้อเพลิง ความสึกหรอของชิ้นส่วน และการเอาชีวิตรอดของนักบิน

---

## 🛠️ 1. Core Gameplay Loop
[ Strategic Board Phase ]
(บริหาร MP / จัดการ Convoy / วางแผนเส้นทาง / รับมือ Simultaneous Enemy Turns)
│
▼  (โดนซุ่มโจมตี / ปะทะ Fleet ศัตรู / บุกยึด Depot)
[ 3rd Person Action Combat Phase ]
(สู้แบบอิสระ / Precision Dash vs Spam / ปรับตาม Fleet Archetype / ปกป้อง Convoy)
│
▼  (จบการรบ / ถอยทัพ / Re-ignition / สูบน้ำมัน)
[ Post-Battle & Garage Phase ]
(ซ่อมเกราะ Wear System / เติมเชื้อเพลิงบริสุทธิ์ / อัปเกรด Frame Tiers / Scavenge Parts)

### 1.1 Game Modes & Onboarding Flow

#### Game Modes
* **Campaign Mode (Main Loop):** โหมดวางแผนเอาชีวิตรอดทางยุทธวิธี เดินทางผ่านแผนที่บอร์ดเกม บริหารทรัพยากร Convoy ปะทะ Enemy Fleets และค้นหา Parts จาก Catalog
* **Combat Simulator (Arena):** โหมดทดสอบการต่อสู้ 3rd Person Action อิสระ สำหรับทดลองประกอบชิ้นส่วนและซ้อมมือกับ AI นักบินรูปแบบต่างๆ

#### Campaign Game Onboarding (ขั้นตอนการเริ่มเล่น)
1. **Hangar Assembly:** เลือกหุ่นเริ่มต้น Tier 1, จัด Loadout อาวุธ และตั้งค่า Pilot
2. **Board Spawn:** วางขบวน Convoy ลงบน Start Tile พร้อมสุ่มสร้าง Enemy Fleets และจุดสนใจ (POIs) บนแผนที่
3. **First Tactical Turn:** เริ่มบริหารค่า MP และ Global Energy ในการเดินบอร์ดวันแรก

---

## ⚙️ 2. Modular Part Catalog & Assembly System (ระบบชิ้นส่วน)

เกมจะไม่ Hardcode ศัตรูเป็นตัวๆ แต่ใช้ระบบ **Procedural Dynamic Assembly** โดยดึงชิ้นส่วนจาก Catalog มาประกอบตามกฎของแต่ละ Fleet

### 2.1 Global Part Catalogs
ชิ้นส่วนทั้งหมดในเกม (ทั้งฝั่งผู้เล่นและศัตรู) ถูกเก็บเป็น Data Resources แบ่งเป็น 5 หมวดหลัก:
* **Head Catalog:** ค่าระบบเซนเซอร์, ความเร็วในการล็อกเป้า, และ HUD Utility
* **Torso Catalog:** เตาปฏิกรณ์หลัก (Core Energy), อัตราการสะสมความร้อน (Heat Generation), และโครงสร้างเกราะหลัก
* **Arm Catalog:** ค่ากำลังแบกน้ำหนัก (Load Capacity), แรงดีดปืน (Recoil Control), และการสวิงอาวุธประชิด
* **Leg Catalog:** โหมดการเคลื่อนที่ (Bipedal Walk / Roller Dash Mechanism), สปีดการพุ่ง, และ MP/Energy Cost
* **Weapon Catalog:** ค่าความเสียหาย, ประเภทกระสุน, อัตราสิ้นเปลืองพลังงาน, และแรงดีด

### 2.2 Dynamic Enemy Generation Logic
* **No Hardcoded Enemies:** ศัตรูทุกตัวถูกสุ่มสร้างขณะสปอว์นบนบอร์ดตาม **Fleet Rules & Tag Constraints**
* **Consistent Looting System (WYSIWYG):** เมื่อยิงศัตรูพัง ชิ้นส่วน อะไหล่ หรือ Inner Frame ที่สแกน/ถอดออกมาได้ จะเป็นชิ้นส่วนเดียวกับที่ศัตรูตัวนั้นติดตั้งและใช้งานอยู่จริง 100%

---

## 🚛 3. Strategic Layer (Tabletop Board Phase)

### 3.1 MP vs Energy Dual-Cost Movement
* **MP (Movement Points):** ตัวแทนของ "เวลา/ระยะทาง" ในแต่ละวัน
* **Energy Cost (เชื้อเพลิงถังหลัก):** หักพลังงานตามประเภทภูมิประเทศ (Terrain)
  * *Road Tile:* $1\text{ MP}$ | $-10\text{ Energy}$ (ทำสปีด ประหยัดน้ำมัน)
  * *Off-Road / Mud:* $1\text{ MP}$ | $-25\text{ Energy}$ (เครื่องยนต์ทำงานหนัก ผลาญน้ำมัน 2.5 เท่า)
  * *Roller Dash Mode:* $1\text{ MP}$ | $-5\text{ Energy}$ (ใช้ล้อทำสปีดบนทางเรียบ)
  * *Refuel Action:* $0\text{ MP}$ (บังคับจบทันที 1 วัน) | $+500\text{ Energy}$

### 3.2 Simultaneous Execution & Turn Logic
* **Player Phase:** ผู้เล่นใช้ Movement Points (MP) เดินและทำ Action บนบอร์ดได้อย่างอิสระ
* **World Execution Phase:** เมื่อกด End Phase / Execute ทุก Faction และทุก Fleet ศัตรูจะประมวลผลและเคลื่อนที่พร้อมกัน (Simultaneous Movement) ภายใน 2-3 วินาที
* **Fog of War Optimization:** ศัตรูที่อยู่นอกระยะเรดาร์จะคำนวณตำแหน่งใหม่เบื้องหลังทันทีโดยไม่แสดง Animation

### 3.3 Enemy Fleet Archetypes & Assembly Rules

| รูปแบบ Fleet | คุณสมบัติบนบอร์ด | Assembly Rules (การดึงชิ้นส่วนจาก Catalog) |
| :--- | :--- | :--- |
| **Recon Fleet** | MP 4-5 (เดินไวมาก) | **Legs:** บังคับ Tag `Roller-Dash` / **Weapons:** อาวุธเบา SMG / **Armor:** Thin |
| **Armored Fleet** | MP 1-2 (เดินช้า ถึก) | **Torso/Legs:** บังคับ Tag `Heavy-Armor` / **Weapons:** Heavy Cannon, โล่ |
| **Artillery Fleet** | ยิงข้ามช่องบนบอร์ดได้ | **Weapons:** บังคับ Tag `Missile-Pod` หรือ `Railgun` ระยะไกล |
| **Hunter-Killer** | สปอว์นตาม Alert Level | **Frame:** Tier 2-3 High-Tech / สุ่มชิ้นส่วน Synergy ระดับสูง |

* **Zone of Control (ZoC):** ช่องรอบตัว Fleet ศัตรู 1 ช่องถือเป็นเขตอิทธิพล หากผู้เล่นเดินก้าวเข้า ZoC ค่า MP ที่เหลือทั้งหมดจะถูกตัดเหลือ 0 ทันที

### 3.4 Convoy & Logistics System
* **Supply Reserve:** รถบรรทุกมีปริมาณน้ำมัน/อะไหล่สำรองจำกัด หากใช้จนหมดต้องพา Convoy ไปเติมที่ Logistics Hub
* **Convoy Breakdown/Ambush:** หากถูกซุ่มโจมตี ฉากสู้ 3rd Person จะกลายเป็น Defense Mission หาก Convoy พัง หุ่นสำรองทั้งหมดจะสูญหาย

### 3.5 Pilot Survival Phase (โหมดนักบินเดินเท้า)
* **Emergency State:** เมื่อหุ่นพลังงานหมดหรือเกราะพังยับ นักบินจะสลัดออกจากหุ่น (Disembark)
* **Objective:** ย่อขนาดตัวใช้ Stealth วิ่งไปหาสากหุ่นศัตรูหรือคลังน้ำมันเพื่อกด "Siphon Fuel" นำกลับมารีบูตเครื่องยนต์ (Re-ignition)

---

## ⛽ 4. Energy Architecture & Refueling System

### 4.1 Real-World Tank Energy Mechanics
* **Cruising Power (เดินบอร์ด):** หักพลังงานตามสภาพภูมิประเทศ
* **High-Burn Combat Rate (ฉากสู้ 3rd Person):** เร่งรอบเครื่องยนต์เต็มกำลัง พลังงานจะหมดภายใน 2-3 นาทีหากกดใช้งานไม่ระมัดระวัง
* **Emergency Idle State:** เมื่อพลังงานหมด หุ่นจะหยุดนิ่ง แต่ระบบเรดาร์และปืนกักกันตัวยังทำงานได้สั้นๆ รอ Pilot ลงมาเติมน้ำมัน

### 4.2 Refueling & Drop Tanks
* **Board Refueling:** จอดประชิด Convoy เพื่อถ่ายโอนพลังงาน (เสีย 1 Turn / Alert Level เพิ่มขึ้น)
* **External Drop Tanks:** ถังพลังงานสำรองภายนอกแขวนหลังหุ่น เพิ่มความจุแต่เป็นจุดอ่อน หากโดนยิงจะระเบิด ต้องกด Purge สลัดทิ้ง
* **Impure Fuel Penalty:** การสูบเชื้อเพลิงเถื่อนหรือจากซากหุ่น จะทำให้ Torso Frame สะสมความร้อน (Overheat) ไวขึ้น

---

## 🤖 5. Combat Layer (3rd Person Action Phase)

### 5.1 Mobility & Precision Dash Dynamics
* **Bipedal Walk / Jump:** สำหรับข้ามสิ่งกีดขวาง ทางชัน และพื้นที่ขรุขระ
* **Roller Dash:** กางล้อจุดไอพ่นพุ่งตัวความเร็วสูงบนพื้นเรียบ
* **Precision Dash vs Spam Dash:**
  * *Precision Dash (หลบถูกจังหวะ):* ใช้ Short-Pulse Ignition รักษา Momentum เดิม ใช้พลังงานน้อยลง 60%
  * *Spam Dash (กดหลบรัวๆ):* เกิด Flash Burn ทำลาย Momentum เครื่องยนต์เค้นรอบสูงสุด ผลาญพลังงานและเกิด Overheat ไว

---

## 🦾 6. Maintenance & Wear Architecture (ระบบความสึกหรอ)

### 6.1 Armor vs Inner Frame
* **Armor System:** รับแรงปะทะก่อน เมื่อ HP = 0 เกราะจะแตก (Armor Purge) การซ่อมด่วนบนบอร์ดจะลด Max Durability ลงเรื่อยๆ
* **Inner Frame Tiers:** กระดูกสันหลังของหุ่น (Tier 1 ถึง Tier 3) กำหนดจำนวน Socket และการรองรับ High-Tech Properties

#### Part Penalties เมื่อ Durability ต่ำ (ชำรุดหนัก)

| ชิ้นส่วน Inner Frame | หน้าที่หลัก | Penalty เมื่อ Durability ต่ำ / เสื่อมสภาพ |
| :--- | :--- | :--- |
| **หัว (Head)** | เซนเซอร์ / ล็อกเป้า | ล็อกเป้าช้า, HUD เกิด Glitch, ต้อง Free-aim เล็งเอง 100% |
| **แขน (Arms)** | คุมปืน / แบกน้ำหนัก | แรงดีดปืนสูง, ฟันดาบช้า, ไม่สามารถถืออาวุธหนักได้ |
| **ขา (Legs)** | การเคลื่อนที่ / ล้อ Roller | MP เดินบนบอร์ดลดลง, Speed ตก, Roller Dash ล้อติดขัด |
| **ลำตัว (Torso)** | เตาปฏิกรณ์ / Core | Max Energy รวมลดลง, สะสมความร้อนไว, Overheat ง่าย |

---

## 🖥️ 7. Board UI Scene Tree Structure (Godot Engine)

```text
BoardUI (CanvasLayer)
├── RootContainer (Control) [Anchors: Full Rect]
│   ├── TopBar_GlobalResources (HBoxContainer) [Anchors: Top Wide]
│   │   ├── EnergyPanel (ProgressBar & Label) ["750/1000 (-15/Turn)"]
│   │   ├── ConvoyPanel (HP Bar, Supply Reserve Label, Backup Units Count)
│   │   └── ConsumablesPanel (Quick Fuel, Repair Kit Buttons)
│   │
│   ├── TopRight_ThreatRadar (VBoxContainer) [Anchors: Top Right]
│   │   ├── AlertPanel (Alert Level Bar & Tier Status)
│   │   ├── ObjectivePanel (Turn Counter & Main Mission)
│   │   └── WeatherHazard (Environmental Hazard Status)
│   │
│   ├── BottomLeft_UnitStatus (PanelContainer) [Anchors: Bottom Left]
│   │   └── VBox (Armor HP, Frame Durability, Part Grid: Head/Torso/Arms/Legs)
│   │
│   └── BottomRight_TileInspector (PanelContainer) [Anchors: Bottom Right]
│       └── VBox (Tile Name, MP Cost, Energy Cost, Terrain Features, Move Button)
│
└── ScreenFX_Overlay (Control) [Anchors: Full Rect / Mouse Filter: Ignore]
    ├── LowEnergyWarning (Red Flashing Vignette < 20% Energy)
    └── DynamicPathLine (Line2D Projection วาดเส้นทางคาดการณ์พลังงาน)
```

## 8. Campaign Progression & Strategic Dilemmas
### 8.1 Map Transition Dilemma
```text
  Strategic Choice: ผู้เล่นต้องเลือกระหว่าง "เสี่ยงเสียเวลาและพลังงานบุกถล่มโรงงานศัตรู" เพื่อตัดกำลังผลิต หรือ "รีบข้ามไปแผนที่ถัดไป" เพื่อถนอม Durability และประหยัด Global Energy

  Escalation Factor: ยิ่งใช้เวลาบนแผนที่เดิมนาน ค่า Alert Level จะพุ่งสูง บีบให้ศัตรูส่ง Hunter-Killer Fleet ลงมาปิดล้อม
```

---

## 👤 9. Unique Legendary Aces & Encounters

### 9.1 "The Vagrant Ace" (เสือซ่อนเล็บแห่งซากสงคราม)
* **Callsign / Name:** Gale 'The Vagrant' Kurogane
* **Signature Machine:** *Scrap Pilgrim* (หุ่นซากเศษเหล็กคลุมผ้าใบเก่า แต่ขับเคลื่อนด้วยระบบ Joint & Thrust Vectoring ชั้นสูง)
* **Lore Concept:** อดีตนักบินระดับตำนานที่ปลดประจำการและเร่ร่อนในเขตสงคราม มีความสามารถระดับ **Predictive Cognition (การอ่านการเคลื่อนไหวล่วงหน้า)** สามารถดักทางและเบี่ยงวิถีโจมตีได้ด้วยการก้าวขยับเพียงเสี้ยววินาที

#### 🕹️ Gameplay Integration & Special Mechanics
1. **Pilot Special Perk: "Pre-Cognitive Flow"**
   * **Zero-Waste Momentum:** ลด Energy Cost ในการ Dash ลง $50\%$ และไม่เกิดอาการ Flash Burn เมื่อกด Dash ต่อเนื่อง
   * **Predictive Precision:** ขยายจังหวะ Precision Dodge ขึ้น $+50\%$ และเพิ่มอัตราการหลบหลีกกระสุน
2. **Tabletop Board Behavior: "The Leading Shadow"**
   * **Predictive Movement:** เมื่อสิ้นสุดวันบนกระดานบอร์ด The Vagrant Ace จะก้าวเดินนำหน้าไปดักรอที่ช่องเส้นทางที่ขบวน Convoy ของผู้เล่นกำลังจะมุ่งหน้าไป 1 ก้าวเสมอ
3. **Unique Encounters (การพบเจอและปฏิสัมพันธ์):**
   * **Seek Guidance:** ผู้เล่นสามารถขอคำชี้แนะเพื่อเรียนรู้เคล็ดวิชาและปลดล็อกสกิล *Pre-Cognitive Flow*
   * **Challenge the Master:** ท้าดวล 1v1 ในสนามประลอง หากชนะสามารถชวนเข้าร่วมกองยาน หรือได้รับชิ้นส่วนระดับ Legendary
   * **Share Supplies:** มอบเชื้อเพลิงบริสุทธิ์เพื่อแลกกับเส้นทางลัดและข้อมูลสแกนแผนที่

---

Document Version: 4.1 (Vagrant Ace & Master Modular Architecture)

Last Updated: August 2026