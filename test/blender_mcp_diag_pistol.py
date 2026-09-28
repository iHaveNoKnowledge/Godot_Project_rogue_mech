"""Diagnose pilot pistol issues: crossed hands, two pistols, muzzle direction.

Binds pistol_idle_loop (f0) on both rigs and measures:
 - hand world positions per rig (hand_l vs hand_r distance)
 - forearm segment distances (do the arms actually cross?)
 - pistol world transforms, local axis directions, scales (mirror check)
 - pistol mesh vertex distribution -> barrel axis, muzzle end, grip anchor

Usage: python test/blender_mcp_diag_pistol.py
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

print("=== object inventory ===")
for o in OB:
    if o.type in ("ARMATURE", "MESH") and any(k in o.name for k in ("Pilot", "Swat", "Pistol")):
        print("%-22s type=%s hide_v=%s scale=%s" % (o.name, o.type, o.hide_viewport,
              tuple(round(v, 3) for v in o.scale)))

RIGS = {"A": OB["Pilot_Character"], "B": OB["Pilot_Character.001"]}
PISTOL = {"A": "PistolProp", "B": "PistolProp.001"}

for rk, rig in RIGS.items():
    sfx = ".001" if rk == "B" else ""
    act = bpy.data.actions.get("pistol_idle_loop" + sfx)
    if act is None:
        print("no action for", rk)
        continue
    bind(rig, act)
scn.frame_set(0)
bpy.context.view_layer.update()
dgv = bpy.context.evaluated_depsgraph_get()

def wmat(rig, ev, bone):
    return ev.pose.bones[bone].matrix @ rig.matrix_world

def seg_dist(a1, a2, b1, b2):
    d1 = a2 - a1
    d2 = b2 - b1
    r = a1 - b1
    a = d1.dot(d1)
    e = d2.dot(d2)
    f = d2.dot(r)
    if a <= 1e-9 or e <= 1e-9:
        return r.length
    c = d1.dot(r)
    b = d1.dot(d2)
    den = a * e - b * b
    s = max(0.0, min(1.0, (b * f - c * e) / den)) if den > 1e-9 else 0.0
    t = (b * s + f) / e
    t = max(0.0, min(1.0, t))
    s = max(0.0, min(1.0, (b * t - c) / a))
    return (a1 + d1 * s - (b1 + d2 * t)).length

print("=== hands at idle f0 ===")
for rk, rig in RIGS.items():
    ev = rig.evaluated_get(dgv)
    B = ("upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r")
    P = {b: wmat(rig, ev, b).translation for b in B}
    d_lr = (P["hand_l"] - P["hand_r"]).length
    print("[%s] hand_r %s hand_l %s | wrist dist %.3f" % (
        rk, tuple(round(v, 3) for v in P["hand_r"]),
        tuple(round(v, 3) for v in P["hand_l"]), d_lr))
    hr = wmat(rig, ev, "hand_r")
    print("[%s] hand_r axisX %s axisY %s axisZ %s" % (
        rk,
        tuple(round(v, 2) for v in (hr.to_3x3() @ Vector((1, 0, 0))).normalized()),
        tuple(round(v, 2) for v in (hr.to_3x3() @ Vector((0, 1, 0))).normalized()),
        tuple(round(v, 2) for v in (hr.to_3x3() @ Vector((0, 0, 1))).normalized())))
    d_up = seg_dist(P["upperarm_l"], P["lowerarm_l"], P["upperarm_r"], P["lowerarm_r"])
    d_lo = seg_dist(P["lowerarm_l"], P["hand_l"], P["lowerarm_r"], P["hand_r"])
    print("[%s] forearm L-vs-R min dist: upper %.3f | lower %.3f" % (rk, d_up, d_lo))

print("=== pistols ===")
for rk in ("A", "B"):
    p = OB[PISTOL[rk]]
    mw = p.matrix_world
    print("%s scale=%s dims=%s pos=%s" % (p.name,
          tuple(round(v, 3) for v in p.scale), tuple(round(v, 3) for v in p.dimensions),
          tuple(round(v, 3) for v in mw.translation)))
    for ax, v in (("X", Vector((1, 0, 0))), ("Y", Vector((0, 1, 0))), ("Z", Vector((0, 0, 1)))):
        print("   local %s -> world %s" % (ax, tuple(round(c, 2) for c in (mw.to_3x3() @ v).normalized())))

print("=== pistol mesh local analysis (PistolProp) ===")
p = OB["PistolProp"]
vs = [v.co for v in p.data.vertices]
print("verts:", len(vs))
xs = [c.x for c in vs]; ys = [c.y for c in vs]; zs = [c.z for c in vs]
print("x range %.4f..%.4f | y range %.4f..%.4f | z range %.4f..%.4f" %
      (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
midy = (min(ys) + max(ys)) / 2
for nm, grp in (("y<mid", [c for c in vs if c.y < midy]), ("y>=mid", [c for c in vs if c.y >= midy])):
    rad = max((c.x ** 2 + c.z ** 2) ** 0.5 for c in grp)
    print("%s: n=%d maxrad=%.4f" % (nm, len(grp), rad))
midz = (min(zs) + max(zs)) / 2
for nm, grp in (("z<mid", [c for c in vs if c.z < midz]), ("z>=mid", [c for c in vs if c.z >= midz])):
    print("%s: n=%d y-span %.3f..%.3f" % (nm, len(grp), min(c.y for c in grp), max(c.y for c in grp)))
zs_sorted = sorted(zs)
zcut = zs_sorted[int(len(zs_sorted) * 0.4)]
grip = [c for c in vs if c.z < zcut]
if grip:
    n = len(grip)
    print("grip centroid (bottom 40%%): (%.4f, %.4f, %.4f)" % (
        sum(c.x for c in grip) / n, sum(c.y for c in grip) / n, sum(c.z for c in grip) / n))
'''

if __name__ == "__main__":
    print(send_code(CODE))
