"""Kimodo NPZ format definition + validation (no model, no torch).

Mirrors the Default NPZ Output Format documented by nv-tlabs/kimodo:
  posed_joints        [T, J, 3]
  global_rot_mats     [T, J, 3, 3]
  local_rot_mats      [T, J, 3, 3]
  foot_contacts       [T, 4]   (left heel, left toe, right heel, right toes)
  smooth_root_pos     [T, 3]
  root_positions      [T, 3]
  global_root_heading [T, 2]

FPS default 30 (Kimodo G1/SOMA pipelines run at 20-30fps; bridge normalizes
to 30 to match af_retarget.json convention used by the pilot pipeline).
"""
from __future__ import annotations

import math

REQUIRED_KEYS = (
    "posed_joints",
    "global_rot_mats",
    "local_rot_mats",
    "foot_contacts",
    "smooth_root_pos",
    "root_positions",
    "global_root_heading",
)

FPS = 30.0


def _is_finite_number(x) -> bool:
    try:
        return math.isfinite(float(x))
    except (TypeError, ValueError):
        return False


def validate_npz_dict(d: dict) -> list:
    """Return a list of error strings (empty = valid). Works on npz-loaded dicts."""
    errors = []
    try:
        import numpy as np
    except ImportError:
        return ["numpy is required to validate Kimodo NPZ"]
    for k in REQUIRED_KEYS:
        if k not in d:
            errors.append("missing key: %s" % k)
    if errors:
        return errors
    try:
        T = int(d["posed_joints"].shape[0])
        J = int(d["posed_joints"].shape[1])
    except (AttributeError, IndexError, TypeError, ValueError):
        return ["posed_joints has unexpected shape"]
    if T < 4:
        errors.append("too few frames T=%d (min 4)" % T)
    if J < 15:
        errors.append("too few joints J=%d (pilot needs >= 15)" % J)
    shapes = {
        "posed_joints": (T, J, 3),
        "global_rot_mats": (T, J, 3, 3),
        "local_rot_mats": (T, J, 3, 3),
        "foot_contacts": (T, 4),
        "smooth_root_pos": (T, 3),
        "root_positions": (T, 3),
        "global_root_heading": (T, 2),
    }
    for k, want in shapes.items():
        got = tuple(int(v) for v in d[k].shape)
        if got != want:
            errors.append("%s shape %s != %s" % (k, got, want))
    for k in REQUIRED_KEYS:
        arr = d[k]
        finite = bool(np.all(np.isfinite(arr)))
        if not finite:
            errors.append("%s contains non-finite values" % k)
    # rotation matrices should be ~orthonormal (rows unit length, det ~ +1)
    try:
        import numpy as np

        sample = d["global_rot_mats"][0, 0]
        row_norms = (sample ** 2).sum(axis=1)
        if not bool(np.all((row_norms > 0.9) & (row_norms < 1.1))):
            errors.append("global_rot_mats[0,0] rows not unit length: %s" % row_norms)
        det = float(np.linalg.det(sample))
        if not (0.9 < det < 1.1):
            errors.append("global_rot_mats[0,0] det=%.3f (want ~1.0)" % det)
    except (IndexError, ValueError):
        errors.append("could not check rotation orthonormality")
    return errors


def describe_npz_dict(d: dict) -> str:
    try:
        T = int(d["posed_joints"].shape[0])
        J = int(d["posed_joints"].shape[1])
        dur = T / FPS
        return "KimodoNPZ T=%d J=%d dur=%.2fs @%.0ffps" % (T, J, dur, FPS)
    except (AttributeError, KeyError, IndexError, TypeError, ValueError):
        return "KimodoNPZ <unreadable>"
