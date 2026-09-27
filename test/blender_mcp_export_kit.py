"""Export the in-use pilot kit variant over res://scenes/pilot/pilot_pistol_kit.glb.

Selects only the live kit (Pilot_Character armature + Pilot_SWAT + PistolProp),
exports with animations and yup=True (Blender +Y forward -> Godot -Z), then
reads back the written GLB JSON to verify: the 3 pistol clips exist and the
pistol node sits under the hand_r joint with a small offset.

Usage: python test/blender_mcp_export_kit.py
"""
from blender_mcp_probe import send_code

# Absolute path to the repo GLB (project root on this machine).
DEST = r"C:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/scenes/pilot/pilot_pistol_kit.glb"

CODE = r'''
import bpy, struct, json, os

DEST = "__DEST__"
OB = bpy.data.objects

KIT = ["Pilot_Character", "Pilot_SWAT", "PistolProp"]

print("--- select kit objects ---")
bpy.ops.object.select_all(action="DESELECT")
for name in KIT:
    OB[name].select_set(True)
    print("selected:", name)
bpy.context.view_layer.objects.active = OB["Pilot_Character"]
bpy.context.scene.frame_set(0)

print("--- export GLB ---")
bpy.ops.export_scene.gltf(
    filepath=DEST,
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_yup=True,
)
print("written:", DEST, os.path.getsize(DEST), "bytes")

print("--- read-back verification ---")
raw = open(DEST, "rb").read()
chunk_len = struct.unpack("<I", raw[12:16])[0]
g = json.loads(raw[20:20 + chunk_len].decode("utf-8"))
parent_of = {}
for i, n in enumerate(g["nodes"]):
    for c in n.get("children", []):
        parent_of[c] = i
names = [n.get("name", "?") for n in g["nodes"]]
anims = sorted(a.get("name", "?") for a in g.get("animations", []))
print("nodes=%d | animations=%s" % (len(names), anims))
missing = [c for c in ("pistol_idle", "pistol_reload", "pistol_shoot") if c not in anims]
print("required clips missing:", missing or "NONE")
pistol_idx = [i for i, n in enumerate(g["nodes"]) if "PistolProp" in (n.get("name") or "")]
for i in pistol_idx:
    t = g["nodes"][i].get("translation") or []
    tl = sum(c * c for c in t) ** 0.5 if t else -1.0
    print("PISTOL %s | parent=%s | offset len=%.4f" % (
        names[i], names[parent_of[i]] if i in parent_of else "ROOT", tl))
'''

if __name__ == "__main__":
    print(send_code(CODE.replace("__DEST__", DEST.replace("\\", "/"))))
