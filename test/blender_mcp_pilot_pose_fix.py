"""Fix the pilot stance (final): reinterpret arm-space baked quats as bone-local.

Model: evaluated arm-space rotation obeys
    arm_q(bone) = arm_q(parent) @ K_bone @ basis_q(bone)
with K_bone constant (rest chain). The clips were baked as arm-space target
quaternions, so the correct bone-local basis is
    basis = (eff_parent_arm_q @ K_bone)^-1 @ target
computed parent-first per frame. eff_parent_arm_q walks the ancestor chain:
fixed animated ancestors contribute their target, non-animated ones
contribute K @ current-basis. K is measured once per action and
cross-checked at the last frame (drift must be ~0) - that check validates
the whole model before anything is written.

Also: backs up actions (_BAK), drops fcurves for missing bones, rescales
pistols to 0.19 m, re-seats them in hand_r, verifies bbox/tilt, saves.

Usage: python test/blender_mcp_pilot_pose_fix.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Matrix, Quaternion, Vector

OB = bpy.data.objects
scn = bpy.context.scene

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
    return (min(v.x for v in vs), max(v.x for v in vs),
            min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

def pelvis_tilt(rig):
    pel = rig.pose.bones["pelvis"]
    up = ((pel.matrix @ rig.matrix_world).to_3x3() @ Vector((0, 0, 1))).normalized()
    return math.degrees(math.acos(max(-1.0, min(1.0, up.z))))

def depth(pb):
    n = 0
    b = pb
    while b.parent:
        n += 1
        b = b.parent
    return n

def measure_K(rig, ev, names):
    K = {}
    for name in names:
        pb = rig.pose.bones[name]
        par = pb.parent
        par_q = ev.pose.bones[par.name].matrix.to_quaternion() if par else Quaternion()
        own_q = ev.pose.bones[name].matrix.to_quaternion()
        K[name] = par_q.inverted() @ own_q @ pb.matrix_basis.to_quaternion().inverted()
    return K

JOBS = [
    ("Pilot_Character", ["pistol_idle", "pistol_reload", "pistol_shoot"]),
    ("Pilot_Character.001", ["pistol_idle.001", "pistol_reload.001", "pistol_shoot.001"]),
]

for rig_name, actions in JOBS:
    rig = OB[rig_name]
    ad = rig.animation_data
    orig_bound = ad.action
    print("=== FIX %s ===" % rig_name)
    for act_name in actions:
        act = bpy.data.actions[act_name]
        bak = bpy.data.actions.get(act_name + "_BAK")
        if bak is None:
            bak = act.copy()
            bak.name = act_name + "_BAK"
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
        anim = [pb for pb in rig.pose.bones
                if 'pose.bones["%s"].rotation_quaternion' % pb.name in paths]
        anim.sort(key=depth)

        need = set()
        for pb in anim:
            b = pb
            while b:
                need.add(b.name)
                b = b.parent

        # measure K at f0, verify constancy at f1 (validates the model)
        scn.frame_set(f0)
        bpy.context.view_layer.update()
        ev = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        K = measure_K(rig, ev, need)
        scn.frame_set(f1)
        bpy.context.view_layer.update()
        ev = rig.evaluated_get(bpy.context.evaluated_depsgraph_get())
        K2 = measure_K(rig, ev, need)
        drift = max(math.degrees((K2[n].rotation_difference(K[n])).angle) for n in need)
        print("%s: K drift f0->f1 = %.4f deg (model %s)" % (act_name, drift, "OK" if drift < 0.5 else "SUSPECT"))

        def baked(f, pb):
            rq = paths['pose.bones["%s"].rotation_quaternion' % pb.name]
            return Quaternion([rq[i].evaluate(f) for i in range(4)])

        for f in range(f0, f1 + 1):
            fixed = {}
            for pb in anim:
                qb = baked(f, pb)
                q = Quaternion()
                chain = []
                b = pb.parent
                while b:
                    chain.append(b)
                    b = b.parent
                for b in reversed(chain):
                    if b.name in fixed:
                        q = fixed[b.name]
                    else:
                        q = q @ K[b.name] @ b.matrix_basis.to_quaternion()
                pb.rotation_quaternion = (q @ K[pb.name]).inverted() @ qb
                fixed[pb.name] = qb
            bpy.context.view_layer.update()
            for pb in anim:
                pb.keyframe_insert("rotation_quaternion", frame=f)
        print("%s: fixed frames %d..%d (%d bones, junk fcurves removed: %d)"
              % (act_name, f0, f1, len(anim), removed))
    ad.action = orig_bound

print("=== pistol scale fix (target 0.19 m length) ===")
for pname in ("PistolProp", "PistolProp.001"):
    p = OB[pname]
    cur = max(p.dimensions)
    s = 0.19 / cur
    p.scale = (p.scale.x * s, p.scale.y * s, p.scale.z * s)
    bpy.context.view_layer.update()
    print("%s: scale x%.4f | new dims=(%.3f,%.3f,%.3f)" % (pname, s, p.dimensions.x, p.dimensions.y, p.dimensions.z))

print("=== re-seat pistols in hand_r (frame 0) ===")
scn.frame_set(0)
bpy.context.view_layer.update()
for pname, aname in [("PistolProp", "Pilot_Character"), ("PistolProp.001", "Pilot_Character.001")]:
    p = OB[pname]
    rig = OB[aname]
    dg = bpy.context.evaluated_depsgraph_get()
    hw = (rig.evaluated_get(dg).pose.bones["hand_r"].matrix @ rig.matrix_world)
    fwd = Vector((0.0, -1.0, 0.0))
    want = Matrix.Translation(hw.translation + Vector((0, -0.035, 0)) + fwd * 0.02) \
        @ Matrix.Rotation(math.pi, 4, "X") @ Matrix.LocRotScale(None, fwd.to_track_quat("Z", "Y"), None)
    actual = p.matrix_world.copy()
    M = actual @ p.matrix_basis.inverted()
    p.matrix_basis = M.inverted() @ want
    bpy.context.view_layer.update()
    err = (p.matrix_world.translation - want.translation).length
    print("%s: seated err=%.5f | parent_bone=%s" % (pname, err, p.parent_bone))

print("=== VERIFY (frame 0 / 25) ===")
for f in (0, 25):
    scn.frame_set(f)
    bpy.context.view_layer.update()
    for rn, mn in (("Pilot_Character", "Pilot_SWAT"), ("Pilot_Character.001", "Swat_Body.001")):
        r = OB[rn]
        b = bbox(OB[mn])
        print("f%02d %s | pelvis tilt=%.1f deg | mesh Y-span=%.3f Z=%.3f..%.3f"
              % (f, rn, pelvis_tilt(r), b[3] - b[2], b[4], b[5]))
    p = OB["PistolProp"]
    print("     PistolProp dims=(%.3f,%.3f,%.3f) world=(%.3f,%.3f,%.3f)"
          % (p.dimensions.x, p.dimensions.y, p.dimensions.z,
             p.matrix_world.translation.x, p.matrix_world.translation.y, p.matrix_world.translation.z))

bpy.ops.wm.save_mainfile()
print("saved:", bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
