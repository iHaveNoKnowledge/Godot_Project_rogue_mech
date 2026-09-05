"""Procedural armor SHELLS over the inner frame (Blender coords: +Y front, +Z up).
Headless: blender --background --python tools/kitbash_shells.py
Exports 10 game-scale glbs (joint-relative) + saves Temp/kitbash_shells.blend.
"""
import bpy, os, math
import bmesh
from mathutils import Vector, Matrix, Quaternion

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLEND_OUT = r"C:\Users\hackd\AppData\Local\Temp\opencode\kitbash_shells.blend"

bpy.ops.wm.read_factory_settings(use_empty=True)


def pbr(name, color, metallic, rough):
    m = bpy.data.materials.new(name)
    # double-sided: shell plates are open surfaces; winding must never cull them
    try:
        m.show_double_sided = True
    except Exception:
        pass
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    return m


TAN = pbr("ShellTan", (0.72, 0.62, 0.47), 0.25, 0.55)
DARK = pbr("ShellDark", (0.08, 0.08, 0.10), 0.8, 0.5)
RED = pbr("ShellRed", (0.62, 0.07, 0.06), 0.3, 0.5)


def assign(o, m):
    if len(o.data.materials) == 0:
        o.data.materials.append(m)
    else:
        o.data.materials[0] = m


def finish(o, mat=TAN, bevel_w=0.004):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    for p in o.data.polygons:
        p.use_smooth = False
    assign(o, mat)
    if bevel_w > 0:
        md = o.modifiers.new("bev", 'BEVEL')
        md.width = bevel_w
        md.segments = 2
        md.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=md.name)
    mw = o.modifiers.new("wn", 'WEIGHTED_NORMAL')
    mw.weight = 50
    bpy.ops.object.modifier_apply(modifier=mw.name)
    return o


def delete_by_pred(o, pred):
    """Delete faces where pred(center, normal) is True. bmesh path (reliable)."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.faces.ensure_lookup_table()
    for f in bm.faces:
        c, n = f.calc_center_median(), f.normal
        f.select = bool(pred(c, n))
    bm.to_mesh(o.data)
    bm.free()
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.tool_settings.mesh_select_mode = (False, False, True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='FACE')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode='OBJECT')


def panel_cyl(name, loc, r, h, cover_deg=200, segs=8, thick=0.012, mat=TAN,
              front=Vector((0, 1, 0))):
    """Open-back curved plate around Z axis. front = outward direction kept."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=segs, radius=r, depth=h, location=loc)
    o = bpy.context.view_layer.objects.active
    o.name = name
    half = math.cos(math.radians(cover_deg / 2.0))
    delete_by_pred(o, lambda c, n: (Vector(n).dot(front) < half))
    md = o.modifiers.new("sol", 'SOLIDIFY')
    md.thickness = thick
    md.offset = 1.0
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)
    return finish(o, mat)


def dome(name, loc, r, squash=(1, 1, 1), mat=TAN, cut_below=None, cut_inner_x=None):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=14, ring_count=9, radius=r, location=loc)
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.scale = squash
    bpy.ops.object.transform_apply(scale=True)
    preds = []
    if cut_below is not None:
        preds.append(lambda c, n, z=cut_below: c.z < z)
    if cut_inner_x is not None:  # open toward torso (x greater than val, left side)
        preds.append(lambda c, n, x=cut_inner_x: c.x > x)
    if preds:
        delete_by_pred(o, lambda c, n: any(p(c, n) for p in preds))
    return finish(o, mat)


def plate(name, loc, size, rot=(0, 0, 0), mat=TAN):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish(o, mat)


def bolt(loc, normal):
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.02, depth=0.018, location=loc)
    o = bpy.context.view_layer.objects.active
    q = Vector((0, 0, 1)).rotation_difference(Vector(normal).normalized())
    o.rotation_euler = q.to_euler()
    bpy.ops.object.transform_apply(rotation=True)
    return finish(o, DARK, bevel_w=0.002)


def vent(loc, normal, w=0.13):
    parts = [plate("vtmp", (loc[0], loc[1], loc[2]), (w, 0.02, 0.10), mat=DARK)]
    # orient frame to normal later by caller rotation; build axis-aligned then rotate group
    return parts


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


FY = Vector((0, 1, 0))  # front

# ---------------- HEAD (joint H) ----------------
H = (0, 0.067, 3.864)
head_parts = [
    dome("h_dome", (0, 0.02, 4.02), 0.21, (1, 1, 1.1), TAN, cut_below=3.88),
    plate("h_visor", (0, 0.155, 4.03), (0.20, 0.05, 0.07), mat=RED),
    plate("h_crest", (0, -0.03, 4.26), (0.035, 0.24, 0.10)),
    plate("h_cheekL", (-0.135, 0.06, 3.95), (0.05, 0.10, 0.15), rot=(0, 0, 0.15)),
    plate("h_cheekR", (0.135, 0.06, 3.95), (0.05, 0.10, 0.15), rot=(0, 0, -0.15)),
    plate("h_chin", (0, 0.10, 3.89), (0.12, 0.08, 0.09)),
    bolt((-0.09, 0.14, 3.97), FY), bolt((0.09, 0.14, 3.97), FY),
]
HEAD = join(head_parts, "SHELL_head")

# ---------------- BODY (joint B) ----------------
B = (0, 0, 3.024)
chest = panel_cyl("b_chest", (0, 0, 3.60), 0.34, 0.66, cover_deg=200, segs=12)
delete_by_pred(chest, lambda c, n: abs(c.x) > 0.38)  # trim sides
back = panel_cyl("b_back", (0, 0, 3.60), 0.34, 0.60, cover_deg=120, segs=12,
                 front=Vector((0, -1, 0)))
collar = panel_cyl("b_collar", (0, 0, 3.95), 0.15, 0.10, cover_deg=360, segs=12)
waist = panel_cyl("b_waist", (0, 0, 3.05), 0.30, 0.12, cover_deg=360, segs=12)
pelvis = plate("b_pelvis", (0, 0.20, 2.75), (0.34, 0.10, 0.30), rot=(0.15, 0, 0))
body_parts = [chest, back, collar, waist, pelvis,
              bolt((-0.20, 0.30, 3.72), FY), bolt((0.20, 0.30, 3.72), FY),
              bolt((-0.20, 0.28, 3.42), FY), bolt((0.20, 0.28, 3.42), FY)]
BODY = join(body_parts, "SHELL_body")

# ---------------- ARM LEFT (upper S, lower E) ----------------
S = (-1.1424, 0, 3.444)
E = (-1.1424, 0, 2.8056)
pauldron = dome("a_paul", (-1.20, 0, 3.52), 0.30, (1, 0.9, 0.85), TAN,
                cut_below=3.38, cut_inner_x=-1.02)
uguard = panel_cyl("a_uguard", (-1.20, 0, 3.22), 0.21, 0.40, cover_deg=210)
ARM_L_UP = join([pauldron, uguard, bolt((-1.20, 0.20, 3.30), FY),
                 bolt((-1.20, 0.20, 3.12), FY)], "SHELL_armL_up")
elbow = dome("a_elbow", (-1.20, 0.02, 2.80), 0.13, mat=DARK)
fguard = panel_cyl("a_fguard", (-1.22, 0, 2.54), 0.22, 0.48, cover_deg=220)
fist = plate("a_fist", (-1.22, 0, 2.10), (0.15, 0.13, 0.15))
ARM_L_LO = join([elbow, fguard, fist, bolt((-1.22, 0.21, 2.62), FY),
                 bolt((-1.22, 0.21, 2.44), FY)], "SHELL_armL_lo")

# ---------------- LEG LEFT (upper Hip, lower Knee) ----------------
HIP = (-0.6384, 0, 2.184)
KN = (-0.6384, 0, 1.26)
thigh = panel_cyl("l_thigh", (-0.64, 0, 1.90), 0.27, 0.70, cover_deg=210, segs=10)
LEG_L_UP = join([thigh, bolt((-0.64, 0.26, 2.05), FY),
                 bolt((-0.64, 0.26, 1.75), FY)], "SHELL_legL_up")
knee = dome("l_knee", (-0.64, 0.03, 1.24), 0.15, mat=TAN)
shin = panel_cyl("l_shin", (-0.64, 0, 0.75), 0.24, 0.80, cover_deg=210, segs=10)
bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.14, depth=0.30,
                                    location=(-0.64, 0.15, 0.12),
                                    rotation=(math.pi / 2, 0, 0))
toe = bpy.context.view_layer.objects.active
toe.name = "l_toe"
finish(toe, TAN)
cuff = panel_cyl("l_cuff", (-0.64, 0, 0.24), 0.17, 0.12, cover_deg=360, segs=10)
LEG_L_LO = join([knee, shin, toe, cuff, bolt((-0.64, 0.23, 0.95), FY),
                 bolt((-0.64, 0.23, 0.60), FY)], "SHELL_legL_lo")


def mirror_x(o):
    """Bake world transform, mirror across WORLD x=0, keep right (x>0) half."""
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.duplicate()
    m = bpy.context.view_layer.objects.active
    md = m.modifiers.new("mir", 'MIRROR')
    md.use_axis[0] = True
    md.use_axis[1] = False
    md.use_axis[2] = False
    md.merge_threshold = 0.004
    bpy.ops.object.modifier_apply(modifier=md.name)
    # delete original (left, x<0) half
    bm = bmesh.new()
    bm.from_mesh(m.data)
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        v.select = (v.co.x < -0.001)
    bm.to_mesh(m.data)
    bm.free()
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.delete(type='VERT')
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return m


ARM_R_UP = mirror_x(ARM_L_UP); ARM_R_UP.name = "SHELL_armR_up"
ARM_R_LO = mirror_x(ARM_L_LO); ARM_R_LO.name = "SHELL_armR_lo"
LEG_R_UP = mirror_x(LEG_L_UP); LEG_R_UP.name = "SHELL_legR_up"
LEG_R_LO = mirror_x(LEG_L_LO); LEG_R_LO.name = "SHELL_legR_lo"

# ---------------- export (joint-relative) ----------------
JMAP = {"SHELL_head": H, "SHELL_body": B,
        "SHELL_armL_up": S, "SHELL_armL_lo": E,
        "SHELL_armR_up": (-S[0], S[1], S[2]), "SHELL_armR_lo": (-E[0], E[1], E[2]),
        "SHELL_legL_up": HIP, "SHELL_legL_lo": KN,
        "SHELL_legR_up": (-HIP[0], HIP[1], HIP[2]),
        "SHELL_legR_lo": (-KN[0], KN[1], KN[2])}
FN = {"SHELL_head": "kitbash_shell_head_001.glb",
      "SHELL_body": "kitbash_shell_body_001.glb",
      "SHELL_armL_up": "kitbash_shell_arm_left_001_upper.glb",
      "SHELL_armL_lo": "kitbash_shell_arm_left_001_lower.glb",
      "SHELL_armR_up": "kitbash_shell_arm_right_001_upper.glb",
      "SHELL_armR_lo": "kitbash_shell_arm_right_001_lower.glb",
      "SHELL_legL_up": "kitbash_shell_leg_left_001_upper.glb",
      "SHELL_legL_lo": "kitbash_shell_leg_left_001_lower.glb",
      "SHELL_legR_up": "kitbash_shell_leg_right_001_upper.glb",
      "SHELL_legR_lo": "kitbash_shell_leg_right_001_lower.glb"}
SLOT = {"SHELL_head": "head", "SHELL_body": "body",
        "SHELL_armL_up": "arm_left", "SHELL_armL_lo": "arm_left",
        "SHELL_armR_up": "arm_right", "SHELL_armR_lo": "arm_right",
        "SHELL_legL_up": "leg_left", "SHELL_legL_lo": "leg_left",
        "SHELL_legR_up": "leg_right", "SHELL_legR_lo": "leg_right"}

for key in ("SHELL_head", "SHELL_body", "SHELL_armL_up", "SHELL_armL_lo",
            "SHELL_armR_up", "SHELL_armR_lo", "SHELL_legL_up", "SHELL_legL_lo",
            "SHELL_legR_up", "SHELL_legR_lo"):
    o = bpy.data.objects[key]
    j = JMAP[key]
    # mesh verts are local (build pos lives in object.location): bake it first,
    # then express joint-relative. Otherwise export double-applies the offset.
    o.data.transform(Matrix.Translation((o.location[0], o.location[1], o.location[2])))
    o.location = (0, 0, 0)
    o.data.transform(Matrix.Translation((-j[0], -j[1], -j[2])))
    outdir = os.path.join(PROJ, "scenes", "mecha", "parts", SLOT[key])
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, FN[key])
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_apply=True, export_materials='EXPORT',
                              export_normals=True, export_texcoords=True)
    print(f"EXPORT {key}: polys={len(o.data.polygons)} -> {out} ({os.path.getsize(out)} bytes)")

bpy.ops.wm.save_as_mainfile(filepath=BLEND_OUT)
print("SAVED", BLEND_OUT)
