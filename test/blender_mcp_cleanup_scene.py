"""Scene cleanup for export: park dead rigs + purge orphan materials.

Single MCP call that:
 1. Moves unused objects (AF_Rig + PilotMesh_OK, HumanRig, PilotRig_QM) into
    the 'glTF_not_exported' collection so the glTF exporter skips them.
 2. Deletes every material with zero users (append/duplicate leftovers).
 3. Proves the effect with a probe GLB export (moved objects must be absent).
 4. Saves the .blend.

Usage: python test/blender_mcp_cleanup_scene.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, struct, json, os, tempfile

OB = bpy.data.objects
MOVE = ["AF_Rig", "PilotMesh_OK", "HumanRig", "PilotRig_QM"]
target = bpy.data.collections["glTF_not_exported"]

print("--- 1) move dead rigs to glTF_not_exported ---")
for name in MOVE:
    o = OB[name]
    for coll in list(o.users_collection):
        coll.objects.unlink(o)
    target.objects.link(o)
    print("moved:", name)

print("--- 2) purge zero-user materials ---")
before = len(bpy.data.materials)
doomed = [m for m in bpy.data.materials if m.users == 0]
for m in doomed:
    bpy.data.materials.remove(m)
print("materials: %d -> %d (removed %d)" % (before, len(bpy.data.materials), len(doomed)))
kept = sorted(m.name for m in bpy.data.materials)
print("remaining:", kept)

print("--- 3) probe export: dead rigs must be gone ---")
path = os.path.join(tempfile.gettempdir(), "pilot_probe_clean.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_animations=False)
raw = open(path, "rb").read()
chunk_len = struct.unpack("<I", raw[12:16])[0]
g = json.loads(raw[20:20 + chunk_len].decode("utf-8"))
os.remove(path)
parent_of = {}
for i, n in enumerate(g["nodes"]):
    for c in n.get("children", []):
        parent_of[c] = i
names = [n.get("name", "?") for n in g["nodes"]]
print("probe nodes=%d | dead rigs present: %s" % (
    len(names), [n for n in names if n in MOVE] or "NONE (clean)"))
pistol_idx = [i for i, n in enumerate(g["nodes"]) if "PistolProp" in (n.get("name") or "")]
for i in pistol_idx:
    t = g["nodes"][i].get("translation") or []
    tl = sum(c * c for c in t) ** 0.5 if t else -1.0
    print("PISTOL %s | parent=%s | offset len=%.4f" % (
        names[i], names[parent_of[i]] if i in parent_of else "ROOT", tl))

print("--- 4) save .blend ---")
bpy.ops.wm.save_mainfile()
print("saved:", bpy.data.filepath, "| dirty:", bpy.data.is_dirty)
'''

if __name__ == "__main__":
    print(send_code(CODE))
