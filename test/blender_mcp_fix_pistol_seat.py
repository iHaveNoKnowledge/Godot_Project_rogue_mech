"""Fix the pilot pistol seat and finger wrap; report hand/pistol metrics.

Root cause found by end-cap analysis: the prop's long (barrel) axis is local
Y (A muzzle at -Y, B muzzle at +Y), but the old re-seat assumed the barrel was
local +Z -> both guns stood upright (muzzles up/down instead of forward).

Modes:
  report       finger curl + hand/pistol metrics at idle f0 (no changes)
  fix          re-seat both props (muzzle = hand_r grip axis, top = +Z, grip
               on palm), verify, hide duplicate rig B, save
  curlfingers  wipe authored finger keys, build a fist-curl plan on rig A by
               probing local axes per segment (tip -> grip anchor), apply the
               plan to both rigs, bake constant keys on every clip, save
  zerofingers  emergency: drop authored finger fcurves from all staged clips

Usage: python test/blender_mcp_fix_pistol_seat.py <report|fix|curlfingers|zerofingers>
"""
import sys

from blender_mcp_probe import send_code

MODE = sys.argv[1] if len(sys.argv) > 1 else "report"

CODE = r'''
import bpy
import math
from mathutils import Vector, Matrix, Quaternion

MODE = "__MODE__"
OB = bpy.data.objects
scn = bpy.context.scene

RIGS = {"A": OB["Pilot_Character"], "B": OB["Pilot_Character.001"]}
PISTOL = {"A": OB["PistolProp"], "B": OB["PistolProp.001"]}
MUZZLE_LOCAL = {"A": Vector((0, -1, 0)), "B": Vector((0, 1, 0))}  # barrel axis sign
TOP = Vector((0, 0, 1))  # slide-top (world-up target) for both props
CLIPS = ["pistol_idle_loop", "pistol_reload", "pistol_shoot", "jog_fwd_l_loop",
         "jog_left_loop", "jog_right_loop", "jog_bwd_loop", "sprint_enter",
         "sword_attack", "sword_regular_combo"]
FING = ("thumb_", "index_", "middle_", "ring_", "pinky_")

def bind(rig, act):
    ad = rig.animation_data or rig.animation_data_create()
    slot = next((s for s in act.slots if s.target_id_type == "OBJECT"), None)
    if slot is None:
        slot = act.slots.new(id_type="OBJECT", name=rig.name)
    ad.action = act
    ad.action_slot = slot

def to_f0(rk):
    rig = RIGS[rk]
    sfx = ".001" if rk == "B" else ""
    bind(rig, bpy.data.actions["pistol_idle_loop" + sfx])
    scn.frame_set(0)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = rig.evaluated_get(dg)
    hand = ev.pose.bones["hand_r"]
    mw = hand.matrix @ rig.matrix_world
    ydir = (mw.to_3x3() @ Vector((0, 1, 0))).normalized()
    palm = mw.translation + ydir * 0.04
    return rig, ev, ydir, palm

def grip_anchor(p):
    """Local-space centre of the grip mass (below/behind the bore)."""
    vs = [v.co for v in p.data.vertices]
    if p.name == "PistolProp":  # A: grip hangs to -Z
        zs = [c.z for c in vs]
        cut = min(zs) + 0.25 * (max(zs) - min(zs))
        grp = [c for c in vs if c.z < cut]
    else:  # B: grip at the rear end, lower z half
        ys = [c.y for c in vs]
        cut = min(ys) + 0.35 * (max(ys) - min(ys))
        grp = [c for c in vs if c.y < cut and c.z < 0]
    n = len(grp)
    return Vector((sum(c.x for c in grp) / n, sum(c.y for c in grp) / n,
                   sum(c.z for c in grp) / n))

if MODE == "report":
    for rk in ("A", "B"):
        rig, ev, ydir, palm = to_f0(rk)
        p = PISTOL[rk]
        grip_w = p.matrix_world @ grip_anchor(p)
        print("[%s] hand_r Y dir %s | palm %s | grip(world) %s | grip-palm %.3f"
              % (rk, tuple(round(v, 3) for v in ydir),
                 tuple(round(v, 3) for v in palm),
                 tuple(round(v, 3) for v in grip_w), (grip_w - palm).length))
        hl = ev.pose.bones["hand_l"].matrix @ rig.matrix_world
        print("[%s] hand_l wrist %s | to grip %.3f" % (
            rk, tuple(round(v, 3) for v in hl.translation),
            (hl.translation - grip_w).length))
        for side in ("r", "l"):
            dsts = []
            for ch in ("index", "middle", "ring", "pinky"):
                tb = ev.pose.bones.get("%s_03_%s" % (ch, side))
                tip = rig.matrix_world @ tb.tail if tb else None
                dsts.append(round((tip - palm).length, 3) if tip else -1)
            print("[%s] %s fingertips->palm_r: %s" % (rk, side, dsts))
elif MODE == "fix":
    for rk in ("A", "B"):
        rig, ev, ydir, palm = to_f0(rk)
        p = PISTOL[rk]
        g = grip_anchor(p)
        # world image of the local barrel axis = the hand's grip axis
        # A: muzzle local -Y -> muzzle_img = ydir  => Y_img = -ydir
        # B: muzzle local +Y -> muzzle_img = ydir  => Y_img = +ydir
        Y_img = -ydir if rk == "A" else ydir
        Z_img = TOP
        X_img = Y_img.cross(Z_img).normalized()
        rot = Matrix((
            (X_img.x, Y_img.x, Z_img.x, 0.0),
            (X_img.y, Y_img.y, Z_img.y, 0.0),
            (X_img.z, Y_img.z, Z_img.z, 0.0),
            (0.0, 0.0, 0.0, 1.0)))
        # place grip anchor onto the palm
        origin = palm - rot.to_3x3() @ g
        want = Matrix.Translation(origin) @ rot @ Matrix.LocRotScale(None, None, p.scale)
        actual = p.matrix_world.copy()
        chain = actual @ p.matrix_basis.inverted()
        p.matrix_basis = chain.inverted() @ want
        bpy.context.view_layer.update()
        err = (p.matrix_world.translation - want.translation).length
        mw2 = p.matrix_world
        muz_w = mw2 @ MUZZLE_LOCAL[rk]
        muz_d = (muz_w - mw2.translation).normalized()
        grip_w2 = mw2 @ g
        print("[%s] seat err %.5f | muzzle dir %s (handY dot %.3f) | muzzle-palm %.3f | grip-palm %.3f"
              % (rk, err, tuple(round(v, 3) for v in muz_d), muz_d.dot(ydir),
                 (muz_w - palm).length, (grip_w2 - palm).length))
    # hide the duplicate rig B so the viewport shows ONE pilot + ONE pistol
    for nm in ("Pilot_Character.001", "Swat_Body.001", "Swat_Feet.001",
               "Swat_Head.001", "Swat_Legs.001", "PistolProp.001"):
        OB[nm].hide_viewport = True
        print("hidden:", nm)
    bpy.ops.wm.save_mainfile()
    print("saved:", bpy.data.filepath)
elif MODE == "curlfingers":
    def ev_get(rig):
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        return rig.evaluated_get(dg)

    # hidden objects are skipped by the viewport depsgraph -> unhide all kit
    for o in OB:
        if o.type in ("ARMATURE", "MESH") and (
                "Pilot" in o.name or "Swat" in o.name or "Pistol" in o.name):
            o.hide_viewport = False
            o.hide_set(False)

    # 1) wipe authored finger keys + reset finger pose on both rigs
    for rk in ("A", "B"):
        rig = RIGS[rk]
        sfx = ".001" if rk == "B" else ""
        for cn in CLIPS:
            act = bpy.data.actions.get(cn + sfx)
            if act is None:
                continue
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in strip.channelbags:
                        for fc in list(cb.fcurves):
                            if "pose.bones[" in fc.data_path and any(
                                    f in fc.data_path for f in FING):
                                cb.fcurves.remove(fc)
        for pb in rig.pose.bones:
            if any(pb.name.startswith(f) for f in FING):
                pb.rotation_quaternion = Quaternion((0, 0, 1), 0.0)

    # 2) build the curl plan on rig A at idle f0: per segment, probe local
    #    axes and keep the rotation that pulls the fingertip to the grip
    rigA = RIGS["A"]
    bind(rigA, bpy.data.actions["pistol_idle_loop"])
    scn.frame_set(0)
    evA = ev_get(rigA)
    handA = evA.pose.bones["hand_r"].matrix @ rigA.matrix_world
    ydirA = (handA.to_3x3() @ Vector((0, 1, 0))).normalized()
    grip_w = handA.translation + ydirA * 0.05  # pistol grip anchor point

    def tip_pos(rig, chain, side):
        e = ev_get(rig)
        tb = e.pose.bones.get("%s_03_%s" % (chain, side))
        return (rig.matrix_world @ tb.tail) if tb else None

    LOC_AX = (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
    ANG = {"01": math.radians(35.0), "02": math.radians(45.0),
           "03": math.radians(30.0)}
    planA = {}
    for side in ("r", "l"):
        for chain in ("thumb", "index", "middle", "ring", "pinky"):
            segs = ["%s_%s_%s" % (chain, lv, side) for lv in ("01", "02", "03")
                    if rigA.pose.bones.get("%s_%s_%s" % (chain, lv, side))]
            for seg in segs:
                pb = rigA.pose.bones[seg]
                lv = seg.split("_")[1]
                B0 = pb.rotation_quaternion.copy()
                d0 = (tip_pos(rigA, chain, side) - grip_w).length
                best = None
                for a in LOC_AX:
                    for sgn in (1.0, -1.0):
                        pb.rotation_quaternion = (B0 @ Quaternion(
                            a, sgn * ANG[lv])).normalized()
                        d = (tip_pos(rigA, chain, side) - grip_w).length
                        if best is None or d < best[0]:
                            best = (d, a, sgn)
                if best is not None and best[0] < d0 - 1e-4:
                    pb.rotation_quaternion = (B0 @ Quaternion(
                        best[1], best[2] * ANG[lv])).normalized()
                    planA[seg] = [best[1], best[2], ANG[lv]]
                else:
                    pb.rotation_quaternion = B0
    # second pass: extra half-steps where they still help (deeper wrap)
    for side in ("r", "l"):
        for chain in ("thumb", "index", "middle", "ring", "pinky"):
            segs = ["%s_%s_%s" % (chain, lv, side) for lv in ("01", "02", "03")]
            for seg in segs:
                if seg not in planA:
                    continue
                a, sgn, ang = planA[seg]
                pb = rigA.pose.bones[seg]
                B0 = pb.rotation_quaternion.copy()
                d0 = (tip_pos(rigA, chain, side) - grip_w).length
                pb.rotation_quaternion = (B0 @ Quaternion(
                    a, sgn * ang * 0.5)).normalized()
                d = (tip_pos(rigA, chain, side) - grip_w).length
                if d < d0 - 1e-4:
                    planA[seg][2] = ang * 1.5
                else:
                    pb.rotation_quaternion = B0
    print("[A] plan: %s" % {k: (v[0].toString() if hasattr(v[0], "toString") else str(v[0]),
                                "+" if v[1] > 0 else "-",
                                round(math.degrees(v[2]), 0))
                             for k, v in planA.items()})
    for side in ("r", "l"):
        for chain in ("thumb", "index", "middle", "ring", "pinky"):
            t = tip_pos(rigA, chain, side)
            if t:
                print("[A] %s_%s tip->grip %.3f" % (chain, side, (t - grip_w).length))

    # 3) apply the plan to both rigs and bake constant keys on every clip
    for rk in ("A", "B"):
        rig = RIGS[rk]
        sfx = ".001" if rk == "B" else ""
        for pb in rig.pose.bones:
            if any(pb.name.startswith(f) for f in FING):
                pb.rotation_quaternion = Quaternion((0, 0, 1), 0.0)
        for seg, (a, sgn, ang) in planA.items():
            if seg in rig.pose.bones:
                rig.pose.bones[seg].rotation_quaternion = Quaternion(a, sgn * ang)
        for cn in CLIPS:
            act = bpy.data.actions.get(cn + sfx)
            if act is None:
                continue
            bind(rig, act)
            cnt = 0
            for seg in planA:
                if seg in rig.pose.bones:
                    rig.pose.bones[seg].keyframe_insert("rotation_quaternion", frame=0)
                    cnt += 1
            print("%s%s: baked %d curl keys" % (cn, sfx, cnt))
        # final report on this rig
        bind(rig, bpy.data.actions["pistol_idle_loop" + sfx])
        scn.frame_set(0)
        dsts = []
        for side in ("r", "l"):
            for chain in ("thumb", "index", "middle", "ring", "pinky"):
                t = tip_pos(rig, chain, side)
                if t:
                    dsts.append(("%s_%s" % (chain[:2], side), round((t - grip_w).length, 3)))
        print("[%s] final tip->grip: %s" % (rk, dsts))

    # re-hide duplicate rig B
    for nm in ("Pilot_Character.001", "Swat_Body.001", "Swat_Feet.001",
               "Swat_Head.001", "Swat_Legs.001", "PistolProp.001"):
        OB[nm].hide_viewport = True
    bpy.ops.wm.save_mainfile()
    print("saved:", bpy.data.filepath)
elif MODE == "zerofingers":
    for rk in ("A", "B"):
        rig = RIGS[rk]
        sfx = ".001" if rk == "B" else ""
        for cn in CLIPS:
            act = bpy.data.actions.get(cn + sfx)
            if act is None:
                continue
            n = 0
            for layer in act.layers:
                for strip in layer.strips:
                    for cb in strip.channelbags:
                        for fc in list(cb.fcurves):
                            if "pose.bones[" in fc.data_path and any(
                                    f in fc.data_path for f in FING):
                                cb.fcurves.remove(fc)
                                n += 1
            print("%s%s: removed %d finger fcurves" % (cn, sfx, n))
    bpy.ops.wm.save_mainfile()
    print("saved")
'''.replace("__MODE__", MODE)

if __name__ == "__main__":
    print(send_code(CODE))
