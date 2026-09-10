
# Master Game Design Document (GDD)

**Project Title:** (Working Title)

**Genre:** Single-Player Hybrid (Tabletop Board + 3rd Person Action Mecha)

**Engine Target:** Godot Engine (Godot 4.x)

**Core Theme:** Military Science Fiction / Tactical Mecha (Grounded, High-Stakes, Strategic Mechanics)

**Core Architecture:** Procedural Modular Assembly System (Catalog-Driven Parts, Enemies & Pilots)

**Core Concept:** เกมวางแผนยุทธศาสตร์ทางทหารสไตล์บอร์ดเกม ผสมผสานฉากต่อสู้ 3rd Person Action ที่เน้นความสมจริง การบริหารเวลา เชื้อเพลิงในรูปแบบ Container Inventory ความสึกหรอของชิ้นส่วน และการเอาชีวิตรอดของนักบิน

## 🛠️ 1. Core Gameplay Loop

```
[ Strategic Board Phase (24-Hour Operational Cycle) ]
 (บริหาร Time Cost / สลับขับ Convoy หรือ Mecha / บริการจัดการ Fuel Inventory / Simultaneous Enemy Turns)
          │
          ▼  (โดนซุ่มโจมตี / ปะทะ Fleet ศัตรู / บุกยึด Fuel Depot)
[ 3rd Person Action Combat Phase ]
 (สู้แบบอิสระ / Precision Dash vs Spam / ปรับตาม Fleet Archetype / ปกป้อง Convoy)
          │
          ▼  (จบการรบ / ถอยทัพ / Re-ignition / ลากถังน้ำมัน)
[ Post-Battle & Garage Phase ]
 (ซ่อมเกราะ Frame Binding / เติมเชื้อเพลิงบริสุทธิ์ / อัปเกรด Core Tiers / Scavenge Parts)
```

### 1.1 Game Modes & Onboarding Flow

#### Game Modes

* **Campaign Mode (Main Loop):** โหมดวางแผนเอาชีวิตรอดทางยุทธวิธี เดินทางผ่านแผนที่บอร์ดเกม บริหารทรัพยากร Convoy ปะทะ Enemy Fleets และค้นหา Parts จาก Catalog^^
* **Combat Simulator (Arena):** โหมดทดสอบการต่อสู้ 3rd Person Action อิสระ สำหรับทดลองประกอบชิ้นส่วนและซ้อมมือกับ AI นักบินรูปแบบต่างๆ^^

#### Campaign Game Onboarding

1. **Hangar Assembly:** เลือกหุ่นเริ่มต้น Tier 1, จัด Loadout อาวุธ และตั้งค่า Pilot^^
2. **Board Spawn:** วางขบวน Convoy ลงบน Start Tile พร้อมสุ่มสร้าง Enemy Fleets และจุดสนใจ (POIs) บนแผนที่^^
3. **First Tactical Turn:** เริ่มบริหาร Time Cost (ชั่วโมง) และ Global Fuel Inventory ในการเดินบอร์ดวันแรก

## ⚙️ 2. Modular Catalog & Procedural Generation Architecture

### 2.1 Global Part Catalogs

ชิ้นส่วนทั้งหมดในเกมถูกเก็บเป็น Data Resources แบ่งเป็น 5 หมวดหลัก:^^

* **Head Catalog:** ค่าระบบเซนเซอร์, ความเร็วในการล็อกเป้า, และ HUD Utility^^
* **Torso Catalog:** เตาปฏิกรณ์หลัก (Power Core Classes), อัตราการสะสมความร้อน (Heat Generation), และโครงสร้างเกราะหลัก
* **Arm Catalog:** ค่ากำลังแบกน้ำหนัก (Load Capacity), แรงดีดปืน (Recoil Control), และการสวิงอาวุธประชิด^^
* **Leg Catalog:** โหมดการเคลื่อนที่ (Bipedal Walk / Roller Dash Mechanism), สปีดการพุ่ง, และ MP/Energy Cost^^
* **Weapon Catalog:** ค่าความเสียหาย, ประเภทกระสุน, อัตราสิ้นเปลืองพลังงาน, และแรงดีด^^
* **Inner Frame Modules (Sleeper Build Engine):** สล็อตติดตั้งโมดูลชิปและเครื่องยนต์ต้นแบบลงบน Inner Frame (Torso 3 ช่อง, Arms ข้างละ 1 ช่อง, Legs ข้างละ 1 ช่อง รวม 7 Sockets) สำหรับสร้าง Roguelike Synergies และ Power Spikes ("ภายนอกรถกระป๋อง ภายในเครื่อง V8")^^

### 2.2 Dynamic Enemy Generation Logic

* **No Hardcoded Enemies:** ศัตรูทุกตัวถูกสุ่มสร้างขณะสปอว์นบนบอร์ดตาม **Fleet Rules & Tag Constraints**
  ^^
* **Consistent Looting System (WYSIWYG):** ชิ้นส่วน อะไหล่ หรือ Inner Frame ที่สแกน/ถอดออกมาได้ จะเป็นชิ้นส่วนเดียวกับที่ศัตรูตัวนั้นติดตั้งและใช้งานอยู่จริง 100%^^

### 2.3 Procedural Pilot Generation System

* **Living Sandbox Pilots:** สุ่มสร้างนักบิน (Pilot Pool) สังกัด Factions ต่างๆ, กองกำลังทหารรับจ้าง (Mercenaries), และ Scavenger ขยะสงคราม
* **Pilot Profile Data Structure:**
  * **Identity:** ชื่อ, ฉายา, สังกัด (Faction), และค่าหัว (Bounty)
  * **Stats & Skills:** ความชำนาญการยิง (Gunnery), การขับเคลื่อน (Evasion/Dash Control), และการบริหารความร้อน
  * **AI Personality Traits:** Aggressive (บุกแหลก), Cautious (Eject ทันทีเมื่อ HP < 20%), Scavenger (มุ่งเก็บซากหุ่นและสูบน้ำมัน)
* **Synergy with Catalog Assembly:** จับคู่ Pilot Profile เข้ากับ Assembly Mecha Unit เพื่อสร้าง AI ที่มีสไตล์เฉพาะตัว

## 🚛 3. Strategic Layer (Tabletop Board Phase)

### 3.1 Dynamic Time Architecture (24-Hour Operational Cycle)

* **Time Cost System:** ใช้หน่วยเวลาบนบอร์ดเป็น **"ชั่วโมง (Hours)"** (1 วัน = 24 Hours)
* **Day / Night Environmental Modifiers:**
  * **Daytime (06:00 - 18:00):** ระยะสแกน Radar สูงสุด แต่เพิ่มค่า Alert Level และถูก Artillery Fleet เล็งเป้าได้ง่าย
  * **Nighttime (18:00 - 06:00):** ระยะสแกนลดลง 50% แต่ลดอัตราการถูกตรวจจับ เหมาะแก่การทำ Stealth Movement และลักลอบขนส่งน้ำมัน

### 3.2 Dual-Cost Terrain Movement & Time Costs

* **Road Tile:** 1 Hour | **$-10\text{ Fuel}$** (ทำสปีด ประหยัดน้ำมัน)
* **Off-Road / Mud:** 3 Hours | **$-25\text{ Fuel}$** (เครื่องยนต์ทำงานหนัก ผลาญน้ำมัน 2.5 เท่า)
* **Roller Dash Mode:** 1 Hour | **$-5\text{ Fuel}$** (ใช้ล้อทำสปีดบนทางเรียบ)
* **Camp / Full Overhaul:** 6 Hours (พักขบวน Convoy ซ่อมใหญ่ และเติมพลังงานบริสุทธิ์)

### 3.3 Vehicle Switching & Emergency Logic

* **Seamless Vehicle Switching:** ผู้เล่นสามารถเลือกสลับระหว่างการควบคุม **Convoy** หรือ **Mecha** บนบอร์ดกระดานได้ตลอดเวลา
* **Convoy Energy Depleted State:** เมื่อ Convoy น้ำมันหมด (0 Energy) ขบวนรถจะหยุดนิ่งบน Tile นั้น แต่ระบบจะบังคับสลับให้ผู้เล่นออกมาควบคุม **Mecha** เพื่อออกเดินทางต่อบนบอร์ดทันที
* **Progression Choices:** เมื่อขับหุ่นออกไปเจอ Tile ที่มีพลังงาน ผู้เล่นเลือกได้ว่า:
  1. **Refuel Mecha Only:** เติมให้หุ่นตัวเองแล้วลุยต่อ (ทิ้ง Convoy ไว้ที่เดิม)
  2. **Haul Fuel Back:** ขับหุ่นนำน้ำมันกลับมาเติม Convoy เพื่อเดินหน้าขบวนใหญ่ร่วมกันต่อ
* **Pilot Emergency Disembark:** หากทั้ง Convoy และหุ่นพลังงานหมด 0% นักบินต้องสลัดออกจากหุ่นเพื่อใช้ระบบ Stealth ลักลอบวิ่งไปสูบน้ำมันเถื่อน (Siphon Fuel) ใส่ถังพกพา นำกลับมารีบูตเครื่องยนต์ (Re-ignition)

### 3.4 Enemy Fleet Archetypes & Board Hazards

| **รูปแบบ Fleet** | **คุณสมบัติบนบอร์ด (Board Mechanics)**                                                                                                                       | **3rd Person Action & Assembly Rules**                                                                                                                                                             |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Recon Fleet**        | เดินไวมาก                                                                                                                                                                 | **Legs:**บังคับ Tag`Roller-Dash`/**Weapons:**SMG เบา / หุ่นสปีดสูง^^                                                                                                               |
| **Armored Fleet**      | เดินช้า ถึก                                                                                                                                                              | **Torso/Legs:**บังคับ Tag`Heavy-Armor`/**Weapons:**Heavy Cannon, โล่^^                                                                                                                        |
| **Artillery Fleet**    | **Board Hazard Only:**รัศมียิงปูพรม 2-3 ช่อง (โดนยิงตัดกำลัง/Debuff บนบอร์ดเมื่อเวลาเดินโดยยังไม่เข้าฉากสู้) | **Weapons:**บังคับ Tag`Missile-Pod`หรือ`Railgun`ระยะไกล (บีบให้ผู้เล่นกด Roller Dash ชาร์จเข้าประชิดเมื่อเดินเข้าชนช่องศัตรู) |
| **Hunter-Killer**      | สปอว์นตาม Alert Level                                                                                                                                                     | **Frame:**Tier 2-3 High-Tech / สุ่มชิ้นส่วน Synergy ระดับสูง สู้เป็นทีม                                                                                                    |

* **Zone of Control (ZoC):** ช่องรอบตัว Fleet ศัตรู 1 ช่องถือเป็นเขตอิทธิพล หากผู้เล่นเดินก้าวเข้า ZoC เวลาและเชื้อเพลิงขาก้าวถัดไปจะถูกคิดเพิ่มขึ้นทันที

### 3.5 Sector Sub-Zones (Micro-Biomes & Tactical Terrain Variations)

* **Micro-Biome Partitioning:** แผนที่เปิดขนาด $25 \times 25$ ในแต่ละ Sector จะถูกแบ่งออกเป็น **2–3 Sub-Zones (โซนย่อย)** อย่างเป็นธรรมชาติด้วยระบบ Voronoi Clustering แบบ Seeded Deterministic
* **Cohesive Tactical Immersion (WYSIWYG Arena):** ทุก Tile บนกระดานจะมี metadata `sub_zone` ระบุเขตภูมิประเทศอย่างชัดเจน และเมื่อเข้าสู่ฉาก Combat 3D ฉากสนามรบจะถูกสร้างให้ตรงกับ Sub-Zone นั้นๆ 100%

#### Sub-Zones Catalog & Arena Mappings

| **Sector Theme** | **Sub-Zone (ID / ชื่อไทย)** | **ลักษณะบนบอร์ด (Board Visual & Props)** | **3D Action Arena Layout & Tactics** |
| :--- | :--- | :--- | :--- |
| **Suburb** (ชานเมือง) | **Residential Village** (`suburb_village`)<br>• หมู่บ้านชานเมือง | ถนนตัดผ่านหนาแน่น, ไอคอนบ้านจัดสรร, เสาไฟฟ้า | บล็อกบ้านพักอาศัย 2 ชั้น, ตรอกซอกซอยแคบ, กำบังหนาแน่น เหมาะกับสายประชิด / Roller-Dash |
| | **Open Meadow** (`suburb_meadow`)<br>• ทุ่งหญ้าชานเมือง | ผืนหญ้าเขียวกว้าง, ดอกไม้, หินประปราย | พื้นที่เปิดโล่งกว้างขวาง วิสัยทัศน์ 360°, ไม่มีสิ่งปลูกสร้างขวาง เหมาะกับสาย Sniper / Long-Range |
| | **Wetland & Lakefront** (`suburb_water`)<br>• ริมน้ำและหนองน้ำชานเมือง | แนวคลอง ลำธาร กอต้นกก และสะพานไม้ | แอ่งน้ำตื้น ลำธารตัดผ่าน และสะพานข้าม น้ำช่วยระบายความร้อน Core แต่ชะลอความเร็วหุ่น |
| **Urban** (เมืองหลวง) | **Downtown Highrise** (`urban_downtown`)<br>• ใจกลางเมืองตึกระฟ้า | ตึกสูงระฟ้าหนาแน่น ลานจอดรถ | ตึกระฟ้าสูง 30–50m ตรอกคอนกรีตลึก มุมอับสายตาเยอะ ขีปนาวุธติดตึกง่าย |
| | **Industrial Logistics Zone** (`urban_industrial`)<br>• เขตอุตสาหกรรม | แทงก์น้ำมัน โกดัง คลังตู้คอนเทนเนอร์ | ไซโลทรงกระบอก กองตู้คอนเทนเนอร์หลากสีสัน กำบังที่สามารถยิงระเบิดหรือทำลายได้ |
| | **Central Metro Park** (`urban_park`)<br>• สวนสาธารณะเมืองหลวง | ลานกว้างใจกลางเมือง สระน้ำ อนุสาวรีย์ | ลานอนุสาวรีย์หิน ซุ้มศาลาพักผ่อนล้อมรอบด้วยสนามหญ้าและแนวต้นไม้ |
| **Desert** (ทะเลทราย) | **Endless Sand Dunes** (`desert_dunes`)<br>• ทะเลทรายลึก | เนินทรายกว้างใหญ่ หินทรายเตี้ยๆ | เนินทรายลอนคลื่นสูงชัน ลดการยึดเกาะของ Roller Dash ต้องใช้กระโดดข้ามสันเนิน |
| | **Rocky Canyon & Badlands** (`desert_canyon`)<br>• หุบเขาหินผา | เสาหินผาสูงชัน ทางเดินช่องแคบ | เสาหินผาทรงกระบอกสูงและแนวกำแพงหิน เหมาะแก่การซุ่มยิงจากมุมสูงและดักซุ่ม |
| | **Oasis Outpost** (`desert_oasis`)<br>• โอเอซิสและแคมป์เหมือง | สระน้ำใจกลางทราย ต้นปาล์ม ซากแคมป์ | บ่อน้ำธรรมชาติล้อมรอบด้วยต้นปาล์มและซากกล่องเสบียง |
| **Forest** (ป่าลึก) | **Dense Canopy Forest** (`forest_deep`)<br>• ป่าทึบ | ป่าสนหนาทึบ ต้นไม้ใหญ่เรียงราย | ต้นไม้หนาแน่น ป่าทึบ กำบังสายตาจากเรดาร์ระยะไกล |
| | **River Crossing** (`forest_river`)<br>• ลำน้ำแบ่งฟาก | แม่น้ำกว้างผ่ากลาง สะพานข้าม 2–3 จุด | แม่น้ำลึกขวางสนามรบ บีบให้ปะทะกันบนแนวสะพานเหล็ก Choke Point |
| | **Logging Camp & Ruins** (`forest_ruins`)<br>• ค่ายตัดไม้และซากโบราณ | เสาหินโบราณ กองไม้ซุง ลานโล่ง | ซากเสาหินมอสส์เกาะ กองท่อนไม้ซุง เหมาะเป็นจุดปะทะขนาดกลาง |

## ⛽ 4. Inventory-Based Fuel Architecture & Power Core Classes

### 4.1 Fuel Container Inventory System

* **Container Item Mechanics:** พลังงานทุกประเภทเก็บเป็น **Item Slot ใน Inventory**
* **Container Capacity:** ถังบรรจุมีขนาดแตกต่างกัน (เช่น 1%, 6%, 10%, 20%, 100%) แต่ละถังถือเป็น 1 Inventory Slot
* **Automatic Stacking Logic:** เมื่อเดินบน Tile หรือเจอ Event แล้วได้พลังงาน ระบบจะนำไปเติมใส่ถังประเภทเดียวกันที่ยังไม่เต็ม **$100\%$** ให้เต็มก่อนโดยอัตโนมัติ
  * *Example:* มี `[100%, 10%]` ใน Inventory ➔ เดินบน Tile เจอถังพลังงาน `6%` ➔ รวมเป็น `[100%, 16%]` (ใช้พื้นที่ 2 Inventory Slots)

### 4.2 Fuel Types & Power Core Compatibility

| **Fuel Item Tag**                                            | **พาหนะ/เครื่องยนต์ที่เติมได้** | **คุณสมบัติ & การนำไปใช้**                                                                                                               |
| ------------------------------------------------------------------ | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Crude Oil Container (น้ำมันดิบ)**                 | **Convoy** ,**Direct Combustion Core**              | หาได้ง่ายทั่วไป เติมใส่ Convoy หรือหุ่นเครื่องยนต์ดีเซล/สันดาปได้ทันที 100% ไร้ Penalty            |
| **Refined Energy Cell (เซลล์พลังงานกลั่น)** | **All Mecha Cores**(หุ่นทุกประเภท)           | ต้องผ่านการกลั่นจาก Convoy หรือหาจากซากบอส เติมให้หุ่นสังเคราะห์/ไฮเทคได้โดยไม่ติด Debuff |
| **Bio-Fuel / Impure Container**                              | **Convoy** ,**Combustion Core**                     | เติมแก้ขัดได้ แต่ถ้านำไปใส่หุ่นเตาสังเคราะห์จะทำให้เกิด Heat สะสมไวขึ้น 30%                       |

### 4.3 Torso Power Core Classes

| **ประเภทเตาพลังงาน**                                | **การใช้พลังงานบนบอร์ด**                                          | **สมรรถนะในฉากสู้ 3D Action**                     | **ข้อเสีย / Trade-off**                                                                                                         |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| **Direct Combustion Core (เครื่องยนต์สันดาปรถ)** | ใช้น้ำมันดิบชนิดเดียวกับ Convoy 100% เติมตรงได้ทันที | แรงบิดสูง แบกอาวุธหนักได้ดี                  | เครื่องยนต์หนัก, สะสม Heat ปานกลางตลอดเวลา, สปีดพุ่งต่ำกว่าเตาไฮเทค                 |
| **Overclocked Hybrid Core**                                         | ประหยัดน้ำมัน 20%                                                              | Roller Dash แรงขึ้น แต่สะสม Heat สูง                  | หากสะสมความร้อนสูงเกินไป จะกิน Durability ของ Frame                                                          |
| **Ancient / Legendary Core (GN Drive Style)**                       | **ไม่กินน้ำมันเลย (**$0\text{ Energy Cost}$**บนบอร์ด)** | Roller Dash / อาวุธลำแสงใช้งานได้ต่อเนื่อง | **ไม่ดร็อปอะไหล่** , ต้องการชิ้นส่วนซ่อมระดับ Legendary, และดึงดูด Hunter-Killer Fleets |

## 🤖 5. Combat Layer (3rd Person Action Phase)

### 5.1 Mobility & Precision Dash Dynamics

* **Bipedal Walk / Jump:** สำหรับข้ามสิ่งกีดขวาง ทางชัน และพื้นที่ขรุขระ^^
* **Roller Dash:** กางล้อจุดไอพ่นพุ่งตัวความเร็วสูงบนพื้นเรียบ^^
* **Precision Dash vs Spam Dash:**
  * *Precision Dash (หลบถูกจังหวะ):* ใช้ Short-Pulse Ignition รักษา Momentum เดิม ใช้พลังงานน้อยลง 60%^^
  * *Spam Dash (กดหลบรัวๆ):* เกิด Flash Burn ทำลาย Momentum เครื่องยนต์เค้นรอบสูงสุด ผลาญพลังงานและเกิด Overheat ไว^^

## 🦾 6. Maintenance, Durability & Damage Architecture

### 6.1 Component Lifetime Durability vs Current HP (The Battery Health Model)

ระบบคำนวณสภาพหุ่นจำลองตามหลักการ **"พลังงานชาร์จ (HP) vs สุขภาพแบตเตอรี่ (Durability / Battery Health)"**:

* **Current HP (พลังชีวิตปัจจุบัน / ค่าชาร์จ 0% - 100%):**
  * ลดลงเมื่อโดนโจมตีในฉากต่อสู้
  * เมื่อ HP = 0 เกราะจะแตกหลุด (Armor Shatter) หรือโครงสร้างเฟรมหยุดทำงาน
  * สามารถเติม/ซ่อมแซมให้เต็มได้ตลอดเวลาผ่านโรงเก็บหุ่น (Hangar) หรือการปะเศษเหล็กฉุกเฉิน (Emergency Scrap Patch)
* **Lifetime Durability (ความสมบูรณ์/อายุการใช้งานของชิ้นส่วน 100% $\rightarrow$ 0%):**
  * **ไม่ใช่ค่าเดียวกับ HP** แต่คืออายุการใช้งานและสภาพความล้าของโลหะ (Metal Fatigue & Wear)
  * **ปัจจัยที่ทำให้ Durability ลดลง:**
    1. **การซ่อมแซม (Repair Wear):** ทุกครั้งที่ทำการซ่อม HP (ทั้ง Field Repair และ Garage Repair) ชิ้นส่วนจะเกิดความสึกหรอสะสม ($-2\%$ ถึง $-10\%$ ต่อครั้ง)
    2. **เกราะแตก / เสียหายวิกฤต (Armor Break / Frame Breach):** เมื่อ HP ลดเหลือ 0 เกราะแตกร้าวรุนแรงทำให้สูญเสีย Durability ถาวร
    3. **ความร้อนสะสมและการยิงต่อเนื่อง (Overheat Stress):** อาวุธที่ยิงซ้ำๆ หรือถูกเค้นยิงในสภาวะความร้อนสูง (Overheat $>75\%$) จะสูญเสีย Durability รวดเร็วขึ้น
  * **ผลกระทบของ Durability:**
    * **Effective Max HP Capping:** $\text{Effective Max HP} = \text{Base Max HP} \times \text{Durability}$ (ชิ้นส่วนที่เสื่อมสภาพจะซ่อม HP กลับมาได้ไม่เต็มค่าเดิม)
    * **Part Penalties เมื่อ Durability ต่ำ (Yellow / Red Zone):**
      * **Head:** ล็อกเป้าช้า, HUD Glitch, ต้อง Free-aim เล็งเอง
      * **Arms:** แรงดีดปืนสูง, อาวุธ Jam ง่าย, ฟันดาบช้า
      * **Legs:** สปีดเดินลดลง, Roller Dash ติดขัด
      * **Torso:** Max Energy รวมลดลง, Overheat ไวขึ้น
    * **Decision to Overhaul / Replace:** เมื่อชิ้นส่วนเสื่อมสภาพจนถึงจุดวิกฤต ผู้เล่นต้องตัดสินใจยกเครื่องใหม่ เปลี่ยนเฟรมใหม่ หรือซื้อ/คราฟต์ชิ้นส่วนใหม่มาทดแทน

---

### 6.2 Directional 3-Stage Damage Shader System

รอยความเสียหายบนพื้นผิวโมเดล 3D คำนวณแบบ Model-Space Procedural Shader อ้างอิงตามทิศทางและจุดปะทะจริง (Hit-Localized & Directional Impact) แบ่งเป็น 3 ระดับ:

1. **Stage 1: Surface Scratches & Paint Scuffs (รอยถลอก/สีลอก / Damage $0.01 - 0.35$):**
   * เกิดเฉพาะรอบจุดปะทะ (`hit_pos`) เป็นรอยขูดขีด รอยกระสุนถาก และรอยไหม้ผิวนอก ไม่เกิดรอยแตกลึกทั้งตัว
2. **Stage 2: Hairline Fractures (รอยแตกร้าวบาง / Damage $0.35 - 0.70$):**
   * รอยแตกลายงาและเส้นใยรอยร้าวเริ่มแตกแขนงแผ่ออกมาจากจุดศูนย์กลางการปะทะ
3. **Stage 3: Severe Structural Breaches (รอยแตกลึก/ฉีกขาด / Damage $0.70 - 1.00$):**
   * รอยแยกกว้างลึก เผยให้เห็นเนื้อโลหะชั้นใน (Exposed Metal) พร้อมวงรอยไหม้เขม่าควัน (Scorch Halo) แผ่ขยายกว้าง
   * เมื่อซ่อมแซมชิ้นส่วนในโรงเก็บหุ่น ระบบจะรีเซ็ต Shader Material Overlay และอัปเดตโมเดล 3D Preview ทันทีแบบ Real-Time

---

### 6.3 Multi-Tier Repair System & Field Maintenance

1. **Field Emergency Repair (Scrap Patching):** ซ่อมเกราะฉุกเฉินบนบอร์ด ใช้ Scrap Metal คืน HP บางส่วน
   * *Visual:* ปรากฏแผ่นเหล็กเชื่อมติดหยาบๆ (Patchwork Armor) บริเวณที่เกราะพัง
2. **Field Structural Preservation (Inner Frame Binding):** ใช้ผ้าทนแรงดึงสูง (Composite Cloth) พันดามโครงกระดูก Inner Frame ที่เปลือยออก เพื่อมัดกระชับรอยร้าวบนเฟรมและปกป้องสายไฟ (เว้นช่วงข้อต่อ Actuators ไว้เพื่อให้ขยับได้ 100%)
   * *Visual:* ผ้าพันแผลหนาๆ พันกระชับแนบไปกับโครงกระดูกท่อนแขน ท่อนขา หรือลำตัวหุ่น
3. **Thermal / Camouflage Cloak:** สวมผ้าคลุมเพื่อลดค่า Thermal Signature และซ่อนตำแหน่งจาก Radar ปืนใหญ่ศัตรู
   * *Visual:* ผ้าคลุมผืนใหญ่ (Physics-enabled Cloak) สะบัดตามการเคลื่อนที่
4. **Full Overhaul:** ซ่อมแซมใหญ่ที่ Base/Convoy เคลียร์ร่องรอยบาดแผลทั้งหมด ดึงประสิทธิภาพคืน 100%

## 👤 7. Unique Legendary Aces & Encounters

### 7.1 "The Vagrant Ace" (เสือซ่อนเล็บแห่งซากสงคราม)

^^* **Callsign / Name:** Gale 'The Vagrant' Kurogane^^

* **Signature Machine:** *Scrap Pilgrim* (หุ่นซากเศษเหล็กคลุมผ้าใบเก่า ขับเคลื่อนด้วยระบบ Joint & Thrust Vectoring ชั้นสูง)^^
* **Lore Concept:** อดีตนักบินระดับตำนานที่ปลดประจำการ มีความสามารถระดับ **Predictive Cognition (การอ่านการเคลื่อนไหวล่วงหน้า)** เบี่ยงวิถีโจมตีได้ด้วยการก้าวขยับเพียงเสี้ยววินาที^^

#### 🕹️ Gameplay Integration

1. **Pilot Special Perk: "Pre-Cognitive Flow"**
   ^^
   * **Zero-Waste Momentum:** ลด Energy Cost ในการ Dash ลง **$50\%$** และไม่เกิดอาการ Flash Burn เมื่อกด Dash ต่อเนื่อง^^
   * **Predictive Precision:** ขยายจังหวะ Precision Dodge ขึ้น **$+50\%$** และเพิ่มอัตราการหลบหลีกกระสุน^^
2. **Tabletop Board Behavior:** สิ้นสุดเวลาประมวลผลบนบอร์ด AI จะก้าวเดินนำหน้าไปดักรอที่ช่องเส้นทางที่ขบวน Convoy กำลังจะมุ่งหน้าไป 1 ก้าวเสมอ^^
3. **Encounters:** ผู้เล่นสามารถขอคำชี้แนะเรียนรู้สกิล, ท้าดวล 1v1 เพื่อชวนเข้าร่วมทีม, หรือมอบเชื้อเพลิงบริสุทธิ์เพื่อแลกกับเส้นทางลัด^^

## 🖥️ 8. Board UI Scene Tree Structure (Godot Engine)

^^**Plaintext**

```
BoardUI (CanvasLayer)
├── RootContainer (Control) [Anchors: Full Rect]
│   ├── TopBar_GlobalResources (HBoxContainer) [Anchors: Top Wide]
│   │   ├── TimePanel (Clock Display: "14:00 - Day 3")
│   │   ├── FuelInventoryPanel (Grid Display: [100%][16%])
│   │   └── ConvoyPanel (HP Bar, Supply Reserve Label)
│   │
│   ├── TopRight_ThreatRadar (VBoxContainer) [Anchors: Top Right]
│   │   ├── AlertPanel (Alert Level Bar & Tier Status)
│   │   └── EnvironmentHazard (Day/Night Weather Status)
│   │
│   ├── BottomLeft_UnitStatus (PanelContainer) [Anchors: Bottom Left]
│   │   └── VBox (Armor HP, Frame Durability, Part Grid: Head/Torso/Arms/Legs)
│   │
│   └── BottomRight_TileInspector (PanelContainer) [Anchors: Bottom Right]
│       └── VBox (Tile Name, Time Cost, Fuel Cost, Move Button)
│
└── ScreenFX_Overlay (Control) [Anchors: Full Rect / Mouse Filter: Ignore]
    ├── LowEnergyWarning (Red Flashing Vignette < 20% Energy)
    └── DynamicPathLine (Line2D Projection วาดเส้นทางคาดการณ์เวลาและพลังงาน)
```

## 🛠️ 9. Engine Plugins & Technical Extensions (Godot 4)

* **Physics & Combat:** `Godot-Jolt` (3D Physics Engine), `Jigglebones` (ผ้าคลุม/ผ้าพันแผลพริ้วไหว)
* **IK & Foot Placement:** `SkeletonIK3D` (Built-in) ร่วมกับ RayCast3D เพื่อให้ฝ่าเท้าและล้อ Roller Dash ปรับมุมเกาะแนบสนิทกับพื้นเอียง (Slope Alignment) โดยเท้าไม่จมหรือลอย
* **Board Mechanics & AI:** `AStar3D` Native / Grid Calculation Utilities
* **Catalog Architecture:** `Resource Database Viewer` (จัดการ Data Resources ใน Catalog)
* **AI Logic Structure:** `Beehave` หรือ Behavior Tree Engine (ควบคุม AI Traits และการสลับโหมดนักบิน)

*Document Version: 6.0 (Clean Architecture & Hour/Inventory Fuel Engine)*

*Last Updated: August 2026*
