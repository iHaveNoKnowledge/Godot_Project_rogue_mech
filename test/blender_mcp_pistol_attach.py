"""Bone-parent the pilot pistols to hand_r on both rigs and verify.

Pipeline (single MCP call):
 1. Capture each pistol's current world matrix (authored next to the posed
    idle hand) and re-parent it to the rig armature with parent_type='BONE',
    parent_bone='hand_r', computing matrix_basis so the visual position is
    preserved at the current (idle) pose.
 2. Blender-side check: pistol must keep its offset when the frame changes
    (moves together with the hand between two frames).
 3. Ground-truth check: export a probe GLB and inspect the JSON - the pistol
    node must be a descendant of the hand_r joint with a small local offset
    (~2-4 cm), not a 0.7 m rest-space offset.

Usage: python test/blender_mcp_pistol_attach.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, struct, json, os, tempfile
from mathutils import Matrix

RIGS = [("PistolProp", "Pilot_Character"), ("PistolProp.001", "Pilot_Character.001")]
OB = bpy.data.objects

def vlen(t):
    return (t[0]**2 + t[1]**2 + t[2]**2) ** 0.5 if t else -1.0

print("--- STEP 1: bone parenting ---")
for pname, aname in RIGS:
    p = OB[pname]
    ar = OB[aname]
    W = p.matrix_world.copy()                       # authored world position
    P = ar.pose.bones["hand_r"].matrix.copy()       # armature-space pose matrix
    Ainv = ar.matrix_world.inverted()
    p.parent = ar
    p.parent_type = "BONE"
    p.parent_bone = "hand_r"
    p.matrix_parent_inverse = Matrix.Identity(4)
    p.matrix_basis = P.inverted() @ (Ainv @ W)
    bpy.context.view_layer.update()
    err = (p.matrix_world.translation - W.translation).length
    print("%s -> bone-parented to %s/hand_r | visual drift after re-parent: %.5f m" % (pname, aname, err))

print("--- STEP 2: follows hand across frames ---")
scn = bpy.context.scene
orig_frame = scn.frame_current
for pname, aname in RIGS:
    p = OB[pname]
    ar = OB[aname]
    pb = ar.pose.bones["hand_r"]
    deltas = []
    for f in (0, 12, 25):
        scn.frame_set(f)
        bpy.context.view_layer.update()
        pp = p.matrix_world.translation.copy()
        hh = (pb.matrix @ ar.matrix_world).translation.copy()
        deltas.append((pp, hh))
    d_p = (deltas[1][0] - deltas[0][0]).length
    d_h = (deltas[1][1] - deltas[0][1]).length
    d_p2 = (deltas[2][0] - deltas[0][0]).length
    d_h2 = (deltas[2][1] - deltas[0][1]).length
    print("%s: f0->f12 pistol=%.4f hand=%.4f | f0->f25 pistol=%.4f hand=%.4f | locked=%s"
          % (pname, d_p, d_h, d_p2, d_h2, abs(d_p - d_h) < 1e-4 and abs(d_p2 - d_h2) < 1e-4))
scn.frame_set(orig_frame)

print("--- STEP 3: probe GLB export + JSON inspection ---")
path = os.path.join(tempfile.gettempdir(), "pilot_probe.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=False)
raw = open(path, "rb").read()
chunk_len = struct.unpack("<I", raw[12:16])[0]
g = json.loads(raw[20:20 + chunk_len].decode("utf-8"))
os.remove(path)

parent_of = {}
for i, n in enumerate(g["nodes"]):
    for c in n.get("children", []):
        parent_of[c] = i

def label(i):
    n = g["nodes"][i]
    if n.get("name"):
        return n["name"]
    if "mesh" in n:
        return "mesh:" + g["meshes"][n["mesh"]].get("name", "?")
    return "node%d" % i

pistol_idx = [i for i, n in enumerate(g["nodes"])
              if "PistolProp" in (n.get("name") or "")
              or ("mesh" in n and "Pistol" in g["meshes"][n["mesh"]].get("name", ""))]
hand_idx = [i for i, n in enumerate(g["nodes"]) if n.get("name") == "hand_r"]
print("probe nodes=%d | hand_r joints found=%d" % (len(g["nodes"]), len(hand_idx)))
for i in pistol_idx:
    chain, j = [], parent_of.get(i)
    while j is not None:
        chain.append(label(j))
        j = parent_of.get(j)
    t = g["nodes"][i].get("translation")
    rot = g["nodes"][i].get("rotation")
    print("PISTOL %s | parent=%s | chain=%s" % (label(i), label(parent_of[i]) if i in parent_of else "ROOT", " <- ".join(chain) or "-"))
    print("   local translation=%s (len=%.4f) rotation=%s" % (t, vlen(t), rot))
for i in hand_idx:
    t = g["nodes"][i].get("translation")
    print("HAND joint hand_r | local translation=%s" % (t,))
'''

if __name__ == "__main__":
    print(send_code(CODE))
