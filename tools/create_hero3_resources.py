"""
Creates ArmorPart .tres resource files for Hero3 Vanguard and registers the pack
into resources/data/mech_catalogs.tres.
"""

import os
import re
import sys

if sys.stdout.encoding != 'utf-8':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
RESOURCES_DIR = os.path.join(BASE_DIR, "resources", "mech", "parts")
CATALOG_PATH = os.path.join(BASE_DIR, "resources", "data", "mech_catalogs.tres")

PACK = {
    "id_prefix": "hero3",
    "name_prefix": "Hero3 Vanguard",
    "color": "Color(0.82, 0.81, 0.79, 1)",
    "type": "Heavy Armor",
    "stats": {
        "head": {"hp": 55.0, "armor": 35.0, "weight": 8.0},
        "body": {"hp": 140.0, "armor": 65.0, "weight": 26.0},
        "arm_left": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
        "arm_right": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
        "leg_left": {"hp": 75.0, "armor": 48.0, "weight": 17.0},
        "leg_right": {"hp": 75.0, "armor": 48.0, "weight": 17.0},
    }
}

def create_tres_files():
    for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
        slot_dir = os.path.join(RESOURCES_DIR, slot)
        os.makedirs(slot_dir, exist_ok=True)

        tres_path = os.path.join(slot_dir, f"hero3_{slot}.tres")
        part_name = f"{PACK['name_prefix']} {slot.replace('_', ' ').title()}"
        stats = PACK["stats"][slot]

        if slot in ["head", "body"]:
            mesh_path = f"res://scenes/mecha/parts/{slot}/hero3_{slot}.tscn"
            content = f"""[gd_resource type="Resource" load_steps=3 format=3]

[ext_resource type="Script" path="res://resources/mech/armor_part.gd" id="1"]
[ext_resource type="PackedScene" path="{mesh_path}" id="2"]

[resource]
script = ExtResource("1")
part_name = "{part_name}"
slot_id = "{slot}"
mesh_scene = ExtResource("2")
max_hp = {stats['hp']}
max_frame_hp = {stats['hp'] * 0.8:.1f}
weight = {stats['weight']}
armor_class = {stats['armor']}
break_threshold = 0.3
part_color = {PACK['color']}
"""
        else:
            upper_mesh = f"res://scenes/mecha/parts/{slot}/hero3_{slot}_upper.tscn"
            lower_mesh = f"res://scenes/mecha/parts/{slot}/hero3_{slot}_lower.tscn"
            content = f"""[gd_resource type="Resource" load_steps=4 format=3]

[ext_resource type="Script" path="res://resources/mech/armor_part.gd" id="1"]
[ext_resource type="PackedScene" path="{upper_mesh}" id="2"]
[ext_resource type="PackedScene" path="{lower_mesh}" id="3"]

[resource]
script = ExtResource("1")
part_name = "{part_name}"
slot_id = "{slot}"
mesh_scene = ExtResource("2")
mesh_scene_lower = ExtResource("3")
max_hp = {stats['hp']}
max_frame_hp = {stats['hp'] * 0.8:.1f}
weight = {stats['weight']}
armor_class = {stats['armor']}
break_threshold = 0.3
part_color = {PACK['color']}
"""
        with open(tres_path, "w", encoding="utf-8") as f:
            f.write(content)
        print(f"Created: {tres_path}")

def update_catalog():
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    slots = ["arm_left", "arm_right", "body", "head", "leg_left", "leg_right"]

    for slot in slots:
        pattern = rf'"{slot}": \[\n\{{'
        match = re.search(pattern, content)
        if not match:
            print(f"Could not find slot section: {slot}")
            continue

        pid = f"hero3_{slot}"
        if f'"id": "{pid}"' in content:
            print(f"Already in catalog: {pid}")
            continue

        pname = f"{PACK['name_prefix']} {slot.replace('_', ' ').title()}"
        st = PACK["stats"][slot]
        ppath = f"res://resources/mech/parts/{slot}/{pid}.tres"

        entry = f"""{{
"armor": {st['armor']},
"color": {PACK['color']},
"hp": {st['hp']},
"id": "{pid}",
"name": "{pname}",
"path": "{ppath}",
"type": "{PACK['type']}",
"weight": {st['weight']}
}}, """

        idx = match.start() + len(f'"{slot}": [\n')
        content = content[:idx] + entry + content[idx:]
        print(f"Added {pid} to catalog under slot {slot}")

    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("Catalog successfully updated.")

if __name__ == "__main__":
    create_tres_files()
    update_catalog()
