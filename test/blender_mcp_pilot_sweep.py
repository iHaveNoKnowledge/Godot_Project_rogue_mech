"""Empirical sweep: which rotation interpretation of the cached quats
reproduces a sane standing pose (idle f0)?

Ground truths we trust:
 - REST pose is a clean standing A-pose (upright, feet on floor).
 - pistol_idle frame 0 should be CLOSE to a standing pose.
Metrics per candidate: mesh Y-span, Z range (feet ~0), hand_r world dir,
mean/max arm-space rotation deviation vs rest.

Usage: python test/blender_mcp_pilot_sweep.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

OB = bpy.data.objects
scn = bpy.context.scene
AF = OB['AF_Rig']
rig = OB['Pilot_Character']
mesh = OB['Pilot_SWAT']
CACHE = "C:/Users/hackd/AppData/Local/Temp/pilot_src_cache.json"
cache = json.load(open(CACHE))
src = 'pistol_idle'
frames = cache[src]['frames']
bones = cache[src]['bones']
fi = 0

def set_pos(r, mode):
    r.data.pose_position = mode
    bpy.context.view_layer.update()

def build_K(r):
    K = {}
    for b in r.data.bones:
        own = b.matrix_local.copy()
        K[b.name] = r.data.bones[b.parent.name].matrix_local.inverted() @ own if b.parent else own
    return K

def order_of(r):
    depth = {}
    def walk(b, d):
        depth[b.name] = d
        for c in b.children:
            walk(c, d + 1)
    for b in r.data.bones:
        if b.parent is None:
            walk(b, 0)
    return sorted(depth.keys(), key=lambda n: depth[n])

set_pos(rig, 'REST')
K = build_K(rig)
REST_ARM = {b.name: b.matrix_local.copy() for b in rig.data.bones}
REST_R = {k: m.to_3x3().copy() for k, m in REST_ARM.items()}
ORDER = order_of(rig)
set_pos(rig, 'POSE')
set_pos(AF, 'REST')
K_AF = build_K(AF)
ORDER_AF = order_of(AF)
set_pos(AF, 'POSE')

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs), min(v.z for v in vs), max(v.z for v in vs))

# cached B matrices (bone-local values as stored)
B_val = {}
for bn, jd in bones.items():
    if jd['rq']:
        q = jd['rq'][fi]
        t = Vector(jd['loc'][fi]) if jd['loc'] else Vector((0, 0, 0))
        B_val[bn] = Matrix.Translation(t) @ Quaternion([q[0], q[1], q[2], q[3]]).to_matrix().to_4x4()

# A_af chain reconstruction (v7)
A_af = {}
for bn in ORDER_AF:
    B = B_val.get(bn, Matrix.Identity(4))
    par = AF.data.bones[bn].parent
    L = K_AF[bn] @ B
    A_af[bn] = A_af[par.name] @ L if par else L

def apply_candidate(name, R_arm):
    """Set arm-space rotations R_arm (dict bn->3x3), rest-conjugated positions."""
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    R_t = {}; p_t = {}; A_t = {}
    for bn in ORDER:
        par = rig.data.bones[bn].parent
        R = R_arm.get(bn, REST_R[bn])
        R_t[bn] = R
        if par is None:
            p = REST_ARM[bn].translation.copy()
        else:
            dR = R_t[par.name] @ REST_R[par.name].inverted()
            p = p_t[par.name] + dR @ (REST_ARM[bn].translation - REST_ARM[par.name].translation)
        p_t[bn] = p
        A_t[bn] = Matrix.Translation(p) @ R.to_4x4()
        L = A_t[par.name].inverted() @ A_t[bn] if par else A_t[bn]
        rig.pose.bones[bn].matrix_basis = K[bn].inverted() @ L
    bpy.context.view_layer.update()
    b = bbox(mesh)
    hw = rig.pose.bones['hand_r'].matrix @ rig.matrix_world
    hd = (hw.to_3x3() @ Vector((0, 1, 0))).normalized()
    devs = []
    for bn, R in R_arm.items():
        devs.append(math.degrees(R.to_quaternion().rotation_difference(REST_R[bn].to_quaternion()).angle))
    dm = ('dev mean %5.1f max %6.1f' % (sum(devs)/len(devs), max(devs))) if devs else 'dev -'
    print('%-22s Yspan %.3f Z %6.2f..%.2f | hand=[%.2f,%.2f,%.2f] | %s'
          % (name, b[1]-b[0], b[2], b[3], hd.x, hd.y, hd.z, dm))

R_afrest = {}
set_pos(AF, 'REST')
R_afrest = {b.name: b.matrix_local.to_3x3().copy() for b in AF.data.bones}
set_pos(AF, 'POSE')

apply_candidate('A: bone-local (ctrl)', {bn: B.to_3x3() for bn, B in B_val.items()})
apply_candidate('B: raw-as-arm (v5)', {bn: B.to_3x3() for bn, B in B_val.items()} if False else {bn: B_val[bn].to_3x3() for bn in B_val})
apply_candidate('C: Rrest_af @ B', {bn: R_afrest[bn] @ B_val[bn].to_3x3() for bn in B_val if bn in R_afrest})
apply_candidate('D: B @ Rrest_af', {bn: B_val[bn].to_3x3() @ R_afrest[bn] for bn in B_val if bn in R_afrest})
apply_candidate('E: chain A_af (v7)', {bn: A_af[bn].to_3x3() for bn in B_val if bn in A_af})
apply_candidate('F: Rrest_pc @ B', {bn: REST_R[bn] @ B_val[bn].to_3x3() for bn in B_val if bn in REST_R})
apply_candidate('G: B @ Rrest_pc', {bn: B_val[bn].to_3x3() @ REST_R[bn] for bn in B_val if bn in REST_R})
apply_candidate('H: identity (rest)', {})
'''

if __name__ == "__main__":
    print(send_code(CODE))
