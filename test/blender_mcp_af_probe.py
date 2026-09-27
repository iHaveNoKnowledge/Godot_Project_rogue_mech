"""Sanity probe for the ActionForge source data (af_all.json).

Reconstructs the source armature-space pose at frame 0 of pistol_idle_loop
by chain recursion over the dumped rest hierarchy (A = A(parent) @ localTR),
applies those arm-space rotations to Pilot_Character's bones (positions
chained from rest offsets), and prints the resulting mesh bbox, hand
direction and feet height. If the authored motion is intact, the pilot
should stand upright with feet on the floor and hands forward - unlike
every reinterpretation of the old baked data.

Usage: python test/blender_mcp_af_probe.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

OB = bpy.data.objects
scn = bpy.context.scene
DATA = json.load(open("C:/Users/hackd/AppData/Local/Temp/af_all.json"))
entry = None
for k, v in DATA.items():
    if "pistol_idle_loop" in v["clips"]:
        entry = v
        break
rest = entry["rest"]
clip = entry["clips"]["pistol_idle_loop"]
bones = clip["bones"]

rig = OB["Pilot_Character"]
mesh = OB["Pilot_SWAT"]

def set_pos(r, mode):
    r.data.pose_position = mode
    bpy.context.view_layer.update()

def build_local(r):
    # bone-local rest TR from Blender (matrix_local relative to parent)
    m = {}
    for b in r.data.bones:
        m[b.name] = b.matrix_local.copy()
    return m

set_pos(rig, "REST")
LOCAL = build_local(rig)
REST_R = {n: m.to_3x3().copy() for n, m in LOCAL.items()}
REST_T = {n: m.translation.copy() for n, m in LOCAL.items()}
ORDER = {}
depth = {}
def walk(b, d):
    depth[b.name] = d
    for c in b.children:
        walk(c, d + 1)
for b in rig.data.bones:
    if b.parent is None:
        walk(b, 0)
ORDER = sorted(depth.keys(), key=lambda n: depth[n])
set_pos(rig, "POSE")

# order by source hierarchy depth
src_depth = {}
def sdepth(n, d):
    src_depth[n] = d
    p = rest.get(n, {}).get("parent")
    if p:
        sdepth(p, d + 1)
for n in rest:
    if rest[n].get("parent") is None:
        sdepth(n, 0)
for n in rest:
    if n not in src_depth:
        sdepth(n, 0)
src_order = sorted(rest.keys(), key=lambda n: src_depth.get(n, 99))

def sample(bd, key_t, key_v, fi):
    if not bd[key_v]:
        return None
    return bd[key_v][fi]

# 1) reconstruct SOURCE armature-space pose (chain recursion over rest TR)
A_src = {}
for n in src_order:
    r = rest[n]
    t = Vector(r["t"])
    q = Quaternion(r["q"])
    L = Matrix.Translation(t) @ q.to_matrix().to_4x4()
    p = r.get("parent")
    A_src[n] = (A_src[p] @ L) if (p and p in A_src) else L  # tolerate chain gaps (leaf joints)

# 2) apply to rig: rotation := A_src rotation; position chain via rest offsets
R_src = {n: A_src[n].to_3x3() for n in A_src}
R_t = {}
p_t = {}
A_t = {}
applied = 0
for bn in ORDER:
    par = rig.data.bones[bn].parent
    R = R_src.get(bn, REST_R[bn])
    R_t[bn] = R
    if par is None:
        p = REST_T[bn].copy()
    else:
        pn = par.name
        dR = R_t[pn] @ REST_R[pn].inverted()
        p = p_t[pn] + dR @ (REST_T[bn] - REST_T[pn])
    p_t[bn] = p
    A_t[bn] = Matrix.Translation(p) @ R.to_4x4()
K = {}
for b in rig.data.bones:
    own = b.matrix_local.copy()
    K[b.name] = rig.data.bones[b.parent.name].matrix_local.inverted() @ own if b.parent else own
for bn in ORDER:
    par = rig.data.bones[bn].parent
    L = A_t[par.name].inverted() @ A_t[bn] if par else A_t[bn]
    rig.pose.bones[bn].matrix_basis = K[bn].inverted() @ L
    if bn in R_src:
        applied += 1
bpy.context.view_layer.update()

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

b = bbox(mesh)
hw = rig.pose.bones["hand_r"].matrix @ rig.matrix_world
hd = (hw.to_3x3() @ Vector((0, 1, 0))).normalized()
fy = min((rig.pose.bones[fb].matrix @ rig.matrix_world).translation.z for fb in ("foot_l", "foot_r") if fb in rig.pose.bones)
print("applied %d/%d source rotations" % (applied, len(R_src)))
print("bbox Y %.3f..%.3f (span %.3f) | Z %.3f..%.3f" % (b[0], b[1], b[1]-b[0], b[2], b[3]))
print("hand_r dir = [%.2f, %.2f, %.2f] | lowest foot z = %.3f" % (hd.x, hd.y, hd.z, fy))
print("VERDICT:", "AUTHORED MOTION INTACT" if (b[2] > -0.06 and abs(hd.y) > 0.7 and b[1]-b[0] < 1.3) else "STILL BROKEN")
# restore rest
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
'''

if __name__ == "__main__":
    print(send_code(CODE))
