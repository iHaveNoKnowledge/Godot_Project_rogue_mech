"""Numerically test transform candidates for the baked quaternions.

For key bones, take the baked fcurve quaternion at frame 0 and predict the
armature-space up-vector under several reinterpretations (raw, rest-cancelled
left/right, armature-space-as-parent). The candidate that makes the pelvis
upright (~0-15 deg) while keeping the thigh pointing down is the fix.

Usage: python test/blender_mcp_pilot_candidate_test.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Vector, Quaternion

OB = bpy.data.objects
A = OB["Pilot_Character"]
act = A.animation_data.action

def all_fcurves(a):
    out = []
    try:
        out.extend(a.fcurves)
        return out
    except AttributeError:
        pass
    for layer in a.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out

by_path = {}
for fc in all_fcurves(act):
    by_path.setdefault(fc.data_path, {})[fc.array_index] = fc

def baked_quat(bone):
    path = 'pose.bones["%s"].rotation_quaternion' % bone
    rq = by_path.get(path)
    if not rq or len(rq) < 4:
        return None
    return Quaternion([rq[i].evaluate(0) for i in range(4)])

def rest_quat(bone):
    return A.data.bones[bone].matrix_local.to_quaternion()

def up_from_world_rot(q_world_rot):
    up = (q_world_rot.to_matrix() @ Vector((0, 0, 1))).normalized()
    return math.degrees(math.acos(max(-1.0, min(1.0, up.z))))

def dir_from_world_rot(q_world_rot, v):
    return (q_world_rot.to_matrix() @ Vector(v)).normalized()

print("--- candidates for pelvis ---")
qb = baked_quat("pelvis")
qr = rest_quat("pelvis")
arm_q = A.matrix_world.to_quaternion()
cands = {
    "raw baked (as-is)": qb,
    "rest* baked": qr @ qb,
    "baked* rest.inv": qb @ qr.inverted(),
    "arm* baked": arm_q @ qb,
}
for name, q in cands.items():
    if q is None:
        continue
    qw = q if name.startswith("arm") else q
    print("  %-18s up-tilt=%6.1f deg" % (name, up_from_world_rot(qw)))

print("--- candidates for thigh_l (target: direction ~ -Z, i.e. pointing down) ---")
qb = baked_quat("thigh_l")
qr = rest_quat("thigh_l")
print("  rest dir of thigh tail (should be down):",
      [round(c, 3) for c in (A.data.bones["thigh_l"].matrix_local.to_3x3() @ Vector((0, 0, 1))).normalized()])
for name, q in {
    "raw baked (as-is)": qb,
    "rest* baked": qr @ qb,
    "baked* rest.inv": qb @ qr.inverted(),
    "arm* baked": arm_q @ qb,
}.items():
    if q is None:
        continue
    d = dir_from_world_rot(q, (0, 0, 1))
    print("  %-18s bone-dir=%s (down-ness %.2f)" % (name, [round(c, 2) for c in d], -d.z))

print("--- what the REST pose itself gives (current eval: 98.9 deg tilt) ---")
pel_world = (A.pose.bones["pelvis"].matrix @ A.matrix_world)
print("  current pose pelvis up-tilt=%.1f deg" % up_from_world_rot(pel_world.to_quaternion()))
rest_world = (A.data.bones["pelvis"].matrix_local @ A.matrix_world)
print("  pure rest pelvis up-tilt=%.1f deg" % up_from_world_rot(rest_world.to_quaternion()))
'''

if __name__ == "__main__":
    print(send_code(CODE))
