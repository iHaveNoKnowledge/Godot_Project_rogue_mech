"""Retarget pistol clips onto Pilot_Character rigs - v4 (final).

Facts measured on-scene:
 - Action bones = PC's 79-name set (incl. "Body"); AF shares 63 of them and
   has 8 extra IK/leaf bones (thumb_04_leaf_l/r animate PC-fcurves only after
   our rebake used AF-authored data... actually the action set == PC set).
 - AF carries LIMIT_* constraints: its EVALUATED pose is ground truth.
 - Hierarchy differs: PC root -> Body -> pelvis, thighs hang off Body.
 - Both rigs share rest root position => AF evaluated root motion (delta from
   its rest) transfers directly as PC root basis.

Plan:
 1) For each source clip: bind to AF, evaluate per frame, snapshot
    armature-space matrices of the 63 shared animated bones.
 2) For rig A and B: per frame, per shared bone: rotation target = AF
    evaluated rotation; translation: root gets AF delta vs AF rest, others
    chain along the rig's own rest offsets; "Body" keeps its rest orientation
    (AF has no Body - it is a PC hierarchy insert). Closed-form basis solve
    parent-first; wipe pose fcurves; re-key (LINEAR).
 3) Verify: rot err vs AF snapshot (shared bones), hand_r dir, motion arc,
    bbox, A/B parity, pistol dims; save.

Usage: python test/blender_mcp_pilot_retarget4.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Matrix, Quaternion, Vector

OB = bpy.data.objects
scn = bpy.context.scene
AF = OB['AF_Rig']
RIGS = {'A': OB['Pilot_Character'], 'B': OB['Pilot_Character.001']}
MESH = {'A': 'Pilot_SWAT', 'B': 'Swat_Body.001'}
CLIPS = {'A': ['pistol_idle', 'pistol_reload', 'pistol_shoot'],
         'B': ['pistol_idle.001', 'pistol_reload.001', 'pistol_shoot.001']}
SRC = ['pistol_idle', 'pistol_reload', 'pistol_shoot']

def set_pos(rig, mode):
    rig.data.pose_position = mode
    bpy.context.view_layer.update()

def build_K(rig):
    K = {}
    for b in rig.data.bones:
        own = b.matrix_local.copy()
        K[b.name] = rig.data.bones[b.parent.name].matrix_local.inverted() @ own if b.parent else own
    return K

ALLRIG = [('AF', AF)] + list(RIGS.items())
for _, r in ALLRIG:
    set_pos(r, 'REST')
Ks = {k: build_K(r) for k, r in ALLRIG}
REST_T = {k: {b.name: b.matrix_local.translation.copy() for b in r.data.bones} for k, r in ALLRIG}
for _, r in ALLRIG:
    set_pos(r, 'POSE')

ORDER = {}
for k, r in ALLRIG:
    depth = {}
    def walk(b, d):
        depth[b.name] = d
        for c in b.children:
            walk(c, d + 1)
    for b in r.data.bones:
        if b.parent is None:
            walk(b, 0)
    ORDER[k] = sorted(depth.keys(), key=lambda n: depth[n])

def fc_map(act):
    out = {}
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    dp = fc.data_path
                    if 'pose.bones[' not in dp:
                        continue
                    bn = dp.split('"')[1]
                    if 'rotation_quaternion' in dp:
                        prop = 'rq'
                    elif dp.endswith('.location'):
                        prop = 'loc'
                    else:
                        continue
                    out.setdefault(bn, {'rq': {}, 'loc': {}})[prop][fc.array_index] = fc
    return out

def frames_of(act):
    mx = 0.0
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    if 'pose.bones[' in fc.data_path and fc.keyframe_points:
                        mx = max(mx, fc.keyframe_points[-1].co.x)
    return list(range(0, int(round(mx)) + 1))

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

AF_ANIMATED = set()
for clip in SRC:
    AF_ANIMATED |= set(fc_map(bpy.data.actions[clip]).keys())

# ---- 1) AF evaluated snapshots (shared bones only) ----
A_af_all = {}
af_hidden = AF.hide_viewport  # hidden objects are SKIPPED by the depsgraph -> frozen eval
AF.hide_viewport = False
bpy.context.view_layer.update()
for clip in SRC:
    act = bpy.data.actions[clip]
    fmv = fc_map(act)
    frames = frames_of(act)
    bind(AF, act)
    snap = {}
    for f in frames:
        scn.frame_set(f)
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = AF.evaluated_get(dg)
        snap[f] = {bn: ev.pose.bones[bn].matrix.copy() for bn in fmv if bn in AF.data.bones}
    def dev(bn):
        if bn not in snap[frames[0]]:
            return 0.0
        q0 = snap[frames[0]][bn].to_3x3().to_quaternion()
        m = 0.0
        for f in frames:
            q = snap[f][bn].to_3x3().to_quaternion()
            m = max(m, math.degrees(q0.rotation_difference(q).angle))
        return m
    print('%s: AF snapshot motion: upperarm_l dev %.2f deg | lowerarm_r dev %.2f deg'
          % (clip, dev('upperarm_l'), dev('lowerarm_r')))
    A_af_all[clip] = snap
AF.hide_viewport = af_hidden
bpy.context.view_layer.update()
AF.animation_data.action = None

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

# ---- 2) rebuild actions ----
for rk, rig in RIGS.items():
    print('=== REBUILD rig %s ===' % rk)
    for clip in CLIPS[rk]:
        src = clip[:-4] if rk == 'B' else clip
        act = bpy.data.actions[clip]
        bind(rig, act)
        wipe_pose_fcurves(act)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        snap = A_af_all[src]
        fmv_keys = set(snap[sorted(snap.keys())[0]].keys())
        for f in sorted(snap.keys()):
            A_af = snap[f]
            A_t = {}
            B_out = {}
            for bn in ORDER[rk]:
                b = rig.data.bones[bn]
                par = b.parent.name if b.parent else None
                if bn in fmv_keys:
                    R = A_af[bn].to_3x3()
                    if par is None:
                        p = A_af[bn].translation
                    elif par in A_t:
                        p = A_t[par].translation + A_t[par].to_3x3() @ \
                            (REST_T[rk][bn] - REST_T[rk][par])
                    else:
                        p = REST_T[rk][bn]
                    A_t[bn] = Matrix.LocRotScale(p, R.to_quaternion(), None)
                    L = A_t[par].inverted() @ A_t[bn] if par else A_t[bn]
                    B_out[bn] = Ks[rk][bn].inverted() @ L
                else:
                    L = Ks[rk][bn]
                    A_t[bn] = A_t[par] @ L if par else L
            for bn, B in B_out.items():
                rig.pose.bones[bn].matrix_basis = B
            bpy.context.view_layer.update()
            for bn, B in B_out.items():
                pb = rig.pose.bones[bn]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                if B.translation.length > 1e-5:
                    pb.keyframe_insert('location', frame=f)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
        scn.frame_set(sorted(snap.keys())[0])
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = rig.evaluated_get(dg)
        A_af = snap[sorted(snap.keys())[0]]
        rerr = 0.0
        for bn in A_af:
            if bn not in rig.pose.bones:
                continue
            ang = ev.pose.bones[bn].matrix.to_3x3().to_quaternion() \
                .rotation_difference(A_af[bn].to_3x3().to_quaternion()).angle
            rerr = max(rerr, ang)
        h1 = handdir(rig, ev, 'hand_r')
        last = sorted(snap.keys())[-1]
        arc = 0.0
        for f in sorted(snap.keys()):
            scn.frame_set(f)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            hf = handdir(rig, rig.evaluated_get(dg), 'hand_r')
            arc = max(arc, math.degrees(h1.angle(hf)))
        scn.frame_set(last)
        bpy.context.view_layer.update()
        b = bbox(OB[MESH[rk]])
        print('%s: f0..%d | rot err vs AF %.3f deg | hand dev from f0 %.2f deg | Yspan %.3f Z %.2f..%.2f'
              % (clip, last, math.degrees(rerr), arc, b[1] - b[0], b[2], b[3]))

# ---- 3) parity + pistol + save ----
scn.frame_set(0)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
print('parity A/B hand_r dir: A=[%.2f,%.2f,%.2f] B=[%.2f,%.2f,%.2f] diff=%.3f deg'
      % (ha.x, ha.y, ha.z, hb.x, hb.y, hb.z, math.degrees(ha.angle(hb))))
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
    rot = Matrix.Rotation(math.pi, 4, 'X') @ Matrix.LocRotScale(None, fwd.to_track_quat('Z', 'Y'), None)
    want = Matrix.Translation(hw.translation + Vector((0, -0.035, 0)) + fwd * 0.02) \
        @ rot @ Matrix.LocRotScale(None, None, p.scale)
    actual = p.matrix_world.copy()
    M = actual @ p.matrix_basis.inverted()
    p.matrix_basis = M.inverted() @ want
    bpy.context.view_layer.update()
    print('%s: dims=(%.3f,%.3f,%.3f) | seated err=%.5f | scale=(%.3f,%.3f,%.3f)'
          % (pname, p.dimensions.x, p.dimensions.y, p.dimensions.z,
             (p.matrix_world.translation - want.translation).length,
             p.scale.x, p.scale.y, p.scale.z))

bpy.ops.wm.save_mainfile()
print('saved:', bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
