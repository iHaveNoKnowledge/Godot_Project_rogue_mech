"""Mecha Kitbash Hard Surface Component pack (game meters).
Each component: origin at mounting face (z=0), detail extends +Z.
Materials: KitDark (gunmetal), KitMid (steel), KitGlow (emissive orange).
Run in Blender: exec(open(<this file>).read()); build_all()
Output: assets/kitbash/mech_kit_*.glb + assets/kitbash/mech_kitbash.blend
"""
import bpy
import os
import math

PROJ = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
OUTDIR = os.path.join(PROJ, "assets", "kitbash")


def get_materials():
    md = bpy.data.materials.new("KitDark")
    md.use_nodes = True
    b = md.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.09, 0.09, 0.11, 1.0)
    b.inputs["Metallic"].default_value = 0.85
    b.inputs["Roughness"].default_value = 0.45

    mm = bpy.data.materials.new("KitMid")
    mm.use_nodes = True
    b2 = mm.node_tree.nodes["Principled BSDF"]
    b2.inputs["Base Color"].default_value = (0.35, 0.36, 0.38, 1.0)
    b2.inputs["Metallic"].default_value = 0.6
    b2.inputs["Roughness"].default_value = 0.5

    mg = bpy.data.materials.new("KitGlow")
    mg.use_nodes = True
    b3 = mg.node_tree.nodes["Principled BSDF"]
    b3.inputs["Base Color"].default_value = (0.96, 0.52, 0.10, 1.0)
    b3.inputs["Metallic"].default_value = 0.1
    b3.inputs["Roughness"].default_value = 0.35
    b3.inputs["Emission Color"].default_value = (0.96, 0.52, 0.10, 1.0)
    b3.inputs["Emission Strength"].default_value = 3.0
    return md, mm, mg


def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()


def box(loc, size, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.view_layer.objects.active
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if mat is not None:
        o.data.materials.append(mat)
    return o


def cyl(loc, r, h, verts=12, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h,
                                        location=loc, rotation=rot)
    o = bpy.context.view_layer.objects.active
    if mat is not None:
        o.data.materials.append(mat)
    return o


def sph(loc, r, mat=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=12, ring_count=8)
    o = bpy.context.view_layer.objects.active
    if mat is not None:
        o.data.materials.append(mat)
    return o


def finish2(name, bevel_w=0.002):
    bpy.ops.object.select_all(action='SELECT')
    if not bpy.context.selected_objects:
        return None
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel_w > 0:
        md = o.modifiers.new("bev", 'BEVEL')
        md.width = bevel_w
        md.segments = 2
        md.limit_method = 'ANGLE'
        bpy.ops.object.modifier_apply(modifier=md.name)
    for p in o.data.polygons:
        p.use_smooth = False
    mw = o.modifiers.new("wn", 'WEIGHTED_NORMAL')
    mw.weight = 50
    bpy.ops.object.modifier_apply(modifier=mw.name)
    return o


def finish(name, bevel_w=0.002):
    return finish2(name, bevel_w)


def export_now(o):
    export(o)
    return o


def export(o):
    os.makedirs(OUTDIR, exist_ok=True)
    out = os.path.join(OUTDIR, o.name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=True,
                              export_apply=True, export_materials='EXPORT')
    print("KIT %s: verts=%d polys=%d" % (o.name, len(o.data.vertices), len(o.data.polygons)))


def build_all():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.materials):
        bpy.data.materials.remove(m, do_unlink=True)
    MD, MM, MG = get_materials()
    B = []

    # 1-2. bolts
    clear(); cyl((0, 0, 0.004), 0.016, 0.008, 12, mat=MD); cyl((0, 0, 0.012), 0.010, 0.016, 6, mat=MD)
    B.append(export_now(finish2("mech_kit_bolt_small")))
    clear(); cyl((0, 0, 0.006), 0.030, 0.012, 16, mat=MD); cyl((0, 0, 0.022), 0.019, 0.032, 6, mat=MD)
    B.append(export_now(finish2("mech_kit_bolt_large")))
    # 3. rivet strip
    clear()
    box((0, 0, 0.003), (0.20, 0.05, 0.006), mat=MD)
    for i in range(5):
        sph((-0.08 + i * 0.04, 0, 0.006), 0.011, mat=MM)
    B.append(export_now(finish2("mech_kit_rivet_strip")))
    # 4. round vent
    clear()
    cyl((0, 0, 0.006), 0.055, 0.012, 20, mat=MD)
    cyl((0, 0, 0.004), 0.046, 0.014, 20, mat=MD)
    for i in range(4):
        box((0, 0, 0.012), (0.088, 0.012, 0.006), rot=(0, 0, i * math.pi / 4), mat=MM)
    B.append(export_now(finish2("mech_kit_vent_circle")))
    # 5. exhaust grille
    clear()
    box((0, 0, 0.008), (0.20, 0.12, 0.016), mat=MD)
    box((0, 0, 0.010), (0.17, 0.09, 0.020), mat=MD)
    for i in range(4):
        box((-0.06375 + i * 0.0425, 0, 0.020), (0.014, 0.086, 0.006), mat=MM)
    B.append(export_now(finish2("mech_kit_exhaust_grille")))
    # 6. flat plate with corner bolts
    clear()
    box((0, 0, 0.006), (0.26, 0.18, 0.012), mat=MM)
    box((0, 0, 0.013), (0.22, 0.14, 0.004), mat=MM)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl((sx * 0.10, sy * 0.065, 0.016), 0.012, 0.008, 6, mat=MD)
    B.append(export_now(finish2("mech_kit_plate_flat")))
    # 7. angled plate
    clear()
    box((-0.05, 0, 0.010), (0.14, 0.18, 0.014), mat=MM)
    box((0.075, 0, 0.035), (0.13, 0.18, 0.014), rot=(0, math.radians(-35), 0), mat=MM)
    B.append(export_now(finish2("mech_kit_plate_angled")))
    # 8. corner guard
    clear()
    box((0, -0.035, 0.05), (0.16, 0.03, 0.10), mat=MD)
    box((0, 0.035, 0.05), (0.16, 0.03, 0.10), mat=MD)
    box((0, 0, 0.005), (0.16, 0.10, 0.010), mat=MD)
    cyl((0, 0, 0.02), 0.014, 0.03, 6, mat=MM)
    B.append(export_now(finish2("mech_kit_corner_guard")))
    # 9. hydraulic piston
    clear()
    cyl((0, 0, 0.020), 0.028, 0.040, 14, mat=MD)
    cyl((0, 0, 0.065), 0.013, 0.080, 10, mat=MM)
    sph((0, 0, 0.108), 0.016, mat=MM)
    box((0, 0, 0.004), (0.07, 0.07, 0.008), mat=MD)
    B.append(export_now(finish2("mech_kit_piston")))
    # 10. ball joint
    clear()
    box((0, 0, 0.010), (0.09, 0.09, 0.020), mat=MD)
    sph((0, 0, 0.045), 0.030, mat=MM)
    cyl((0, 0, 0.085), 0.014, 0.060, 10, mat=MD)
    B.append(export_now(finish2("mech_kit_ball_joint")))
    # 11. sensor eye
    clear()
    box((0, 0, 0.008), (0.09, 0.09, 0.016), mat=MD)
    cyl((0, 0, 0.018), 0.028, 0.012, 16, mat=MD)
    cyl((0, 0, 0.024), 0.020, 0.006, 16, mat=MG)
    B.append(export_now(finish2("mech_kit_sensor_eye")))
    # 12. light bar
    clear()
    box((0, 0, 0.010), (0.22, 0.05, 0.020), mat=MD)
    box((0, 0, 0.020), (0.19, 0.032, 0.006), mat=MG)
    B.append(export_now(finish2("mech_kit_light_bar")))
    # 13. antenna stub
    clear()
    cyl((0, 0, 0.008), 0.022, 0.016, 12, mat=MD)
    cyl((0, 0, 0.14), 0.005, 0.26, 8, mat=MD)
    sph((0, 0, 0.272), 0.008, mat=MG)
    B.append(export_now(finish2("mech_kit_antenna_stub")))
    # 14. antenna fin
    clear()
    box((0, 0, 0.004), (0.10, 0.05, 0.008), mat=MD)
    box((0, 0.008, 0.13), (0.012, 0.10, 0.26), rot=(math.radians(-8), 0, 0), mat=MM)
    box((0, 0.018, 0.20), (0.014, 0.03, 0.10), rot=(math.radians(-8), 0, 0), mat=MG)
    B.append(export_now(finish2("mech_kit_antenna_fin")))
    # 15. periscope
    clear()
    cyl((0, 0, 0.05), 0.020, 0.10, 12, mat=MD)
    box((0, 0.015, 0.115), (0.07, 0.09, 0.05), rot=(math.radians(-20), 0, 0), mat=MM)
    box((0, 0.048, 0.108), (0.05, 0.012, 0.03), rot=(math.radians(-20), 0, 0), mat=MG)
    B.append(export_now(finish2("mech_kit_periscope")))
    # 16. thruster nozzle
    clear()
    cyl((0, 0, 0.020), 0.055, 0.040, 18, mat=MD)
    cyl((0, 0, 0.052), 0.038, 0.030, 18, rot=(math.pi, 0, 0), mat=MM)
    cyl((0, 0, 0.058), 0.026, 0.008, 18, mat=MD)
    box((0, 0, 0.004), (0.13, 0.13, 0.008), mat=MD)
    B.append(export_now(finish2("mech_kit_thruster_nozzle")))
    # 17. hardpoint rail
    clear()
    box((0, 0, 0.008), (0.26, 0.06, 0.016), mat=MD)
    for i in range(3):
        box((-0.08 + i * 0.08, 0, 0.020), (0.03, 0.05, 0.012), mat=MM)
    B.append(export_now(finish2("mech_kit_hardpoint_rail")))
    # 18. greeble cluster
    clear()
    box((0, 0, 0.010), (0.22, 0.22, 0.020), mat=MD)
    box((-0.06, 0.03, 0.035), (0.08, 0.10, 0.05), mat=MM)
    box((0.055, -0.04, 0.030), (0.09, 0.07, 0.04), rot=(0, 0, 0.4), mat=MM)
    cyl((0.02, 0.06, 0.045), 0.018, 0.07, 10, mat=MD)
    cyl((-0.02, -0.07, 0.028), 0.012, 0.05, 8, mat=MG)
    box((0.075, 0.055, 0.026), (0.05, 0.05, 0.016), mat=MD)
    B.append(export_now(finish2("mech_kit_greeble_cluster")))

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    import glob as _glob
    for _g in sorted(_glob.glob(os.path.join(OUTDIR, "mech_kit_*.glb"))):
        bpy.ops.import_scene.gltf(filepath=_g)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUTDIR, "mech_kitbash.blend"))
    print("SAVED mech_kitbash.blend, %d components" % len([o for o in B if o is not None]))


if __name__ == "__main__":
    build_all()
