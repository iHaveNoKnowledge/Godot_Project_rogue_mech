---
name: godot-game-dev
description: Clean Code, Architecture, and Mechanics rules for Rogue-Mech in Godot Engine (GDScript)
---

# Rogue-Mech Development Guidelines

## 1. General Architecture & GDScript Standards
- **Single Responsibility:** 1 Script ต่อ 1 Node/Functionality ห้ามใส่ Player Control, UI และ Combat Logic รวมกัน
- **Composition over Inheritance:** ใช้ Node/Custom Resource ในการแบ่งฟังก์ชัน (เช่น HealthComponent, HitboxComponent, EquipmentManager)
- **Signal-Up, Call-Down:** Node แม่เรียก Function Node ลูกได้โดยตรง แต่ Node ลูกต้องส่งข้อมูลหา Node แม่ผ่าน Signal เท่านั้น ห้ามใช้ `get_parent().get_parent()`
- **Explicit Type Hinting:** ระบุประเภทตัวแปรและ Return type เสมอ เช่น `var hp: float = 100.0`, `func take_damage(amount: float) -> void:`
- **State Machine Pattern:** ใช้ Enum หรือ Node-based State Machine สำหรับจัดการสถานะตัวละคร/หุ่นยนต์ ห้ามใช้ `if/else` ซ้อนกันยาวๆ ใน `_process()`

## 2. Equipment & Attribute System
- **Resource-based Stats:** ใช้ `Resource` (`.tres`) สำหรับข้อมูล Item, Equipment และ Base Stats ห้าม Hardcode ค่าลงใน GDScript
- **Attribute Modifier Pattern:** คำนวณ Stat Dynamic ด้วยสูตร:
  `Final Stat = (Base + Flat Modifiers) * (1 + Percent Modifiers)`
- **Equipment Manager:** แยก `EquipmentManager` ออกมาเพื่อจัดการสวมใส่/ถอด โดยส่ง Signal `equipment_changed` ไปให้ UI และ Stat recalculate ทำงานแยกกัน

## 3. Rogue-Mech Core Mechanics (6-Part Body & Combat)
- **Modular Mech Part Structure:**
  - หุ่นทุกตัวต้องประกอบด้วย 6 ชิ้นส่วน: `Head`, `Torso`, `LeftArm`, `RightArm`, `LeftLeg`, `RightLeg`
  - ทุก Part เป็น Custom Resource มี `max_hp`, `current_hp`, `armor`, และ `durability`
  - เมื่อ `current_hp` ของ Part ใดเป็น 0 ให้ส่ง Signal `part_destroyed(part_type)` เพื่อสั่ง Disable อาวุธ/การเคลื่อนไหวของชิ้นส่วนนั้นทันที
- **Tactical Damage Resolution:**
  - คำนวณ Hit Location ตาม Random Weight หรือ Target Specific Part
  - Damage ที่เกินจากชิ้นส่วนที่พังแล้ว (Overkill Damage) ให้ Bleed Over เข้าสู่ `Torso` หลัก
- **Repair & Scrap Management:**
  - รองรับการสลับ Part, การดรอป Scrap จากซากศัตรู และการซ่อมบำรุงใน Garage Phase

## 4. Era & Timeline Progression System
- **Era-Driven Data Pools:**
  - ใช้ `EraResource` เก็บค่า `era_id`, `available_part_pool`, `event_pool`, และ `enemy_pool`
  - ระบบสุ่มดรอปชิ้นส่วนและสุ่ม Event ต้องกรองผ่าน `CurrentEra` เสมอ
- **Cross-Era Compatibility:**
  - ชิ้นส่วนทุกชิ้นต้องระบุ `era_tier`
  - หากใส่ Part ข้ามยุคสมัย ให้คำนวณ `CompatibilityModifier` (เช่น เพิ่ม Energy Drain หรือเพิ่ม Bonus Stat แบบ Relic)
- **Global Era Manager:**
  - ใช้ `EraManager` ควบคุมการเปลี่ยนยุคตาม Progress และส่ง Signal `era_changed(new_era)` เพื่อเปลี่ยน Theme, BGM และ Pool ไอเทมทันที

## 5. Rogue-like Event System
- **Data-driven Text Encounters:** เก็บข้อความ ตัวเลือก เงื่อนไข และผลลัพธ์ของเหตุการณ์สุ่มไว้ใน `EventResource`