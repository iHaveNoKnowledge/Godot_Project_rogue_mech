"""
Generates .tres ArmorPart resources and updates mech_catalogs.tres for the extracted modular parts.
"""
import os

BASE_DIR = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech"
PARTS_DIR = os.path.join(BASE_DIR, "scenes", "mecha", "parts")
RESOURCES_DIR = os.path.join(BASE_DIR, "resources", "mech", "parts")

PACKS = {
    "scout": {
        "title": "Aegis Scout",
        "color": "Color(0.2, 0.7, 0.85, 1)",
        "stats": {
            "head": {"hp": 30.0, "armor": 15.0, "weight": 3.0},
            "body": {"hp": 65.0, "armor": 25.0, "weight": 10.0},
            "arm_left": {"hp": 25.0, "armor": 15.0, "weight": 4.0},
            "arm_right": {"hp": 25.0, "armor": 15.0, "weight": 4.0},
            "leg_left": {"hp": 35.0, "armor": 20.0, "weight": 6.0},
            "leg_right": {"hp": 35.0, "armor": 20.0, "weight": 6.0},
        }
    },
    "line": {
        "title": "Titan Line",
        "color": "Color(0.3, 0.5, 0.7, 1)",
        "stats": {
            "head": {"hp": 40.0, "armor": 25.0, "weight": 5.0},
            "body": {"hp": 90.0, "armor": 40.0, "weight": 16.0},
            "arm_left": {"hp": 35.0, "armor": 25.0, "weight": 7.0},
            "arm_right": {"hp": 35.0, "armor": 25.0, "weight": 7.0},
            "leg_left": {"hp": 50.0, "armor": 30.0, "weight": 10.0},
            "leg_right": {"hp": 50.0, "armor": 30.0, "weight": 10.0},
        }
    },
    "vanguard": {
        "title": "Colossus Vanguard",
        "color": "Color(0.85, 0.45, 0.2, 1)",
        "stats": {
            "head": {"hp": 55.0, "armor": 35.0, "weight": 8.0},
            "body": {"hp": 130.0, "armor": 60.0, "weight": 24.0},
            "arm_left": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
            "arm_right": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
            "leg_left": {"hp": 70.0, "armor": 45.0, "weight": 15.0},
            "leg_right": {"hp": 70.0, "armor": 45.0, "weight": 15.0},
        }
    }
}

def create_tres_files():
    for pack_id, pack_info in PACKS.items():
        for slot in ["head", "body", "arm_left", "arm_right", "leg_left", "leg_right"]:
            slot_dir = os.path.join(RESOURCES_DIR, slot)
            os.makedirs(slot_dir, exist_ok=True)
            
            tres_path = os.path.join(slot_dir, f"{pack_id}_{slot}.tres")
            part_name = f"{pack_info['title']} {slot.replace('_', ' ').title()}"
            stats = pack_info["stats"][slot]
            
            if slot in ["head", "body"]:
                mesh_path = f"res://scenes/mecha/parts/{slot}/{pack_id}_{slot}.glb"
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
part_color = {pack_info['color']}
"""
            else:
                upper_mesh = f"res://scenes/mecha/parts/{slot}/{pack_id}_{slot}_upper.glb"
                lower_mesh = f"res://scenes/mecha/parts/{slot}/{pack_id}_{slot}_lower.glb"
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
part_color = {pack_info['color']}
"""
            with open(tres_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Created Resource: {tres_path}")

if __name__ == "__main__":
    create_tres_files()
