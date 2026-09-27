"""Re-bake original GLB animation onto both pilot rigs (final fix).

Math: glTF joint locals L(J) = K(J) @ B(J) with K(J) = A_rest(parent)^-1 @
A_rest(J) (rest chain, full 4x4) and B(J) = Blender bone-local basis.
So B(J) = K(J)^-1 @ L(J):
 - rig A restores the ORIGINAL animated basis exactly (the GLB was exported
   from this rig's rest chain);
 - rig B (.001) gets the exact rest-chain retarget (K_B^-1 @ K_A-equivalent
   via L, since L is armature-space motion in the same identity rig pose).

Source: C:/Users/hackd/AppData/Local/Temp/pilot_anim.json
(python test/extract_glb_anim.py - per-channel timelines, fps=30).

Steps: for each rig+clip - wipe pose fcurves, per frame set every joint's
matrix_basis = K^-1 @ L (rotation timeline; translation timeline separately,
defaulting to its first/last value), key rot+loc; verify the clip is
non-static (upperarm_r direction arc); then pose sanity, pistol rescale to
0.19 m, re-seat with scale preserved, save.

Usage: python test/blender_mcp_pilot_rebake.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

OB = bpy.data.objects
scn = bpy.context.scene
DATA = json.load(open("C:/Users/hackd/AppData/Local/Temp/pilot_anim.json"))

def sample(times, vals, t):
    if t <= times[0]:
        return vals[0]
    if t >= times[-1]:
        return vals[-1]
    for i in range(len(times) - 1):
        if times[i] <= t <= times[i + 1]:
            a = (t - times[i]) / (times[i + 1] - times[i])
            return [vals[i][k] + (vals[i + 1][k] - vals[i][k]) * a for k in range(len(vals[i]))]
    return vals[-1]

def locrot_to_matrix(t, q):
    return Matrix.Translation(Vector(t)) @ Quaternion([q[3], q[0], q[1], q[2]]).to_matrix().to_4x4()

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

def ydir(rig, ev, bone):
    m = ev.pose.bones[bone].matrix @ rig.matrix_world
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()

def rest_K(rig):
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    K = {}
    for bone in rig.data.bones:
        par = bone.parent
        own = bone.matrix_local.copy()
        K[bone.name] = (rig.data.bones[par.name].matrix_local.inverted() @ own) if par else own
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    return K

def wipe_pose_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in list(cb.fcurves):
                    if "pose.bones[" in fc.data_path:
                        cb.fcurves.remove(fc)

JOBS = [
    ("Pilot_Character", ["pistol_idle", "pistol_reload", "pistol_shoot"]),
    ("Pilot_Character.001", ["pistol_idle.001", "pistol_reload.001", "pistol_shoot.001"]),
]

for rig_name, clips in JOBS:
    rig = OB[rig_name]
    ad = rig.animation_data
    if ad is None:
        ad = rig.animation_data_create()
    orig = ad.action
    K = rest_K(rig)
    print("=== REBAKE %s ===" % rig_name)
    for clip in clips:
        joints = DATA[clip]
        act = bpy.data.actions.get(clip)
        if act is None:
            act = bpy.data.actions.new(clip)
            print("(recreated missing action: %s)" % clip)
        ad.action = act
        wipe_pose_fcurves(act)
        t_end = max(max(j["t_r"]) for j in joints.values())
        frames = list(range(0, int(round(t_end)) + 1))
        for f in frames:
            for jname, jd in joints.items():
                if jname not in rig.pose.bones:
                    continue
                q = sample(jd["t_r"], jd["r"], float(f)) if jd["r"] else (0, 0, 0, 1)
                t = sample(jd["t_tr"], jd["tr"], float(f)) if jd["tr"] else (0, 0, 0)
                L = locrot_to_matrix(t, q)
                B = K[jname].inverted() @ L
                rig.pose.bones[jname].matrix_basis = B
            bpy.context.view_layer.update()
            for jname in joints:
                if jname not in rig.pose.bones:
                    continue
                pb = rig.pose.bones[jname]
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        # verify non-static motion
        scn.frame_set(0); bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        d1 = ydir(rig, rig.evaluated_get(dg), "upperarm_r")
        scn.frame_set(frames[-1]); bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        d2 = ydir(rig, rig.evaluated_get(dg), "upperarm_r")
        arc = math.degrees(d1.angle(d2))
        print("%s: frames 0..%d | upperarm_r dir arc = %.2f deg %s"
              % (clip, frames[-1], arc, "OK" if arc > 0.05 else "STATIC?"))
    ad.action = orig

print("=== pose sanity at f0 (pistol_idle bound) ===")
scn.frame_set(0)
bpy.context.view_layer.update()
for rn, mn in (("Pilot_Character", "Pilot_SWAT"), ("Pilot_Character.001", "Swat_Body.001")):
    r = OB[rn]
    dg = bpy.context.evaluated_depsgraph_get()
    ev = r.evaluated_get(dg)
    h = ydir(r, ev, "hand_r")
    b = bbox(OB[mn])
    print("%s: hand_r Y-dir=[%.2f,%.2f,%.2f] | mesh Yspan=%.3f Z=%.3f..%.3f"
          % (rn, h.x, h.y, h.z, b[1] - b[0], b[2], b[3]))

print("=== pistol scale 0.19 m + re-seat (scale preserved) ===")
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
    print("%s: scale x%.4f dims=(%.3f,%.3f,%.3f) | seated err=%.5f"
          % (pname, s, p.dimensions.x, p.dimensions.y, p.dimensions.z,
             (p.matrix_world.translation - want.translation).length))

bpy.ops.wm.save_mainfile()
print("saved:", bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
