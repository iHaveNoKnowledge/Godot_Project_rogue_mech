"""Retarget pistol clips onto Pilot_Character rigs - v7 (reconstructed A_af).

Established facts:
 - The GLB joint-locals L ARE the original rig's armature-space poses
   (exporter merges rest x pose). The Blender action stores B = L @ K_af^-1
   (bone-local on AF) - the arm-space meaning is recoverable exactly:
       A_af(J, f) = A_af(parent, f) @ (K_af(J) @ B(J, f))   (chain recursion)
   (The earlier "model mismatch" abort was a false positive: the depsgraph
   skipped the HIDDEN AF object, freezing its evaluation at REST.)
 - Therefore the correct target pose for each rig: arm-space rotation of
   bone J := rotation of A_af(J); positions chain the rig's OWN rest
   offsets, conjugated by the parent's arm-space rotation delta vs rest:
       p(J) = p(par) + dR(par) @ (restT(J) - restT(par)),
       dR(par) = R_tgt(par) @ R_rest(par)^-1 ;  root adds raw loc delta.
 - Bone-local basis: B_tgt(J) = K(J)^-1 @ (A_tgt(par)^-1 @ A_tgt(J)).
 - v5 lesson: raw fcurve quats are NOT arm-space rotations (that produced
   the flung mesh); only the reconstructed A_af rotations are.

Stages: A -> B -> finish (verify + pistol re-seat + save).
Source cache: pilot_src_cache.json (retarget5.py cache).

Usage: python test/blender_mcp_pilot_retarget7.py <A|B|finish>
"""
import json
import sys

from blender_mcp_probe import send_code

STAGE = sys.argv[1] if len(sys.argv) > 1 else "A"
CACHE = "C:/Users/hackd/AppData/Local/Temp/pilot_src_cache.json"

CODE = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

STAGE = "__STAGE__"
CACHE = "__CACHE__"

OB = bpy.data.objects
scn = bpy.context.scene
AF = OB['AF_Rig']
RIGS = {'A': OB['Pilot_Character'], 'B': OB['Pilot_Character.001']}
MESH = {'A': 'Pilot_SWAT', 'B': 'Swat_Body.001'}
CLIPS = {'A': ['pistol_idle', 'pistol_reload', 'pistol_shoot'],
         'B': ['pistol_idle.001', 'pistol_reload.001', 'pistol_shoot.001']}

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
ORDER = {rk: order_of(RIGS[rk]) for rk in RIGS}
for rk in RIGS:
    set_pos(RIGS[rk], 'POSE')
set_pos(AF, 'REST')
K_AF = build_K(AF)
ORDER_AF = order_of(AF)
set_pos(AF, 'POSE')

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
        print('(recreated missing action: %s)' % name)
    return act

cache = json.load(open(CACHE))

if STAGE in ('A', 'B'):
    rig = RIGS[STAGE]
    for clip in CLIPS[STAGE]:
        src = clip[:-4] if STAGE == 'B' else clip
        frames = cache[src]['frames']
        bones = cache[src]['bones']
        act = get_or_make_action(clip)
        bind(rig, act)
        wipe_pose_fcurves(act)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
        for f in frames:
            fi = frames.index(f)
            # 1) reconstruct source armature-space pose (chain recursion)
            A_af = {}
            for bn in ORDER_AF:
                B = Matrix.Identity(4)
                if bn in bones:
                    jd = bones[bn]
                    if jd['rq']:
                        q = jd['rq'][fi]
                        t = Vector(jd['loc'][fi]) if jd['loc'] else Vector((0, 0, 0))
                        B = Matrix.Translation(t) @ Quaternion([q[0], q[1], q[2], q[3]]).to_matrix().to_4x4()
                par = AF.data.bones[bn].parent
                L = K_AF[bn] @ B
                A_af[bn] = A_af[par.name] @ L if par else L
            # 2) target arm-space pose: L rotations + own rest positions
            R_t = {}
            p_t = {}
            rootname = ORDER[STAGE][0]
            for bn in ORDER[STAGE]:
                par = rig.data.bones[bn].parent
                if bn in A_af:
                    R = A_af[bn].to_3x3().copy()
                else:
                    R = REST_R[STAGE][bn].copy()  # Body, *_end: rest
                R_t[bn] = R
                if par is None:
                    p = REST_ARM[STAGE][bn].translation.copy()
                    if bn in bones and bones[bn]['loc']:
                        p += Vector(bones[bn]['loc'][fi])
                else:
                    pn = par.name
                    dR = R_t[pn] @ REST_R[STAGE][pn].inverted()
                    p = p_t[pn] + dR @ (REST_ARM[STAGE][bn].translation -
                                        REST_ARM[STAGE][pn].translation)
                p_t[bn] = p
            # 3) bone-local basis solve (parent-first)
            A_t = {}
            for bn in ORDER[STAGE]:
                if bn not in bones:
                    continue
                par = rig.data.bones[bn].parent
                A_t[bn] = Matrix.Translation(p_t[bn]) @ R_t[bn].to_4x4()
                L = A_t[par.name].inverted() @ A_t[bn] if par else A_t[bn]
                rig.pose.bones[bn].matrix_basis = Ks[STAGE][bn].inverted() @ L
            bpy.context.view_layer.update()
            for bn in bones:
                if bn not in rig.pose.bones:
                    continue
                pb = rig.pose.bones[bn]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                pb.keyframe_insert('location', frame=f)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
        print('%s: rebuilt %d frames' % (clip, len(frames)))

elif STAGE == 'finish':
    for rk, rig in RIGS.items():
        for clip in CLIPS[rk]:
            src = clip[:-4] if rk == 'B' else clip
            frames = cache[src]['frames']
            act = bpy.data.actions[clip]
            bind(rig, act)
            scn.frame_set(frames[0])
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev = rig.evaluated_get(dg)
            h1 = handdir(rig, ev, 'hand_r')
            q1 = ev.pose.bones['upperarm_l'].matrix.to_3x3().to_quaternion()
            dev = 0.0
            zmin = 1e9; zmax = -1e9; yspan = 0.0
            for f in frames:
                scn.frame_set(f)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                evf = rig.evaluated_get(dg)
                q = evf.pose.bones['upperarm_l'].matrix.to_3x3().to_quaternion()
                dev = max(dev, math.degrees(q1.rotation_difference(q).angle))
                b = bbox(OB[MESH[rk]])
                zmin = min(zmin, b[2]); zmax = max(zmax, b[3])
                yspan = max(yspan, b[1] - b[0])
            print('%s: Yspan max %.3f Z %.2f..%.2f | hand_r=[%.2f,%.2f,%.2f] | upperarm_l dev %.2f deg'
                  % (clip, yspan, zmin, zmax, h1.x, h1.y, h1.z, dev))
    scn.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
    hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
    print('parity A/B hand_r: diff=%.3f deg' % math.degrees(ha.angle(hb)))
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
        print('%s: dims=(%.3f,%.3f,%.3f) | seated err=%.5f'
              % (pname, p.dimensions.x, p.dimensions.y, p.dimensions.z,
                 (p.matrix_world.translation - want.translation).length))
    bpy.ops.wm.save_mainfile()
    print('saved:', bpy.data.filepath)
'''.replace("__STAGE__", STAGE).replace("__CACHE__", CACHE)

if __name__ == "__main__":
    print(send_code(CODE))
