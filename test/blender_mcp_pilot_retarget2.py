"""Retarget pistol clips (authored on AF_Rig) onto Pilot_Character rigs - v2.

Math (closed-form, no depsgraph in the inner loop):
  Chain model (verified by GLB round-trip): A(J) = A(parent) @ K(J) @ B(J),
  K(J) = rest(parent)^-1 @ rest(J) (4x4), B = bone-local basis.
  1) Snapshot AF's fcurve bases B_af per frame, rebuild AF's armature-space
     chain A_af recursively, and VERIFY against Blender's own evaluation
     (max rotation err < 0.01 deg) - guards the whole model.
  2) Target for PC: rotation of A_pc(J) = rotation of A_af(J) (armature-space
     match => posture identical), position chained on PC's own rest offsets:
       p(J) = p(parent) + R_target(parent) @ (restPC(J).t - restPC(parent).t)
       root: p(root) = A_af(root).translation
     Then L = A_target(parent)^-1 @ A_target(J), B_pc = K_pc(J)^-1 @ L.
  3) Wipe pose fcurves, re-key all 6 actions (LINEAR), verify pose/motion/
     parity, pistol check, save.

Usage: python test/blender_mcp_pilot_retarget2.py
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

for k, r in RIGS.items():
    n = sum(len(pb.constraints) for pb in r.pose.bones)
    print('%s constraints: %d' % (k, n))

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

def basis_from(fmap, f):
    q = Quaternion([fmap['rq'][i].evaluate(f) for i in range(4)]) if len(fmap['rq']) == 4 else Quaternion()
    t = Vector([fmap['loc'][i].evaluate(f) for i in range(3)]) if len(fmap['loc']) == 3 else Vector((0, 0, 0))
    return Matrix.Translation(t) @ q.to_matrix().to_4x4()

def frames_of(act):
    mx = 0.0
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    if 'pose.bones[' in fc.data_path and fc.keyframe_points:
                        mx = max(mx, fc.keyframe_points[-1].co.x)
    return list(range(0, int(round(mx)) + 1))

def chain_A(rig_key, rig, fmap, f):
    """Recursive armature-space chain; B from fcurves when animated else identity."""
    A = {}
    for bn in ORDER[rig_key]:
        b = rig.data.bones[bn]
        B = basis_from(fmap[bn], f) if bn in fmap else Matrix.Identity(4)
        par = b.parent.name if b.parent else None
        L = Ks[rig_key][bn] @ B
        A[bn] = A[par] @ L if par else L
    return A

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

# ---- 1) snapshot AF bases + verify recursion model against evaluation ----
snap = {}   # clip -> {frame -> {bone -> (quat_wxyz, handled via A_af)}}
A_af_all = {}
fmap_of = {}
for clip in ['pistol_idle', 'pistol_reload', 'pistol_shoot']:
    act = bpy.data.actions[clip]
    fmap_of[clip] = fc_map(act)
    frames = frames_of(act)
    snap[clip] = frames
    A_af_all[clip] = {f: chain_A('AF', AF, fmap_of[clip], f) for f in frames}

worst = 0.0
for clip in ['pistol_idle', 'pistol_reload', 'pistol_shoot']:
    act = bpy.data.actions[clip]
    ad = bind(AF, act)
    frames = snap[clip]
    for f in (frames[0], frames[len(frames) // 2], frames[-1]):
        scn.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = AF.evaluated_get(dg)
        A = A_af_all[clip][f]
        for bn, m in A.items():
            pr = ev.pose.bones[bn].matrix
            ang = pr.to_3x3().to_quaternion().rotation_difference(m.to_3x3().to_quaternion()).angle
            worst = max(worst, ang)
    ad.action = None
print('AF recursion model check: max rotation err = %.4f deg %s'
      % (math.degrees(worst), 'OK' if math.degrees(worst) < 0.01 else 'MODEL MISMATCH!'))
if math.degrees(worst) >= 0.01:
    raise RuntimeError('recursion model does not match Blender evaluation - aborting')

def handdir(rig, ev, bone):
    m = ev.pose.bones[bone].matrix @ rig.matrix_world
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()

def bbox(o):
    vs = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs),
            min(v.x for v in vs), max(v.x for v in vs))

def wipe_pose_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in list(cb.fcurves):
                    if 'pose.bones[' in fc.data_path:
                        cb.fcurves.remove(fc)

# ---- 2) rebuild all 6 actions from AF-derived targets ----
for rk, rig in RIGS.items():
    print('=== REBUILD rig %s ===' % rk)
    for clip in CLIPS[rk]:
        src = clip[:-4] if rk == 'B' else clip
        act = bpy.data.actions[clip]
        ad = bind(rig, act)
        wipe_pose_fcurves(act)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        frames = snap[src]
        for f in frames:
            A_af = A_af_all[src][f]
            A_t = {}
            B_out = {}
            for bn in ORDER[rk]:
                b = rig.data.bones[bn]
                par = b.parent.name if b.parent else None
                if bn in fmap_of[src]:
                    R = A_af[bn].to_3x3()
                    if par:
                        p = A_t[par].translation + A_t[par].to_3x3() @ \
                            (rig.data.bones[bn].matrix_local.translation -
                             rig.data.bones[par].matrix_local.translation)
                    else:
                        p = A_af[bn].translation
                    A_t[bn] = Matrix.LocRotScale(p, R.to_quaternion(), None)
                    L = A_t[par].inverted() @ A_t[bn] if par else A_t[bn]
                    B_out[bn] = Ks[rk][bn].inverted() @ L
                else:
                    L = Ks[rk][bn]
                    A_t[bn] = A_t[par] @ L if par else L
            for bn, B in B_out.items():
                pb = rig.pose.bones[bn]
                pb.matrix_basis = B
            bpy.context.view_layer.update()
            for bn, B in B_out.items():
                pb = rig.pose.bones[bn]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                if len(fmap_of[src].get(bn, {}).get('loc', {})) == 3 or B.translation.length > 1e-5:
                    pb.keyframe_insert('location', frame=f)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
        # verify motion + pose for this clip
        scn.frame_set(frames[0])
        dg = bpy.context.evaluated_depsgraph_get()
        ev1 = rig.evaluated_get(dg)
        h1 = handdir(rig, ev1, 'hand_r')
        scn.frame_set(frames[-1])
        dg = bpy.context.evaluated_depsgraph_get()
        ev2 = rig.evaluated_get(dg)
        h2 = handdir(rig, ev2, 'hand_r')
        arc = math.degrees(h1.angle(h2))
        # rotation match vs AF target
        scn.frame_set(frames[0])
        dg = bpy.context.evaluated_depsgraph_get()
        ev = rig.evaluated_get(dg)
        A_af = A_af_all[src][frames[0]]
        rerr = 0.0
        for bn in fmap_of[src]:
            if bn not in rig.pose.bones:
                continue
            ang = ev.pose.bones[bn].matrix.to_3x3().to_quaternion() \
                .rotation_difference(A_af[bn].to_3x3().to_quaternion()).angle
            rerr = max(rerr, ang)
        b = bbox(OB[MESH[rk]])
        print('%s: f0..%d | hand arc %.2f deg | rot err vs AF %.4f deg | Yspan %.3f Z %.2f..%.2f'
              % (clip, frames[-1], arc, math.degrees(rerr), b[1] - b[0], b[2], b[3]))

# ---- 3) pistol check ----
for pname, rk in (('PistolProp', 'A'), ('PistolProp.001', 'B')):
    p = OB[pname]
    rig = RIGS[rk]
    scn.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    hw = rig.evaluated_get(dg).pose.bones['hand_r'].matrix @ rig.matrix_world
    print('%s: dims=(%.3f,%.3f,%.3f) | dist hand->pistol %.4f m | scale=(%.3f,%.3f,%.3f)'
          % (pname, p.dimensions.x, p.dimensions.y, p.dimensions.z,
             (p.matrix_world.translation - hw.translation).length,
             p.scale.x, p.scale.y, p.scale.z))

# parity A vs B
scn.frame_set(0)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
print('parity A/B hand_r dir: A=[%.2f,%.2f,%.2f] B=[%.2f,%.2f,%.2f] diff=%.3f deg'
      % (ha.x, ha.y, ha.z, hb.x, hb.y, hb.z, math.degrees(ha.angle(hb))))

bpy.ops.wm.save_mainfile()
print('saved:', bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
