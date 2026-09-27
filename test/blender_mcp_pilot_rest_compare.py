"""Confirm the action/rest mismatch: compare A vs B rest matrices and B's pose tilt.

If rig B (the glTF round-tripped .001 pair) evaluates its own clip upright
while rig A leans 98.9 deg, and their bone rest orientations differ by about
that amount, the actions were baked against B-style rests.

Usage: python test/blender_mcp_pilot_rest_compare.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Vector

OB = bpy.data.objects
A = OB["Pilot_Character"]
B = OB["Pilot_Character.001"]

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

def tilt_deg(pel_matrix_world_rot):
    up = (pel_matrix_world_rot @ Vector((0, 0, 1))).normalized()
    return math.degrees(math.acos(max(-1.0, min(1.0, up.z))))

print("--- rig B (.001) evaluation across pistol_idle.001 ---")
scn = bpy.context.scene
for f in (0, 20, 50):
    scn.frame_set(f)
    bpy.context.view_layer.update()
    pel = B.pose.bones["pelvis"]
    up_world = ((pel.matrix @ B.matrix_world).to_3x3() @ Vector((0, 0, 1))).normalized()
    t = math.degrees(math.acos(max(-1.0, min(1.0, up_world.z))))
    print("frame %2d | B pelvis up-tilt=%.1f deg" % (f, t))
scn.frame_set(0)

print("--- rest orientation comparison (bones with biggest delta) ---")
diffs = []
for bn in A.data.bones:
    b_bn = B.data.bones.get(bn.name)
    if b_bn is None:
        continue
    q_a = bn.matrix_local.to_quaternion()
    q_b = b_bn.matrix_local.to_quaternion()
    dq = q_a.rotation_difference(q_b)
    ang = math.degrees(dq.angle)
    if ang > 1.0:
        diffs.append((round(ang, 1), bn.name))
diffs.sort(reverse=True)
print("bones whose REST differs >1 deg (angle, name):")
for ang, name in diffs[:25]:
    print("  %6.1f deg  %s" % (ang, name))
print("total differing: %d / %d common bones" % (len(diffs), len([b for b in A.data.bones if B.data.bones.get(b.name)])))

print("--- B rest Y-span of its SWAT parts (sanity) ---")
bmeshes = [OB[n] for n in ("Swat_Body.001", "Swat_Head.001", "Swat_Legs.001", "Swat_Feet.001")]
vs = []
for m in bmeshes:
    vs.extend(m.matrix_world @ Vector(v) for v in m.bound_box)
print("B parts world: Y %.3f..%.3f (span %.3f) Z %.3f..%.3f" % (
    min(v.y for v in vs), max(v.y for v in vs),
    max(v.y for v in vs) - min(v.y for v in vs),
    min(v.z for v in vs), max(v.z for v in vs)))
'''

if __name__ == "__main__":
    print(send_code(CODE))
