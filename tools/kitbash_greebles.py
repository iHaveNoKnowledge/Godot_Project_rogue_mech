"""Procedural hard-surface greeble kit (game meters). Headless Blender:
  blender --background --python tools/kitbash_greebles.py
Output: assets/kitbash/kit_<name>.glb + kitbash.blend (all with dark-metal material).
"""
import bpy, os, math

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTDIR = os.path.join(PROJ, "assets", "kitbash")
os.makedirs(OUTDIR, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

mat = bpy.data.materials.new("KitbashDark")
mat.use_nodes = True
bsdf = mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.09, 0.09, 0.11, 1.0)
bsdf.inputs["Metallic"].default_value = 0.85
bsdf.inputs["Roughness"].default_value = 0.45


def finish(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    md = obj.modifiers.new("bev", 'BEVEL')
    md.width = 0.003
    md.segments = 2
    md.limit_method = 'ANGLE'
    bpy.ops.object.modifier_apply(modifier=md.name)
    for p in obj.data.polygons:
        p.use_smooth = True
        p.material_index = 0
    if len(obj.data.materials) == 0:
        obj.data.materials.append(mat)
    else:
        obj.data.materials[0] = mat
    mw = obj.modifiers.new("wn", 'WEIGHTED_NORMAL')
    mw.weight = 50
    bpy.ops.object.modifier_apply(modifier=mw.name)
    return obj


def join_all(name):
    bpy.ops.object.select_all(action='SELECT')
    bpy.context.view_layer.objects.active = bpy.context.scene.objects[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return finish(o)


def box(loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.view_layer.objects.active
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return o


def cyl(loc, r, h, verts=12, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h,
                                        location=loc, rotation=rot)
    return bpy.context.view_layer.objects.active


def build_vent():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    box((0, 0, 0.012), (0.16, 0.10, 0.024))          # frame
    for i in range(5):                                 # slats
        x = -0.056 + i * 0.028
        box((x, 0, 0.028), (0.016, 0.088, 0.006), rot=(0.5, 0, 0))
    box((0, 0, 0.002), (0.13, 0.075, 0.004))           # dark recess
    return join_all("kit_vent")


def build_bolt():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    cyl((0, 0, 0.004), 0.028, 0.008, 16)               # washer
    cyl((0, 0, 0.016), 0.018, 0.024, 6)                # hex head
    return join_all("kit_bolt")


def build_hinge():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    box((-0.035, 0, 0.006), (0.06, 0.05, 0.012))       # leaf L
    box((0.035, 0, 0.006), (0.06, 0.05, 0.012))        # leaf R
    cyl((0, 0, 0.014), 0.012, 0.11, 12, rot=(0, math.pi / 2, 0))  # pin
    return join_all("kit_hinge")


def build_intake():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    bpy.ops.mesh.primitive_torus_add(major_radius=0.05, minor_radius=0.016,
                                     major_segments=20, minor_segments=10,
                                     location=(0, 0, 0.016))
    cyl((0, 0, 0.004), 0.048, 0.008, 20)               # dark mouth
    return join_all("kit_intake")


def build_handle():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    cyl((-0.05, 0, 0.02), 0.009, 0.04, 10)             # post L
    cyl((0.05, 0, 0.02), 0.009, 0.04, 10)              # post R
    cyl((0, 0, 0.04), 0.009, 0.118, 10, rot=(0, math.pi / 2, 0))  # bar
    return join_all("kit_handle")


for build in (build_vent, build_bolt, build_hinge, build_intake, build_handle):
    o = build()
    out = os.path.join(OUTDIR, o.name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_apply=True, export_materials='EXPORT')
    print(f"KIT {o.name}: verts={len(o.data.vertices)} polys={len(o.data.polygons)} -> {out}")

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTDIR, "kitbash.blend"))
print("SAVED kitbash.blend")
