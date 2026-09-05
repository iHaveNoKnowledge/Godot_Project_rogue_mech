extends Node3D
# Test scene to preview Wanzer parts in-game without editing catalog.
# Attach to TestWanzer root; it will auto-equip Wanzer 6 parts on MechaBase via PartMeshManager.

func _ready() -> void:
	var mecha = $MechaBase
	if not mecha:
		push_error("MechaBase not found")
		return
	var pm = mecha.get_node_or_null("PartMeshManager")
	if not pm:
		push_error("PartMeshManager not found")
		return

	# Ensure frames exist (default inner frame) so Armor can show
	var loadout := {
		"head": {"frame": {"id":"frame_head_01","equipped":true}, "armor": {"id":"line_head","equipped":true,"path":"res://resources/mech/parts/head/line_head.tres","slot":"head"}},
		"body": {"frame": {"id":"frame_body_01","equipped":true}, "armor": {"id":"line_body","equipped":true,"path":"res://resources/mech/parts/body/line_body.tres","slot":"body"}},
		"arm_left": {"frame": {"id":"frame_arm_left_01","equipped":true}, "armor": {"id":"line_arm_left","equipped":true,"path":"res://resources/mech/parts/arm_left/line_arm_left.tres","slot":"arm_left"}},
		"arm_right": {"frame": {"id":"frame_arm_right_01","equipped":true}, "armor": {"id":"line_arm_right","equipped":true,"path":"res://resources/mech/parts/arm_right/line_arm_right.tres","slot":"arm_right"}},
		"leg_left": {"frame": {"id":"frame_leg_left_01","equipped":true}, "armor": {"id":"line_leg_left","equipped":true,"path":"res://resources/mech/parts/leg_left/line_leg_left.tres","slot":"leg_left"}},
		"leg_right": {"frame": {"id":"frame_leg_right_01","equipped":true}, "armor": {"id":"line_leg_right","equipped":true,"path":"res://resources/mech/parts/leg_right/line_leg_right.tres","slot":"leg_right"}},
	}

	pm.refresh_from_loadout(loadout)
	print("[TestWanzer] Equipped Line Modular Pack via refresh_from_loadout")
	for slot in ["head","body","arm_left","arm_right","leg_left","leg_right"]:
		var tres_path = "res://resources/mech/parts/%s/wanzer_%s_001.tres" % [slot, slot]
		print("  %s -> %s exists: %s" % [slot, tres_path, ResourceLoader.exists(tres_path)])
		var glb_path = "res://scenes/mecha/parts/%s/wanzer_%s.glb" % [slot, slot]
		print("  GLB %s exists: %s" % [glb_path, ResourceLoader.exists(glb_path)])
