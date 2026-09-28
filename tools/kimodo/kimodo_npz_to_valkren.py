"""Transfer Kimodo NPZ motion -> Valkren mech joints (Godot Node3D euler).

Valkren (MechaBase, ~5.5m) is NOT a humanoid skeleton: it is a Node3D rig
(Body/Head/ArmL+R/ForeL+R/LegL+R/ShinL+R/FootL+R) driven by euler rotations,
see MechaWalkingSystem (Godot +X pitch = swing forward, shin negative =
knee flex, forearm positive = piston elbow, body negative X = charge lean).

Mapping principle (no double inversion): mocap arms/legs/torso ALREADY move
correctly relative to each other, so measured segment angles map DIRECTLY
onto the matching mech joint. (The -0.75 counter-swing factor in
MechaWalkingSystem exists because there the LEGS drive the arms
procedurally; here the mocap arms drive themselves.)

Measured per frame from posed_joints (+ heading):
  thigh pitch L/R  -> LegLeft/Right.rotation.x        clamp [-60, +45] deg
  knee flex   L/R  -> ShinLeft/Right.rotation.x = -flex clamp [-55, 0]
  arm pitch   L/R  -> ArmLeft/Right.rotation.x        clamp [-45, +45]
  elbow flex  L/R  -> Forearm.rotation.x = 35+(flex-25)*0.3 clamp [20, 60]
  torso pitch      -> Body.rotation.x = pitch + lean_bias clamp [-30, +10]
  torso twist      -> Body.rotation.y                     clamp [-12, +12]
  torso pitch*0.35 -> Head.rotation.x                     clamp [-15, +15]
  pelvis bob * 3.0 -> Body.off_y (position.y delta)   clamp [-0.30, +0.20]
  foot swing       -> LegLeft/Right.off_y lift 0..0.23 (smoothed contacts)
  FootLeft/Right   -> identity (mech feet stay flat, lift carries clearance)

Output: {clip: {duration, fps, frames, joints: {name: {rot: [[x,y,z] deg],
off_y: [m]}}}} — euler degrees, Godot Node3D convention. y/z stay ~0 so
euler order is irrelevant in practice.

Loop input: Kimodo generates linear (often run-then-settle) clips. --crop A:B
selects a steady segment and --loop-blend K crossfades its tail into its
head so the result loops seamlessly as base locomotion.

G1 robots have no neck/head joints: pass --shoulder-mid-torso to measure the
torso from pelvis to the shoulder midpoint instead of a neck joint.

Sizes: angles transfer scale-free; translations scale by BOB_SCALE=3.0
(Valkren hip 3.0m vs human 0.9m). --lean-bias adds the Valkren charge lean
mocap torsos never have (default -12 deg, 0 disables). --thigh-rear-gain
multiplies BACKWARD (negative) thigh swing only, so push-off extension can
be exaggerated without touching front reach (precedent: THIGH_BOOST in
MechaClipRetarget, which scales swing to lengthen mech strides).

A 2-bone FK (hip 3.001 / shin 1.34 / foot 1.291, from mecha_base.tscn)
rejects clips whose feet sink below rest - 0.10m.

Usage:
  python tools/kimodo/kimodo_npz_to_valkren.py --npz in.npz --clip NAME --out out.json
  python tools/kimodo/kimodo_npz_to_valkren.py --validate-only --json out.json
  # real SOMA-77 NPZ needs role indices:
  python tools/kimodo/kimodo_npz_to_valkren.py --npz soma.npz --clip run --out run.json \
      --map-json '{\"pelvis\": 0, \"neck\": 12, ...}'
"""
from __future__ import annotations

import argparse
import json
import math
import sys

sys.path.insert(0, "tools/kimodo")

FPS = 30.0
BOB_SCALE = 3.0
LIFT_MAX = 0.23
FOOT_REST_Y = 3.001 - 1.34 - 1.291  # 0.37, from mecha_base.tscn rest offsets
HIP_X = 0.6384
HIP_Y = 3.001
SHIN_LEN = 1.34
FOOT_LEN = 1.291

ROLES = ("pelvis", "neck", "upperarm_l", "upperarm_r", "lowerarm_l",
         "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r",
         "foot_l", "foot_r")

# Default role -> joint index for the 19-joint mock order.
MOCK_ORDER = ["pelvis", "spine_01", "spine_02", "neck_01", "Head",
              "clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
              "lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
              "thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l"]
DEFAULT_MAP = {"neck": MOCK_ORDER.index("neck_01")}
DEFAULT_MAP.update({r: MOCK_ORDER.index(r) for r in ROLES if r != "neck"})

VALKREN_JOINTS = ("Body", "Head", "ArmLeft", "ArmRight", "ForearmLeft",
                  "ForearmRight", "LegLeft", "LegRight", "ShinLeft",
                  "ShinRight", "FootLeft", "FootRight")

# (x_min, x_max, yz_max_abs) in degrees; off_y (min, max) in meters.
# Leg/shin ranges follow MechaClipRetarget baked-clip precedent
# (THIGH_MAX ~80 deg, SHIN_MIN ~-125 deg), not the tighter procedural
# robot gait, so Kimodo's exaggerated high knees survive the transfer.
LIMITS = {
    "Body": ((-30.0, 10.0, 12.0), (-0.35, 0.25)),
    "Head": ((-15.0, 15.0, 5.0), (0.0, 0.0)),
    "ArmLeft": ((-45.0, 45.0, 2.0), (0.0, 0.0)),
    "ArmRight": ((-45.0, 45.0, 2.0), (0.0, 0.0)),
    "ForearmLeft": ((20.0, 60.0, 2.0), (0.0, 0.0)),
    "ForearmRight": ((20.0, 60.0, 2.0), (0.0, 0.0)),
    "LegLeft": ((-60.0, 75.0, 2.0), (0.0, 0.35)),
    "LegRight": ((-60.0, 75.0, 2.0), (0.0, 0.35)),
    "ShinLeft": ((-90.0, 0.0, 2.0), (0.0, 0.0)),
    "ShinRight": ((-90.0, 0.0, 2.0), (0.0, 0.0)),
    "FootLeft": ((-3.0, 3.0, 3.0), (0.0, 0.0)),
    "FootRight": ((-3.0, 3.0, 3.0), (0.0, 0.0)),
}


def _clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


def _norm3(v) -> list:
    n = math.sqrt(sum(c * c for c in v))
    return [c / n for c in v] if n > 1e-9 else [0.0, -1.0, 0.0]


def _pitch_from_vertical(d, fwd) -> float:
    """Sagittal angle of unit dir d from vertical, deg, + = forward.
    Works for down-pointing (limbs) and up-pointing (torso) segments."""
    f = sum(d[i] * fwd[i] for i in range(3))
    return math.degrees(math.atan2(f, abs(d[1])))


def _angle_between(a, b) -> float:
    dot = _clamp(sum(a[i] * b[i] for i in range(3)), -1.0, 1.0)
    return math.degrees(math.acos(dot))


def _twist_deg(shoulder, hip) -> float:
    """Signed yaw between shoulder line and hip line, deg about +Y."""
    ax, az = shoulder[0], shoulder[2]
    bx, bz = hip[0], hip[2]
    if math.hypot(ax, az) < 1e-9 or math.hypot(bx, bz) < 1e-9:
        return 0.0
    return math.degrees(math.atan2(ax * bz - az * bx, ax * bx + az * bz))


def _smooth(xs: list, window: int = 7) -> list:
    if window <= 1:
        return list(xs)
    n = len(xs)
    out = []
    h = window // 2
    for i in range(n):
        lo = max(0, i - h)
        hi = min(n, i + h + 1)
        out.append(sum(xs[lo:hi]) / (hi - lo))
    return out


def _fk_foot_y(hip_x: float, thigh_deg: float, shin_deg: float, lift: float) -> float:
    th = math.radians(thigh_deg)
    sh = math.radians(shin_deg)
    knee_y = HIP_Y + lift - SHIN_LEN * math.cos(th)
    return knee_y - FOOT_LEN * math.cos(th + sh)


def convert(npz_path: str, clip: str, role_map: dict,
            lean_bias: float = -12.0, crouch: float = 0.06,
            crop: tuple | None = None, loop_blend: int = 0,
            shoulder_mid_torso: bool = False,
            symmetrize_arms: bool = False,
            thigh_rear_gain: float = 1.0) -> dict:
    import numpy as np

    from kimodo_npz_format import validate_npz_dict

    d = dict(np.load(npz_path))
    errs = validate_npz_dict(d)
    if errs:
        raise ValueError("invalid Kimodo NPZ: %s" % errs)
    if crop is not None:
        a, b = crop
        d = {k: np.asarray(v)[a:b] for k, v in d.items()}
    posed = d["posed_joints"]
    contacts = d["foot_contacts"]
    root = d["root_positions"]
    T = posed.shape[0]
    if loop_blend > 0 and loop_blend * 2 >= T:
        raise ValueError("loop_blend %d too large for T=%d" % (loop_blend, T))
    P = {r: np.asarray(posed[:, role_map[r], :], dtype=float) for r in ROLES}

    # Forward axis: root TRAVEL direction (xz) is ground truth. The heading
    # channel does not track travel on every skeleton (G1 heading sits near
    # +X while the root runs +Z), so it is only a fallback for in-place clips.
    disp = np.asarray([float(root[-1, 0]) - float(root[0, 0]), 0.0,
                       float(root[-1, 2]) - float(root[0, 2])])
    if float(np.linalg.norm(disp)) > 0.05:
        fwd = disp / float(np.linalg.norm(disp))
    else:
        hx = float(np.mean(d["global_root_heading"][:, 0]))
        hz = float(np.mean(d["global_root_heading"][:, 1]))
        hn = math.hypot(hx, hz) or 1.0
        fwd = np.array([hx / hn, 0.0, hz / hn])
    fwd = [float(fwd[0]), 0.0, float(fwd[2])]

    swing_l = _smooth([1.0 - max(float(contacts[f, 0]), float(contacts[f, 1]))
                       for f in range(T)])
    swing_r = _smooth([1.0 - max(float(contacts[f, 2]), float(contacts[f, 3]))
                       for f in range(T)])
    # Binary stance per foot (1 = on ground). Drives footstep audio sync at
    # runtime: touchdown edge 0->1 = footstep, liftoff edge 1->0 = lift.
    stance_l = [1 if max(float(contacts[f, 0]), float(contacts[f, 1])) >= 0.5 else 0
                for f in range(T)]
    stance_r = [1 if max(float(contacts[f, 2]), float(contacts[f, 3])) >= 0.5 else 0
                for f in range(T)]
    pelvis_y0 = float(root[0, 1])

    J: dict = {j: {"rot": [], "off_y": []} for j in VALKREN_JOINTS}
    for f in range(T):
        raw = {r: [float(P[r][f, i]) for i in range(3)] for r in ROLES}

        def seg(a: str, b: str) -> list:
            v = [raw[b][i] - raw[a][i] for i in range(3)]
            return _norm3(v)

        thigh_l = seg("thigh_l", "calf_l")
        thigh_r = seg("thigh_r", "calf_r")
        shin_l = seg("calf_l", "foot_l")
        shin_r = seg("calf_r", "foot_r")
        arm_l = seg("upperarm_l", "lowerarm_l")
        arm_r = seg("upperarm_r", "lowerarm_r")
        if shoulder_mid_torso:
            top = [(raw["upperarm_l"][i] + raw["upperarm_r"][i]) / 2.0 for i in range(3)]
        else:
            top = raw["neck"]
        torso = _norm3([top[i] - raw["pelvis"][i] for i in range(3)])

        t_pitch = _pitch_from_vertical(torso, fwd)
        th_l = _pitch_from_vertical(thigh_l, fwd)
        th_r = _pitch_from_vertical(thigh_r, fwd)
        kn_l = _angle_between(thigh_l, shin_l)
        kn_r = _angle_between(thigh_r, shin_r)
        a_l = _pitch_from_vertical(arm_l, fwd)
        a_r = _pitch_from_vertical(arm_r, fwd)
        # elbow flex from the lowerarm LOCAL rotation magnitude (0 = straight).
        e_l = _flex_from_local(d, "lowerarm_l", role_map, f)
        e_r = _flex_from_local(d, "lowerarm_r", role_map, f)

        body_x = _clamp(t_pitch + lean_bias, *LIMITS["Body"][0][:2])
        twist = _clamp(_twist_deg(
            [raw["upperarm_l"][i] - raw["upperarm_r"][i] for i in range(3)],
            [raw["thigh_l"][i] - raw["thigh_r"][i] for i in range(3)]),
            -LIMITS["Body"][0][2], LIMITS["Body"][0][2])
        bob = _clamp((float(root[f, 1]) - pelvis_y0) * BOB_SCALE,
                     *LIMITS["Body"][1]) - crouch
        bob = _clamp(bob, *LIMITS["Body"][1])

        leg_lx = _clamp(th_l if th_l >= 0 else th_l * thigh_rear_gain,
                          *LIMITS["LegLeft"][0][:2])
        leg_rx = _clamp(th_r if th_r >= 0 else th_r * thigh_rear_gain,
                          *LIMITS["LegRight"][0][:2])
        shin_lx = _clamp(-kn_l, *LIMITS["ShinLeft"][0][:2])
        shin_rx = _clamp(-kn_r, *LIMITS["ShinRight"][0][:2])
        arm_lx = _clamp(a_l, *LIMITS["ArmLeft"][0][:2])
        arm_rx = _clamp(a_r, *LIMITS["ArmRight"][0][:2])
        fore_lx = _clamp(35.0 + (e_l - 25.0) * 0.3, *LIMITS["ForearmLeft"][0][:2])
        fore_rx = _clamp(35.0 + (e_r - 25.0) * 0.3, *LIMITS["ForearmRight"][0][:2])
        head_x = _clamp(body_x * 0.35, *LIMITS["Head"][0][:2])
        lift_l = _clamp(swing_l[f] * LIFT_MAX, *LIMITS["LegLeft"][1])
        lift_r = _clamp(swing_r[f] * LIFT_MAX, *LIMITS["LegRight"][1])

        rows = {
            "Body": ([body_x, twist, 0.0], bob),
            "Head": ([head_x, 0.0, 0.0], 0.0),
            "ArmLeft": ([arm_lx, 0.0, 0.0], 0.0),
            "ArmRight": ([arm_rx, 0.0, 0.0], 0.0),
            "ForearmLeft": ([fore_lx, 0.0, 0.0], 0.0),
            "ForearmRight": ([fore_rx, 0.0, 0.0], 0.0),
            "LegLeft": ([leg_lx, 0.0, 0.0], lift_l),
            "LegRight": ([leg_rx, 0.0, 0.0], lift_r),
            "ShinLeft": ([shin_lx, 0.0, 0.0], 0.0),
            "ShinRight": ([shin_rx, 0.0, 0.0], 0.0),
            "FootLeft": ([0.0, 0.0, 0.0], 0.0),
            "FootRight": ([0.0, 0.0, 0.0], 0.0),
        }
        for j, (rot, off) in rows.items():
            J[j]["rot"].append([round(v, 3) for v in rot])
            J[j]["off_y"].append(round(off, 4))

    # Arm symmetrization (optional post-process): Kimodo G1 runs often hold
    # one arm back (training bias). L'=(L-R)/2, R'=-L' keeps Kimodo's pump
    # timing/amplitude but symmetric. Arms stay separate tracks, so weapon
    # layers can still replace them wholesale later.
    # NOTE: symmetrize BEFORE the loop crossfade below.
    if symmetrize_arms:
        n = len(J["ArmLeft"]["rot"])
        al_all = [J["ArmLeft"]["rot"][f][0] for f in range(n)]
        ar_all = [J["ArmRight"]["rot"][f][0] for f in range(n)]
        al_mean = sum(al_all) / n
        ar_mean = sum(ar_all) / n
        (x_lo, x_hi, _yz) = LIMITS["ArmLeft"][0]
        for f in range(n):
            sym = ((al_all[f] - al_mean) - (ar_all[f] - ar_mean)) / 2.0
            sym = _clamp(sym, x_lo, x_hi)
            J["ArmLeft"]["rot"][f][0] = round(sym, 3)
            J["ArmRight"]["rot"][f][0] = round(-sym, 3)
            fl = J["ForearmLeft"]["rot"][f][0]
            fr = J["ForearmRight"]["rot"][f][0]
            favg = _clamp((fl + fr) / 2.0, *LIMITS["ForearmLeft"][0][:2])
            J["ForearmLeft"]["rot"][f][0] = round(favg, 3)
            J["ForearmRight"]["rot"][f][0] = round(favg, 3)

    # Loop crossfade: the last K frames morph toward the head (frames
    # 1..K-1, then 0) so the final frame EQUALS frame 0 and playback wraps
    # seamlessly (base-locomotion requirement).
    if loop_blend > 0:
        for j in VALKREN_JOINTS:
            rot = J[j]["rot"]
            off = J[j]["off_y"]
            for i in range(loop_blend):
                f = T - loop_blend + i
                a = (i + 1) / loop_blend
                tgt = (i + 1) if (i + 1) < loop_blend else 0
                rot[f] = [round(rot[f][c] * (1 - a) + rot[tgt][c] * a, 3) for c in range(3)]
                off[f] = round(off[f] * (1 - a) + off[tgt] * a, 4)

    # FK floor check (fail fast before writing).
    worst = 1e9
    for f in range(T):
        for side, sx in (("Left", -HIP_X), ("Right", HIP_X)):
            _ = sx
            th = J["Leg" + side]["rot"][f][0]
            sh = J["Shin" + side]["rot"][f][0]
            li = J["Leg" + side]["off_y"][f]
            worst = min(worst, _fk_foot_y(0.0, th, sh, li))
    if worst < FOOT_REST_Y - 0.10:
        raise ValueError("FK floor fail: min foot y %.3f < %.3f" % (worst, FOOT_REST_Y - 0.10))
    out = {clip: {"duration": T / FPS, "fps": FPS, "frames": T, "joints": J,
                  "foot_min_y": round(worst, 4)}}
    if loop_blend > 0:
        # Stance follows the same wrap: tail copies head (shifted by one) so
        # the last frame's stance equals frame 0 -> no spurious step event.
        for key in ("stance_l", "stance_r"):
            src = stance_l if key == "stance_l" else stance_r
            dst = [0] * T
            for f in range(T - loop_blend):
                dst[f] = src[f]
            for i in range(loop_blend):
                dst[T - loop_blend + i] = src[(i + 1) % loop_blend]
            out[clip][key] = dst
    else:
        out[clip]["stance_l"] = stance_l
        out[clip]["stance_r"] = stance_r
    return out


def _flex_from_local(d, role: str, role_map: dict, f: int) -> float:
    """Flex angle (deg, 0 = straight) of a joint from its local rot matrix."""
    import numpy as np

    m = np.array(d["local_rot_mats"][f, role_map[role]])
    tr = float(np.trace(m))
    return math.degrees(math.acos(_clamp((tr - 1.0) / 2.0, -1.0, 1.0)))


def validate_clip_json(path: str) -> list:
    data = json.load(open(path))
    errors = []
    if len(data) != 1:
        return ["expected exactly 1 clip in %s, got %d" % (path, len(data))]
    clip, rec = next(iter(data.items()))
    joints = rec.get("joints", {})
    missing = [j for j in VALKREN_JOINTS if j not in joints]
    if missing:
        return ["missing joints: %s" % missing]
    n = len(joints["Body"]["rot"])
    if n < 4:
        return ["too few frames: %d" % n]
    for key in ("stance_l", "stance_r"):
        if key in rec and len(rec[key]) != n:
            errors.append("%s len %d != %d" % (key, len(rec[key]), n))
        if key in rec and any(v not in (0, 1) for v in rec[key]):
            errors.append("%s not binary" % key)
    if errors:
        return errors
    for j in VALKREN_JOINTS:
        (x_lo, x_hi, yz), (o_lo, o_hi) = LIMITS[j]
        rot = joints[j]["rot"]
        off = joints[j]["off_y"]
        if len(rot) != n or len(off) != n:
            errors.append("%s length mismatch" % j)
            continue
        for i in range(n):
            r = rot[i]
            if not all(math.isfinite(float(v)) for v in r + [off[i]]):
                errors.append("%s[%d] non-finite" % (j, i))
                break
            if not (x_lo - 1e-6 <= float(r[0]) <= x_hi + 1e-6):
                errors.append("%s.rot.x[%d]=%.1f outside [%.0f, %.0f]"
                              % (j, i, float(r[0]), x_lo, x_hi))
                break
            if abs(float(r[1])) > yz + 1e-6 or abs(float(r[2])) > yz + 1e-6:
                errors.append("%s[%d] y/z exceeds %.0f deg" % (j, i, yz))
                break
            if not (o_lo - 1e-6 <= float(off[i]) <= o_hi + 1e-6):
                errors.append("%s.off_y[%d]=%.3f outside [%.2f, %.2f]"
                              % (j, i, float(off[i]), o_lo, o_hi))
                break
    if errors:
        return errors
    worst = 1e9
    for f in range(n):
        for side in ("Left", "Right"):
            th = float(joints["Leg" + side]["rot"][f][0])
            sh = float(joints["Shin" + side]["rot"][f][0])
            li = float(joints["Leg" + side]["off_y"][f])
            worst = min(worst, _fk_foot_y(0.0, th, sh, li))
    if worst < FOOT_REST_Y - 0.10:
        errors.append("FK floor fail: min foot y %.3f" % worst)
    if not errors:
        print("KIMODO_VALKREN_OK %s frames=%d joints=%d foot_min_y=%.3f"
              % (clip, n, len(VALKREN_JOINTS), worst))
    return errors


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz")
    ap.add_argument("--clip", default="valkren_run")
    ap.add_argument("--out")
    ap.add_argument("--map-json", default=None,
                    help='JSON {"role": source_index} for real SOMA-77 NPZ')
    ap.add_argument("--lean-bias", type=float, default=-12.0)
    ap.add_argument("--crouch", type=float, default=0.06)
    ap.add_argument("--crop", default=None,
                    help='"A:B" frame range of a steady segment (e.g. "76:116")')
    ap.add_argument("--loop-blend", type=int, default=0,
                    help="crossfade N tail frames into the head for seamless loop")
    ap.add_argument("--shoulder-mid-torso", action="store_true",
                    help="torso measured pelvis->shoulder-midpoint (G1 has no neck)")
    ap.add_argument("--symmetrize-arms", action="store_true",
                    help="mirror-average arm pump (fixes one-arm-back G1 bias)")
    ap.add_argument("--thigh-rear-gain", type=float, default=1.0,
                    help="exaggerate BACKWARD thigh swing only (push-off), e.g. 1.7")
    ap.add_argument("--json", default=None)
    ap.add_argument("--validate-only", action="store_true")
    args = ap.parse_args()
    if args.validate_only:
        if not args.json:
            raise SystemExit("--validate-only needs --json")
        errs = validate_clip_json(args.json)
        if errs:
            raise SystemExit("KIMODO_VALKREN_FAIL: %s" % errs)
        return
    if not args.npz or not args.out:
        raise SystemExit("needs --npz and --out (or --validate-only --json)")
    role_map = dict(DEFAULT_MAP)
    if args.map_json:
        role_map.update({k: int(v) for k, v in json.load(open(args.map_json)).items()})
        absent = [r for r in ROLES if r not in role_map]
        if absent:
            raise SystemExit("map-json missing roles: %s" % absent)
    crop = None
    if args.crop:
        a, b = args.crop.split(":")
        crop = (int(a), int(b))
    out = convert(args.npz, args.clip, role_map, args.lean_bias, args.crouch,
                  crop=crop, loop_blend=args.loop_blend,
                  shoulder_mid_torso=args.shoulder_mid_torso,
                  symmetrize_arms=args.symmetrize_arms,
                  thigh_rear_gain=args.thigh_rear_gain)
    json.dump(out, open(args.out, "w"))
    errs = validate_clip_json(args.out)
    if errs:
        raise SystemExit("converted but policy failed: %s" % errs)
    print("KIMODO_VALKREN_CONVERT_OK %s -> %s" % (args.npz, args.out))


if __name__ == "__main__":
    main()
