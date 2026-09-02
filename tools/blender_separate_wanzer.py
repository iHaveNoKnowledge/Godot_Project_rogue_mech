"""
Blender 4.2+ : Separate Wanzer GLB by Loose Parts + Box split into 6 slots
Usage:
  blender --background --python tools/blender_separate_wanzer.py
  or inside Blender Text Editor -> Run Script
Input : assets/models/wanzer_frontmission.glb (or wanzer_frontmission.glb)
Output: scenes/mecha/parts/{head,body,arm_left,arm_right,leg_left,leg_right}/wanzer_{slot}_blender.glb
        + weapon as scenes/mecha/parts/body/wanzer_weapon.glb (or assets/models)
        Origin reset to geometry median for each part.
"""
import bpy, os, sys, pathlib

proj = pathlib.Path(__file__).resolve().parents[1] if "__file__" in globals() else pathlib.Path(r"C:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech")
# Fallback
if not (proj / "assets").exists():
    proj = pathlib.Path(r"C:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech")

src = proj / "assets" / "models" / "wanzer_frontmission.glb"
if not src.exists():
    src = proj / "assets" / "models" / "wanzer_frontmission.glb"
print(f"[Blender] Import {src}")

# Clean scene
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))

# Collect imported meshes
imported = [o for o in bpy.context.scene.objects if o.type == 'MESH']
print(f"Imported {len(imported)} mesh objects")
if not imported:
    raise RuntimeError("No mesh imported")

# Join into one if multiple
bpy.ops.object.select_all(action='DESELECT')
for o in imported:
    o.select_set(True)
bpy.context.view_layer.objects.active = imported[0]
if len(imported) > 1:
    bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
print(f"Joined to {obj.name} verts={len(obj.data.vertices)}")

# Try Separate by Loose Parts
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.separate(type='LOOSE')
bpy.ops.object.mode_set(mode='OBJECT')
loose = [o for o in bpy.context.scene.objects if o.type=='MESH']
print(f"Loose parts: {len(loose)}")

# If Loose Parts gives 1 (single watertight), fallback to box split by bounds
# We'll classify each loose part by centroid into 6 slots
# Weapon detection: long thin bbox (length > 1.5x width/height) and in front (y ~ center, z > 0.4)
def classify(obj):
    # world bbox
    mw = obj.matrix_world
    coords = [mw @ v.co for v in obj.data.vertices]
    if not coords: return "body"
    xs = [c.x for c in coords]; ys = [c.y for c in coords]; zs = [c.z for c in coords]
    cx, cy, cz = sum(xs)/len(xs), sum(ys)/len(ys), sum(zs)/len(zs)
    # bbox size
    sx, sy, sz = max(xs)-min(xs), max(ys)-min(ys), max(zs)-min(zs)
    longest = max(sx, sy, sz)
    # Weapon: very long along one axis and thin on others, and centered near rifle position (in front)
    # Hunyuan wanzer: bounds ~1.58x1.96x1.21, rifle along Z, y ~0.3, thin
    is_long = longest > 0.9 and min(sx, sy, sz) < 0.18
    if is_long and abs(cy) < 0.6 and cz > 0.35:
        return "weapon"
    if cy > 0.55:
        return "head"
    if cy < -0.05:
        return "legs"  # combined legs
    if cx < -0.28:
        return "arm_left"
    if cx > 0.28:
        return "arm_right"
    return "body"

# Group loose parts
groups = {"head":[], "body":[], "arm_left":[], "arm_right":[], "legs":[], "weapon":[]}
for o in loose:
    slot = classify(o)
    groups[slot].append(o)
    print(f"  {o.name} centroid classified as {slot}")

# Join per slot
import collections
for slot, objs in groups.items():
    if not objs:
        print(f"[Skip] {slot} empty")
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    slot_obj = bpy.context.view_layer.objects.active
    # Reset origin to center of mass (median)
    bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='MEDIAN')
    # Also apply location to 0,0,0? Keep world position but origin centered
    # For Godot, pivot should be at slot joint: we keep origin at geometry center as requested
    # Export
    # Map slot name to Godot path
    godot_slot_map = {
        "head":"head",
        "body":"body",
        "arm_left":"arm_left",
        "arm_right":"arm_right",
        "legs":"leg_left",  # we save legs as leg_left for now, also duplicate to leg_right? But request says Legs single
        "weapon":"body",  # weapon saved alongside body as separate, use body folder with weapon name
    }
    # Decide output filenames
    if slot == "legs":
        # Save as wanzer_legs.glb to body? Actually legs should be in leg_left and leg_right? For this 6-part spec we save combined
        out_name = "wanzer_legs.glb"
        out_dir = proj / "scenes" / "mecha" / "parts" / "leg_left"
        asset_name = "wanzer_legs.glb"
    elif slot == "weapon":
        out_name = "wanzer_weapon.glb"
        out_dir = proj / "assets" / "models"
        asset_name = "wanzer_weapon.glb"
    else:
        out_name = f"wanzer_{slot}_blender.glb"
        out_dir = proj / "scenes" / "mecha" / "parts" / godot_slot_map[slot]
        asset_name = f"wanzer_{slot}_blender.glb"

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / out_name
    # Select only this object for export
    bpy.ops.object.select_all(action='DESELECT')
    slot_obj.select_set(True)
    bpy.context.view_layer.objects.active = slot_obj
    bpy.ops.export_scene.gltf(filepath=str(out_path), export_format='GLB', export_apply=True)
    print(f"[Export] {slot} -> {out_path} ({out_path.stat().st_size} bytes)")

    # Also copy to assets/models for preview
    asset_path = proj / "assets" / "models" / asset_name
    if asset_path != out_path:
        import shutil
        shutil.copy(str(out_path), str(asset_path))
        print(f"  copied to {asset_path}")

    # Also create .tscn wrapper and .tres for Godot (optional)
    if slot in ("head","body","arm_left","arm_right"):
        tscn_dir = proj / "scenes" / "mecha" / "parts" / godot_slot_map[slot]
        tscn_path = tscn_dir / f"wanzer_{slot}_blender.tscn"
        glb_res = f"res://scenes/mecha/parts/{godot_slot_map[slot]}/{out_name}"
        with open(tscn_path,"w",encoding="utf-8") as f:
            f.write("[gd_scene format=3]\n")
            f.write(f'[ext_resource type="PackedScene" path="{glb_res}" id="1"]\n')
            f.write(f'[node name="wanzer_{slot}_blender" type="Node3D"]\n')
            f.write('[node name="Model" parent="." instance=ExtResource("1")]\n')
        print(f"  tscn {tscn_path}")

print("[Done] Separate by Loose Parts + Origin Reset complete")

