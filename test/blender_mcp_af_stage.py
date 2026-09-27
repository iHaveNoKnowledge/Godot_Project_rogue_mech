"""Stage the ActionForge retargeted clips onto both pilot rigs (final).

Input: C:/Users/hackd/AppData/Local/Temp/af_retarget.json
  {clip: {duration, fps, frames, bones: {name: {q:[[w,x,y,z]..], t:[[..]]}}}}

Per rig (A then B): for each clip create/replace the action (suffix .001 on
rig B), wipe pose fcurves, per frame set matrix_basis from q/t, keyframe
rotation_quaternion + location (LINEAR). Then verify motion per clip,
restore idle binding, re-seat pistols at 0.19 m, save.

Usage: python test/blender_mcp_af_stage.py <A|B|finish>
"""
import sys

from blender_mcp_probe import send_code

STAGE = sys.argv[1] if len(sys.argv) > 1 else "A"
SRC = "C:/Users/hackd/AppData/Local/Temp/af_retarget.json"

CODE = r'''
import bpy, json, math
from mathutils import Matrix, Quaternion, Vector

STAGE = "__STAGE__"
SRC = "__SRC__"

OB = bpy.data.objects
scn = bpy.context.scene
RIGS = {"A": OB["Pilot_Character"], "B": OB["Pilot_Character.001"]}
MESH = {"A": "Pilot_SWAT", "B": "Swat_Body.001"}
PISTOL = {"A": "PistolProp", "B": "PistolProp.001"}

CLIPS = ["pistol_idle_loop", "pistol_reload", "pistol_shoot",
         "jog_fwd_l_loop", "jog_left_loop", "jog_right_loop",
         "jog_bwd_loop", "sprint_enter",
         "sword_attack", "sword_regular_combo"]

def bind(rig, act):
    ad = rig.animation_data or rig.animation_data_create()
    slot = None
    for s in act.slots:
        if s.target_id_type == "OBJECT":
            slot = s
            break
    if slot is None:
        slot = act.slots.new(id_type="OBJECT", name=rig.name)
    ad.action = act
    ad.action_slot = slot
    return ad

def wipe_pose_fcurves(act):
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in list(cb.fcurves):
                    if "pose.bones[" in fc.data_path:
                        cb.fcurves.remove(fc)

def get_or_make_action(name):
    act = bpy.data.actions.get(name)
    if act is None:
        act = bpy.data.actions.new(name)
    act.use_fake_user = True
    return act

def handdir(rig, ev, bone):
    m = ev.pose.bones[bone].matrix @ rig.matrix_world
    return (m.to_3x3() @ Vector((0, 1, 0))).normalized()

if STAGE in ("A", "B"):
    rig = RIGS[STAGE]
    data = json.load(open(SRC))
    sfx = ".001" if STAGE == "B" else ""
    # rotation-only keying: the authored source has no translation motion
    # (in-place clips, constant body height; height changes come from leg
    # rotations) and keying locations makes limbs stretch during evaluation
    LOC_KEYS = set()
    for cname in CLIPS:
        if cname not in data:
            print("missing in json:", cname)
            continue
        rec = data[cname]
        act = get_or_make_action(cname + sfx)
        bind(rig, act)
        wipe_pose_fcurves(act)
        for pb in rig.pose.bones:
            pb.matrix_basis = Matrix.Identity(4)
            pb.location = (0, 0, 0)
        n = rec["frames"]
        for fi in range(n):
            for bn, bd in rec["bones"].items():
                if bn not in rig.pose.bones:
                    continue
                q = bd["q"][fi] if fi < len(bd["q"]) else [1, 0, 0, 0]
                t = bd["t"][fi] if fi < len(bd["t"]) else [0, 0, 0]
                pb = rig.pose.bones[bn]
                pb.rotation_quaternion = Quaternion([q[0], q[1], q[2], q[3]])
                pb.location = Vector([t[0], t[1], t[2]]) if bn in LOC_KEYS else Vector((0, 0, 0))
            bpy.context.view_layer.update()
            for bn in rec["bones"]:
                if bn not in rig.pose.bones:
                    continue
                pb = rig.pose.bones[bn]
                pb.keyframe_insert("rotation_quaternion", frame=fi)
                if bn in LOC_KEYS:
                    pb.keyframe_insert("location", frame=fi)
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    for fc in cb.fcurves:
                        for k in fc.keyframe_points:
                            k.interpolation = "LINEAR"
        print("%s%s: staged %d frames, %d bones" % (cname, sfx, n, len(rec["bones"])))

elif STAGE == "finish":
    data = json.load(open(SRC))
    ok = True
    for rk, rig in RIGS.items():
        sfx = ".001" if rk == "B" else ""
        for cname in CLIPS:
            aname = cname + sfx
            if aname not in bpy.data.actions:
                print("MISSING action:", aname)
                ok = False
                continue
            act = bpy.data.actions[aname]
            bind(rig, act)
            frames = data[cname]["frames"]
            scn.frame_set(0)
            bpy.context.view_layer.update()
            dg = bpy.context.evaluated_depsgraph_get()
            ev = rig.evaluated_get(dg)
            h1 = handdir(rig, ev, "hand_r")
            q1 = ev.pose.bones["thigh_l"].matrix.to_3x3().to_quaternion()
            dev = 0.0
            ymin = 1e9
            for f in range(frames):
                scn.frame_set(f)
                bpy.context.view_layer.update()
                dg = bpy.context.evaluated_depsgraph_get()
                evf = rig.evaluated_get(dg)
                dev = max(dev, math.degrees(q1.rotation_difference(
                    evf.pose.bones["thigh_l"].matrix.to_3x3().to_quaternion()).angle))
                mesh = OB[MESH[rk]]
                vs = [mesh.matrix_world @ Vector(v) for v in mesh.bound_box]
                ymin = min(ymin, min(v.z for v in vs))
            moving = dev > 8.0
            print("%s (%s): leg motion %.1f deg | mesh ymin %.3f | %s"
                  % (aname, rk, dev, ymin, "OK" if (ymin > -0.08 and (moving or cname.startswith("pistol"))) else "FAIL"))
            if not (ymin > -0.08 and (moving or cname.startswith("pistol"))):
                ok = False
    # re-seat pistols at idle f0
    for rk in ("A", "B"):
        rig = RIGS[rk]
        p = OB[PISTOL[rk]]
        bind(rig, bpy.data.actions["pistol_idle_loop" + (".001" if rk == "B" else "")])
        scn.frame_set(0)
        bpy.context.view_layer.update()
        cur = max(p.dimensions)
        if abs(cur - 0.19) > 0.005:
            s = 0.19 / cur
            p.scale = (p.scale.x * s, p.scale.y * s, p.scale.z * s)
            bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        hw = (rig.evaluated_get(dg).pose.bones["hand_r"].matrix @ rig.matrix_world)
        fwd = Vector((0.0, -1.0, 0.0))
        rot = Matrix.LocRotScale(None, fwd.to_track_quat("Z", "Y"), None)
        want = Matrix.Translation(hw.translation + Vector((0, -0.035, 0)) + fwd * 0.02) \
            @ rot @ Matrix.LocRotScale(None, None, p.scale)
        actual = p.matrix_world.copy()
        M = actual @ p.matrix_basis.inverted()
        p.matrix_basis = M.inverted() @ want
        bpy.context.view_layer.update()
        print("%s seated err=%.5f" % (PISTOL[rk], (p.matrix_world.translation - want.translation).length))
    bpy.ops.wm.save_mainfile()
    print("saved:", bpy.data.filepath)
    print("OVERALL:", "PASS" if ok else "CHECK FAILURES")
'''.replace("__STAGE__", STAGE).replace("__SRC__", SRC)

if __name__ == "__main__":
    print(send_code(CODE))
