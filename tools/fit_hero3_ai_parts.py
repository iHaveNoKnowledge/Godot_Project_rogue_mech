"""
Fit TRELLIS-2 AI part meshes (head/torso/armL/legL) to Hero3 game rig:
rotate to +Y-forward, scale to true meters, mirror right side, split limbs
at elbow/knee with overlap band, set pivot origins, export 10 game GLBs.

Run inside Blender (Blender MCP): exec(open(<this file>).read()); fit_all()
"""

import bpy
import os
from mathutils import Vector, Matrix

OUT3D = r"Z:\comfyUI\raiwanan\output\3d"
BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
PARTS_DIR = os.path.join(BASE_DIR, "scenes", "mecha", "parts")

SRC = {
    "head": os.path.join(OUT3D, "hero3_head_00001.glb"),
    "torso": os.path.join(OUT3D, "hero3_torso_00001.glb"),
    "armL": os.path.join(OUT3D, "hero3_armL_00001.glb"),
    "legL": os.path.join(OUT3D, "hero3_legL_00001.glb"),
}

# (target Blender size axis, target size) + placement + pivot
SPEC = {
    "head": {"axis": 0, "size": 0.72, "place": ("min_z", 3.62), "cx": 0.0, "cy": 0.02,
             "pivot": (0, 0.0672, 3.864), "file": ("head", "hero3_head")},
    "torso": {"axis": 2, "size": 1.80, "place": ("min_z", 2.02), "cx": 0.0, "cy": 0.0,
              "pivot": (0, 0, 3.024), "file": ("body", "hero3_body")},
    "armL": {"axis": 2, "size": 1.50, "place": ("max_z", 3.62), "cx": -1.14, "cy": 0.0,
             "pivot_up": (-1.1424, 0, 3.444), "pivot_lo": (-1.1424, 0, 2.8056),
             "split_z": 2.8056,
             "file_up": ("arm_left", "hero3_arm_left_upper"),
             "file_lo": ("arm_left", "hero3_arm_left_lower")},
    "legL": {"axis": 2, "size": 2.16, "place": ("min_z", 0.02), "cx": -0.64, "cy": 0.03,
             "pivot_up": (-0.6384, 0, 2.184), "pivot_lo": (-0.6384, 0, 1.26),
             "split_z": 1.26,
             "file_up": ("leg_left", "hero3_leg_left_upper"),
             "file_lo": ("leg_left", "hero3_leg_left_lower")},
}

ELBOW_Z = 2.8056
KNEE_Z = 1.26


def clean_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me, do_unlink=True)


def select_only(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def world_bbox(obj):
    ws = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    mn = [min(v[i] for v in ws) for i in range(3)]
    mx = [max(v[i] for v in ws) for i in range(3)]
    return mn, mx


def import_part(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
    if len(new) > 1:
        bpy.ops.object.select_all(action='DESELECT')
        for o in new:
            o.select_set(True)
        bpy.context.view_layer.objects.active = new[0]
        bpy.ops.object.join()
        return bpy.context.view_layer.objects.active
    return new[0]


def prep_mesh(obj, target_faces=25000):
    select_only(obj)
    # face +Y forward (TRELLIS comes facing -Y)
    obj.rotation_euler = (0, 0, 3.14159265)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    # decimate
    faces = len(obj.data.polygons)
    if faces > target_faces:
        dec = obj.modifiers.new("dec", 'DECIMATE')
        dec.ratio = target_faces / faces
        dec.use_collapse_triangulate = True
        bpy.ops.object.modifier_apply(modifier="dec")
    # flat shade + edge split
    for p in obj.data.polygons:
        p.use_smooth = False
    es = obj.modifiers.new("es", 'EDGE_SPLIT')
    es.split_angle = 0.5236
    bpy.ops.object.modifier_apply(modifier="es")
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return obj


def scale_to(obj, axis, size):
    mn, mx = world_bbox(obj)
    cur = (mx[axis] - mn[axis]) or 1e-6
    s = size / cur
    obj.scale = (obj.scale[0] * s, obj.scale[1] * s, obj.scale[2] * s)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def move_so(obj, mode, value, cx, cy):
    select_only(obj)
    mn, mx = world_bbox(obj)
    dx = cx - (mn[0] + mx[0]) / 2
    dy = cy - (mn[1] + mx[1]) / 2
    if mode == "min_z":
        dz = value - mn[2]
    else:
        dz = value - mx[2]
    obj.location = (obj.location[0] + dx, obj.location[1] + dy, obj.location[2] + dz)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


def set_pivot(obj, pivot):
    # tankhead convention: origin stays (0,0,0) == pivot BY CONSTRUCTION.
    # Geometry is currently in world coords -> bake -pivot into verts.
    select_only(obj)
    obj.data.transform(Matrix.Translation((-pivot[0], -pivot[1], -pivot[2])))
    obj.data.update()
    obj.location = (0, 0, 0)


def export_obj(obj, slot, name):
    select_only(obj)
    path = os.path.join(PARTS_DIR, slot, name + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_apply=True, export_materials='EXPORT', export_normals=True)
    print("EXPORTED %s faces=%d" % (path, len(obj.data.polygons)))


def mirror_copy(obj, name):
    dup = obj.copy()
    dup.data = obj.data.copy()
    bpy.context.collection.objects.link(dup)
    dup.name = name
    select_only(dup)
    dup.scale.x = -1.0
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return dup


def split_limb(obj, split_z, overlap=0.04):
    select_only(obj)
    up = obj
    lo = obj.copy()
    lo.data = obj.data.copy()
    bpy.context.collection.objects.link(lo)
    # upper keeps z >= split - overlap
    select_only(up)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.bisect(plane_co=(0, 0, split_z - overlap), plane_no=(0, 0, -1),
                        clear_inner=True, clear_outer=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    # lower keeps z <= split + overlap
    select_only(lo)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.bisect(plane_co=(0, 0, split_z + overlap), plane_no=(0, 0, 1),
                        clear_inner=True, clear_outer=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return up, lo


def fit_all():
    clean_scene()
    print("=== Fitting Hero3 AI parts ===")

    # ---- HEAD ----
    s = SPEC["head"]
    head = import_part(SRC["head"])
    prep_mesh(head)
    scale_to(head, s["axis"], s["size"])
    move_so(head, s["place"][0], s["place"][1], s["cx"], s["cy"])
    set_pivot(head, s["pivot"])
    export_obj(head, *s["file"])

    # ---- TORSO ----
    s = SPEC["torso"]
    torso = import_part(SRC["torso"])
    prep_mesh(torso, target_faces=40000)
    scale_to(torso, s["axis"], s["size"])
    move_so(torso, s["place"][0], s["place"][1], s["cx"], s["cy"])
    set_pivot(torso, s["pivot"])
    export_obj(torso, *s["file"])

    # ---- ARM (left, then mirror) ----
    s = SPEC["armL"]
    arm = import_part(SRC["armL"])
    prep_mesh(arm, target_faces=30000)
    scale_to(arm, s["axis"], s["size"])
    move_so(arm, s["place"][0], s["place"][1], s["cx"], s["cy"])
    armR = mirror_copy(arm, "armR_full")
    for side_obj, piv_up, piv_lo, f_up, f_lo, x_sign in [
            (arm, s["pivot_up"], s["pivot_lo"], s["file_up"], s["file_lo"], -1),
            (armR, (1.1424, 0, 3.444), (1.1424, 0, 2.8056),
             ("arm_right", "hero3_arm_right_upper"),
             ("arm_right", "hero3_arm_right_lower"), 1)]:
        # recenter mirrored copy on +X
        if x_sign > 0:
            select_only(side_obj)
            mn, mx = world_bbox(side_obj)
            side_obj.location.x += 1.14 - (mn[0] + mx[0]) / 2
            bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        up, lo = split_limb(side_obj, s["split_z"])
        set_pivot(up, piv_up)
        export_obj(up, *f_up)
        set_pivot(lo, piv_lo)
        export_obj(lo, *f_lo)

    # ---- LEG (left, then mirror) ----
    s = SPEC["legL"]
    leg = import_part(SRC["legL"])
    prep_mesh(leg, target_faces=30000)
    scale_to(leg, s["axis"], s["size"])
    move_so(leg, s["place"][0], s["place"][1], s["cx"], s["cy"])
    legR = mirror_copy(leg, "legR_full")
    for side_obj, piv_up, piv_lo, f_up, f_lo, x_sign in [
            (leg, s["pivot_up"], s["pivot_lo"], s["file_up"], s["file_lo"], -1),
            (legR, (0.6384, 0, 2.184), (0.6384, 0, 1.26),
             ("leg_right", "hero3_leg_right_upper"),
             ("leg_right", "hero3_leg_right_lower"), 1)]:
        if x_sign > 0:
            select_only(side_obj)
            mn, mx = world_bbox(side_obj)
            side_obj.location.x += 0.64 - (mn[0] + mx[0]) / 2
            bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
        up, lo = split_limb(side_obj, s["split_z"])
        set_pivot(up, piv_up)
        export_obj(up, *f_up)
        set_pivot(lo, piv_lo)
        export_obj(lo, *f_lo)

    print("=== Fit done: 10 game GLBs ===")


if __name__ == "__main__":
    fit_all()
