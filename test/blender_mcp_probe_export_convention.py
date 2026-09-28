"""Determine the glTF exporter's bone-parented-object bake convention.

Compares the exported PistolProp node TRS in the kit GLB against two
candidate formulas computed in Blender at idle f0:
  (a) P = J_rest^-1 @ W   (baked against the bone REST matrix)
  (b) P = J_pose^-1 @ W   (baked against the animated f0 pose)

Usage: python test/blender_mcp_probe_export_convention.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, struct, json
from mathutils import Vector, Matrix, Quaternion

GLB = "C:/Users/hackd/OneDrive/\u0e40\u0e2d\u0e01\u0e2a\u0e32\u0e23/GitHub/Godot_Project_rogue_mech/scenes/pilot/pilot_pistol_kit.glb"
OB = bpy.data.objects
scn = bpy.context.scene

rig = OB["Pilot_Character"]
ad = rig.animation_data
act = bpy.data.actions["pistol_idle_loop"]
slot = next((s for s in act.slots if s.target_id_type == "OBJECT"), None)
ad.action = act
ad.action_slot = slot
scn.frame_set(0)
bpy.context.view_layer.update()

arm_i = rig.matrix_world.inverted()
p = OB["PistolProp"]
W = arm_i @ p.matrix_world            # pistol world in armature space

pb = rig.pose.bones["hand_r"]
J_pose = pb.matrix.copy()             # armature-space animated pose at f0
J_rest = pb.bone.matrix_local.copy()  # armature-space rest

def rel(J):
    return J.inverted() @ W

def trs(m):
    t = m.to_translation()
    q = m.to_quaternion()
    s = m.to_scale()
    return (tuple(round(v, 4) for v in t), tuple(round(v, 4) for v in q),
            tuple(round(v, 4) for v in s))

print("W (arm space):", trs(W))
print("candidate (a) rest-baked  J_rest^-1 @ W:", trs(rel(J_rest)))
print("candidate (b) pose-baked  J_pose^-1 @ W:", trs(rel(J_pose)))

raw = open(GLB, "rb").read()
jl = struct.unpack("<I", raw[12:16])[0]
g = json.loads(raw[20:20 + jl].decode())
names = [n.get("name", "?") for n in g["nodes"]]
for i, n in enumerate(g["nodes"]):
    if n.get("name") == "PistolProp":
        t = n.get("translation", [0, 0, 0])
        r = n.get("rotation", [0, 0, 0, 1])
        s = n.get("scale", [1, 1, 1])
        print("GLB node TRS:", (tuple(round(v, 4) for v in t),
                                tuple(round(v, 4) for v in r),
                                tuple(round(v, 4) for v in s)))
        break
'''

if __name__ == "__main__":
    print(send_code(CODE))
