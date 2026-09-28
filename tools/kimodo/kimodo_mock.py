"""Create a synthetic Kimodo-format NPZ for CI (no GPU, no model download).

Modes:
  walk: 2s @30fps in-place walk, 1s stride, thighs +/-25deg, gentle bob.
  run:  1.6s @30fps in-place run, 0.6s stride, thighs +/-40deg, deep knees,
         bigger bounce plus a flight window (all contacts zero).

Joint order (19, matches PILOT_BONES in kimodo_npz_to_pilot.py):
  pelvis, spine_01, spine_02, neck_01, Head,
  clavicle_r, clavicle_l, upperarm_r, upperarm_l,
  lowerarm_r, lowerarm_l, hand_r, hand_l,
  thigh_r, thigh_l, calf_r, calf_l, foot_r, foot_l

Usage:
  python tools/kimodo/kimodo_mock.py --out tools/kimodo/samples/kimodo_mock.npz
  python tools/kimodo/kimodo_mock.py --mode run --out tools/kimodo/samples/kimodo_mock_run.npz
"""
from __future__ import annotations

import argparse
import math

import numpy as np

from kimodo_npz_format import FPS, REQUIRED_KEYS, validate_npz_dict

PILOT_JOINTS_19 = [
    "pelvis", "spine_01", "spine_02", "neck_01", "Head",
    "clavicle_r", "clavicle_l", "upperarm_r", "upperarm_l",
    "lowerarm_r", "lowerarm_l", "hand_r", "hand_l",
    "thigh_r", "thigh_l", "calf_r", "calf_l", "foot_r", "foot_l",
]

# Rest offsets (meters, Y-up, +Z... authoring space matches pilot kit approx):
# pelvis 0.9, head ~1.7, feet ~0.08. Segment lengths stay fixed (rigid offsets
# rotated by joint spin) so the no-stretch policy holds by construction.
REST_OFFSET = {
    "pelvis": (0.0, 0.90, 0.0),
    "spine_01": (0.0, 0.12, 0.0),
    "spine_02": (0.0, 0.14, 0.0),
    "neck_01": (0.0, 0.16, 0.0),
    "Head": (0.0, 0.14, 0.0),
    "clavicle_r": (0.10, 0.10, 0.0),
    "clavicle_l": (-0.10, 0.10, 0.0),
    "upperarm_r": (0.10, -0.04, 0.0),
    "upperarm_l": (-0.10, -0.04, 0.0),
    "lowerarm_r": (0.0, -0.28, 0.0),
    "lowerarm_l": (0.0, -0.28, 0.0),
    "hand_r": (0.0, -0.26, 0.02),
    "hand_l": (0.0, -0.26, 0.02),
    "thigh_r": (0.10, -0.10, 0.0),
    "thigh_l": (-0.10, -0.10, 0.0),
    "calf_r": (0.0, -0.42, 0.0),
    "calf_l": (0.0, -0.42, 0.0),
    "foot_r": (0.0, -0.42, 0.06),
    "foot_l": (0.0, -0.42, 0.06),
}

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


def _ry(deg: float) -> np.ndarray:
    # NOTE: mock spins about Y so the walk reads side-on in authoring space;
    # the converter re-expresses these as bone-local quats on the pilot rig,
    # so the axis choice here does not leak into Godot.
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def build_mock(frames: int = 60, stride_period: float = 1.0,
                 swing: float = 25.0, knee_base: float = -12.0,
                 knee_depth: float = 18.0, bob: float = 0.03,
                 pelvis_h: float = 0.90, elbow: float = -20.0,
                 flight_frac: float = 0.0) -> dict:
    J = len(PILOT_JOINTS_19)
    idx = {n: i for i, n in enumerate(PILOT_JOINTS_19)}
    posed = np.zeros((frames, J, 3))
    global_rot = np.zeros((frames, J, 3, 3))
    local_rot = np.zeros((frames, J, 3, 3))
    contacts = np.zeros((frames, 4))
    smooth_root = np.zeros((frames, 3))
    root_pos = np.zeros((frames, 3))
    heading = np.zeros((frames, 2))
    heading[:, 0] = 1.0  # facing +X

    order = ["pelvis"] + [n for n in PILOT_JOINTS_19 if n != "pelvis"]
    for f in range(frames):
        t = f / FPS
        phase = 2.0 * math.pi * t / stride_period
        bob_amp = bob * math.cos(2.0 * phase)
        swing_r = swing * math.sin(phase)
        swing_l = swing * math.sin(phase + math.pi)
        knee_r = knee_base - knee_depth * max(0.0, math.sin(phase + 0.6))
        knee_l = knee_base - knee_depth * max(0.0, math.sin(phase + math.pi + 0.6))
        arm_r = -swing_r * 0.5
        arm_l = -swing_l * 0.5
        spin = {
            "thigh_r": swing_r, "thigh_l": swing_l,
            "calf_r": knee_r, "calf_l": knee_l,
            "upperarm_r": arm_r, "upperarm_l": arm_l,
            "lowerarm_r": elbow, "lowerarm_l": elbow,
            "foot_r": -(swing_r + knee_r) * 0.4,
            "foot_l": -(swing_l + knee_l) * 0.4,
        }
        g_pos = {}
        g_rot = {}
        for n in order:
            r = _ry(spin.get(n, 0.0))
            off = np.array(REST_OFFSET[n])
            if n == "pelvis":
                g_rot[n] = r
                g_pos[n] = np.array([0.0, pelvis_h + bob_amp, 0.0])
            else:
                p = PARENT[n]
                g_rot[n] = g_rot[p] @ r
                g_pos[n] = g_pos[p] + g_rot[p] @ off
            local_rot[f, idx[n]] = r
            global_rot[f, idx[n]] = g_rot[n]
            posed[f, idx[n]] = g_pos[n]
        root_pos[f] = g_pos["pelvis"]
        smooth_root[f] = g_pos["pelvis"]
        # flight window (run): both feet off ground around each passing pose
        cyc = (phase % (2.0 * math.pi)) / (2.0 * math.pi)
        in_flight = flight_frac > 0.0 and (
            abs(cyc - 0.25) < flight_frac or abs(cyc - 0.75) < flight_frac)
        if in_flight:
            contacts[f] = [0.0, 0.0, 0.0, 0.0]
        elif math.sin(phase) > 0:
            contacts[f] = [1.0, 1.0, 0.0, 0.0]
        else:
            contacts[f] = [0.0, 0.0, 1.0, 1.0]
    return {
        "posed_joints": posed,
        "global_rot_mats": global_rot,
        "local_rot_mats": local_rot,
        "foot_contacts": contacts,
        "smooth_root_pos": smooth_root,
        "root_positions": root_pos,
        "global_root_heading": heading,
    }


def main() -> None:
    presets = {
        "walk": dict(frames=60, stride_period=1.0, swing=25.0,
                     knee_base=-12.0, knee_depth=18.0, bob=0.03,
                     pelvis_h=0.90, elbow=-20.0, flight_frac=0.0),
        "run": dict(frames=48, stride_period=0.6, swing=40.0,
                    knee_base=-15.0, knee_depth=50.0, bob=0.05,
                    pelvis_h=0.92, elbow=-35.0, flight_frac=0.06),
    }
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=list(presets), default="walk")
    ap.add_argument("--frames", type=int, default=None)
    args = ap.parse_args()
    kw = dict(presets[args.mode])
    if args.frames is not None:
        kw["frames"] = args.frames
    frames = int(kw.pop("frames"))
    d = build_mock(frames, **kw)
    errs = validate_npz_dict(d)
    if errs:
        raise SystemExit("mock failed validation: %s" % errs)
    np.savez(args.out, **d)
    print("KIMODO_MOCK_OK mode=%s %s T=%d J=%d keys=%s"
          % (args.mode, args.out, frames, len(PILOT_JOINTS_19),
             ",".join(REQUIRED_KEYS)))


if __name__ == "__main__":
    main()
