"""Inventory the ActionForge source GLB set (Z:/animations/...).

For each file: clip name(s), joint count, frame count/duration, and how many
of its joints exist in Pilot_Character's 79-bone set (read from the current
kit GLB). Tells us which clips are directly usable for retargeting.

Usage: python test/extract_actionforge_set.py
"""
import glob
import json
import struct

SRC_DIR = "Z:/animations/actionforge-12-clips-inplace-anim-only"
KIT = ("C:/Users/hackd/OneDrive/เอกสาร/GitHub/Godot_Project_rogue_mech/"
       "scenes/pilot/pilot_pistol_kit.glb")


def read_glb_json(path):
    raw = open(path, "rb").read()
    jl = struct.unpack("<I", raw[12:16])[0]
    return json.loads(raw[20:20 + jl].decode("utf-8"))


kit_g = read_glb_json(KIT)
kit_names = set(n.get("name") for n in kit_g["nodes"] if n.get("name"))
# rest translation per kit joint (for length comparison later)
print("kit joints: %d" % len(kit_names))
print()

for path in sorted(glob.glob(SRC_DIR + "/*.glb")):
    g = read_glb_json(path)
    names = [n.get("name", "?") for n in g["nodes"]]
    print("=== %s" % path.split("/")[-1])
    for anim in g.get("animations", []):
        joints = set()
        for ch in anim["channels"]:
            if ch["target"].get("node") is not None:
                joints.add(names[ch["target"]["node"]])
        shared = len(joints & kit_names)
        missing = sorted(joints - kit_names)
        # duration from a sampler
        dur = 0.0
        for ch in anim["channels"][:1]:
            sam = anim["samplers"][ch["sampler"]]
            acc = g["accessors"][sam["input"]]
            dur = acc.get("max", [0])[0]
        print("  clip '%s': %d joints (%d in kit) dur %.2fs"
              % (anim.get("name", "?"), len(joints), shared, dur))
        if missing:
            print("    not in kit: %s" % missing)
    if not g.get("animations"):
        print("  (no animations)")
