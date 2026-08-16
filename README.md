# Mecha Roguelike Action 3rd-Person

เกมแอ็กชัน 3D มุมมองบุคคลที่สามที่ผู้เล่นควบคุมหุ่นรบ Mecha เดินทางผ่านแผนที่แบบ Roguelike ต่อสู้กับศัตรู เก็บกู้อาวุธและชิ้นส่วนเกราะ แล้วบริหารทรัพยากรเพื่อไปให้ถึงบอสของแต่ละ Sector

โปรเจกต์นี้พัฒนาด้วย **Godot 4.6.2.stable** และใช้ GDScript

## ภาพรวมเกม

ลูปการเล่นหลัก:

```text
Main Menu
    -> Board Map
    -> เลือกเส้นทาง
        -> Combat
        -> Event
        -> Safehouse
        -> Data Node
        -> Extraction / Boss
    -> รับรางวัลและ Salvage
    -> กลับไปยัง Board Map
```

จุดเด่นของเกม:

- ควบคุม Mecha แบบ 3D Third-person
- ต่อสู้เป็น Wave กับศัตรูหลายประเภท
- ยิงอาวุธจากมือซ้ายและมือขวา
- เล็งแบบ Manual หรือ Lock-on เป้าหมาย
- แยกความเสียหายตามชิ้นส่วนของหุ่น
- ชิ้นส่วนเกราะพังและถูกถอดออกระหว่างการต่อสู้
- Eject นักบินออกจากหุ่นและขึ้นหุ่นสำรองได้
- จัดการน้ำหนัก ความเร็ว อาวุธ กระสุน และทรัพยากร
- แผนที่สร้างแบบ Procedural และมีเส้นทางแตกแขนง
- ระบบ Heat และ Wanted เพิ่มความยากตามการเล่น
- ระบบ Hangar สำหรับเลือก Chassis ซ่อมแซม และเปลี่ยนอุปกรณ์
- บันทึกความคืบหน้าลงไฟล์ Save Game

## ความต้องการของระบบ

- Godot `4.6.2.stable`
- Renderer 3D ที่รองรับ Godot 4
- Windows, Linux หรือ macOS ที่รัน Godot 4 ได้

## วิธีเปิดโปรเจกต์

1. เปิด Godot 4.6.2
2. เลือก `Import`
3. เลือกไฟล์ `project.godot` ในโฟลเดอร์นี้
4. เปิดโปรเจกต์
5. กด `F6` เพื่อรันฉากปัจจุบัน หรือ `F5` เพื่อรันเกมจาก Main Menu

ฉากเริ่มต้นถูกกำหนดไว้ที่:

```text
res://scenes/main_menu/main_menu.tscn
```

## ปุ่มควบคุม

| การทำงาน | ปุ่มเริ่มต้น |
| --- | --- |
| เดินหน้า | `W` |
| ถอยหลัง | `S` |
| เคลื่อนที่ซ้าย | `A` |
| เคลื่อนที่ขวา | `D` |
| Strafe / บังคับหันตัว | `Left Shift` |
| กระโดด | `Space` |
| โต้ตอบ | `E` |
| Eject ออกจาก Mecha | `F` |
| เปิด/ปิด Roller Dash | `Page Up` |
| Dash | `Page Down` |
| ยิงอาวุธมือซ้าย | เมาส์ซ้าย |
| ยิงอาวุธมือขวา | เมาส์ขวา |
| เล็ง | ปุ่มเมาส์กลาง |
| เปลี่ยนอาวุธมือซ้าย | `1` |
| เปลี่ยนอาวุธมือขวา | `3` |
| ทิ้งอาวุธ | `X` |
| Reload | `R` |
| Pause | `Esc` |
| ปลดล็อกกล้อง | `Tab` |

สามารถเปลี่ยน Input Map ได้จาก `Project Settings > Input Map`

## ระบบเกม

### Mecha Combat

การต่อสู้เกิดขึ้นในสนาม 3D ที่สร้างองค์ประกอบบางส่วนแบบ Procedural มีระบบกล้อง Third-person, Lock-on, Projectile, VFX, Screen Shake และ HUD สำหรับแสดงสถานะการต่อสู้

ศัตรูที่มีอยู่ในโปรเจกต์ ได้แก่:

- Rusher / Grunt
- Ranged Mecha
- Heavy Mecha
- Support Mecha
- Shield Knight (ถือโล่ + อาวุธ Melee — ยกโล่กันขณะบุก แล้วลดโล่ตอนฟัน)
- Shield Gunner (ถือโล่ + ปืน — ยกโล่กันระหว่างยิง ช่องโหว่ตอนยิงแต่ละนัด)
- Tank
- Stalking Ace
- Boss Overlord

### ความเสียหายและชิ้นส่วน

ตัวหุ่นแบ่งเป็นส่วนหลัก 6 ส่วน:

- Head
- Body
- Left Arm
- Right Arm
- Left Leg
- Right Leg

แต่ละส่วนมี HP, Armor และ Weight ของตัวเอง เมื่อเกราะถูกทำลาย ระบบจะแสดงความเสียหายและเปลี่ยนสภาพ Mesh ของชิ้นส่วนนั้นเป็น Inner Frame ตามที่กำหนดไว้ในระบบ

### ระบบ Type ของการโจมตี (Heat / Pierce / Blunt)

อาวุธทุกชิ้นยิงหนึ่งในสาม Type:

- 🔥 **Heat** — Beam Rifle/Carbine/Mk2, Missile ทุกแบบ, Heat Blade
- 🗡️ **Pierce** — Machine Gun/LMG/HMG, Minigun, Railgun, Beam Sniper, Combat Knife, Pile Bunker
- 🔨 **Blunt** — Shotgun/Sawed-Off, Assault Cannon, Gatling, Mace

เกราะแต่ละชิ้นมี `defense_type` ของตัวเอง (Heat/Pierce/Blunt):

- การโจมตีที่ **ตรงกับ Type** ของเกราะ → เกราะลดทอนด้วย Armor Class ตามปกติ
- การโจมตีที่ **ไม่ตรง Type** → เกราะลดทอนไม่ได้ รับความเสียหายเต็ม (จนกว่าเกราะจะพัง)
- เกราะที่ไม่มี defense_type (Balanced) ลดทอนทุก Type อย่างเท่ากัน

### โล่ (Shield Plate)

โล่เป็น **แผ่นวัสดุจริงที่ถือบนแขน** (ไม่ใช่บาเรียพลังงาน) ไม่มี Regeneration — เมื่อรับความเสียหายแล้ว HP โล่จะไม่กลับคืน และโล่ที่พังจะไม่สามารถยกขึ้นมาใช้ได้อีกในการต่อสู้ครั้งนั้น

โล่แต่ละแบบมี `shield_type` (Anti-Type) ของตัวเอง:

- โดนการโจมตี **ตรงกับ Anti-Type** → ดูดซับเต็มที่ แต่ HP โล่ลดช้า (40% ของ damage)
- โดน Type อื่น → กันได้เต็มที่แต่ HP โล่หมดเร็ว (100% ของ damage)

เช่น ถือโล่ Anti-Pierce แล้วเจอ Pile Bunker (Pierce) — โล่จะกันได้ยาวนานเพราะเป็น Type ที่ตรงกัน แต่ถ้าโดน Heat หรือ Blunt โล่จะละลายเร็ว

### อาวุธและน้ำหนัก

อาวุธสามารถติดตั้งที่มือซ้าย มือขวา หรือเก็บไว้ใน Carry Inventory อาวุธในโปรเจกต์มีหลายประเภท เช่น:

- Beam Rifle และ Beam Carbine
- Machine Gun และ Gatling Gun
- Shotgun
- Missile
- Shield
- Heat Blade
- Pile Bunker
- อาวุธประชิดประเภทอื่นๆ

น้ำหนักรวมของเกราะและอาวุธมีผลต่อความเร็วและการควบคุม Mecha จึงต้องเลือกระหว่างเกราะหนักที่ทนทานกับความคล่องตัว

### Roguelike Board

Board Map เป็นแผนที่แบบโหนดที่มีเส้นทางเชื่อมต่อกัน ผู้เล่นต้องเลือกเส้นทางไปทีละ Tile โดย Tile แต่ละประเภทให้ผลต่างกัน เช่น:

- `Combat` เข้า Arena และต่อสู้กับศัตรู
- `Event` เกิดเหตุการณ์สุ่มและได้รับหรือเสียทรัพยากร
- `Safehouse` ลด Heat และใช้สำหรับพักหรือจัดการระบบสนับสนุน
- `Data Node` ได้ Data Cores
- `Exit` นำไปสู่การต่อสู้กับ Boss

### Heat และ Wanted

ค่า Heat จะเปลี่ยนตามการต่อสู้และการเดินทาง เมื่อ Heat สูงขึ้น ระบบจะเพิ่มขีดจำกัดกำลังรบของศัตรู เพิ่ม Wanted Level และทำให้ Wave มีศัตรูมากขึ้นหรือมี HP สูงขึ้น

ค่าเหล่านี้ถูกเก็บไว้ใน `GlobalData` และจัดการโดย `HeatWantedSystem`

### Hangar และการบันทึกเกม

ใน Hangar ผู้เล่นสามารถ:

- เลือก Chassis
- เปลี่ยนชิ้นส่วนเกราะ
- เปลี่ยนอาวุธ
- ซ่อมชิ้นส่วนที่เสียหาย
- ตรวจสอบน้ำหนักและสถิติของ Mecha

ข้อมูล Run ถูกบันทึกเป็น JSON ที่:

```text
user://savegame.json
```

## โครงสร้างโฟลเดอร์

```text
res://
├── autoload/                 Singleton และข้อมูลระดับเกม
├── resources/mech/           Resource ของเกราะ Chassis และอาวุธ
├── scenes/                   ฉากเกม ฉาก UI และฉากศัตรู
├── scripts/mecha/            การควบคุม Combat Health และ Weapon ของ Mecha
├── scripts/board/            การสร้างและจัดการ Board Map
├── scripts/systems/          Spawn Loot Salvage Damage และ Heat
├── scripts/ui/               HUD เมนู Hangar และหน้าจอรางวัล
├── scripts/arena/            การสร้างสนามต่อสู้ สิ่งกีดขวาง และบรรยากาศ
├── scripts/audio/             ระบบเสียงและเพลง
├── shaders/                  Shader สำหรับความเสียหายและเกราะแตก
├── project.godot             การตั้งค่าโปรเจกต์และ Input Map
└── ARCHITECTURE.md           เอกสารโครงสร้างและ Signal Flow ภายในเกม
```

## Autoload หลัก

| ชื่อ | ไฟล์ | หน้าที่ |
| --- | --- | --- |
| `EventBus` | `autoload/event_bus.gd` | ศูนย์กลาง Signal ระหว่างระบบ |
| `GlobalData` | `autoload/global_data.gd` | ข้อมูล Mecha, Run, อาวุธ และทรัพยากร |
| `GameManager` | `autoload/game_manager.gd` | จัดการ State และเปลี่ยนฉาก |
| `AudioManager` | `scripts/autoload/audio_manager.tscn` | จัดการเสียงและเพลง |
| `HeatWantedSystem` | `scripts/systems/heat_wanted_system.gd` | คำนวณ Heat, Wanted และการระดมพลของศัตรู |

State หลักของเกมคือ:

```text
MENU -> BOARD -> COMBAT -> BOARD
                 ├-> SAFEHOUSE
                 ├-> HANGAR
                 └-> EJECT -> PILOT
```

## สถานะปัจจุบัน

โปรเจกต์อยู่ในระยะ Prototype / Vertical Slice ที่มีระบบหลักจำนวนมากพร้อมสำหรับการพัฒนาต่อ ได้แก่ Combat, Board Map, Enemy Wave, Weapon, Salvage, Hangar, Eject และ Save Game

ส่วนที่ควรตรวจสอบเพิ่มเติมก่อนทำ Build จริง:

- ทดสอบทุกเส้นทางของ Board และการเปลี่ยนฉาก
- ตรวจ runtime error ของระบบ Stalking Ace Ambush
- ตรวจ Resource path ของอาวุธและฉากศัตรูทั้งหมด
- ทดสอบ Save/Load หลังเปลี่ยน Chassis หรืออุปกรณ์
- ปรับสมดุล Heat, Wanted, จำนวน Wave และค่า Damage
- เพิ่ม automated test หรือ validation สำหรับข้อมูล Resource

## เอกสารเพิ่มเติม

รายละเอียด Signal Flow, State Machine, Resource System และ Weapon Flow อยู่ใน:

```text
ARCHITECTURE.md
```
