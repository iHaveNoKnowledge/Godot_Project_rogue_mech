import bpy


def run_ai_script_safely(script_code: str):
    # 1. บันทึก State ก่อนรัน (สร้าง Undo Step)
    bpy.ops.ed.undo_push(message="Before AI Execution")

    # 2. ปรับ Context ให้ปลอดภัย (กลับสู่ OBJECT Mode เสมอ)
    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    try:
        # 3. รันสคริปต์ที่ AI ส่งมา
        exec(script_code)
        print("Harness: Execution Successful")
        return True
    except Exception as e:
        # 4. หากเกิด Error ให้ Rollback Scene กลับทันที
        print(f"Harness Error Detected: {e}")
        bpy.ops.ed.undo()
        raise e


def capture_test_render(output_path="res://test_render.png"):
    bpy.context.scene.render.filepath = output_path
    bpy.ops.render.render(write_still=True)
