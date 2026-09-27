"""Detailed scene report from the running Blender via blender-mcp (localhost:9876).

Usage: python test/blender_mcp_scene_report.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy

out = []

out.append("=== OBJECTS ===")
for o in bpy.data.objects:
    parent = o.parent.name if o.parent else "-"
    mod_str = ",".join(f"{m.type}:{m.name}" for m in o.modifiers) or "-"
    line = f"{o.name} | {o.type} | parent={parent} | mods=[{mod_str}]"
    if o.type == 'MESH':
        mats = [m.name if m else "EMPTY-SLOT" for m in o.data.materials]
        line += f" | mats={mats} | verts={len(o.data.vertices)} faces={len(o.data.polygons)}"
        if o.data.shape_keys:
            line += f" | shapekeys={len(o.data.shape_keys.key_blocks)}"
        if o.animation_data and o.animation_data.action:
            line += f" | action={o.animation_data.action.name}"
    elif o.type == 'ARMATURE':
        line += f" | bones={len(o.data.bones)} pose_bones={len(o.pose.bones)}"
        if o.animation_data and o.animation_data.action:
            line += f" | action={o.animation_data.action.name}"
        else:
            line += " | action=None"
    out.append(line)

out.append("=== MATERIALS ===")
for mat in bpy.data.materials:
    users = [u.name for u in bpy.data.objects
             if u.type == 'MESH' and any(m == mat for m in u.data.materials)]
    info = f"{mat.name} | users={users}"
    if mat.use_nodes:
        principled = None
        for n in mat.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                principled = n
                break
        if principled:
            try:
                bc = tuple(round(c, 3) for c in principled.inputs['Base Color'].default_value[:])
                rough = round(principled.inputs['Roughness'].default_value, 2)
                metal = round(principled.inputs['Metallic'].default_value, 2)
                tex = "linked" if principled.inputs['Base Color'].is_linked else "flat"
            except Exception:
                bc, rough, metal, tex = "?", "?", "?", "?"
            info += f" | baseColor={bc} rough={rough} metal={metal} baseColorTex={tex}"
        else:
            info += " | no-principled-bsdf"
    else:
        info += " | nodes=off"
    out.append(info)

out.append("=== ACTIONS ===")

def curve_count(a):
    # Blender <=4.3: Action.fcurves; 4.4+: slotted actions (layers/strips/channelbags)
    try:
        return len(a.fcurves)
    except AttributeError:
        total = 0
        for layer in a.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    total += len(cb.fcurves)
        return total

acts = list(bpy.data.actions)
out.append(f"total={len(acts)}")
for a in acts:
    frames = (a.frame_range[0], a.frame_range[1]) if a.frame_range else "?"
    out.append(f"{a.name} | frames={frames} | curves={curve_count(a)}")

out.append("=== COLLECTIONS ===")
for coll in bpy.data.collections:
    objs = [o.name for o in coll.objects]
    out.append(f"{coll.name}: {objs}")

print(chr(10).join(out))
'''

if __name__ == "__main__":
    print(send_code(CODE))
