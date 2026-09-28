"""Probe pistol props' local geometry: find barrel axis, muzzle end, grip side.

Bins vertices along the long axis and across it to locate the thin muzzle end
and the offset grip mass, for BOTH props (A: PistolProp, B: PistolProp.001).
Also reports parenting (bone parent?), modifiers, and the kit's rest-pose
finger curl (to judge zeroing authored finger keys).

Usage: python test/blender_mcp_probe_pistol_axes.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy
from mathutils import Vector

OB = bpy.data.objects
scn = bpy.context.scene

def bind(rig, act):
    ad = rig.animation_data or rig.animation_data_create()
    slot = next((s for s in act.slots if s.target_id_type == "OBJECT"), None)
    if slot is None:
        slot = act.slots.new(id_type="OBJECT", name=rig.name)
    ad.action = act
    ad.action_slot = slot

bind(OB["Pilot_Character"], bpy.data.actions["pistol_idle_loop"])
bind(OB["Pilot_Character.001"], bpy.data.actions["pistol_idle_loop.001"])
scn.frame_set(0)
bpy.context.view_layer.update()

print("=== parenting / modifiers ===")
for nm in ("PistolProp", "PistolProp.001"):
    p = OB[nm]
    par = p.parent
    print("%s parent=%s parent_type=%s parent_bone=%s mods=%s" % (
        nm, par.name if par else None, p.parent_type, p.parent_bone,
        [m.type for m in p.modifiers]))

print("=== prop local geometry bins ===")
for nm in ("PistolProp", "PistolProp.001"):
    p = OB[nm]
    vs = [v.co for v in p.data.vertices]
    ys = [c.y for c in vs]
    y0, y1 = min(ys), max(ys)
    print("--- %s (verts %d) y %.4f..%.4f ---" % (nm, len(vs), y0, y1))
    NB = 8
    for i in range(NB):
        lo = y0 + (y1 - y0) * i / NB
        hi = y0 + (y1 - y0) * (i + 1) / NB
        grp = [c for c in vs if lo <= c.y < hi or (i == NB - 1 and c.y == y1)]
        if not grp:
            continue
        n = len(grp)
        cx = sum(c.x for c in grp) / n
        cz = sum(c.z for c in grp) / n
        rad = max((c.x - cx) ** 2 + (c.z - cz) ** 2 for c in grp) ** 0.5
        xr = (min(c.x for c in grp), max(c.x for c in grp))
        zr = (min(c.z for c in grp), max(c.z for c in grp))
        print("ybin%d [%.3f..%.3f] n=%3d cx=%+.4f cz=%+.4f maxrad=%.4f x%s z%s"
              % (i, lo, hi, n, cx, cz, rad,
                 "(%.3f,%.3f)" % xr, "(%.3f,%.3f)" % zr))
    # grip mass: vertices far from the Y axis line
    far = [c for c in vs if (c.x ** 2 + c.z ** 2) > 0.01]
    if far:
        n = len(far)
        gx = sum(c.x for c in far) / n
        gy = sum(c.y for c in far) / n
        gz = sum(c.z for c in far) / n
        print("offset mass (rad>0.1): n=%d centroid=(%+.4f, %+.4f, %+.4f)" % (n, gx, gy, gz))

print("=== kit rest-pose finger curl (rig A) ===")
rig = OB["Pilot_Character"]
def rest_dir(pb):
    b = pb.bone
    return (b.matrix_local.to_3x3() @ Vector((0, 1, 0))).normalized()
for chain in ("thumb", "index", "middle", "ring", "pinky"):
    segs = sorted([pb.name for pb in rig.pose.bones if pb.name.startswith(chain + "_") and "leaf" not in pb.name])
    dirs = []
    for s in segs:
        d = rest_dir(rig.pose.bones[s])
        dirs.append((s, tuple(round(v, 2) for v in d)))
    print(chain, dirs)

print("=== hand idle finger sample ===")
dg = bpy.context.evaluated_depsgraph_get()
ev = rig.evaluated_get(dg)
idx1 = ev.pose.bones.get("index_01_l")
if idx1:
    m = idx1.matrix @ rig.matrix_world
    print("index_01_l idle world pos", tuple(round(v, 3) for v in m.translation))
'''

if __name__ == "__main__":
    print(send_code(CODE))
