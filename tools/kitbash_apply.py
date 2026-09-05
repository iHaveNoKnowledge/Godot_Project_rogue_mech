"""Hard-surface post + kitbash greeble attach. Headless Blender:
  blender --background --python tools/kitbash_apply.py -- <target.glb> <out.glb> [seed] [count]
Steps: limited-dissolve planarize -> edge-split crisp -> weighted normal ->
       scatter kit greebles on outward flat-ish faces -> export.
"""
import bpy, os, sys, math, random
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
SEED = int(argv[2]) if len(argv) > 2 else 7
COUNT = int(argv[3]) if len(argv) > 3 else 14
random.seed(SEED)
np.random.seed(SEED)

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KITDIR = os.path.join(PROJ, "assets", "kitbash")
KITS = ["kit_vent.glb", "kit_bolt.glb", "kit_bolt.glb", "kit_hinge.glb",
        "kit_intake.glb", "kit_handle.glb", "kit_bolt.glb", "kit_vent.glb"]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
target = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
bpy.context.view_layer.objects.active = target

# 0. soup cleanup: weld duplicates, drop nested inner shells + speckles
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.remove_doubles(threshold=0.0008)
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.normals_make_consistent(inside=False)
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
MARGIN, SPECK = 0.001, 25
sname = target.name
parts = [x for x in bpy.context.scene.objects
         if x.type == 'MESH' and (x.name == sname or x.name.startswith(sname + "."))]
info = []
for p in parts:
    ws = np.array([target.matrix_world @ v.co for v in p.data.vertices])
    info.append({"o": p, "np": len(p.data.polygons), "lo": ws.min(axis=0), "hi": ws.max(axis=0)})
info.sort(key=lambda d: -d["np"])
keep, boxes, dn, ds = [], [], 0, 0
for d in info:
    if d["np"] < SPECK:
        ds += d["np"]
        bpy.data.objects.remove(d["o"], do_unlink=True)
        continue
    if any(bool(np.all(d["lo"] >= klo - MARGIN) and np.all(d["hi"] <= khi + MARGIN)) for klo, khi in boxes):
        dn += d["np"]
        bpy.data.objects.remove(d["o"], do_unlink=True)
    else:
        keep.append(d)
        boxes.append((d["lo"], d["hi"]))
bpy.ops.object.select_all(action='DESELECT')
for d in keep:
    d["o"].select_set(True)
bpy.context.view_layer.objects.active = keep[0]["o"]
if len(keep) > 1:
    bpy.ops.object.join()
target = bpy.context.view_layer.objects.active
print(f"CLEANUP kept {len(keep)} islands, dropped nested={dn} speck={ds} -> {len(target.data.polygons)} polys")
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
bpy.context.view_layer.objects.active = target

# 1. planarize soup curves into armor panels (keeps UVs)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.dissolve_limited(angle_limit=math.radians(4.0), use_dissolve_boundaries=False,
                              delimit={'NORMAL'})
bpy.ops.object.mode_set(mode='OBJECT')
print(f"DISSOLVE -> {len(target.data.polygons)} polys")

# 2. crisp hard-surface edges (angle-based split, no manual sharp flags needed)
bpy.ops.object.mode_set(mode='OBJECT')
for p in target.data.polygons:
    p.use_smooth = True
es = target.modifiers.new("es", 'EDGE_SPLIT')
es.split_angle = math.radians(35.0)
es.use_edge_sharp = True
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.object.modifier_apply(modifier=es.name)
wn = target.modifiers.new("wn", 'WEIGHTED_NORMAL')
wn.weight = 50
bpy.ops.object.modifier_apply(modifier=wn.name)

# 3. candidate faces: outward + mid-size panels
me = target.data
n = len(me.polygons)
vco = np.empty(len(me.vertices) * 3, dtype=np.float64)
me.vertices.foreach_get("co", vco)
V = vco.reshape(-1, 3)
center = V.mean(axis=0)
fn = np.empty(n * 3, dtype=np.float64)
me.polygons.foreach_get("normal", fn)
FN = fn.reshape(-1, 3)
fc = np.array([target.matrix_world @ p.center for p in me.polygons])
area = np.empty(n, dtype=np.float64)
me.polygons.foreach_get("area", area)
outward = ((fc - center) * FN).sum(axis=1) > 0
ok = outward & (area > 0.0008) & (area < 0.05)
cands = np.where(ok)[0]
print(f"CANDIDATE faces: {len(cands)}/{n}")
random.shuffle(cands)
picked = cands[:COUNT].tolist() if len(cands) else []

# 4. attach kit pieces
from mathutils import Vector, Quaternion
placed = []
for i, fi in enumerate(picked):
    kit = KITS[i % len(KITS)]
    bpy.ops.import_scene.gltf(filepath=os.path.join(KITDIR, kit))
    parts = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.select_get()]
    g = parts[0]
    for o in parts[1:]:
        bpy.data.objects.remove(o, do_unlink=True)
    c, nrm = fc[fi], FN[fi] / (np.linalg.norm(FN[fi]) + 1e-12)
    g.location = Vector(c) + Vector(nrm) * -0.004  # embed 4mm
    q = Vector((0, 0, 1)).rotation_difference(Vector(nrm))
    g.rotation_euler = (q @ Quaternion((0, 0, 1), random.uniform(0, math.pi * 2))).to_euler()
    s = random.uniform(0.8, 1.4)
    g.scale = (s, s, s)
    placed.append(g.name)
print(f"PLACED {len(placed)}: {placed}")

# 5. join + export
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
for nm in placed:
    bpy.data.objects[nm].select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.object.join()
print(f"JOINED polys={len(target.data.polygons)}")
bpy.ops.object.select_all(action='DESELECT')
target.select_set(True)
bpy.context.view_layer.objects.active = target
bpy.ops.export_scene.gltf(filepath=DST, export_format='GLB', use_selection=True,
                          export_apply=True, export_materials='EXPORT',
                          export_normals=True, export_texcoords=True)
print(f"EXPORT -> {DST} ({os.path.getsize(DST)} bytes)")
