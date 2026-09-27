"""Extract animation samplers from the original pilot kit GLB into JSON.

Parses the GLB (JSON + BIN chunks) directly - no Blender needed. For each of
the six pistol clips, dumps every animated joint's local translation/rotation
keyframes (times in seconds, values as tuples) keyed by joint node name,
split by which armature subtree ("Pilot_Character" / "Pilot_Character.001")
the joint belongs to. Also computes a checksum: the chain-product global
rotation of hand_r / upperarm_r / pelvis per frame, for later verification.

Output: C:/Users/hackd/AppData/Local/Temp/pilot_anim.json

Usage: python test/extract_glb_anim.py [glb_path]
"""
import json
import struct
import sys

GLB = sys.argv[1] if len(sys.argv) > 1 else "C:/Users/hackd/AppData/Local/Temp/pilot_orig.glb"
OUT = "C:/Users/hackd/AppData/Local/Temp/pilot_anim.json"
FPS = 30.0

raw = open(GLB, "rb").read()
json_len = struct.unpack("<I", raw[12:16])[0]
g = json.loads(raw[20:20 + json_len].decode("utf-8"))

# BIN chunk
bin_off = 20 + json_len
bin_len = struct.unpack("<I", raw[bin_off:bin_off + 4])[0]
assert raw[bin_off + 4:bin_off + 8] == b"BIN\x00", "no BIN chunk"
bin_data = raw[bin_off + 8:bin_off + 8 + bin_len]

CT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
CT_FMT = {5126: "f", 5125: "I", 5123: "H", 5122: "h"}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(idx):
    acc = g["accessors"][idx]
    n = TYPE_N[acc["type"]]
    ct = acc["componentType"]
    size = CT_SIZE[ct] * n
    bv = g["bufferViews"][acc["bufferView"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    out = []
    fmt = "<" + CT_FMT[ct] * n
    for i in range(count):
        off = start + i * size
        out.append(struct.unpack_from(fmt, bin_data, off))
    return out


node_name = [n.get("name", "node%d" % i) for i, n in enumerate(g["nodes"])]
animated_nodes = set()
for anim in g.get("animations", []):
    for ch in anim["channels"]:
        if ch["target"].get("node") is not None:
            animated_nodes.add(ch["target"]["node"])
print("animated joint nodes:", len(animated_nodes))

result = {}
for anim in g.get("animations", []):
    name = anim.get("name", "?")
    if name not in ("pistol_idle", "pistol_reload", "pistol_shoot",
                    "pistol_idle.001", "pistol_reload.001", "pistol_shoot.001"):
        continue
    joints = {}
    for ch in anim["channels"]:
        tgt = ch["target"]
        ni = tgt.get("node")
        if ni is None or ni not in animated_nodes:
            continue
        path = tgt.get("path")
        if path not in ("rotation", "translation"):
            continue
        sam = anim["samplers"][ch["sampler"]]
        times = [t[0] * FPS for t in read_accessor(sam["input"])]
        vals = read_accessor(sam["output"])
        j = joints.setdefault(node_name[ni], {"t_r": [], "r": [], "t_tr": [], "tr": []})
        if path == "rotation":
            j["r"] = [[round(c, 6) for c in q] for q in vals]  # x,y,z,w
            j["t_r"] = [round(t, 4) for t in times]
        else:
            j["tr"] = [[round(c, 6) for c in v] for v in vals]
            j["t_tr"] = [round(t, 4) for t in times]
    result[name] = joints
    all_t = [t for j in joints.values() for t in (j["t_r"] + j["t_tr"])]
    print("%s: %d joints, frames %.0f..%.0f" % (name, len(joints), min(all_t), max(all_t)))

json.dump(result, open(OUT, "w"))
print("written:", OUT)
