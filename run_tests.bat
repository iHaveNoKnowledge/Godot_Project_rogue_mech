# ตัวอย่าง run_tests.sh
# สั่งให้ Godot รัน GUT test ทั้งหมดแบบไม่เปิดหน้าจอ แล้วส่งค่า Return Code ออกมา
godot --headless -s plug-ins/gut/gut_cmdln.gd -gdir=res://test/unit/ -gexit