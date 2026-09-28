# Kimodo Bridge — NVIDIA Kimodo motion diffusion → Valkren mech (Godot 4.6.2)

`kimodo-motion-diffusion` (nv-tlabs/kimodo) เจนท่า human/humanoid จาก text +
kinematic constraints แล้ว bridge นี้ transfer มาใช้กับหุ่น Valkren
(MechaBase Node3D rig สูง ~5.5m — ไม่ใช่ humanoid skeleton)

> โค้ด Kimodo ต้นทาง: Apache-2.0 / โมเดล RP-SEED: NVIDIA Open Model License /
> โมเดล SMPLX-RP-v1: NVIDIA R&D (ห้ามใช้ commercial)

## ทำไมไม่ clone โมเดลมาทั้งก้อนใน repo นี้

- โมเดล + mocap หนักหลาย GB, VRAM default ~17GB (text encoder)
- เครื่อง dev หลัก (RTX 4070 Ti 12GB) ต้องรันแบบ `TEXT_ENCODER_DEVICE=cpu` → VRAM <3GB
- repo ต้นทางพัฒนาบน Linux, Windows แนะนำผ่าน Docker

bridge นี้เลยเก็บแค่ **ตัว transfer + mock + policy** ส่วนการเจนจริงรันแยกข้างนอก

## โครงไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `kimodo_npz_format.py` | นิยาม + validate ฟอร์แมต NPZ ของ Kimodo (ไม่อ่านโมเดล) |
| `kimodo_mock.py` | สร้าง NPZ ปลอม (`--mode walk/run`) สำหรับ CI โดยไม่ต้องมี GPU |
| `kimodo_npz_to_valkren.py` | transfer NPZ → Valkren JSON (euler deg + FK ตรวจเท้า) |
| `kimodo_generate.py` | wrapper เรียก `kimodo_gen` / Docker (dry-run ได้โดยไม่ต้องติดตั้ง) |
| `samples/valkren_walk.json` | fixture ท่าเดิน (60 เฟรม) ใช้ใน unit test |
| `samples/valkren_run.json` | fixture ท่าวิ่ง (48 เฟรม) ใช้ใน unit test |

## หลักการ transfer (อ่านก่อนแก้)

Valkren ขับด้วย euler บน Node3D (`MechaWalkingSystem`):
ขา rotation.x + = สวิงหน้า / เข่า - = งอ / ศอก + = piston /
ตัว -X = หมอบพุ่ง ช่วงลิมิตดู `LIMITS` ในตัว transfer

- mocap แขน/ขา/ลำตัวขยับถูกสัมพัทธ์กันอยู่แล้ว → วัดมุม segment
  จาก `posed_joints` แล้ว map **ตรงๆ** ห้ามกลับเครื่องหมายซ้ำ
  (ตัวคูณ counter-swing ใน `MechaWalkingSystem` มีไว้เพราะ procedural
  เอาขาไปขับแขน ไม่เกี่ยวกับงานนี้)
- มุมไม่สนสเกล ส่วน translation คูณ `BOB_SCALE=3.0` (สะโพก Valkren
  3.0m vs คน 0.9m) + `lean_bias` -12° (ท่าหมอบพุ่งที่ mocap ไม่มี)
- JSON เก็บ euler องศา (ไม่ใช่ quaternion — เคยบั๊กสลับลำดับ
  `x,y,z,w` มาแล้ว) แกน y/z ≈ 0 จึงไม่ติดปัญหา euler order
- FK 2 ข้อ (hip 3.001 / shin 1.34 / foot 1.291 จาก `mecha_base.tscn`)
  ปัดคลิปที่เท้าจมใต้ rest − 0.10m ทิ้งตั้งแต่ตอนแปลง

## การเจนจริง (แยกข้างนอก repo)

```bash
# ทางที่แนะนำ: Docker (Windows)
docker compose -f <kimodo-checkout>/docker-compose.yaml up
docker exec -it kimodo kimodo_gen "a person running" --duration 4

# การ์ด VRAM < 17GB (เช่น 4070 Ti 12GB):
TEXT_ENCODER_DEVICE=cpu kimodo_gen "a person running" --duration 4

# โมเดลที่แนะนำ: Kimodo-SOMA-RP-v1.1 (SOMA 77-joint, Bones Rigplay 700 ชม.)
# NPZ จริงต้องส่ง --map-json ระบุ index ของ 12 roles
# (pelvis, neck, upperarm_l/r, lowerarm_l/r, thigh_l/r, calf_l/r, foot_l/r)
```

## แปลงมาใช้กับ Valkren

```bash
# 1. สร้าง mock (ไม่ต้องมีโมเดล/GPU)
python tools/kimodo/kimodo_mock.py --mode walk --out tools/kimodo/samples/kimodo_mock.npz
python tools/kimodo/kimodo_mock.py --mode run --out tools/kimodo/samples/kimodo_mock_run.npz

# 2. แปลง NPZ -> Valkren JSON
python tools/kimodo/kimodo_npz_to_valkren.py \
  --npz tools/kimodo/samples/kimodo_mock_run.npz \
  --clip valkren_run --out tools/kimodo/samples/valkren_run.json

# 3. ตรวจ			
python tools/kimodo/kimodo_npz_to_valkren.py --validate-only \
  --json tools/kimodo/samples/valkren_run.json
```

## Godot policy

`res://scripts/systems/kimodo_valkren_policy.gd`:
`KimodoValkrenPolicy.validate_clip_dict()` ตรวจ JSON (12 joints ครบ,
ทุกแกนในลิมิต mech, finite, FK เท้าไม่จม) ก่อนเอาเข้า AnimationPlayer
หรือ driver แบบ procedural
