"""Decisive probe: find each pistol prop's true muzzle axis via end-cap analysis.

For every local axis, reports the span and both end caps (vertex count,
centroid, max perpendicular radius). A muzzle = thin end cap (small radius);
a grip = offset mass at an end. Prints a suggested barrel axis and grip side
per prop, plus world-direction checks under the current seat.

Usage: python test/blender_mcp_probe_pistol_ends.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy
from mathutils import Vector

OB = bpy.data.objects

def axis_report(vs, ax):
    idx = {"x": 0, "y": 1, "z": 2}[ax]
    vals = [c[idx] for c in vs]
    lo, hi = min(vals), max(vals)
    span = hi - lo
    out = []
    for tag, plane in (("lo", lo), ("hi", hi)):
        cap = [c for c in vs if abs(c[idx] - plane) <= span * 0.03]
        if not cap:
            continue
        n = len(cap)
        cen = [sum(c[k] for c in cap) / n for k in range(3)]
        rad = max((c[(idx + 1) % 3] - cen[(idx + 1) % 3]) ** 2 +
                  (c[(idx + 2) % 3] - cen[(idx + 2) % 3]) ** 2 for c in cap) ** 0.5
        out.append((tag, n, cen, rad))
    return lo, hi, span, out

for nm in ("PistolProp", "PistolProp.001"):
    p = OB[nm]
    vs = [v.co.copy() for v in p.data.vertices]
    print("=== %s (verts %d) ===" % (nm, len(vs)))
    for ax in ("x", "y", "z"):
        lo, hi, span, caps = axis_report(vs, ax)
        line = "%s: span %.4f..%.4f (len %.4f)" % (ax, lo, hi, span)
        for tag, n, cen, rad in caps:
            line += " | %s-end n=%d cen=(%+.4f,%+.4f,%+.4f) rad=%.4f" % (
                tag, n, cen[0], cen[1], cen[2], rad)
        print(line)
    print()

print("=== current seat world dirs (f0 idle) ===")
for nm in ("PistolProp", "PistolProp.001"):
    p = OB[nm]
    mw = p.matrix_world
    for ax, v in (("+X", Vector((1, 0, 0))), ("+Y", Vector((0, 1, 0))),
                  ("+Z", Vector((0, 0, 1))), ("-Y", Vector((0, -1, 0)))):
        print("%s local %s -> world %s" % (nm, ax,
              tuple(round(c, 2) for c in (mw.to_3x3() @ v).normalized())))
'''

if __name__ == "__main__":
    print(send_code(CODE))
