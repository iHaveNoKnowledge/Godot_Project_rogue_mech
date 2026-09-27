"""Restore actions from _BAK and measure with CORRECT metrics.

1) Restores every fixed action from its _BAK copy (undo of the failed fix).
2) Measures location/scale fcurve value ranges (are translations meaningful?).
3) Measures spine direction using the bone Y-axis (head->tail), which is the
   correct 'up' for Blender bones, at several frames + REST.
4) Mesh bboxes for the same states (the honest judge).

Usage: python test/blender_mcp_pilot_restore_measure.py
"""
from blender_mcp_probe import send_code

CODE = r'''
import bpy, math
from mathutils import Vector

OB = bpy.data.objects
scn = bpy.context.scene
A = OB["Pilot_Character"]

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

def bbox(mesh_obj):
    vs = [mesh_obj.matrix_world @ Vector(v) for v in mesh_obj.bound_box]
    return (min(v.y for v in vs), max(v.y for v in vs),
            min(v.z for v in vs), max(v.z for v in vs))

print("=== 1) restore actions from _BAK ===")
for name in ("pistol_idle", "pistol_reload", "pistol_shoot"):
    bak = bpy.data.actions.get(name + "_BAK")
    act = bpy.data.actions[name]
    if bak:
        cb_dst, cb_src = None, None
        for layer in act.layers:
            for strip in layer.strips:
                cb_dst = strip.channelbags[0]
        for layer in bak.layers:
            for strip in layer.strips:
                cb_src = strip.channelbags[0]
        # wipe destination curves and copy backups over
        for fc in list(cb_dst.fcurves):
            cb_dst.fcurves.remove(fc)
        import copy as _c
        for fc in cb_src.fcurves:
            n = cb_dst.fcurves.new(data_path=fc.data_path, index=fc.array_index)
            n.keyframe_points.add(len(fc.keyframe_points))
            for i, kp in enumerate(fc.keyframe_points):
                n.keyframe_points[i].co = kp.co
                n.keyframe_points[i].interpolation = kp.interpolation
                n.keyframe_points[i].easing = kp.easing
            n.update()
        print("restored:", name)
for name in ("pistol_idle.001", "pistol_reload.001", "pistol_shoot.001"):
    if bpy.data.actions.get(name + "_BAK"):
        print("note: .001 actions were also modified; restoring", name)
        bak = bpy.data.actions[name + "_BAK"]
        act = bpy.data.actions[name]
        cb_dst = None
        for layer in act.layers:
            for strip in layer.strips:
                cb_dst = strip.channelbags[0]
        cb_src = None
        for layer in bak.layers:
            for strip in layer.strips:
                cb_src = strip.channelbags[0]
        for fc in list(cb_dst.fcurves):
            cb_dst.fcurves.remove(fc)
        for fc in cb_src.fcurves:
            n = cb_dst.fcurves.new(data_path=fc.data_path, index=fc.array_index)
            n.keyframe_points.add(len(fc.keyframe_points))
            for i, kp in enumerate(fc.keyframe_points):
                n.keyframe_points[i].co = kp.co
                n.keyframe_points[i].interpolation = kp.interpolation
                n.keyframe_points[i].easing = kp.easing
            n.update()
        print("restored:", name)

print("=== 2) location/scale channel value ranges (pistol_idle) ===")
ad = A.animation_data
ad.action = bpy.data.actions["pistol_idle"]
ranges = {}
for fc in all_fcurves(ad.action):
    if ".location" in fc.data_path or ".scale" in fc.data_path:
        vals = [kp.co[1] for kp in fc.keyframe_points]
        key = fc.data_path.rsplit(".", 1)[-1]
        lo, hi = min(vals), max(vals)
        cur = ranges.setdefault(key, [1e9, -1e9])
        ranges[key] = [min(cur[0], lo), max(cur[1], hi)]
for k, v in sorted(ranges.items()):
    print("  %s channel range across all bones: %.4f .. %.4f" % (k, v[0], v[1]))
big_loc = []
for fc in all_fcurves(ad.action):
    if ".location" in fc.data_path:
        vals = [kp.co[1] for kp in fc.keyframe_points]
        if max(abs(min(vals)), abs(max(vals))) > 0.01:
            big_loc.append((fc.data_path.split('"')[1], fc.array_index, round(min(vals), 3), round(max(vals), 3)))
print("  bones with |location| > 1cm:", big_loc[:20] if big_loc else "NONE")

print("=== 3) CORRECT spine metric (bone Y-axis vs world up) ===")
def spine_tilt(rig, ev=None):
    pel = (ev or rig).pose.bones["pelvis"]
    m = pel.matrix @ rig.matrix_world
    up = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    return math.degrees(math.acos(max(-1.0, min(1.0, up.z))))

bpy.context.view_layer.update()
A.data.pose_position = "REST"
bpy.context.view_layer.update()
print("  REST: spine tilt=%.1f deg | mesh Yspan=%.3f Z=%.3f..%.3f" % (
    spine_tilt(A), bbox(OB["Pilot_SWAT"])[1] - bbox(OB["Pilot_SWAT"])[0],
    bbox(OB["Pilot_SWAT"])[2], bbox(OB["Pilot_SWAT"])[3]))
A.data.pose_position = "POSE"
bpy.context.view_layer.update()
for f in (0, 25, 50):
    scn.frame_set(f)
    bpy.context.view_layer.update()
    b = bbox(OB["Pilot_SWAT"])
    print("  f%02d (as-is clip): spine tilt=%.1f deg | mesh Yspan=%.3f Z=%.3f..%.3f" % (
        f, spine_tilt(A), b[1] - b[0], b[2], b[3]))
scn.frame_set(0)
print("done (no save - inspect numbers first)")
'''

if __name__ == "__main__":
    print(send_code(CODE))
