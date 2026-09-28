# Kimodo Bridge — NVIDIA Kimodo motion diffusion → pilot rig (Godot 4.6.2)

`kimodo-motion-diffusion` (nv-tlabs/kimodo) เจนท่า human/humanoid จาก text + kinematic
constraints แล้ว bridge นี้แปลงผลลัพธ์มาใช้กับ pilot kit ของโปรเจกต์นี้

> โค้ด Kimodo ต้นทาง: Apache-2.0 / โมเดล RP-SEED: NVIDIA Open Model License /
> โมเดล SMPLX-RP-v1: NVIDIA R&D (ห้ามใช้ commercial) — อ่าน license ที่ HuggingFace
> ก่อนเจนงานจริง

## ทำไมไม่ clone โมเดลมาทั้งก้อนใน repo นี้

- โมเดล + mocap หนักหลาย GB, VRAM default ~17GB (text encoder)
- เครื่อง dev หลัก (RTX 4070 Ti 12GB) ต้องรันแบบ `TEXT_ENCODER_DEVICE=cpu` → VRAM <3GB
- repo ต้นทางพัฒนาบน Linux, Windows แนะนำผ่าน Docker

bridge นี้เลยเก็บแค่ **ตัวแปลง + mock + policy** ส่วนการเจนจริงรันแยกข้างนอก

## โครงไฟล์

| ไฟล์ | หน้าที่ |
|---|---|
| `kimodo_npz_format.py` | นิยาม + validate ฟอร์แมต NPZ ของ Kimodo (ไม่อ่านโมเดล) |
| `kimodo_mock.py` | สร้าง NPZ ปลอม (walk เคาะเท้า 60 เฟรม) สำหรับ CI โดยไม่ต้องมี GPU |
| `kimodo_npz_to_pilot.py` | แปลง NPZ → pilot retarget JSON ทรงเดียวกับ `af_retarget.json` |
| `kimodo_generate.py` | wrapper เรียก `kimodo_gen` / Docker (dry-run ได้โดยไม่ต้องติดตั้ง) |
| `blender_stage_kimodo.py` | สคริปต์รันใน Blender: stage JSON ลง armature pilot + export GLB (`export_yup=True`) |
| `samples/kimodo_pilot_walk.json` | fixture ตัวอย่าง (สร้างจาก mock) ใช้ใน unit test |

## ฟอร์แมต Kimodo NPZ (ที่รองรับ)

```text
posed_joints      [T, J, 3]     ตำแหน่ง joint ระดับโลก
global_rot_mats   [T, J, 3, 3]  rotation matrix ระดับโลก
local_rot_mats    [T, J, 3, 3]  rotation matrix เทียบ parent
foot_contacts     [T, 4]        [left heel, left toe, right heel, right toes]
smooth_root_pos   [T, 3]        root แบบ smooth (ใช้วาด path)
root_positions    [T, 3]        root จริง (pelvis trajectory)
global_root_heading [T, 2]      heading direction
```

## การเจนจริง (แยกข้างนอก repo)

```bash
# ทางที่แนะนำ: Docker (Windows)
docker compose -f <kimodo-checkout>/docker-compose.yaml up
docker exec -it kimodo kimodo_gen "a person walking stealthily" --duration 5 --num_samples 1

# การ์ด VRAM < 17GB (เช่น 4070 Ti 12GB):
TEXT_ENCODER_DEVICE=cpu kimodo_gen "a person walking, tired" --duration 4

# โมเดลที่แนะนำ: Kimodo-SOMA-RP-v1.1 (SOMA 77-joint, Bones Rigplay 700 ชม.)
```

## แปลงมาใช้กับ pilot

```bash
# 1. สร้าง mock (ไม่ต้องมีโมเดล/GPU)
python tools/kimodo/kimodo_mock.py --out tools/kimodo/samples/kimodo_mock.npz

# 2. แปลง NPZ -> pilot JSON
python tools/kimodo/kimodo_npz_to_pilot.py \
  --npz tools/kimodo/samples/kimodo_mock.npz \
  --clip kimodo_pilot_walk --out tools/kimodo/samples/kimodo_pilot_walk.json

# 3. ตรวจ			
python tools/kimodo/kimodo_npz_to_pilot.py --validate-only \
  --json tools/kimodo/samples/kimodo_pilot_walk.json
```

## Mapping SOMA(77) → pilot kit (19 bones)

pilot kit ใช้กระดูก (ตาม `test/unit/pilot_humanoid_limits_verify.gd`):

```text
pelvis, spine_01, spine_02, neck_01, Head,
clavicle_r/l, upperarm_r/l, lowerarm_r/l, hand_r/l,
thigh_r/l, calf_r/l, foot_r/l
```

mock ใช้ mock joint index 0..18 แมป 1:1 ตามลำดับข้างบน ส่วน NPZ จริงจาก SOMA-77
ให้ override ด้วย `--map-json` (ดูตัวอย่างใน `kimodo_npz_to_pilot.py --help`)
เพราะชื่อ joint ของ SOMA (`somaskel77`) ไม่ตรงกับ pilot ตรงๆ ต้องเลือก
ข้อต่อที่ตรงกัน (pelvis/spine/neck/head/แขน/ขา) แล้วทิ้งนิ้ว/ข้อเสริม

policy การ retarget (ตาม pilot_humanoid_limits):
- pelvis rest ~0.65–1.0m, head ~1.55–2.0m, feet ≥ −0.06m
- ความยาว segment เพี้ยนได้ < 3% (no stretch)
- elbow/knee ห้ามพับจน hinge < 30/40 deg (no inside-out), ทุกค่าต้อง finite

## Blender staging

เปิด Blender → Text Editor → รัน `blender_stage_kimodo.py`:

- คาดหวัง armature ชื่อ `Pilot_Character` (เหมือน `test/blender_mcp_export_kit.py`)
- วางท่าตาม JSON (quaternion bone-local + pelvis delta), key ทุกเฟรม @30fps
- ตรวจ `verify_bounds`/`verify_overlap` ก่อน export (ดู skill blender-assembly)
- export: `bpy.ops.export_scene.gltf(..., export_format="GLB",
  use_selection=True, export_animations=True, export_yup=True)`
- convention: Blender `+Y` forward → Godot `-Z` forward, ห้าม author หน้าหัน `-Y`

## Godot policy

`res://scripts/systems/kimodo_clip_policy.gd`:
`KimodoClipPolicy.validate_clip_dict()` ใช้ตรวจ JSON ที่แปลงแล้ว
(โครงเดียวกับ unit test) ก่อนเอาเข้า AnimationPlayer
