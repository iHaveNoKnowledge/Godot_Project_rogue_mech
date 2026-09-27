"""Retarget pistol clips onto Pilot_Character rigs - v5 (root cause fix).

Root cause (established by measurement): the clip fcurves store ARMATURE-SPACE
rotations written into bone-local rotation_quaternion channels (classic
retarget bug from the original retarget commit). Evidence: reading the same
quats as armature-space gives a near-upright pelvis (~21.5 deg) while
bone-local interpretation gives the 98.9-deg Michael-Jackson tilt seen in
game. (AF_Rig evaluation is unusable as ground truth: hidden objects are
skipped by the background depsgraph, so its eval was frozen at REST.)

Fix, closed-form per rig (no depsgraph, no AF):
  For each frame, for each animated bone J (parent-first):
    R(J)  = fcurve quat, interpreted as armature-space rotation
    p(J)  = p(parent) + R(parent) @ (restT(J) - restT(parent));  root adds
            its raw location delta (in-place clips)
    A(J)  = Translation(p) @ R
    B(J)  = K(J)^-1 @ (A(parent)^-1 @ A(J))   -> re-key as bone-local
  Rig B shares the same source quats with its own rest chain K_B.

Stages (run separately to keep each MCP call short):
  python blender_mcp_pilot_retarget5.py cache    # snapshot source quats to JSON
  python blender_mcp_pilot_retarget5.py A        # rebuild rig A actions
  python blender_mcp_pilot_retarget5.py B        # rebuild rig B actions
  python blender_mcp_pilot_retarget5.py finish   # verify + pistol re-seat + save

Usage: python test/blender_mcp_pilot_retarget5.py <stage>
"""
import json
import sys

from blender_mcp_probe import send_code

STAGE = sys.argv[1] if len(sys.argv) > 1 else "cache"
CACHE = "C:/Users/hackd/AppData/Local/Temp/pilot_src_cache.json"

CODE = r'''
import bpy, json, math, os
from mathutils import Matrix, Quaternion, Vector

STAGE = "__STAGE__"
CACHE = "__CACHE__"

OB = bpy.data.objects
scn = bpy.context.scene
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

for rk, rig in RIGS.items():
    set_pos(rig, 'REST')
Ks = {rk: build_K(rig) for rk, rig in RIGS.items()}
REST_T = {rk: {b.name: b.matrix_local.translation.copy() for b in rig.data.bones} for rk, rig in RIGS.items()}
REST_ARM = {rk: {b.name: b.matrix_local.copy() for b in rig.data.bones} for rk, rig in RIGS.items()}
for rk, rig in RIGS.items():
    set_pos(rig, 'POSE')

ORDER = {}
for rk, rig in RIGS.items():
    depth = {}
    def walk(b, d):
        depth[b.name] = d
        for c in b.children:
            walk(c, d + 1)
    for b in rig.data.bones:
        if b.parent is None:
            walk(b, 0)
    ORDER[rk] = sorted(depth.keys(), key=lambda n: depth[n])

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

if STAGE == 'cache':
    cache = {}
    for clip in SRC:
        act = bpy.data.actions[clip]
        fmv = fc_map(act)
        frames = frames_of(act)
        data = {}
        for bn, ch in fmv.items():
            rq = []
            loc = []
            for f in frames:
                if len(ch['rq']) == 4:
                    q = Quaternion([ch['rq'][i].evaluate(f) for i in range(4)])
                    rq.append([round(q.w, 6), round(q.x, 6), round(q.y, 6), round(q.z, 6)])
                if len(ch['loc']) == 3:
                    loc.append([round(ch['loc'][i].evaluate(f), 6) for i in range(3)])
            data[bn] = {'rq': rq, 'loc': loc}
        cache[clip] = {'frames': frames, 'bones': data}
        print('%s cached: %d frames, %d bones' % (clip, len(frames), len(data)))
    json.dump(cache, open(CACHE, 'w'))
    print('cache written:', CACHE)

elif STAGE in ('A', 'B'):
    rig = RIGS[STAGE]
    cache = json.load(open(CACHE))
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
            # pass 1: armature-space positions from rest positions + rotation deltas
            R_arm = {}
            p_arm = {}
            for bn in ORDER[STAGE]:
                if bn not in bones:
                    continue
                q = bones[bn]['rq'][fi] if bones[bn]['rq'] else [1, 0, 0, 0]
                R = Quaternion([q[0], q[1], q[2], q[3]]).to_matrix().to_3x3()
                R_arm[bn] = R
                par = rig.data.bones[bn].parent
                if par is None:
                    p = REST_ARM[STAGE][bn].translation.copy()
                    if bones[bn]['loc']:
                        p += Vector(bones[bn]['loc'][fi])
                else:
                    pn = par.name
                    # delta of parent's animated arm-space rotation vs its rest
                    delta = R_arm[pn] @ REST_ARM[STAGE][pn].to_3x3().inverted()
                    p = p_arm[pn] + delta @ (REST_ARM[STAGE][bn].translation -
                                             REST_ARM[STAGE][pn].translation)
                p_arm[bn] = p
            # pass 2: bone-local basis solve
            A_t = {}
            B_out = {}
            for bn in ORDER[STAGE]:
                if bn not in bones:
                    continue
                par = rig.data.bones[bn].parent
                A_t[bn] = Matrix.Translation(p_arm[bn]) @ R_arm[bn].to_4x4()
                L = A_t[par.name].inverted() @ A_t[bn] if par else A_t[bn]
                B_out[bn] = Ks[STAGE][bn].inverted() @ L
            for bn, B in B_out.items():
                rig.pose.bones[bn].matrix_basis = B
            bpy.context.view_layer.update()
            for bn, B in B_out.items():
                pb = rig.pose.bones[bn]
                pb.keyframe_insert('rotation_quaternion', frame=f)
                pb.keyframe_insert('location', frame=f)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = 'LINEAR'
        print('%s: rebuilt %d frames, %d bones keyed' % (clip, len(frames), len(B_out)))

elif STAGE == 'finish':
    cache = json.load(open(CACHE))
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
            for f in frames:
                scn.frame_set(f)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                evf = rig.evaluated_get(dg)
                q = evf.pose.bones['upperarm_l'].matrix.to_3x3().to_quaternion()
                dev = max(dev, math.degrees(q1.rotation_difference(q).angle))
            scn.frame_set(frames[0])
            bpy.context.view_layer.update()
            b = bbox(OB[MESH[rk]])
            print('%s: Yspan %.3f Z %.2f..%.2f | hand_r=[%.2f,%.2f,%.2f] | upperarm_l dev %.2f deg'
                  % (clip, b[1] - b[0], b[2], b[3], h1.x, h1.y, h1.z, dev))
    scn.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ha = handdir(RIGS['A'], RIGS['A'].evaluated_get(dg), 'hand_r')
    hb = handdir(RIGS['B'], RIGS['B'].evaluated_get(dg), 'hand_r')
    print('parity A/B hand_r: A=[%.2f,%.2f,%.2f] B=[%.2f,%.2f,%.2f] diff=%.3f deg'
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
'''.replace("__STAGE__", STAGE).replace("__CACHE__", CACHE)

if __name__ == "__main__":
    print(send_code(CODE))
