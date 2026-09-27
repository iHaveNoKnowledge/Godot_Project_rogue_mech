"""Seat the bone-parented pistols at their authored offsets - measured solve.

Instead of assuming Blender's bone-parent matrix formula, measure the actual
parent chain M per pistol (world = M @ basis holds affinely), then solve
basis = M^-1 @ W for the authored world position W. Exact regardless of any
hidden factors (e.g. head->tail offsets) in Blender 5 bone parenting.
Verified in-Blender (world == W, follows hand) and via probe GLB JSON.

Usage: python test/blender_mcp_pistol_reseat.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, struct, json, os, tempfile
from mathutils import Matrix

OB = bpy.data.objects
RIGS = [("PistolProp", "Pilot_Character"), ("PistolProp.001", "Pilot_Character.001")]
AUTH = {"PistolProp": (-0.003, -0.525, 1.608), "PistolProp.001": (-0.009, -0.516, 1.598)}

scn = bpy.context.scene
scn.frame_set(0)
bpy.context.view_layer.update()

print("--- measured-solve seating ---")
for pname, aname in RIGS:
    p = OB[pname]
    ar = OB[aname]
    actual = p.matrix_world.copy()
    basis = p.matrix_basis.copy()
    M = actual @ basis.inverted()          # real parent chain, measured
    W = Matrix.Translation(AUTH[pname])    # authored world position
    p.matrix_basis = M.inverted() @ W
    bpy.context.view_layer.update()
    t = p.matrix_world.translation
    err = (t - W.translation).length
    dg = bpy.context.evaluated_depsgraph_get()
    hw = (ar.evaluated_get(dg).pose.bones["hand_r"].matrix @ ar.matrix_world).translation
    print("%s | world=(%.4f,%.4f,%.4f) | seat_err=%.6f | dist_to_hand=%.4f"
          % (pname, t.x, t.y, t.z, err, (t - hw).length))

print("--- follow check (frame 0 -> 25) ---")
for pname, aname in RIGS:
    p = OB[pname]
    ar = OB[aname]
    pb = ar.pose.bones["hand_r"]
    scn.frame_set(0); bpy.context.view_layer.update()
    p0 = p.matrix_world.translation.copy(); h0 = (pb.matrix @ ar.matrix_world).translation.copy()
    scn.frame_set(25); bpy.context.view_layer.update()
    p1 = p.matrix_world.translation.copy(); h1 = (pb.matrix @ ar.matrix_world).translation.copy()
    dp, dh = (p1 - p0).length, (h1 - h0).length
    print("%s: pistol=%.4f hand=%.4f locked=%s" % (pname, dp, dh, abs(dp - dh) < 1e-4))
scn.frame_set(0)

print("--- probe GLB re-check ---")
path = os.path.join(tempfile.gettempdir(), "pilot_probe3.glb")
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
for i in pistol_idx:
    t = g["nodes"][i].get("translation") or []
    tl = sum(c * c for c in t) ** 0.5 if t else -1.0
    print("PISTOL %s | parent=%s | local translation len=%.4f"
          % (label(i), label(parent_of[i]) if i in parent_of else "ROOT", tl))
'''

if __name__ == "__main__":
    print(send_code(CODE))
