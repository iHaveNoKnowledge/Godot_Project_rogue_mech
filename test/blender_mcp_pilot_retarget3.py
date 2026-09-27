"""Retarget pistol clips (authored on AF_Rig) onto Pilot_Character rigs - v3.

AF_Rig carries LIMIT_* constraints on nearly every bone, so its EVALUATED pose
is the animation ground truth (raw fcurve recursion mismatches it). Plan:
  1) Bind each source clip to AF, evaluate depsgraph per frame, snapshot the
     armature-space pose A_af[J](f) for every animated bone (~122 frames).
  2) For each target rig (A, B): target rotation R(J) = R(A_af[J]) per frame
     (armature-space match => identical posture); translation chained along
     the rig's own rest offsets (root takes AF root translation). Then
       L = A_t(parent)^-1 @ A_t(J),  B = K(J)^-1 @ L   (closed-form,
     parent-first, no depsgraph in the loop). Wipe pose fcurves, re-key.
  3) Verify: rotation err vs AF snapshot, hand_r direction, motion arc,
     bbox, A/B parity, pistol dims; save.

Usage: python test/blender_mcp_pilot_retarget3.py
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

# ---- 1) snapshot AF evaluated armature-space pose per frame per clip ----
A_af_all = {}
fmap_of = {}
for clip in SRC:
    act = bpy.data.actions[clip]
    fmap_of[clip] = fc_map(act)
    frames = frames_of(act)
    bind(AF, act)
    snap = {}
    for f in frames:
        scn.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = AF.evaluated_get(dg)
        snap[f] = {bn: ev.pose.bones[bn].matrix.copy() for bn in ORDER['AF'] if bn in fmap_of[clip]}
    A_af_all[clip] = snap
    print('%s: AF evaluated snapshot %d frames, %d bones/frame' % (clip, len(frames), len(snap[frames[0]])))
ad = AF.animation_data
ad.action = None

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

# ---- 2) rebuild all 6 actions from AF evaluated ground truth ----
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
        frames = sorted(snap.keys())
        fmv = fmap_of[src]
        for f in frames:
            A_af = snap[f]
            A_t = {}
            B_out = {}
            for bn in ORDER[rk]:
                b = rig.data.bones[bn]
                par = b.parent.name if b.parent else None
                if bn in fmv:
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
                rig.pose.bones[bn].matrix_basis = B
            bpy.context.view_layer.update()
            for bn, B in B_out.items():
                pb = rig.pose.bones[bn]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                if len(fmv.get(bn, {}).get('loc', {})) == 3 or B.translation.length > 1e-5:
                    pb.keyframe_insert('location', frame=f)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
        # verify: rotation err vs AF snapshot + motion arc + bbox
        scn.frame_set(frames[0])
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev = rig.evaluated_get(dg)
        A_af = snap[frames[0]]
        rerr = 0.0
        for bn in fmv:
            if bn not in rig.pose.bones:
                continue
            ang = ev.pose.bones[bn].matrix.to_3x3().to_quaternion() \
                .rotation_difference(A_af[bn].to_3x3().to_quaternion()).angle
            rerr = max(rerr, ang)
        h1 = handdir(rig, ev, 'hand_r')
        scn.frame_set(frames[-1])
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        ev2 = rig.evaluated_get(dg)
        h2 = handdir(rig, ev2, 'hand_r')
        arc = math.degrees(h1.angle(h2))
        b = bbox(OB[MESH[rk]])
        print('%s: f0..%d | rot err vs AF %.4f deg | hand arc %.2f deg | Yspan %.3f Z %.2f..%.2f'
              % (clip, frames[-1], math.degrees(rerr), arc, b[1] - b[0], b[2], b[3]))

# ---- 3) parity + pistol + save ----
scn.frame_set(0)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
print('parity A/B hand_r dir: A=[%.2f,%.2f,%.2f] B=[%.2f,%.2f,%.2f] diff=%.3f deg'
      % (ha.x, ha.y, ha.z, hb.x, hb.y, hb.z, math.degrees(ha.angle(hb))))
for pname, rk in (('PistolProp', 'A'), ('PistolProp.001', 'B')):
    p = OB[pname]
    rig = RIGS[rk]
    dg = bpy.context.evaluated_depsgraph_get()
    hw = rig.evaluated_get(dg).pose.bones['hand_r'].matrix @ rig.matrix_world
    print('%s: dims=(%.3f,%.3f,%.3f) | dist hand->pistol %.4f m | scale=(%.3f,%.3f,%.3f)'
          % (pname, p.dimensions.x, p.dimensions.y, p.dimensions.z,
             (p.matrix_world.translation - hw.translation).length,
             p.scale.x, p.scale.y, p.scale.z))

bpy.ops.wm.save_mainfile()
print('saved:', bpy.data.filepath)
'''

if __name__ == "__main__":
    print(send_code(CODE))
