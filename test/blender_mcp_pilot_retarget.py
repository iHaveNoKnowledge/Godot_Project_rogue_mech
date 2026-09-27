"""Retarget pistol actions from AF_Rig (ground truth) onto both pilot rigs.

Root cause (measured): actions were authored/baked on AF_Rig, then copied
verbatim to Pilot_Character(.001) whose arm-bone rest orientations differ -
same local quats produced the sky-pointing arms. AF_Rig + its mesh evaluate
correctly (upright 8.9 deg spine, hand pointing -Y forward), so it is the
authoritative source.

Method (per rig, per action, per frame):
 1. Restore the action from its _BAK copy (disk state is still broken).
 2. Drop junk fcurves (thumb_04_leaf_*).
 3. Closure bones = animated + all their ancestors.
 4. Play the action on AF_Rig; read every closure bone's evaluated
    armature-space matrix (both rigs sit at identity, so armature spaces
    are directly comparable).
 5. On the target, parent-first: basis = K(bone)^-1 @ A_AF(parent)^-1 @ A_AF(bone)
    with K(bone) = A_rest(parent)^-1 @ A_rest(bone) from the REST pose
    (full 4x4, covers rotation AND location).
 6. Key rotation_quaternion + location on all closure bones.
Then: scale both pistols to 0.19 m, re-seat in hand_r with scale preserved,
verify spine tilt / hand direction match AF / bboxes, save.

Usage: python test/blender_mcp_pilot_retarget.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Matrix, Vector

OB = bpy.data.objects
scn = bpy.context.scene
AF = OB["AF_Rig"]

def all_fcurves(a):
    out = []
    try:
        out.extend(a.fcurves)
        return out
    except AttributeError:
        pass
    for layer in a.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out

def channelbag(a):
    for layer in a.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                return cb
    return None

def by_path(fcs):
    d = {}
    for fc in fcs:
        d.setdefault(fc.data_path, {})[fc.array_index] = fc
    return d

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

def depth(pb):
    n = 0
    b = pb
    while b.parent:
        n += 1
        b = b.parent
    return n

def restore_from_bak(act_name):
    bak = bpy.data.actions.get(act_name + "_BAK")
    if not bak:
        print("  !! no _BAK for", act_name)
        return
    act = bpy.data.actions[act_name]
    cb_dst = channelbag(act)
    cb_src = channelbag(bak)
    for fc in list(cb_dst.fcurves):
        cb_dst.fcurves.remove(fc)
    for fc in cb_src.fcurves:
        n = cb_dst.fcurves.new(data_path=fc.data_path, index=fc.array_index)
        n.keyframe_points.add(len(fc.keyframe_points))
        for i, kp in enumerate(fc.keyframe_points):
            n.keyframe_points[i].co = kp.co
            n.keyframe_points[i].interpolation = kp.interpolation
            n.keyframe_points[i].easing = kp.easing
        n.update()

def copy_action_from(src_action, dst_action):
    cb_dst = channelbag(dst_action)
    cb_src = channelbag(src_action)
    for fc in list(cb_dst.fcurves):
        cb_dst.fcurves.remove(fc)
    for fc in cb_src.fcurves:
        n = cb_dst.fcurves.new(data_path=fc.data_path, index=fc.array_index)
        n.keyframe_points.add(len(fc.keyframe_points))
        for i, kp in enumerate(fc.keyframe_points):
            n.keyframe_points[i].co = kp.co
            n.keyframe_points[i].interpolation = kp.interpolation
            n.keyframe_points[i].easing = kp.easing
        n.update()

AF_AD = AF.animation_data
af_orig_action = AF_AD.action

JOBS = [
    ("Pilot_Character", "Pilot_SWAT",
     ["pistol_idle", "pistol_reload", "pistol_shoot"]),
    ("Pilot_Character.001", "Swat_Body.001",
     ["pistol_idle.001", "pistol_reload.001", "pistol_shoot.001"]),
]

for rig_name, mesh_name, actions in JOBS:
    rig = OB[rig_name]
    ad = rig.animation_data
    print("=== RETARGET %s ===" % rig_name)
    for act_name in actions:
        restore_from_bak(act_name)
        act = bpy.data.actions[act_name]
        ad.action = act
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        cb = channelbag(act)
        removed = 0
        if cb:
            for fc in list(cb.fcurves):
                if "pose.bones[" in fc.data_path:
                    bn = fc.data_path.split('"')[1]
                    if bn not in rig.pose.bones:
                        cb.fcurves.remove(fc)
                        removed += 1
        paths = by_path(all_fcurves(act))
        anim_names = set(p.split('"')[1] for p in paths if "pose.bones[" in p
                         and ".rotation_quaternion" in p)
        closure = set()
        for pb in rig.pose.bones:
            if pb.name in anim_names:
                b = pb
                while b:
                    closure.add(b.name)
                    b = b.parent
        closure -= set(b.name for b in rig.pose.bones if b.name.endswith("_end")
                       and b.name not in anim_names)
        bones = sorted([rig.pose.bones[n] for n in closure], key=depth)
        # K from REST pose (full 4x4)
        rig.data.pose_position = "REST"
        bpy.context.view_layer.update()
        K = {}
        for pb in bones:
            par = pb.parent
            rest = rig.data.bones[pb.name].matrix_local
            if par:
                K[pb.name] = rig.data.bones[par.name].matrix_local.inverted() @ rest
            else:
                K[pb.name] = rest
        rig.data.pose_position = "POSE"
        bpy.context.view_layer.update()
        # per frame: AF ground truth -> target bases parent-first
        for f in range(f0, f1 + 1):
            AF_AD.action = act
            scn.frame_set(f)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev_af = AF.evaluated_get(dg)
            af_m = {}
            for name in closure:
                af_m[name] = (ev_af.pose.bones[name].matrix.copy()
                              if name in ev_af.pose.bones else Matrix.Identity(4))
            for pb in bones:
                par = pb.parent
                par_af = af_m[par.name] if par else Matrix.Identity(4)
                basis = K[pb.name].inverted() @ (par_af.inverted() @ af_m[pb.name])
                pb.matrix_basis = basis
            bpy.context.view_layer.update()
            for pb in bones:
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        print("%s: retargeted frames %d..%d (%d closure bones, junk removed: %d)"
              % (act_name, f0, f1, len(bones), removed))
    ad.action = None

AF_AD.action = af_orig_action
scn.frame_set(0)
bpy.context.view_layer.update()

print("=== pistol scale fix (0.19 m) + re-seat (scale preserved) ===")
for pname, aname in [("PistolProp", "Pilot_Character"), ("PistolProp.001", "Pilot_Character.001")]:
    p = OB[pname]
    rig = OB[aname]
    cur = max(p.dimensions)
    s = 0.19 / cur
    p.scale = (p.scale.x * s, p.scale.y * s, p.scale.z * s)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    hw = (rig.evaluated_get(dg).pose.bones["hand_r"].matrix @ rig.matrix_world)
    fwd = Vector((0.0, -1.0, 0.0))
    rot = Matrix.Rotation(math.pi, 4, "X") @ Matrix.LocRotScale(None, fwd.to_track_quat("Z", "Y"), None)
    want = Matrix.Translation(hw.translation + Vector((0, -0.035, 0)) + fwd * 0.02) \
        @ rot @ Matrix.LocRotScale(None, None, p.scale)
    actual = p.matrix_world.copy()
    M = actual @ p.matrix_basis.inverted()
    p.matrix_basis = M.inverted() @ want
    bpy.context.view_layer.update()
    err = (p.matrix_world.translation - want.translation).length
    print("%s: scale x%.4f dims=(%.3f,%.3f,%.3f) | seated err=%.5f | bone=%s"
          % (pname, s, p.dimensions.x, p.dimensions.y, p.dimensions.z, err, p.parent_bone))

print("=== VERIFY ===")
scn.frame_set(0)
bpy.context.view_layer.update()
def ydir(rig, bone):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = rig.evaluated_get(dg)
    m = ev.pose.bones[bone].matrix @ rig.matrix_world
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()
for rn, mn in (("AF_Rig", "PilotMesh_OK"),
               ("Pilot_Character", "Pilot_SWAT"),
               ("Pilot_Character.001", "Swat_Body.001")):
    r = OB[rn]
    hd = ydir(r, "hand_r")
    b = bbox(OB[mn])
    print("%s: hand_r Y-dir=[%.2f,%.2f,%.2f] | mesh Yspan=%.3f Z=%.3f..%.3f"
          % (rn, hd.x, hd.y, hd.z, b[1] - b[0], b[2], b[3]))

bpy.ops.wm.save_mainfile()
print("saved:", bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
