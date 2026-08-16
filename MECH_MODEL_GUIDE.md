# คู่มือเพิ่ม Model เข้าเกม (Mech Parts & Animation)

เอกสารนี้อธิบายวิธีเพิ่มโมเดล 3D เข้าไปในโปรเจกต์ Godot นี้แบบครบวงจร ตั้งแต่
โครงสร้างพาร์ตแบบโมดูลาร์ วิธีสร้าง/วางไฟล์ `.glb` วิธีผูก `ArmorPart` ไปจนถึงการ
ใส่แอนิเมชันจากภายนอก

---

## 1. โครงสร้างพาร์ตแบบโมดูลาร์

เครื่อง (Mecha) ประกอบจาก 6 ช่อง (slot) แยกชิ้นกัน แต่ละช่องรับ 2 ส่วน:

- **Inner Frame** — โครง/โครงกระดูกกลไกของชิ้นนั้น (เช่น แขนท่อนบน-ท่อนล่าง)
- **Outer Armor** — เกราะที่หุ้มภายนอก (สิ่งที่ผู้เล่นสวม/เปลี่ยน)

| slot | โหนดหลัก | โหนดท่อนล่าง (ข้อต่อ) |
|------|-----------|----------------------|
| `head` | `Head` | — |
| `body` | `Body` | — |
| `arm_left` | `ArmLeft` | `ArmLeft/ForearmLeft` (ข้อศอก) |
| `arm_right` | `ArmRight` | `ArmRight/ForearmRight` (ข้อศอก) |
| `leg_left` | `LegLeft` | `LegLeft/ShinLeft` (เข่า) |
| `leg_right` | `LegRight` | `LegRight/ShinRight` (เข่า) |

โหลดมาจาก `scenes/mecha/mecha_base.tscn` และถูกประกอบที่ runtime โดย
`PartMeshManager` (`scripts/mecha/part_mesh_manager.gd`):

- `mesh_scene` → instantiate ใส่ `ArmorMesh` (เกราะ)
- `inner_frame_scene` → instantiate ใส่ `FrameMesh` (โครง)

> โมเดล legacy ใน `mecha_base.tscn` (เช่น `Zenisrev` หรือ primitive เดิม) จะถูกซ่อน
> อัตโนมัติโดย `_hide_all_legacy_models()` ไม่ต้องลบเอง

---

## 2. วิธีที่เกมรู้จัก "พาร์ตหนึ่งชิ้น" — ไฟล์ ArmorPart

ทุกพาร์ตถูกนิยามด้วยไฟล์ Resource ชนิด `ArmorPart`
(`resources/mech/armor_part.gd`) ซึ่งมี field ต่อไปนี้:

| field | ความหมาย |
|-------|-----------|
| `part_name` | ชื่อพาร์ต |
| `slot_id` | ช่อง slot (`arm_left`, `body`, ...) |
| `mesh_scene` | `PackedScene` ของเกราะชั้นนอก |
| `inner_frame_scene` | `PackedScene` ของโครง/ชั้นใน |
| `max_hp` / `max_frame_hp` | HP ของเกราะ / โครง |
| `weight` | น้ำหนัก |
| `armor_class` | ค่าป้องกัน |
| `break_threshold` | สัดส่วน HP ที่พาร์ตจะแตก |
| `part_color` | สีที่ใช้แทน (ตอนยังไม่มี mesh) |
| `icon` | ไอคอนใน UI |

ตัวอย่าง `resources/mech/parts/arm_left/arm_left_001.tres`:

```text
[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://resources/mech/armor_part.gd" id="1"]

[resource]
script = ExtResource("1")
part_name = "Barbatos Left Shoulder Guard"
slot_id = "arm_left"
max_hp = 25.0
max_frame_hp = 25.0
weight = 6.0
armor_class = 15.0
break_threshold = 0.3
part_color = Color(0.9, 0.9, 0.95, 1)
```

---

## 3. โฟลเดอร์รับ assets — วางไฟล์ตรงนี้

```
scenes/mecha/parts/
  ├── head/          ← .glb เกราะหัว
  ├── body/          ← .glb เกราะลำตัว
  ├── arm_left/      ← .glb เกราะแขนซ้าย
  ├── arm_right/     ← .glb เกราะแขนขวา
  ├── leg_left/      ← .glb เกราะขาซ้าย
  └── leg_right/     ← .glb เกราะขาขวา
scenes/mecha/animations/   ← .glb ไฟล์แอนิเมชัน (ถ้าต้องการ)
resources/mech/parts/{slot}/{id}.tres   ← ArmorPart ผูก mesh (แก้ตรงนี้)
```

---

## 4. ขั้นตอนเพิ่มพาร์ตใหม่ (ทำตามลำดับ)

### 4.1 เตรียมโมเดล (Blender / Maya / ฯลฯ)

แนะนำ export เป็น **glTF 2.0 (.glb)**:

- หน่วยเป็น **เมตร** และหันหน้าไปทาง **-Z** (ทิศที่ Godot ใช้เป็นหน้า)
- **Orientation** ตั้ง `Forward: -Z, Up: +Y`
- **Scale**: ใช้สเกล 1:1 กับขนาดเกม (ความสูงตัวเต็ม ~2.4–2.6 ม. ในสเกลของ mecha)
- แยกท่อนบน/ท่อนล่างให้ pivot อยู่ที่ข้อต่อ (ต้นแขน pivot ที่ไหล่, ท่อนปลาย pivot ที่ศอก ฯลฯ)
- ถ้าเป็นเกราะชั้นเดียว (ไม่แยกโครง) ให้ระบุแค่ `mesh_scene` ก็พอ ส่วน `inner_frame_scene`
  จะยังใช้ตัวสร้าง procedural อัตโนมัติแทน

### 4.2 วางไฟล์ + import

1. นำ `.glb` ไปวางในโฟลเดอร์ตาม slot (ข้อ 3)
2. รัน import ให้ Godot รู้จัก:
   ```
   Godot_v4.6.2-stable_win64_console.exe --headless --import --path .
   ```
3. เปิด Godot Editor → ตรวจที่ `FileSystem` ว่า `.glb` ถูก import เป็น `PackedScene` แล้ว

### 4.3 ผูก ArmorPart

เปิดไฟล์ `resources/mech/parts/{slot}/{id}.tres` ของพาร์ตนั้น (เช่น `body_001.tres`)
แล้วตั้ง:

```text
mesh_scene = ExtResource("...")        # ลาก .glb เกราะมาใส่
inner_frame_scene = ExtResource("...") # (optional) ลาก .glb โครงมาใส่
```

หรือถ้าจะสร้างพาร์ตใหม่ทั้งตัว: ก็อป `.tres` เดิมมาเปลี่ยนชื่อไฟล์ + แก้ `part_name`,
`slot_id`, ตั้งค่าสถิติ แล้วตั้ง `mesh_scene`

> เกม resolve path ของ `.tres` เองตาม convention
> `res://resources/mech/parts/{slot}/{id}.tres` (ฟังก์ชัน `_convention_part_path`
> ใน `part_mesh_manager.gd`) — แค่ drop ไฟล์ `.tres` ลงโฟลเดอร์ + มี id อยู่ใน catalog
> ก็ render ได้ทันที โดยไม่ต้องแก้โค้ด

### 4.4 (ถ้ามี) เพิ่ม id ใหม่ใน catalog

Catalog อยู่ที่ `resources/data/mech_catalogs.tres` → `armor_catalog[slot]` เป็น list
ของ entry ที่มี `id`, `name`, `path`, `hp`, `armor`, `weight`, `color`, `type`

- `path` ต้องชี้ไปไฟล์ `.tres` ที่สร้างในข้อ 4.3
- ถ้าไม่ระบุ `path` ระบบจะ fallback หา `.tres` ตาม convention อัตโนมัติ

---

## 5. แอนิเมชันจากภายนอก (skinned parts)

ปัจจุบันเกมใช้แอนิเมชัน procedural (หมุน pivot โหนดตามโค้ด) เป็นค่าเริ่มต้นอยู่แล้ว
สามารถสลับไปใช้แอนิเมชันจากไฟล์ (Blender/Mixamo) ได้โดยไม่ต้องแตะเกมเพลย์

### 5.1 ตั้งสเกเลตันให้ตรงกับ convention

ระบบใช้ `Skeleton3D` โหนดชื่อ `Rig` ใน `mecha_base.tscn` ขับทุกพาร์ตพร้อมกัน
ดังนั้นทุกพาร์ตที่ทำ skin animation **ต้อง rig เข้ากับชื่อกระดูกเดียวกัน**
(ดู `scripts/mecha/mecha_rig.gd`):

```
Bone_Head        Bone_Neck
Bone_Torso       Bone_Hip
Bone_UpperArm_L  Bone_UpperArm_R
Bone_LowerArm_L  Bone_LowerArm_R
Bone_Hand_L      Bone_Hand_R
Bone_Thigh_L     Bone_Thigh_R
Bone_Shin_L      Bone_Shin_R
Bone_Foot_L      Bone_Foot_R
```

### 5.2 ใส่คลิปแอนิเมชัน

วางไฟล์ `.glb` ที่ฝังคลิปไว้ใน `scenes/mecha/animations/` Godot import คลิป
เข้าสู่ `AnimationPlayer` อัตโนมัติ ต้องตั้งชื่อคลิปให้ตรงกับรายการนี้:

```
idle, run, jump_launch, jump_fall, land, kneel,
core_breach, shield_raise, roller_dash, recoil
```

### 5.3 เปิดใช้งาน

ใน `mecha_base.tscn` โหนด `AnimationSystem` มี export ชื่อ
`use_clip_animation` (`scripts/mecha/mecha_animation.gd`):

- ตั้งเป็น `true` → เล่นจากคลิป
- ถ้ายังไม่มีคลิปใน `AnimationPlayer` ระบบจะ fallback กลับไป procedural อัตโนมัติ
  (ปลอดภัยที่จะเปิดทิ้งไว้ก่อน)

---

## 6. Checklist ส่งงาน

- [ ] `.glb` อยู่ในโฟลเดอร์ slot ที่ถูก (`scenes/mecha/parts/{slot}/`)
- [ ] `.tres` มี `mesh_scene` ชี้ไป `.glb` (หรือไม่มี mesh = ใช้ procedural แทน)
- [ ] (ถ้าใหม่) catalog มี entry ชี้ `path` ไป `.tres`
- [ ] รัน import แล้ว (`--headless --import --path .`)
- [ ] รันเทสที่เกี่ยวข้อง:
  - `tests/mecha_kneel_verify.tscn`
  - `tests/hangar_panels_verify.tscn`
  - `tests/enemy_shield_verify.tscn`
  - `tests/ally_loadout_verify.tscn`
- [ ] commit + push (ตาม AGENTS.md)

---

## 7. ไฟล์/โค้ดที่เกี่ยวข้อง

| ไฟล์ | หน้าที่ |
|------|---------|
| `resources/mech/armor_part.gd` | class `ArmorPart` (field ทั้งหมดของพาร์ต) |
| `resources/mech/parts/{slot}/{id}.tres` | พาร์ตทีละ id — แก้ตรงนี้เพื่อผูก mesh |
| `resources/data/mech_catalogs.tres` | catalog ของเกราะในเกม |
| `scripts/mecha/part_mesh_manager.gd` | ประกอบพาร์ต + resolve `.tres` ตาม convention |
| `scripts/mecha/mecha_rig.gd` | convention ชื่อกระดูก + ชื่อคลิป + โฟลเดอร์ assets |
| `scripts/mecha/mecha_animation.gd` | procedural ปัจจุบัน + ตัวเปิดคลิป `use_clip_animation` |
| `scenes/mecha/mecha_base.tscn` | โครงโหนด (`Head/Body/Arm*/Leg*`, `Rig`, `AnimationPlayer`) |
| `scenes/mecha/parts/`, `scenes/mecha/animations/` | โฟลเดอร์วาง `.glb` |