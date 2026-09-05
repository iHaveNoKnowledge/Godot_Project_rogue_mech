"""Build hard-surface pauldron concept (tan armor + dark vents + red trim), render white-bg.
Headless Blender: blender --background --python tools/kitbash_concept.py -- [out.png]
Default output matches the Trellis kitbash workflow input (Z:/comfyUI/raiwanan/input/kitbash_component.png).
"""
import bpy, os, sys, math

OUT = r"Z:\comfyUI\raiwanan\input\kitbash_component.png"
if "--" in sys.argv:
    _args = sys.argv[sys.argv.index("--") + 1:]
    if _args:
        OUT = _args[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

tan = bpy.data.materials.new("TanArmor")
tan.use_nodes = True
b = tan.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.72, 0.62, 0.47, 1.0)
b.inputs["Metallic"].default_value = 0.25
b.inputs["Roughness"].default_value = 0.55

dark = bpy.data.materials.new("DarkJoint")
dark.use_nodes = True
b = dark.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.08, 0.08, 0.10, 1.0)
b.inputs["Metallic"].default_value = 0.8
b.inputs["Roughness"].default_value = 0.5

red = bpy.data.materials.new("RedTrim")
red.use_nodes = True
b = red.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.65, 0.08, 0.06, 1.0)
b.inputs["Metallic"].default_value = 0.3
b.inputs["Roughness"].default_value = 0.5


def mat(o, m):
    if len(o.data.materials) == 0:
        o.data.materials.append(m)
    else:
        o.data.materials[0] = m


def bev(o, w=0.008):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    md = o.modifiers.new("bev", 'BEVEL')
    md.width = w
    md.segments = 2
    md.limit_method = 'ANGLE'
    bpy.ops.object.modifier_apply(modifier=md.name)
    for p in o.data.polygons:
        p.use_smooth = True
    mw = o.modifiers.new("wn", 'WEIGHTED_NORMAL')
    bpy.ops.object.modifier_apply(modifier=mw.name)


# main shell: half-dome scaled (pauldron cap)
bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5,
                                    location=(0, 0, 0.30))
shell = bpy.context.view_layer.objects.active
shell.scale = (1.0, 0.85, 0.62)
bpy.ops.object.transform_apply(scale=True)
# cut bottom half
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.mesh.bisect(plane_co=(0, 0, 0.30), plane_no=(0, 0, -1), clear_inner=True)
bpy.ops.object.mode_set(mode='OBJECT')
mat(shell, tan)
bev(shell, 0.012)

# top ridge plate
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.02, 0.60))
ridge = bpy.context.view_layer.objects.active
ridge.dimensions = (0.34, 0.30, 0.07)
bpy.ops.object.transform_apply(scale=True)
mat(ridge, tan)
bev(ridge, 0.01)

# red trim stripe across ridge
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.02, 0.645))
trim = bpy.context.view_layer.objects.active
trim.dimensions = (0.20, 0.31, 0.02)
bpy.ops.object.transform_apply(scale=True)
mat(trim, red)

# side vent (dark slats) on outer face
for i in range(4):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.42, -0.05 + i * 0.0, 0.30))
    s = bpy.context.view_layer.objects.active
    s.dimensions = (0.03, 0.20, 0.025)
    s.rotation_euler = (0, 0, 0.35)
    bpy.ops.object.transform_apply(rotation=True, scale=True)
    mat(s, dark)
# vent recess backing
bpy.ops.mesh.primitive_cube_add(size=1, location=(0.40, 0, 0.30))
vb = bpy.context.view_layer.objects.active
vb.dimensions = (0.02, 0.26, 0.16)
bpy.ops.object.transform_apply(scale=True)
mat(vb, dark)

# bolt row along front rim
for i in range(5):
    x = -0.28 + i * 0.14
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.022, depth=0.03,
                                        location=(x, 0.33, 0.16))
    bt = bpy.context.view_layer.objects.active
    bt.rotation_euler = (math.pi / 2.2, 0, 0)
    bpy.ops.object.transform_apply(rotation=True)
    mat(bt, dark)

# rear hinge blocks
for sx in (-1, 1):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(sx * 0.30, -0.30, 0.22))
    h = bpy.context.view_layer.objects.active
    h.dimensions = (0.12, 0.10, 0.10)
    bpy.ops.object.transform_apply(scale=True)
    mat(h, dark)
    bev(h, 0.008)

# white studio
if bpy.context.scene.world is None:
    bpy.context.scene.world = bpy.data.worlds.new("White")
world = bpy.context.scene.world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
scene.render.engine = 'BLENDER_EEVEE'
scene.eevee.taa_render_samples = 32
scene.render.resolution_x, scene.render.resolution_y = 1024, 1024
scene.render.film_transparent = False
bpy.ops.object.light_add(type='SUN', location=(3, 4, 6))

camd = bpy.data.cameras.new("c")
cam = bpy.data.objects.new("c", camd)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (1.8, 1.8, 1.1)
import mathutils
d = mathutils.Vector((0, 0, 0.32)) - cam.location
cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("CONCEPT ->", OUT)
