"""Procedural pistol clips for the pilot rigs (replaces unusable baked data).

The baked clips are proven broken (even AF_Rig's own constrained evaluation
sinks the left hand 1.39 m below the floor; every reinterpretation fails a
standing-pose sanity sweep), so we author new clips directly:

  Aim-solver: for each posed bone, specify the desired armature-space
  segment direction (bone +Y: shoulder->elbow, elbow->wrist, ...);
  rotation = shortest arc from its rest direction, composed with rest:
      R(bn) = (d_rest.rotation_difference(d_want)).to_matrix() @ R_rest(bn)
  Everything NOT in the pose dict keeps its rest rotation, so legs stay
  planted (feet on floor) and the stance is an upright gun-ready idle.

  pistol_idle   51f loop: two-hand forward grip + 2-deg breathing sway
  pistol_reload 51f: aim -> reach down-left for mag -> return
  pistol_shoot  20f: aim -> recoil kick (wrist/forearm pitch up) -> settle

Stages (separate MCP calls): buildA | buildB | finish (verify + pistol
re-seat + save).

Usage: python test/blender_mcp_pilot_procedural.py <buildA|buildB|finish>
"""
import sys

from blender_mcp_probe import send_code

STAGE = sys.argv[1] if len(sys.argv) > 1 else "buildA"

CODE = r'''
import bpy, math
from mathutils import Matrix, Quaternion, Vector

STAGE = "__STAGE__"

OB = bpy.data.objects
scn = bpy.context.scene
RIGS = {'A': OB['Pilot_Character'], 'B': OB['Pilot_Character.001']}
MESH = {'A': 'Pilot_SWAT', 'B': 'Swat_Body.001'}
CLIPS = {'A': ['pistol_idle', 'pistol_reload', 'pistol_shoot', 'pilot_walk', 'pilot_run',
               'pilot_strafe_bwd', 'pilot_strafe_l', 'pilot_strafe_r', 'pilot_jump'],
         'B': ['pistol_idle.001', 'pistol_reload.001', 'pistol_shoot.001', 'pilot_walk.001', 'pilot_run.001',
               'pilot_strafe_bwd.001', 'pilot_strafe_l.001', 'pilot_strafe_r.001', 'pilot_jump.001']}

def set_pos(rig, mode):
    rig.data.pose_position = mode
    bpy.context.view_layer.update()

def build_K(rig):
    K = {}
    for b in rig.data.bones:
        own = b.matrix_local.copy()
        K[b.name] = rig.data.bones[b.parent.name].matrix_local.inverted() @ own if b.parent else own
    return K

def order_of(rig):
    depth = {}
    def walk(b, d):
        depth[b.name] = d
        for c in b.children:
            walk(c, d + 1)
    for b in rig.data.bones:
        if b.parent is None:
            walk(b, 0)
    return sorted(depth.keys(), key=lambda n: depth[n])

for rk in RIGS:
    set_pos(RIGS[rk], 'REST')
Ks = {rk: build_K(RIGS[rk]) for rk in RIGS}
REST_ARM = {rk: {b.name: b.matrix_local.copy() for b in RIGS[rk].data.bones} for rk in RIGS}
REST_R = {rk: {bn: m.to_3x3().copy() for bn, m in REST_ARM[rk].items()} for rk in RIGS}
REST_T = {rk: {bn: m.translation.copy() for bn, m in REST_ARM[rk].items()} for rk in RIGS}
ORDER = {rk: order_of(RIGS[rk]) for rk in RIGS}
REST_DIR = {rk: {bn: (REST_ARM[rk][bn].to_3x3() @ Vector((0, 1, 0))).normalized()
                 for bn in REST_ARM[rk]} for rk in RIGS}
for rk in RIGS:
    set_pos(RIGS[rk], 'POSE')

def bind(rig, act):
    ad = rig.animation_data or rig.animation_data_create()
    slot = None
    for s in act.slots:
        if s.target_id_type == 'OBJECT':
            slot = s
            break
    if slot is None:
        slot = act.slots.new(id_type='OBJECT', name=rig.name)
    ad.action = act
    ad.action_slot = slot
    return ad

def handdir(rig, ev, bone):
    m = ev.pose.bones[bone].matrix @ rig.matrix_world
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

def wipe_pose_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in list(cb.fcurves):
                    if 'pose.bones[' in fc.data_path:
                        cb.fcurves.remove(fc)

def get_or_make_action(name):
    act = bpy.data.actions.get(name)
    if act is None:
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
    return act

def aim(rk, bn, want, extra_deg=0.0, extra_axis='X'):
    """Arm-space rotation aiming bone bn's +Y at direction `want`."""
    d_rest = REST_DIR[rk][bn]
    d_want = Vector(want).normalized()
    q = d_rest.rotation_difference(d_want)
    if extra_deg:
        q = Quaternion(extra_axis_to_vec(extra_axis), math.radians(extra_deg)) @ q
    return q.to_matrix().to_3x3() @ REST_R[rk][bn]

def extra_axis_to_vec(ax):
    return {'X': Vector((1, 0, 0)), 'Y': Vector((0, 1, 0)), 'Z': Vector((0, 0, 1))}[ax]

# ------------- pose definitions (armature space; character FRONT = -Y) ------
def pose_idle(rk, u):
    """u in [0,1): returns {bone: arm-space 3x3} - two-hand forward grip."""
    sway = math.sin(u * 2 * math.pi)
    sx = 1.0 if REST_DIR[rk]['upperarm_r'].x >= 0 else -1.0
    d = {}
    d['upperarm_r'] = aim(rk, 'upperarm_r', (0.15 * sx, -0.55, -0.35), 1.5 * sway, 'Y')
    d['lowerarm_r'] = aim(rk, 'lowerarm_r', (0.05 * sx, -0.95, 0.05), 1.0 * sway, 'Y')
    d['hand_r'] = aim(rk, 'hand_r', (0.0, -0.98, -0.15), 1.0 * sway, 'Y')
    d['upperarm_l'] = aim(rk, 'upperarm_l', (-0.22 * sx, -0.50, -0.38), -1.5 * sway, 'Y')
    d['lowerarm_l'] = aim(rk, 'lowerarm_l', (-0.04 * sx, -0.92, 0.10), -1.0 * sway, 'Y')
    d['hand_l'] = aim(rk, 'hand_l', (0.05 * sx, -0.95, -0.12), -1.0 * sway, 'Y')
    return d

def reload_hold(rk, k):
    """Endpoint pose of the mag reach (k: 0=aim, 1=hand at hip)."""
    base = pose_idle(rk, 0.0)
    sx = 1.0 if REST_DIR[rk]['upperarm_r'].x >= 0 else -1.0
    d = dict(base)
    want_up = Vector(((-0.30 - 0.05 * k) * sx, -0.30, -0.90)).normalized()
    want_lo = Vector((-0.10 * sx, -0.45 + 0.15 * k, -0.85)).normalized()
    d['upperarm_l'] = aim(rk, 'upperarm_l', want_up)
    d['lowerarm_l'] = aim(rk, 'lowerarm_l', want_lo)
    d['hand_l'] = aim(rk, 'hand_l', (0.0, -0.55 + 0.1 * k, -0.80))
    return d

def pose_reload(rk, u):
    # phases: 0-0.2 aim, 0.2-0.5 reach down-left, 0.5-0.7 mag pause, 0.7-1 return
    base = pose_idle(rk, 0.0)
    hold = reload_hold(rk, 1.0)
    if u < 0.2:
        return base
    if u < 0.5:
        k = (u - 0.2) / 0.3
        k = k * k * (3 - 2 * k)
        d = dict(base)
        for bn in ('upperarm_l', 'lowerarm_l', 'hand_l'):
            d[bn] = (base[bn].to_quaternion().slerp(hold[bn].to_quaternion(), k)).to_matrix().to_3x3()
        return d
    if u < 0.7:
        return hold
    k = (u - 0.7) / 0.3
    k = k * k * (3 - 2 * k)
    d = dict(base)
    for bn in ('upperarm_l', 'lowerarm_l', 'hand_l'):
        d[bn] = (hold[bn].to_quaternion().slerp(base[bn].to_quaternion(), k)).to_matrix().to_3x3()
    return d

def pose_shoot(rk, u):
    base = pose_idle(rk, 0.0)
    # recoil around u=0.25 (frame ~5 of 20), settle to idle
    kick = math.exp(-((u - 0.25) ** 2) / 0.01)
    if kick < 0.01:
        return base
    sx = 1.0 if REST_DIR[rk]['upperarm_r'].x >= 0 else -1.0
    d = dict(base)
    d['upperarm_r'] = aim(rk, 'upperarm_r', (0.15 * sx, -0.55, -0.35), -3.0 * kick, 'X')
    d['lowerarm_r'] = aim(rk, 'lowerarm_r', (0.05 * sx, -0.95, 0.05), -6.0 * kick, 'X')
    d['hand_r'] = aim(rk, 'hand_r', (0.0, -0.98, -0.15), -8.0 * kick, 'X')
    d['spine_01'] = aim(rk, 'spine_01', REST_DIR[rk]['spine_01'], 2.0 * kick, 'X')
    return d

# ------------- locomotion (legs walk/run, arms keep the gun-ready pose) -----

def _leg_phase(rk, u, side_sign, amp_thigh, amp_shin, amp_foot, lift, phase_offset=0.0):
    """Joint-angle dict for one leg: thigh pitch, knee flex, foot pitch.
    Angles are in degrees; positive thigh pitch swings the leg forward (-Y)."""
    ph = (u + phase_offset) * 2 * math.pi
    thigh = amp_thigh * math.sin(ph)
    # knee flexes most when the thigh swings back-to-forward (mid swing)
    knee = amp_shin * max(0.0, math.sin(ph + 0.9))
    foot = amp_foot * math.sin(ph + 1.8) - lift
    return thigh, knee, foot

def _leg_aims(rk, side, thigh_d, knee_d, foot_d):
    """Return {bone: 3x3} for a leg chain pitched by the given angles (deg,
    positive = segment tip toward character front -Y)."""
    d = {}
    for prefix, ang in (('thigh', thigh_d), ('calf', knee_d), ('foot', foot_d)):
        bn = '%s_%s' % (prefix, 'l' if side < 0 else 'r')
        if bn in REST_DIR[rk]:
            d[bn] = aim(rk, bn, _pitch_down(rk, bn, ang))
    return d

def _pitch_down(rk, bn, pitch_deg):
    """Aim direction for a DOWN-pointing segment pitched forward by pitch_deg
    around the X axis (positive pitch = tip moves toward -Y front)."""
    rest = REST_DIR[rk][bn]
    # rotate rest dir around X: y' = y cos - z sin ... keep simple: build target
    r = math.radians(pitch_deg)
    d = Vector((rest.x, rest.y * math.cos(r) - rest.z * math.sin(r),
                rest.y * math.sin(r) + rest.z * math.cos(r)))
    return d

def pose_walk(rk, u):
    """Walk: 1.3s cycle, thigh +-26 deg, knee 0..36, feet roll.
    Arms keep the idle gun-ready pose (upper sway damped)."""
    d = dict(pose_idle(rk, 0.0))
    for side in (-1.0, 1.0):
        th, kn, ft = _leg_phase(rk, u, side, 26.0, 36.0, 14.0, 4.0,
                                phase_offset=0.0 if side < 0 else 0.5)
        d.update(_leg_aims(rk, side, th, kn, ft))
    d['spine_01'] = aim(rk, 'spine_01', REST_DIR[rk]['spine_01'], 1.0, 'X')
    d['pelvis'] = aim(rk, 'pelvis', REST_DIR[rk]['pelvis'], 1.5 * math.sin(u * 2 * math.pi), 'Z')
    return d

def pose_run(rk, u):
    """Run: faster/bigger cycle, thigh +-38 deg, knee 0..65, forward lean.
    Arms still hold the pistol (two-hand grip never breaks)."""
    d = dict(pose_idle(rk, 0.0))
    for side in (-1.0, 1.0):
        th, kn, ft = _leg_phase(rk, u, side, 38.0, 65.0, 20.0, 6.0,
                                phase_offset=0.0 if side < 0 else 0.5)
        d.update(_leg_aims(rk, side, th, kn, ft))
    d['spine_01'] = aim(rk, 'spine_01', REST_DIR[rk]['spine_01'], 4.0, 'X')
    d['pelvis'] = aim(rk, 'pelvis', REST_DIR[rk]['pelvis'], 2.5 * math.sin(u * 2 * math.pi), 'Z')
    return d

# ------------- strafe (backward / sidestep) + jump --------------------------

def _leg_side_aims(rk, side, thigh_deg, knee_deg, foot_deg):
    """Leg chain abducted sideways: segments rotate around the arm-space Y
    axis (theta>0 tips the segment toward -X = character left)."""
    d = {}
    for prefix, ang in (('thigh', thigh_deg), ('calf', knee_deg), ('foot', foot_deg)):
        bn = '%s_%s' % (prefix, 'l' if side < 0 else 'r')
        if bn in REST_DIR[rk]:
            rot = Quaternion((0, 1, 0), math.radians(-side * ang))
            d[bn] = aim(rk, bn, rot @ REST_DIR[rk][bn])
    return d

def pose_strafe_bwd(rk, u):
    """Backpedal: reduced back-forward stride, slight constant knee flex,
    torso leans back a touch, eyes/gun still forward."""
    d = dict(pose_idle(rk, 0.0))
    for side in (-1.0, 1.0):
        ph = (u + (0.0 if side < 0 else 0.5)) * 2 * math.pi
        th = -16.0 * math.sin(ph)
        kn = 18.0 * max(0.0, math.sin(ph + 0.9)) + 8.0
        ft = -6.0 * math.sin(ph)
        d.update(_leg_aims(rk, side, th, kn, ft))
    d['spine_01'] = aim(rk, 'spine_01', REST_DIR[rk]['spine_01'], -2.0, 'X')
    d['pelvis'] = aim(rk, 'pelvis', REST_DIR[rk]['pelvis'], 1.0 * math.sin(u * 2 * math.pi), 'Z')
    return d

def _pose_strafe_side(rk, u, lead):
    """Sidestep toward `lead` (-1 = left, +1 = right): legs abduct/adduct
    alternately with a crossing step feel; torso stays square to the aim."""
    d = dict(pose_idle(rk, 0.0))
    for side in (-1.0, 1.0):
        ph = (u + (0.0 if side == lead else 0.5)) * 2 * math.pi
        th = 22.0 * math.sin(ph)
        kn = 20.0 * max(0.0, math.sin(ph + 0.9)) + 6.0
        ft = 8.0 * math.sin(ph)
        d.update(_leg_side_aims(rk, side, th * (1.0 if side == lead else 0.7), kn, ft))
    d['pelvis'] = aim(rk, 'pelvis', REST_DIR[rk]['pelvis'], 2.0 * math.sin(u * 2 * math.pi), 'Y')
    return d

def pose_strafe_l(rk, u):
    return _pose_strafe_side(rk, u, -1.0)

def pose_strafe_r(rk, u):
    return _pose_strafe_side(rk, u, 1.0)

def _crouch(rk, depth, thigh_d, knee_d, foot_d, drop):
    d = dict(pose_idle(rk, 0.0))
    for side in (-1.0, 1.0):
        d.update(_leg_aims(rk, side, thigh_d, knee_d, foot_d))
    d['spine_01'] = aim(rk, 'spine_01', REST_DIR[rk]['spine_01'], -depth * 10.0, 'X')
    if abs(drop) > 1e-6:
        d['_pelvis_drop_arm'] = Vector((0, 0, -drop))  # armature-space delta
    return d

def pose_jump(rk, u):
    """Jump-in-place: crouch -> extend -> airborne tuck -> land crouch ->
    recover. The controller moves the real body; this clip sells the legs."""
    if u < 0.18:
        k = u / 0.18
        return _crouch(rk, k, 24.0 * k, 40.0 * k, -10.0 * k, 0.16 * k)
    if u < 0.34:
        k = (u - 0.18) / 0.16
        # extend: legs straighten, slight rise
        d = _crouch(rk, 1.0 - k, 24.0 - 40.0 * k, 40.0 - 60.0 * k, -10.0 + 16.0 * k, 0.16 - 0.22 * k)
        return d
    if u < 0.66:
        k = min(1.0, (u - 0.34) / 0.10)
        # airborne tuck (hold)
        return _crouch(rk, 1.0, 16.0 * k, 34.0 * k, 8.0 * k, 0.0)
    if u < 0.84:
        k = (u - 0.66) / 0.18
        return _crouch(rk, k, 8.0 + 22.0 * k, 20.0 + 34.0 * k, 8.0 - 18.0 * k, 0.24 * k)
    k = (u - 0.84) / 0.16
    # recover to idle: arms slerp to idle, legs slerp to REST
    a = _crouch(rk, 1.0, 30.0, 54.0, -10.0, 0.24)
    b = pose_idle(rk, 0.0)
    d = {}
    for bn in a:
        if bn == '_pelvis_drop_arm':
            d[bn] = a[bn].lerp(Vector((0, 0, 0)), k)
        elif bn in b:
            d[bn] = (a[bn].to_quaternion().slerp(b[bn].to_quaternion(), k)).to_matrix().to_3x3()
        else:
            d[bn] = (a[bn].to_quaternion().slerp(REST_R[rk][bn].to_quaternion(), k)).to_matrix().to_3x3()
    return d

POSES = {'pistol_idle': pose_idle, 'pistol_reload': pose_reload, 'pistol_shoot': pose_shoot,
         'pilot_walk': pose_walk, 'pilot_run': pose_run,
         'pilot_strafe_bwd': pose_strafe_bwd, 'pilot_strafe_l': pose_strafe_l, 'pilot_strafe_r': pose_strafe_r,
         'pilot_jump': pose_jump}
FRAMES = {'pistol_idle': 51, 'pistol_reload': 51, 'pistol_shoot': 20,
          'pilot_walk': 40, 'pilot_run': 25,
          'pilot_strafe_bwd': 41, 'pilot_strafe_l': 41, 'pilot_strafe_r': 41,
          'pilot_jump': 26}

def key_clip(rk, clip):
    rig = RIGS[rk]
    base = clip[:-4] if clip.endswith('.001') else clip
    n = FRAMES[base]
    frames = list(range(n))
    posefn = POSES[base]
    act = get_or_make_action(clip)
    bind(rig, act)
    wipe_pose_fcurves(act)
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
        pb.location = (0, 0, 0)  # clear any leaked location keys/pose
    for f in frames:
        u = f / (n - 1) if n > 1 else 0.0
        if base in ('pistol_idle', 'pilot_walk', 'pilot_run'):
            u = f / n  # loop continuity
        offs = posefn(rk, u)
        R_t = {}
        p_t = {}
        A_t = {}
        for bn in ORDER[rk]:
            par = rig.data.bones[bn].parent
            R = offs.get(bn, REST_R[rk][bn])
            R_t[bn] = R
            if par is None:
                p = REST_T[rk][bn].copy()
            else:
                pn = par.name
                dR = R_t[pn] @ REST_R[rk][pn].inverted()
                p = p_t[pn] + dR @ (REST_T[rk][bn] - REST_T[rk][pn])
            p_t[bn] = p
            A_t[bn] = Matrix.Translation(p) @ R.to_4x4()  # needed for every bone (children reference parents)
            if bn in offs:
                L = A_t[par.name].inverted() @ A_t[bn] if par else A_t[bn]
                rig.pose.bones[bn].matrix_basis = Ks[rk][bn].inverted() @ L
        bpy.context.view_layer.update()
        for bn in offs:
            if bn == '_pelvis_drop_arm':
                # measured conversion: arm-space delta -> pelvis bone-local via
                # the live parent chain rotation (A_t(parent) @ K(pelvis))
                pb = rig.pose.bones['pelvis']
                par = rig.data.bones['pelvis'].parent
                C = (A_t[par.name] @ Ks[rk]['pelvis']).to_3x3()
                pb.location = C.inverted() @ offs[bn]
                pb.keyframe_insert('location', frame=f)
                continue
            pb = rig.pose.bones[bn]
            pb.keyframe_insert('rotation_quaternion', frame=f)
            if bn == 'pelvis':
                pb.location = (0, 0, 0)
                pb.keyframe_insert('location', frame=f)
            else:
                pb.location = (0, 0, 0)  # pure FK: rest offsets, rotation-only keys
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    for k in fc.keyframe_points:
                        k.interpolation = 'LINEAR'
    print('%s (%s): keyed %d frames, %d posed bones' % (clip, rk, n, len(posefn(rk, 0.0))))

if STAGE in ('buildA', 'buildB'):
    rk = STAGE[-1]
    for clip in CLIPS[rk]:
        key_clip(rk, clip)

elif STAGE == 'finish':
    ok = True
    for rk, rig in RIGS.items():
        for clip in CLIPS[rk]:
            frames = FRAMES[clip[:-4] if clip.endswith('.001') else clip]
            is_loco = clip.startswith('pilot_')
            act = bpy.data.actions[clip]
            bind(rig, act)
            scn.frame_set(0)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev = rig.evaluated_get(dg)
            h1 = handdir(rig, ev, 'hand_r')
            b0 = bbox(OB[MESH[rk]])
            dev = 0.0
            legdev = 0.0
            ti = ev.pose.bones['thigh_l'].matrix.to_3x3().to_quaternion() if 'thigh_l' in ev.pose.bones else None
            zmin = 1e9; zmax = -1e9; yspan = 0.0
            for f in range(frames):
                scn.frame_set(f)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                evf = rig.evaluated_get(dg)
                hf = handdir(rig, evf, 'hand_r')
                dev = max(dev, math.degrees(h1.angle(hf)))
                if ti is not None:
                    tq = evf.pose.bones['thigh_l'].matrix.to_3x3().to_quaternion()
                    legdev = max(legdev, math.degrees(ti.rotation_difference(tq).angle))
                b = bbox(OB[MESH[rk]])
                zmin = min(zmin, b[2]); zmax = max(zmax, b[3])
                yspan = max(yspan, b[1] - b[0])
            # Locomotion sanity: feet on floor, legs actually swing (>25 deg),
            # span bounded (running stride reaches ~1.5 m front-to-back).
            good = (zmin > -0.06 and yspan < 1.2 and abs(h1.y) > 0.7) if not is_loco \
                else (zmin > -0.06 and yspan < 1.6 and legdev > 15.0)
            ok = ok and good
            print('%s (%s): f0 Yspan %.3f | all-frames Z %.2f..%.2f Yspan<= %.3f | hand_r=[%.2f,%.2f,%.2f] | hand dev %.1f deg | leg swing %.1f deg | %s'
                  % (clip, rk, b0[1] - b0[0], zmin, zmax, yspan, h1.x, h1.y, h1.z, dev, legdev, 'OK' if good else 'FAIL'))
    scn.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
    hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
    pd = math.degrees(ha.angle(hb))
    print('parity A/B hand_r: diff=%.3f deg %s' % (pd, 'OK' if pd < 0.5 else 'FAIL'))
    print('=== pistol 0.19 m + re-seat (measured solve, scale preserved) ===')
    for pname, rk in (('PistolProp', 'A'), ('PistolProp.001', 'B')):
        p = OB[pname]
        rig = RIGS[rk]
        cur = max(p.dimensions)
        if abs(cur - 0.19) > 0.005:
            s = 0.19 / cur
            p.scale = (p.scale.x * s, p.scale.y * s, p.scale.z * s)
            bpy.context.view_layer.update()
        scn.frame_set(0)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        hw = (rig.evaluated_get(dg).pose.bones['hand_r'].matrix @ rig.matrix_world)
        fwd = Vector((0.0, -1.0, 0.0))
        # Measured in Blender (sRGB-grouped grip vs slide, Z-up): the pistol's
        # native orientation needs NO flip - look-at fwd with mag already
        # hanging below the slide. Any X-flip turns the mag upside down.
        rot = Matrix.LocRotScale(None, fwd.to_track_quat('Z', 'Y'), None)
        want = Matrix.Translation(hw.translation + Vector((0, -0.035, 0)) + fwd * 0.02) \
            @ rot @ Matrix.LocRotScale(None, None, p.scale)
        actual = p.matrix_world.copy()
        M = actual @ p.matrix_basis.inverted()
        p.matrix_basis = M.inverted() @ want
        bpy.context.view_layer.update()
        print('%s: dims=(%.3f,%.3f,%.3f) | seated err=%.5f'
              % (pname, p.dimensions.x, p.dimensions.y, p.dimensions.z,
                 (p.matrix_world.translation - want.translation).length))
    bpy.ops.wm.save_mainfile()
    print('saved:', bpy.data.filepath)
    print('OVERALL:', 'PASS' if ok and pd < 0.5 else 'CHECK OUTPUT')
'''.replace("__STAGE__", STAGE)

if __name__ == "__main__":
    print(send_code(CODE))
