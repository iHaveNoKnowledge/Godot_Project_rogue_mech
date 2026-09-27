"""Dump all ActionForge source clips into one JSON for Blender retargeting.

For every GLB in the ActionForge dir, extracts:
  rest:   joint name -> {parent, t:[3], q:[w,x,y,z]}  (node local rest TR)
  clips:  name -> {duration_s, bones: {joint: {t: [[x,y,z] per frame],
          q: [[w,x,y,z] per frame], times: [s per frame]}}}
Times are per-channel (rotation/translation timelines differ); the Blender
side samples linearly. Only joints that exist in the kit are kept.

Output: C:/Users/hackd/AppData/Local/Temp/af_all.json

Usage: python test/extract_af_all.py
"""
import glob
import json
import os
import struct

SRC_DIR = "Z:/animations/actionforge-12-clips-inplace-anim-only"
KIT = ("C:/Users/hackd/OneDrive/\u0e40\u0e2d\u0e01\u0e2a\u0e32\u0e23/GitHub/"
       "Godot_Project_rogue_mech/scenes/pilot/pilot_pistol_kit.glb")
OUT = "C:/Users/hackd/AppData/Local/Temp/af_all.json"

CT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
CT_FMT = {5126: "f", 5125: "I", 5123: "H", 5122: "h"}
TYPE_N = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    raw = open(path, "rb").read()
    jl = struct.unpack("<I", raw[12:16])[0]
    g = json.loads(raw[20:20 + jl].decode("utf-8"))
    bin_off = 20 + jl
    bl = struct.unpack("<I", raw[bin_off:bin_off + 4])[0]
    assert raw[bin_off + 4:bin_off + 8] == b"BIN\x00"
    return g, raw[bin_off + 8:bin_off + 8 + bl]


def read_accessor(g, bin_data, idx):
    acc = g["accessors"][idx]
    n = TYPE_N[acc["type"]]
    size = CT_SIZE[acc["componentType"]] * n
    bv = g["bufferViews"][acc["bufferView"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = "<" + CT_FMT[acc["componentType"]] * n
    return [struct.unpack_from(fmt, bin_data, start + i * size)
            for i in range(acc["count"])]


kit_g, _ = read_glb(KIT)
kit_names = set(n.get("name") for n in kit_g["nodes"] if n.get("name"))

out = {}
for path in sorted(glob.glob(SRC_DIR + "/*.glb")):
    base = os.path.basename(path)
    g, bin_data = read_glb(path)
    nodes = g["nodes"]
    names = [n.get("name", "node%d" % i) for i, n in enumerate(nodes)]

    # rest: parent map + local TR (rotation first like Blender)
    rest = {}
    for i, n in enumerate(nodes):
        if not names[i] or names[i] not in kit_names:
            continue
        t = n.get("translation", [0, 0, 0])
        q = n.get("rotation", [0, 0, 0, 1])  # x,y,z,w -> convert
        rest[names[i]] = {
            "parent": names[n["children"][0]] if False else None,
            "t": [round(v, 6) for v in t],
            "q": [round(q[3], 6), round(q[0], 6), round(q[1], 6), round(q[2], 6)],
        }
    # parents among kept joints
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            if names[c] in rest:
                rest[names[c]]["parent"] = names[i] if names[i] in rest else None

    clips = {}
    for anim in g.get("animations", []):
        cname = anim.get("name", os.path.splitext(base)[0])
        bones = {}
        dur = 0.0
        for ch in anim["channels"]:
            tgt = ch["target"]
            ni = tgt.get("node")
            if ni is None or names[ni] not in kit_names:
                continue
            jn = names[ni]
            sam = anim["samplers"][ch["sampler"]]
            times = [round(t[0], 4) for t in read_accessor(g, bin_data, sam["input"])]
            vals = read_accessor(g, bin_data, sam["output"])
            dur = max(dur, times[-1] if times else 0.0)
            b = bones.setdefault(jn, {"t": [], "q": [], "times_t": [], "times_q": []})
            if tgt["path"] == "rotation":
                b["q"] = [[round(v[3], 6), round(v[0], 6), round(v[1], 6), round(v[2], 6)] for v in vals]
                b["times_q"] = times
            elif tgt["path"] == "translation":
                b["t"] = [[round(v[0], 6), round(v[1], 6), round(v[2], 6)] for v in vals]
                b["times_t"] = times
        clips[cname] = {"duration": round(dur, 4), "bones": bones}
        print("%s -> %s: %d joints, %.2fs" % (base, cname, len(bones), dur))
    out[base] = {"rest": rest, "clips": clips}

json.dump(out, open(OUT, "w"))
print("written:", OUT)
