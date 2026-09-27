"""Diagnose the pilot stance / pistol scale / bone health via Blender MCP.

Measures: object transforms, pistol dimensions vs the untouched .001 twin,
NLA tracks, manual unkeyed pose deviation at frame 0, and bone health
(root/leaf sanity, rest vs pose, expected-clip bone coverage).

Usage: python test/blender_mcp_pilot_diagnose.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy
from math import degrees
from mathutils import Vector

OB = bpy.data.objects
pilot = OB["Pilot_Character"]
ad = pilot.animation_data
act = ad.action if ad else None

print("=== 1) object transforms ===")
for n in ("Pilot_Character", "Pilot_SWAT", "PistolProp", "Pilot_Character.001", "PistolProp.001"):
    o = OB[n]
    print("%s: loc=(%.3f,%.3f,%.3f) rot_deg=(%.1f,%.1f,%.1f) scale=(%.4f,%.4f,%.4f)" % (
        n, o.location.x, o.location.y, o.location.z,
        degrees(o.rotation_euler.x), degrees(o.rotation_euler.y), degrees(o.rotation_euler.z),
        o.scale.x, o.scale.y, o.scale.z))

print("=== 2) pistol dimensions (local dims / world bbox) ===")
def wbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.x for v in vs), max(v.x for v in vs),
            min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))
for n in ("PistolProp", "PistolProp.001"):
    p = OB[n]
    d = p.dimensions
    b = wbox(p)
    print("%s: local dims=(%.3f,%.3f,%.3f) obj_scale=(%.3f,%.3f,%.3f) world_len=%.3f" % (
        n, d.x, d.y, d.z, p.scale.x, p.scale.y, p.scale.z,
        max(b[1]-b[0], b[3]-b[2], b[5]-b[4])))

print("=== 3) NLA / action state ===")
print("nla_tracks:", [t.name for t in ad.nla_tracks] if ad else [])
print("action:", act.name if act else None, "| slots:", [s.identifier for s in act.slots] if act else [])

print("=== 4) manual unkeyed pose at frame 0 (vs fcurve value) ===")
scn = bpy.context.scene
scn.frame_set(0)
bpy.context.view_layer.update()

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

fcs = all_fcurves(act) if act else []
by_path = {}
for fc in fcs:
    by_path.setdefault(fc.data_path, {})[fc.array_index] = fc
devs = []
for pb in pilot.pose.bones:
    rq = by_path.get(pb.path_from_id("rotation_quaternion"), {})
    if not rq:
        continue
    cur = pb.rotation_quaternion
    for i in (1, 2, 3):
        fc = rq.get(i)
        if fc and abs(cur[i] - fc.evaluate(0)) > 0.02:
            devs.append((pb.name, i, round(cur[i] - fc.evaluate(0), 3)))
print("bones deviating >0.02 from fcurve@f0:", devs if devs else "NONE")

print("=== 5) pilot world height at frame 0 (bbox) ===")
b = wbox(OB["Pilot_SWAT"])
print("Pilot_SWAT world: X %.3f..%.3f Y %.3f..%.3f Z %.3f..%.3f | height=%.3f" % (
    b[0], b[1], b[2], b[3], b[4], b[5], b[5] - b[4]))

print("=== 6) bone health ===")
a_bones = pilot.data.bones
b_bones = OB["Pilot_Character.001"].data.bones
top_a = [bn.name for bn in a_bones if bn.parent is None]
top_b = [bn.name for bn in b_bones if bn.parent is None]
print("top-level bones A:", top_a, "| B:", top_b)
print("A=%d bones | B=%d bones | name-diff: A-only=%s B-only=%s" % (
    len(a_bones), len(b_bones),
    sorted(set(x.name for x in a_bones) - set(x.name for x in b_bones)),
    sorted(set(x.name for x in b_bones) - set(x.name for x in a_bones))))
sided = [bn for bn in a_bones if bn.name.endswith((".L", ".R"))]
print("symmetric .L/.R pairs:", len([x for x in sided if x.endswith(".L")]), "L vs",
      len([x for x in sided if x.endswith(".R")]), "R")
leaf = [bn.name for bn in a_bones if not bn.children]
print("leaf bones (%d): %s" % (len(leaf), leaf))
root = a_bones.get("root")
if root:
    print("root rest matrix head:", [round(c, 3) for c in root.head_local],
          "| tail:", [round(c, 3) for c in root.tail_local])
pelvis = a_bones.get("pelvis")
if pelvis:
    print("pelvis rest head:", [round(c, 3) for c in pelvis.head_local],
          "tail:", [round(c, 3) for c in pelvis.tail_local])

print("=== 7) clip bone coverage ===")
paths = set(fc.data_path for fc in fcs)
anim_bones = set(p.split('"')[1] for p in paths if p.startswith("pose.bones["))
all_bones = set(x.name for x in a_bones)
print("animated bones: %d | missing-from-rig: %s | never-animated: %d" % (
    len(anim_bones), sorted(anim_bones - all_bones), len(all_bones - anim_bones)))
print("never-animated bones:", sorted(all_bones - anim_bones))
scn.frame_set(0)
'''

if __name__ == "__main__":
    print(send_code(CODE))
