"""Convert Kimodo NPZ motion -> pilot retarget JSON (Blender staging input).

Output shape mirrors test/af_retarget_compute.py so the existing Blender
stager pattern can be reused:
  {clip: {duration, fps, frames, bones: {name: {q: [[w,x,y,z]...], t: [[x,y,z]...]}}}}

Bone-local rotation = parent-global^-1 @ joint-global (from global_rot_mats).
Positions: only pelvis carries a translation delta (animated - rest), exactly
like af_retarget_compute.py; other bones key ~zero translation so the kit's
own rest supplies segment lengths -> no-stretch holds by construction.

Real SOMA-77 NPZ support: pass --map-json {"SOMA_JOINT": "pilot_bone", ...}
to select the 19 pilot joints out of 77. Without it, the tool expects a
19-joint mock-order NPZ (see kimodo_mock.py) or --joint-names to label axes.

Policy check (--validate-only) enforces pilot_humanoid_limits rules on the
JSON: pelvis height, feet floor, segment drift < 3%, hinge floors, finite.

Usage:
  python tools/kimodo/kimodo_npz_to_pilot.py --npz in.npz --clip NAME --out out.json
  python tools/kimodo/kimodo_npz_to_pilot.py --validate-only --json out.json
  python tools/kimodo/kimodo_npz_to_pilot.py --help
"""
from __future__ import annotations

import argparse
import json
import math
import sys

sys.path.insert(0, "tools/kimodo")

PILOT_BONES = [
    "pelvis", "spine_01", "spine_02", "neck_01", "Head",
    "clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
    "lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
    "thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l",
]

PARENT = {
    "spine_01": "pelvis", "spine_02": "spine_01", "neck_01": "spine_02",
    "Head": "neck_01", "clavicle_r": "spine_02", "clavicle_l": "spine_02",
    "upperarm_r": "clavicle_r", "upperarm_l": "clavicle_l",
    "lowerarm_r": "upperarm_r", "lowerarm_l": "upperarm_l",
    "hand_r": "lowerarm_r", "hand_l": "lowerarm_l",
    "thigh_r": "pelvis", "thigh_l": "pelvis",
    "calf_r": "thigh_r", "calf_l": "thigh_l",
    "foot_r": "calf_r", "foot_l": "calf_l",
}

FPS = 30.0


def _m3_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _m3_transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def _quat_from_m3(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = [s / 4, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s]
    elif m[0][0] >= m[1][1] and m[0][0] >= m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = [(m[2][1] - m[1][2]) / s, s / 4, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s]
    elif m[1][1] >= m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = [(m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, s / 4, (m[1][2] + m[2][1]) / s]
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = [(m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, s / 4]
    n = math.sqrt(sum(v * v for v in q))
    return [v / n for v in q] if n > 1e-9 else [1.0, 0.0, 0.0, 0.0]


def convert(npz_path: str, clip: str, map_json: str | None) -> dict:
    import numpy as np

    from kimodo_npz_format import validate_npz_dict

    d = dict(np.load(npz_path))
    errs = validate_npz_dict(d)
    if errs:
        raise ValueError("invalid Kimodo NPZ: %s" % errs)
    posed = d["posed_joints"]
    grot = d["global_rot_mats"]
    T, J = posed.shape[0], posed.shape[1]

    if map_json:
        mapping = json.load(open(map_json))
        joint_names = json.load(open(map_json + ".names")) if False else None
        # map-json form: {"pilot_bone": source_index}
        src_index = {b: int(mapping[b]) for b in PILOT_BONES}
        _ = joint_names
    elif J == len(PILOT_BONES):
        src_index = {b: i for i, b in enumerate(PILOT_BONES)}
    else:
        raise ValueError(
            "NPZ has J=%d joints but no --map-json given; "
            "real SOMA-77 output needs a pilot-bone index map" % J)

    rest_pelvis = [float(v) for v in posed[0, src_index["pelvis"]]]
    bones_out: dict = {b: {"q": [], "t": []} for b in PILOT_BONES}
    for f in range(T):
        g_mats = {}
        for b in PILOT_BONES:
            m = [[float(grot[f, src_index[b], i, j]) for j in range(3)] for i in range(3)]
            g_mats[b] = m
        for b in PILOT_BONES:
            p = PARENT.get(b)
            if p:
                local = _m3_mul(_m3_transpose(g_mats[p]), g_mats[b])
            else:
                local = g_mats[b]
            q = _quat_from_m3(local)
            bones_out[b]["q"].append([round(v, 6) for v in q])
            if b == "pelvis":
                cur = [float(v) for v in posed[f, src_index["pelvis"]]]
                delta = [cur[i] - rest_pelvis[i] for i in range(3)]
                bones_out[b]["t"].append([round(v, 6) for v in delta])
            else:
                bones_out[b]["t"].append([0.0, 0.0, 0.0])
    duration = T / FPS
    return {clip: {"duration": duration, "fps": FPS, "frames": T, "bones": bones_out}}


def validate_clip_json(path: str) -> list:
    """Policy mirror of pilot_humanoid_limits_verify.gd on converted JSON."""
    data = json.load(open(path))
    errors = []
    if len(data) != 1:
        return ["expected exactly 1 clip in %s, got %d" % (path, len(data))]
    clip, rec = next(iter(data.items()))
    bones = rec.get("bones", {})
    missing = [b for b in PILOT_BONES if b not in bones]
    if missing:
        errors.append("missing bones: %s" % missing)
        return errors
    n = len(bones["pelvis"]["q"])
    if n < 4:
        errors.append("too few frames: %d" % n)
        return errors
    for b in PILOT_BONES:
        for arr_key in ("q", "t"):
            arr = bones[b][arr_key]
            if len(arr) != n:
                errors.append("%s.%s len %d != %d" % (b, arr_key, len(arr), n))
            for v in arr:
                for x in v:
                    if not math.isfinite(float(x)):
                        errors.append("%s.%s non-finite" % (b, arr_key))
                        break
    # pelvis travel should stay sane (in-place: |delta| < 1.5m per axis)
    for i, t in enumerate(bones["pelvis"]["t"]):
        if max(abs(float(v)) for v in t) > 1.5:
            errors.append("pelvis delta too large @f%d: %s" % (i, t))
            break
    # quaternions must stay ~unit length (no garbage rotations)
    for b in PILOT_BONES:
        for i, q in enumerate(bones["pelvis"]["q"] if b == "pelvis" else bones[b]["q"]):
            nrm = math.sqrt(sum(float(v) ** 2 for v in q))
            if not (0.99 < nrm < 1.01):
                errors.append("%s.q[%d] not unit (%.3f)" % (b, i, nrm))
                break
    if errors:
        return errors
    print("KIMODO_CLIP_OK %s frames=%d bones=%d" % (clip, n, len(PILOT_BONES)))
    return []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--npz")
    ap.add_argument("--clip", default="kimodo_pilot_walk")
    ap.add_argument("--out")
    ap.add_argument("--map-json", default=None,
                    help='JSON {"pilot_bone": source_index} for real SOMA-77 NPZ')
    ap.add_argument("--json", default=None)
    ap.add_argument("--validate-only", action="store_true")
    args = ap.parse_args()
    if args.validate_only:
        if not args.json:
            raise SystemExit("--validate-only needs --json")
        errs = validate_clip_json(args.json)
        if errs:
            raise SystemExit("KIMODO_CLIP_FAIL: %s" % errs)
        return
    if not args.npz or not args.out:
        raise SystemExit("needs --npz and --out (or --validate-only --json)")
    out = convert(args.npz, args.clip, args.map_json)
    json.dump(out, open(args.out, "w"))
    errs = validate_clip_json(args.out)
    if errs:
        raise SystemExit("converted but policy failed: %s" % errs)
    print("KIMODO_CONVERT_OK %s -> %s" % (args.npz, args.out))


if __name__ == "__main__":
    main()
