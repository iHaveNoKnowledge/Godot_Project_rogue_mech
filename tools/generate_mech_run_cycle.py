## Mech Run Cycle generator — propulsive run, not a hung puppet.
## Run inside Blender's Text Editor (Blender 5.x, layered actions).
## Rig needed: Mech_Rig with bones Root > Body(pelvis) > Head/ArmL/ArmR/LegL/LegR,
## ForeL/ForeR under arms, ShinL/ShinR under legs. Run ENSURE_RIG first once.
## Conventions: Blender Z-up, +Y forward. Limb +X rotation = forward swing.
##montage: 28-frame loop @30fps, 2 steps. Phases per step:
##  CONTACT (f1/f15): pelvis dips low to take body weight, lead leg reaches,
##    trail leg at FULL EXTENSION.
##  ABSORB (f5/f19): pelvis lowest, stance knee folds, toe-off begins.
##    Curve exits SLOW here (resist) ...
##  PUSH-OFF (f8/f22): pelvis drives UP & FORWARD, stance leg extended back,
##    opposite knee HIGH and tucked. Curve arrives STEEP here (snap/explode).
##  FLIGHT (f12/f26): pelvis apex, legs scissor mid-air, slight stretch.

import bpy  # type: ignore[import-not-found]  # provided by Blender at runtime
import math

D = math.radians
RIG_NAME = "Mech_Rig"
ACTION_NAME = "Mech_Run"
LOOP = (1, 28)
KEY_FRAMES = (1, 5, 8, 12, 15, 19, 22, 26, 29)
SNAP_OUT = (5, 19)   # absorb: flat right handle = full stop before explode
SNAP_IN = (8, 22)    # push-off: flat left handle = steep snap arrival
BONES = ("Root", "Body", "Head", "ArmL", "ArmR", "ForeL", "ForeR",
         "LegL", "LegR", "ShinL", "ShinR")

# (pelvisZ, pelvisY, rootY, bodyX, headX, armL, armR, elbL, elbR,
#  thighL, shinL, thighR, shinR, squash)
POSES = {
    1: (-0.16, 0.00, 0.00, 12, -7, -45, 45, 50, 70, 40, -12, -50, -5, 0.98),
    5: (-0.20, -0.02, -0.01, 12, -7, -30, 30, 55, 65, 10, -35, -55, -15, 0.97),
    8: (-0.06, 0.08, 0.04, 15, -10, -50, 50, 60, 55, -45, -8, 60, -90, 1.02),
    12: (0.00, 0.10, 0.02, 13, -8, -10, 10, 60, 60, 10, -70, 30, -30, 1.02),
    15: (-0.16, 0.00, 0.00, 12, -7, 45, -45, 70, 50, -50, -5, 40, -12, 0.98),
    19: (-0.20, -0.02, -0.01, 12, -7, 30, -30, 65, 55, -55, -15, 10, -35, 0.97),
    22: (-0.06, 0.08, 0.04, 15, -10, 50, -50, 55, 60, 60, -90, -45, -8, 1.02),
    26: (0.00, 0.10, 0.02, 13, -8, 10, -10, 60, 60, 30, -30, 10, -70, 1.02),
    29: (-0.16, 0.00, 0.00, 12, -7, -45, 45, 50, 70, 40, -12, -50, -5, 0.98),
}


def get_rig() -> bpy.types.Object:
    rig = bpy.data.objects[RIG_NAME]
    bpy.context.view_layer.objects.active = rig
    return rig


def ensure_root(rig: bpy.types.Object) -> None:
    bpy.ops.object.mode_set(mode="EDIT")
    arm = rig.data
    if "Root" not in arm.edit_bones:
        root = arm.edit_bones.new("Root")
        root.head = (0, -0.3, 0.05)
        root.tail = (0, 0.6, 0.05)  # +Y = forward
        arm.edit_bones["Body"].parent = root
    bpy.ops.object.mode_set(mode="OBJECT")


def apply_pose(bones, p) -> None:
    (pZ, pY, rY, bodyX, headX, aL, aR, eL, eR,
     lLx, lLs, lRx, lRs, scl) = p
    bones["Root"].location = (0, rY, 0)
    bones["Body"].location = (0, pY, pZ)
    bones["Body"].rotation_euler = (D(bodyX), 0, 0)
    bones["Body"].scale = (2 - scl, 2 - scl, scl)  # squash & stretch, ~volume kept
    bones["Head"].location = (0, 0, 0)  # locked to collar: gaze by rotation only
    bones["Head"].rotation_euler = (D(headX), 0, 0)
    bones["ArmL"].rotation_euler = (D(aL), D(6.0), 0)
    bones["ArmR"].rotation_euler = (D(aR), D(-6.0), 0)
    bones["ForeL"].rotation_euler = (D(eL), 0, 0)
    bones["ForeR"].rotation_euler = (D(eR), 0, 0)
    bones["LegL"].rotation_euler = (D(lLx), 0, 0)
    bones["LegR"].rotation_euler = (D(lRx), 0, 0)
    bones["ShinL"].rotation_euler = (D(lLs), 0, 0)
    bones["ShinR"].rotation_euler = (D(lRs), 0, 0)


def key_frame(bones, fr: int) -> None:
    for n in BONES:
        if n == "Root":
            bones[n].keyframe_insert(data_path="location", frame=fr)
        elif n == "Body":
            bones[n].keyframe_insert(data_path="location", frame=fr)
            bones[n].keyframe_insert(data_path="scale", frame=fr)
            bones[n].keyframe_insert(data_path="rotation_euler", frame=fr)
        elif n == "Head":
            bones[n].keyframe_insert(data_path="location", frame=fr)
            bones[n].keyframe_insert(data_path="rotation_euler", frame=fr)
        else:
            bones[n].keyframe_insert(data_path="rotation_euler", frame=fr)


def build_action(rig: bpy.types.Object) -> bpy.types.Action:
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"  # explicit euler, matches skill pre-check
    if rig.animation_data is None:
        rig.animation_data_create()
    ad = rig.animation_data
    assert ad is not None
    act = bpy.data.actions.new(ACTION_NAME)
    act.frame_start, act.frame_end = LOOP
    ad.action = act
    bones = rig.pose.bones
    for fr in KEY_FRAMES:
        apply_pose(bones, POSES[fr])
        key_frame(bones, fr)
    bpy.ops.object.mode_set(mode="OBJECT")
    return act


def polish_easing(act: bpy.types.Action) -> None:
    """BEZIER+AUTO everywhere, except snap handles on pelvis/thigh curves:
    flat (zero-slope) handles at absorb-out and push-in = stop-then-explode."""
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                for fc in cb.fcurves:
                    is_pelvis = fc.data_path.endswith("location") and "Body" in fc.data_path
                    is_thigh = "LegL" in fc.data_path or "LegR" in fc.data_path
                    snap_lane = is_pelvis or is_thigh
                    for kp in fc.keyframe_points:
                        fx = int(round(kp.co.x))
                        if snap_lane and fx in SNAP_OUT:
                            kp.interpolation = "BEZIER"
                            kp.handle_right_type = "FREE"
                            kp.handle_right = (kp.co.x + 0.8, kp.co.y)
                            kp.handle_left_type = "AUTO"
                        elif snap_lane and fx in SNAP_IN:
                            kp.interpolation = "BEZIER"
                            kp.handle_left_type = "FREE"
                            kp.handle_left = (kp.co.x - 0.8, kp.co.y)
                            kp.handle_right_type = "AUTO"
                        else:
                            kp.interpolation = "BEZIER"
                            kp.handle_left_type = "AUTO"
                            kp.handle_right_type = "AUTO"


def main() -> None:
    rig = get_rig()
    ensure_root(rig)
    act = build_action(rig)
    polish_easing(act)
    print("RUN_CYCLE_OK", act.name)


if __name__ == "__main__":
    main()
