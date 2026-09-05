"""
Adds the scout, line, and vanguard armor parts into resources/data/mech_catalogs.tres
so they appear in the Hangar Catalog, Craftery, and Part lists.
"""

import os
import re

CATALOG_PATH = r"c:\Users\hackd\OneDrive\เอกสาร\GitHub\Godot_Project_rogue_mech\resources\data\mech_catalogs.tres"

PACKS = [
    {
        "id_prefix": "scout",
        "name_prefix": "Aegis Scout",
        "color": "Color(0.2, 0.7, 0.85, 1)",
        "type": "Light Armor",
        "stats": {
            "head": {"hp": 30.0, "armor": 15.0, "weight": 3.0},
            "body": {"hp": 65.0, "armor": 25.0, "weight": 10.0},
            "arm_left": {"hp": 25.0, "armor": 15.0, "weight": 4.0},
            "arm_right": {"hp": 25.0, "armor": 15.0, "weight": 4.0},
            "leg_left": {"hp": 35.0, "armor": 20.0, "weight": 6.0},
            "leg_right": {"hp": 35.0, "armor": 20.0, "weight": 6.0},
        }
    },
    {
        "id_prefix": "line",
        "name_prefix": "Titan Line",
        "color": "Color(0.3, 0.5, 0.7, 1)",
        "type": "Standard Armor",
        "stats": {
            "head": {"hp": 40.0, "armor": 25.0, "weight": 5.0},
            "body": {"hp": 90.0, "armor": 40.0, "weight": 16.0},
            "arm_left": {"hp": 35.0, "armor": 25.0, "weight": 7.0},
            "arm_right": {"hp": 35.0, "armor": 25.0, "weight": 7.0},
            "leg_left": {"hp": 50.0, "armor": 30.0, "weight": 10.0},
            "leg_right": {"hp": 50.0, "armor": 30.0, "weight": 10.0},
        }
    },
    {
        "id_prefix": "vanguard",
        "name_prefix": "Colossus Vanguard",
        "color": "Color(0.85, 0.45, 0.2, 1)",
        "type": "Heavy Armor",
        "stats": {
            "head": {"hp": 55.0, "armor": 35.0, "weight": 8.0},
            "body": {"hp": 130.0, "armor": 60.0, "weight": 24.0},
            "arm_left": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
            "arm_right": {"hp": 50.0, "armor": 40.0, "weight": 11.0},
            "leg_left": {"hp": 70.0, "armor": 45.0, "weight": 15.0},
            "leg_right": {"hp": 70.0, "armor": 45.0, "weight": 15.0},
        }
    }
]

def add_catalog_entries():
    with open(CATALOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    slots = ["arm_left", "arm_right", "body", "head", "leg_left", "leg_right"]
    
    for slot in slots:
        pattern = rf'"{slot}": \[\{{'
        match = re.search(pattern, content)
        if not match:
            print(f"Could not find slot section: {slot}")
            continue

        entries_str = ""
        for pack in PACKS:
            pid = f"{pack['id_prefix']}_{slot}"
            # Check if already present
            if f'"id": "{pid}"' in content:
                continue
            
            pname = f"{pack['name_prefix']} {slot.replace('_', ' ').title()}"
            st = pack["stats"][slot]
            ppath = f"res://resources/mech/parts/{slot}/{pid}.tres"
            
            entry = f"""{{
"armor": {st['armor']},
"color": {pack['color']},
"hp": {st['hp']},
"id": "{pid}",
"name": "{pname}",
"path": "{ppath}",
"type": "{pack['type']}",
"weight": {st['weight']}
}}, """
            entries_str += entry

        if entries_str:
            # Insert right after `"{slot}": [`
            idx = match.start() + len(f'"{slot}": [')
            content = content[:idx] + "\n" + entries_str + content[idx:]

    with open(CATALOG_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    print("Updated mech_catalogs.tres with all modular packs.")

if __name__ == "__main__":
    add_catalog_entries()
