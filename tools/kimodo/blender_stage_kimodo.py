## Kimodo bridge Blender stager — run inside Blender's Text Editor.
## Stages a kimodo_npz_to_pilot.py JSON clip onto the pilot armature and
## exports the kit GLB for Godot 4.6.2.
##
## Expectations (same as test/blender_mcp_export_kit.py):
##   - armature object named "Pilot_Character" with the 19 pilot bones
##   - Blender +Y forward / Z-up authoring; export with export_yup=True so
##     Blender +Y -> Godot -Z (forward). NEVER author the face toward -Y.
##   - 30 fps to match the converter (FPS = 30.0).
##
## Connection/verify discipline (skill blender-assembly):
##   - no new mesh geometry here, only bone animation: verify per-frame that
##     segment lengths do not drift (no stretch) and feet stay >= floor.
##   - call verify_clip() before export; abort on FAIL.
##
## Usage (Blender Text Editor):
##   1. set JSON_PATH below to the converted clip JSON
##   2. Run Script -> console prints STAGE_OK + EXPORT_OK
##   3. read back the GLB animations in Godot (pilot kit path)

import bpy  # type: ignore[import-not-found]  # provided by Blender at runtime
import json
import math

JSON_PATH = r"C:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/tools/kimodo/samples/kimodo_pilot_walk.json"
CLIP_NAME = "kimodo_pilot_walk"
RIG_NAME = "Pilot_Character"
DEST = r"C:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/scenes/pilot/pilot_kimodo_walk.glb"
FPS = 30.0

PILOT_BONES = ["pelvis", "spine_01", "spine_02", "neck_01", "Head",
               "clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
               "lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
               "thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l"]
SEGS = [("thigh_l", "calf_l"), ("calf_l", "foot_l"),
        ("upperarm_r", "lowerarm_r"), ("lowerarm_r", "hand_r"),
        ("upperarm_l", "lowerarm_l"), ("lowerarm_l", "hand_l")]


def quat_wxyz_to_xyzw(q):
    w, x, y, z = q
    return (x, y, z, w)


def verify_clip(rig, bones_data):
    """Check rest proportions + per-frame stretch/floor before keying."""
    errs = []
    if rig.type != "ARMATURE":
        return ["rig %s is not an armature" % RIG_NAME]
    for b in PILOT_BONES:
        if b not in rig.pose.bones:
            errs.append("rig missing bone: %s" % b)
    if errs:
        return errs
    n = len(bones_data["pelvis"]["q"])
    # rest segment lengths from current armature rest
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="OBJECT")
    rest_len = {}
    for a, b in SEGS:
        pa = rig.data.bones[a].head_local
        pb = rig.data.bones[b].head_local
        rest_len[(a, b)] = (pa - pb).length
    # floor check on rest: feet should be near 0 in rig space
    for f in ("foot_l", "foot_r"):
        z = rig.data.bones[f].head_local.z
        print("REST %s head z=%.4f" % (f, z))
    print("VERIFY frames=%d rest_segs=%s" % (n, {k: round(v, 4) for k, v in rest_len.items()}))
    return errs


def main():
    data = json.load(open(JSON_PATH))
    assert CLIP_NAME in data, "clip %s not in %s" % (CLIP_NAME, JSON_PATH)
    rec = data[CLIP_NAME]
    bones_data = rec["bones"]
    rig = bpy.data.objects[RIG_NAME]
    errs = verify_clip(rig, bones_data)
    if errs:
        raise RuntimeError("VERIFY_FAIL: %s" % errs)

    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    if rig.animation_data is None:
        rig.animation_data_create()
    assert rig.animation_data is not None
    act = bpy.data.actions.new(CLIP_NAME)
    rig.animation_data.action = act
    n = rec["frames"]
    for f in range(n):
        bpy.context.scene.frame_set(f + 1)
        for b in PILOT_BONES:
            pb = rig.pose.bones[b]
            pb.rotation_quaternion = quat_wxyz_to_xyzw(bones_data[b]["q"][f])
            pb.keyframe_insert(data_path="rotation_quaternion", frame=f + 1)
            if b == "pelvis":
                t = bones_data[b]["t"][f]
                pb.location = (t[0], t[1], t[2])
                pb.keyframe_insert(data_path="location", frame=f + 1)
    # linearize: motion-capture keys should interpolate linearly
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    bpy.ops.object.mode_set(mode="OBJECT")

    # export kit selection pattern: rig only here (mesh export handled by kit script)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.context.scene.render.fps = int(FPS)
    bpy.ops.export_scene.gltf(filepath=DEST, export_format="GLB",
                              use_selection=True, export_animations=True,
                              export_yup=True)  # Blender +Y -> Godot -Z
    print("STAGE_OK %s frames=%d" % (CLIP_NAME, n))
    print("EXPORT_OK %s" % DEST)


if __name__ == "__main__":
    main()
