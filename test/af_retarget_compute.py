"""Compute retargeted bone-local keys for the ActionForge clips - pure math,
no Blender involved. Output JSON is consumed by the Blender stager.

Model (measured on this pipeline):
 - Source GLB (ActionForge): rest node TR per joint + animation samples.
   Source armature-space animated pose by chain recursion:
       A(J, f) = A(parent, f) @ L(J, f),  L = Translation @ Rotation
   Bind geometry from the skin's inverse bind matrices:
       B_src(J) = IBM(J)^-1   (armature-space bind pose of the SOURCE)
 - Bind-relative deformation:  M(J, f) = A(J, f) @ B_src(J)^-1
 - Frame conversion source-arm-space -> Blender-arm-space: one global
   rotation G, measured by bone-direction congruence over shared bones
   (candidates Rx(90) * Ry(yaw)); pick the lowest max residual.
       M_bl(J,f) = G @ M @ G^-1 ;  A_tgt(J,f) = M_bl(J,f) @ A_rest_bl(J)
   (the kit's own Blender rest supplies positions)
 - Bone-local keys: L = A_tgt(parent)^-1 @ A_tgt(J), B = K_bl(J)^-1 @ L.
 - Sanity at f0: pelvis height ~0.9, feet z >= -0.06, hand forward-ish.

Output: C:/Users/hackd/AppData/Local/Temp/af_retarget.json
  {clip: {duration, fps, frames, bones: {name: {q:[[w,x,y,z]..], t:[[x,y,z]..]}}}}

Usage: python test/af_retarget_compute.py
"""
import json
import math
import os
import struct

SRC_DIR = "Z:/animations/actionforge-12-clips-inplace-anim-only"
AF_JSON = "C:/Users/hackd/AppData/Local/Temp/af_all.json"
KBL_JSON = "C:/Users/hackd/AppData/Local/Temp/kit_kbl.json"
OUT = "C:/Users/hackd/AppData/Local/Temp/af_retarget.json"
FPS = 30.0


def m4_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def m4_inv(m):
    inv = [[0.0] * 4 for _ in range(4)]
    inv[0][0] = m[1][1] * m[2][2] - m[1][2] * m[2][1]
    inv[0][1] = m[0][2] * m[2][1] - m[0][1] * m[2][2]
    inv[0][2] = m[0][1] * m[1][2] - m[0][2] * m[1][1]
    inv[1][0] = m[1][2] * m[2][0] - m[1][0] * m[2][2]
    inv[1][1] = m[0][0] * m[2][2] - m[0][2] * m[2][0]
    inv[1][2] = m[0][2] * m[1][0] - m[0][0] * m[1][2]
    inv[2][0] = m[1][0] * m[2][1] - m[1][1] * m[2][0]
    inv[2][1] = m[0][1] * m[2][0] - m[0][0] * m[2][1]
    inv[2][2] = m[0][0] * m[1][1] - m[0][1] * m[1][0]
    det = m[0][0] * inv[0][0] + m[0][1] * inv[1][0] + m[0][2] * inv[2][0]
    if abs(det) < 1e-12:
        raise ValueError("singular")
    det = 1.0 / det
    for i in range(3):
        for j in range(3):
            inv[i][j] *= det
    t = [m[0][3], m[1][3], m[2][3]]
    for i in range(3):
        inv[i][3] = -(inv[i][0] * t[0] + inv[i][1] * t[1] + inv[i][2] * t[2])
    inv[3] = [0.0, 0.0, 0.0, 1.0]
    return inv


def m4_from_tr(t, q):
    w, x, y, z = q
    n = math.sqrt(w * w + x * x + y * y + z * z)
    w, x, y, z = w / n, x / n, y / n, z / n
    return [
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), t[0]],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), t[1]],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), t[2]],
        [0.0, 0.0, 0.0, 1.0],
    ]


def m4_rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "x":
        r = [[1, 0, 0], [0, c, -s], [0, s, c]]
    elif axis == "y":
        r = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    else:
        r = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    return [[r[0][0], r[0][1], r[0][2], 0],
            [r[1][0], r[1][1], r[1][2], 0],
            [r[2][0], r[2][1], r[2][2], 0],
            [0, 0, 0, 1]]


def v3_sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def v3_add(a, b):
    return [a[i] + b[i] for i in range(3)]


def v3_len(a):
    return math.sqrt(sum(v * v for v in a))


def v3_norm(a):
    n = v3_len(a)
    return [v / n for v in a] if n > 1e-9 else [0.0, 0.0, 0.0]


def m3_mulv(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def m3_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def m3_transpose(m):
    return [[m[j][i] for j in range(3)] for i in range(3)]


def quat_normalize(q):
    n = math.sqrt(sum(v * v for v in q))
    return [v / n for v in q] if n > 1e-9 else [1.0, 0.0, 0.0, 0.0]


def quat_slerp(a, b, k):
    dot = sum(a[i] * b[i] for i in range(4))
    if dot < 0:
        b = [-v for v in b]
        dot = -dot
    if dot > 0.9995:
        return quat_normalize([a[i] + (b[i] - a[i]) * k for i in range(4)])
    th = math.acos(max(-1.0, min(1.0, dot)))
    sth = math.sin(th)
    wa = math.sin((1 - k) * th) / sth
    wb = math.sin(k * th) / sth
    return [a[i] * wa + b[i] * wb for i in range(4)]


def quat_from_m3(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        return quat_normalize([(s / 4), (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s])
    i = max(range(3), key=lambda k: m[k][k])
    if i == 0:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        return quat_normalize([(m[2][1] - m[1][2]) / s, s / 4, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s])
    if i == 1:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        return quat_normalize([(m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, s / 4, (m[1][2] + m[2][1]) / s])
    s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
    return quat_normalize([(m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, s / 4])


def m3_of(m4):
    return [m4[0][:3], m4[1][:3], m4[2][:3]]


def sample_pair(times, t):
    if not times:
        return None, 0.0
    if t <= times[0]:
        return 0, 0.0
    if t >= times[-1]:
        return len(times) - 1, 0.0
    for i in range(len(times) - 1):
        if times[i] <= t <= times[i + 1]:
            span = times[i + 1] - times[i]
            return i, (0.0 if span <= 1e-9 else (t - times[i]) / span)
    return len(times) - 1, 0.0


af = json.load(open(AF_JSON))
kbl = json.load(open(KBL_JSON))
parent = {n: rec["parent"] for n, rec in kbl.items()}
K_bl = {n: rec["K"] for n, rec in kbl.items()}

_rest_cache = {}


def rest_arm(n):
    if n in _rest_cache:
        return _rest_cache[n]
    p = parent.get(n)
    m = K_bl[n] if not p else m4_mul(rest_arm(p), K_bl[n])
    _rest_cache[n] = m
    return m


depth = {}


def get_depth(n):
    if n not in depth:
        p = parent.get(n)
        depth[n] = 0 if not p else get_depth(p) + 1
    return depth[n]


order = sorted(kbl.keys(), key=get_depth)

src_entry = next(v for v in af.values() if "pistol_idle_loop" in v["clips"])
src_rest = src_entry["rest"]
src_parent = {n: rec.get("parent") for n, rec in src_rest.items()}


def read_ibms(path):
    raw = open(path, "rb").read()
    jl = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20:20 + jl].decode())
    bin_off = 20 + jl
    bl = struct.unpack("<I", raw[bin_off:bin_off + 4])[0]
    bd = raw[bin_off + 8:bin_off + 8 + bl]
    names = [n.get("name", "?") for n in g["nodes"]]
    out = {}
    for sk in g.get("skins", []):
        acc = g["accessors"][sk["inverseBindMatrices"]]
        off = g["bufferViews"][acc["bufferView"]].get("byteOffset", 0) + acc.get("byteOffset", 0)
        for i, nidx in enumerate(sk["joints"]):
            nm = names[nidx]
            if nm not in kbl:
                continue
            m = list(struct.unpack_from("<16f", bd, off + i * 64))
            M = [[m[0], m[4], m[8], m[12]],
                 [m[1], m[5], m[9], m[13]],
                 [m[2], m[6], m[10], m[14]],
                 [m[3], m[7], m[11], m[15]]]
            out[nm] = m4_inv(M)  # bind pose in source arm space
    return out


B_src = read_ibms(SRC_DIR + "/pilot_pistol_idle_loop-inplace-anim-only.glb")
print("source bind poses: %d joints (reference only)" % len(B_src))


def wt(m):
    return [m[0][3], m[1][3], m[2][3]]


# source armature-space REST by chain recursion over node TR (sane standing pose)
_src_rest_arm = {}


def src_rest_arm(n):
    if n in _src_rest_arm:
        return _src_rest_arm[n]
    r = src_rest[n]
    L = m4_from_tr(r["t"], r["q"])
    p = r.get("parent")
    m = m4_mul(src_rest_arm(p), L) if (p and p in src_rest) else L
    _src_rest_arm[n] = m
    return m


src_dirs = {}
for n in src_rest:
    p = src_rest[n].get("parent")
    if p and p in src_rest:
        d = v3_sub(wt(src_rest_arm(n)), wt(src_rest_arm(p)))
        if v3_len(d) > 1e-6:
            src_dirs[n] = v3_norm(d)

bl_dirs = {}
for n in src_dirs:
    p = parent.get(n)
    if p and p in kbl:
        d = v3_sub(wt(rest_arm(n)), wt(rest_arm(p)))
        if v3_len(d) > 1e-6:
            bl_dirs[n] = v3_norm(d)

cands = {}
for xdeg in (90, -90):
    for yaw in (0, 90, 180, 270):
        G = m4_rot("x", xdeg)
        if yaw:
            G = m4_mul(G, m4_rot("y", yaw))
        G3 = m3_of(G)
        residuals = []
        for n, es in src_dirs.items():
            if n not in bl_dirs:
                continue
            eg = m3_mulv(G3, es)
            dot = max(-1.0, min(1.0, sum(eg[i] * bl_dirs[n][i] for i in range(3))))
            residuals.append(math.degrees(math.acos(dot)))
        residuals.sort()
        med = residuals[len(residuals) // 2]
        worst = residuals[-1]
        key = (xdeg, yaw)
        cands[key] = (med, worst, G)
        print("G candidate Rx(%d)*Ry(%d): median %.2f deg (max %.2f)" % (xdeg, yaw, med, worst))

best_key = min(cands, key=lambda k: cands[k][0])
med, worst, G = cands[best_key]
G3 = m3_of(G)
G3_inv = m3_transpose(G3)
print("chosen G: Rx(%d)*Ry(%d) median residual %.2f deg (max %.2f - leaves may flip)"
      % (best_key[0], best_key[1], med, worst))
if med > 5.0:
    print("WARNING: median residual high - check axes")

ratios = []
for n in src_dirs:
    p = src_rest[n].get("parent")
    if p and p in src_rest and n in bl_dirs:
        lb = v3_len(v3_sub(wt(rest_arm(n)), wt(rest_arm(p))))
        ls = v3_len(v3_sub(wt(src_rest_arm(n)), wt(src_rest_arm(p))))
        if ls > 1e-6:
            ratios.append(lb / ls)
ratios.sort()
print("bone length ratio bl/src: median %.3f (p10 %.3f p90 %.3f)"
      % (ratios[len(ratios) // 2], ratios[len(ratios) // 10], ratios[len(ratios) * 9 // 10]))

out = {}
for fname, entry in af.items():
    for cname, clip in entry["clips"].items():
        duration = clip["duration"]
        nframes = int(math.ceil(duration * FPS)) + 1
        rec = entry["rest"]
        sdepth = {}

        def sd(n):
            if n not in sdepth:
                p = rec.get(n, {}).get("parent")
                sdepth[n] = 0 if not p else sd(p) + 1
            return sdepth[n]

        for n in rec:
            sd(n)
        order_s = sorted(rec.keys(), key=lambda n: sdepth[n])

        A_tgt_all = []
        for fi in range(nframes):
            R_t = {}
            p_t = {}
            f = fi / FPS
            A_src = {}
            for n in order_s:
                r = rec[n]
                bd = clip["bones"].get(n)
                if bd:
                    iq, kq = sample_pair(bd["times_q"], f)
                    it, kt = sample_pair(bd["times_t"], f)
                    if bd["q"]:
                        i2 = min(iq + 1, len(bd["q"]) - 1)
                        q = quat_slerp(bd["q"][iq], bd["q"][i2], kq)
                    else:
                        q = r["q"]
                    if bd["t"]:
                        i2 = min(it + 1, len(bd["t"]) - 1)
                        t = [bd["t"][it][k] + (bd["t"][i2][k] - bd["t"][it][k]) * kt for k in range(3)]
                    else:
                        t = r["t"]
                    L = m4_from_tr(t, q)
                else:
                    L = m4_from_tr(r["t"], r["q"])
                p = r.get("parent")
                A_src[n] = m4_mul(A_src[p], L) if (p and p in A_src) else L
            At = {}
            for n in order:
                if n not in kbl:
                    continue
                par = parent.get(n)
                if n not in A_src or n not in src_rest:
                    # kit-only mid bones (Body, *_end): identity deformation on
                    # the animated parent chain
                    if par and par in At:
                        At[n] = m4_mul(At[par], K_bl[n])
                    else:
                        At[n] = [row[:] for row in rest_arm(n)]
                    continue
                # rest-relative deformation of the SOURCE, re-expressed on the
                # kit's rest (root rotation cancels: M(root)=I when unanimated)
                M = m4_mul(A_src[n], m4_inv(src_rest_arm(n)))
                Mr_bl = m3_mul(G3, m3_mul(m3_of(M), G3_inv))
                Mt_bl = m3_mulv(G3, wt(M))
                M_bl = [
                    [Mr_bl[0][0], Mr_bl[0][1], Mr_bl[0][2], Mt_bl[0]],
                    [Mr_bl[1][0], Mr_bl[1][1], Mr_bl[1][2], Mt_bl[1]],
                    [Mr_bl[2][0], Mr_bl[2][1], Mr_bl[2][2], Mt_bl[2]],
                    [0.0, 0.0, 0.0, 1.0],
                ]
                At[n] = m4_mul(M_bl, rest_arm(n))
            # resolve kit-only mid bones (Body, *_end) so their children key
            # against the ANIMATED parent chain, not a frozen rest frame
            for bn in order:
                if bn in At:
                    continue
                p = parent.get(bn)
                if p and p in At:
                    At[bn] = m4_mul(At[p], K_bl[bn])
            A_tgt_all.append(At)

        bones_out = {}
        for At in A_tgt_all:
            for n in order:
                if n not in At:
                    continue
                p = parent.get(n)
                Ap = At[p] if (p and p in At) else None
                L = m4_mul(m4_inv(Ap), At[n]) if Ap else At[n]
                B = m4_mul(m4_inv([row[:] for row in K_bl[n]]), L)
                q = quat_from_m3(m3_of(B))
                bo = bones_out.setdefault(n, {"q": [], "t": []})
                bo["q"].append([round(v, 6) for v in q])
                if n == "pelvis":
                    # Blender pose location is a DELTA from rest: key the
                    # animated-vs-rest arm-space delta in the local frame
                    C = m3_of(m4_mul(Ap, K_bl[n])) if Ap else m3_of(m4_mul(rest_arm(parent.get(n)), K_bl[n]))
                    delta = v3_sub(wt(At[n]), wt(rest_arm(n)))
                    dl = m3_mulv(m3_transpose(C), delta)
                    bo["t"].append([round(dl[0], 6), round(dl[1], 6), round(dl[2], 6)])
                else:
                    bo["t"].append([round(B[0][3], 6), round(B[1][3], 6), round(B[2][3], 6)])

        At0 = A_tgt_all[0]
        pz = wt(At0["pelvis"])[2] if "pelvis" in At0 else float("nan")
        fz = min([wt(At0[b])[2] for b in ("foot_l", "foot_r") if b in At0] or [float("nan")])
        hy = wt(At0["hand_r"])[2] if "hand_r" in At0 else float("nan")
        print("%s: %d frames | f0 pelvis z %.3f | feet z min %.3f | hand z %.3f"
              % (cname, len(A_tgt_all), pz, fz, hy))
        ok = fz > -0.06 and 0.75 < pz < 1.05
        print("   sanity:", "OK" if ok else "CHECK")
        out[cname] = {"duration": duration, "fps": FPS, "frames": nframes, "bones": bones_out}

json.dump(out, open(OUT, "w"))
print("written:", OUT)
