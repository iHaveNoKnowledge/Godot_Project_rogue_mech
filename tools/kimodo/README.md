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

## การเจนจริงด้วย Kimodo Gen (G1 robot)

สภาพแวดล้อม (อยู่นอก repo นี้): venv ที่
`%TEMP%/opencode/kimodo-venv` (torch CUDA 2.14+cu126),
ซอร์ส clone ที่ `%TEMP%/opencode/kimodo`,
ติดตั้งด้วย `SKIP_MOTION_CORRECTION_IN_SETUP=1`
(G1 ไม่ใช้ postprocess). ต้องมี HF token ที่มีสิทธิ์ gated model
`meta-llama/Meta-Llama-3-8B-Instruct` (text encoder) และการ์ด
VRAM <17GB ต้อง `TEXT_ENCODER_DEVICE=cpu`

```bash
TEXT_ENCODER_DEVICE=cpu kimodo_gen --model Kimodo-G1-RP-v1 \
  --duration 4.0 --seed 42 --output kimodo_mech_run4 \
  "a massive humanoid combat robot running forward continuously ..."
# -> kimodo_mech_run4.npz (Kimodo NPZ, J=34) + .csv (MuJoCo qpos)
```

บทเรียนจากการเจนจริง (seed 21/42):
- Kimodo สร้างแบบ run-then-settle (วิ่ง ~200f แล้วหยุดเอง) → ครอป
  เฉพาะช่วง steady (`--crop "128:170"`, L-contact ถึง L-contact 2 รอบ)
  แล้ว `--loop-blend 6` ให้หัว/ท้ายต่อกัน (test ตรวจ diff = 0)
- ทิศ forward ใช้ **root travel** (xz) อย่าใช้ heading channel
  (G1 heading ชี้ +X ขณะที่ root วิ่ง +Z)
- G1 ไม่มีคอ/หัว → `--shoulder-mid-torso` วัด torso จาก
  pelvis ถึงกึ่งกลางไหล่
- G1 มักถือแขนข้างหนึ่งไว้ข้างหลัง → `--symmetrize-arms`
  เฉลี่ยแบบ zero-mean ให้ pump สมมาตร (แขนยังแยก track พร้อม
  ถูกแทนด้วย weapon layer)
- G1 วิ่งตัวค่อนข้างตรง → `--lean-bias -28` ให้หมอบพุ่งแบบ Valkren
  (net ≈ -19..-12, อยู่ใน clamp [-30,10] ที่อิง MechaClipRetarget)
- ลิมิตขา/เข่าเปิดกว้างตาม baked-clip precedent
  (ขา [-60,75], เข่า [-90,0]) เพื่อรับ high-knee ของ Kimodo

ตัวอย่าง canonical: `samples/kimodo_g1_run_crop.npz` (41f)
→ `samples/valkren_kimodo_run.json` (42f loop, FK เท้า ≥ 0.53m)
พิสูจน์บน Rig จริงใน Blender แล้ว (action `kimodo_run_final`
+ NLA แยกชั้น `kimodo_run_lower`/`weapon_hold_demo`:
ขาเท่ากันเป๊ะทั้งเปิด/ปิด weapon layer = separable จริง)

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
