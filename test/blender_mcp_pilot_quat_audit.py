"""Locate the tilted-stance cause: quaternion completeness + per-frame bend.

For every animated bone: report missing quaternion components (0..3) and
missing location components. Then evaluate the armature across the clip and
report per-frame pelvis/spine world tilt and character Y-span so we know
whether the whole clip is bent or only the first frame.

Usage: python test/blender_mcp_pilot_quat_audit.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy
from mathutils import Vector

OB = bpy.data.objects
pilot = OB["Pilot_Character"]
act = pilot.animation_data.action

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

fcs = all_fcurves(act)
print("--- quaternion/location completeness per animated bone ---")
comp = {}
for fc in fcs:
    comp.setdefault(fc.data_path, set()).add(fc.array_index)
broken = []
for path, idxs in sorted(comp.items()):
    if "rotation_quaternion" in path:
        missing = {0, 1, 2, 3} - idxs
        if missing:
            broken.append((path, "rot missing %s" % sorted(missing)))
    elif "location" in path:
        missing = {0, 1, 2} - idxs
        if missing:
            broken.append((path, "loc missing %s" % sorted(missing)))
print("incomplete channels:", broken if broken else "NONE")

print("--- channels per bone summary ---")
per_bone = {}
for path, idxs in comp.items():
    if "pose.bones[" in path:
        bn = path.split('"')[1]
        ch = path.rsplit(".", 1)[-1]
        per_bone.setdefault(bn, []).append("%s:%d" % (ch, len(idxs)))
for bn in sorted(per_bone):
    print("  %s: %s" % (bn, ",".join(sorted(per_bone[bn]))))

print("--- fcurve extrapolation / modifiers (non-constant) ---")
weird = [(fc.data_path, fc.array_index, fc.extrapolation,
          [m.type for m in fc.modifiers])
         for fc in fcs if fc.extrapolation != "CONSTANT" or fc.modifiers]
print("non-default extrapolation/modifiers:", weird[:10] if weird else "NONE")

print("--- per-frame bend evaluation ---")
scn = bpy.context.scene
pb_pelvis = pilot.pose.bones.get("pelvis")
spine_names = [b.name for b in pilot.data.bones if b.name.startswith("spine")]
arm_inv = pilot.matrix_world.inverted()

def tilt(vec):
    import math
    return math.degrees(math.acos(max(-1.0, min(1.0, vec.z))))

for f in range(0, 55, 5):
    scn.frame_set(f)
    bpy.context.view_layer.update()
    ev = pilot.evaluated_get(bpy.context.evaluated_depsgraph_get())
    pel = ev.pose.bones["pelvis"]
    up_world = (pel.matrix.to_3x3() @ Vector((0, 0, 1))).normalized()
    t1 = tilt(up_world)
    vs = [pilot.matrix_world @ Vector(v) for v in OB["Pilot_SWAT"].bound_box]
    yspan = max(v.y for v in vs) - min(v.y for v in vs)
    zmin = min(v.z for v in vs)
    zmax = max(v.z for v in vs)
    print("frame %2d | pelvis up-tilt=%.1f deg | Y-span=%.3f | Z=%.3f..%.3f" % (f, t1, yspan, zmin, zmax))
scn.frame_set(0)

print("--- rest-pose sanity: rest Y-span of Pilot_SWAT (no pose) ---")
pilot.data.pose_position = "REST"
bpy.context.view_layer.update()
vs = [pilot.matrix_world @ Vector(v) for v in OB["Pilot_SWAT"].bound_box]
print("REST: Y-span=%.3f Z=%.3f..%.3f" % (
    max(v.y for v in vs) - min(v.y for v in vs), min(v.z for v in vs), max(v.z for v in vs)))
pilot.data.pose_position = "POSE"
bpy.context.view_layer.update()
'''

if __name__ == "__main__":
    print(send_code(CODE))
