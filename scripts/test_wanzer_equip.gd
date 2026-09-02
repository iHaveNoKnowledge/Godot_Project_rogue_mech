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
	# Wanzer uses custom ArmorPart tres that already point to wanzer_{slot}.tscn
	var loadout := {
		"head": {"frame": {"id":"frame_head_01","equipped":true}, "armor": {"id":"wanzer_head","equipped":true,"path":"res://resources/mech/parts/head/wanzer_head.tres","slot":"head"}},
		"body": {"frame": {"id":"frame_body_01","equipped":true}, "armor": {"id":"wanzer_body","equipped":true,"path":"res://resources/mech/parts/body/wanzer_body.tres","slot":"body"}},
		"arm_left": {"frame": {"id":"frame_arm_left_01","equipped":true}, "armor": {"id":"wanzer_arm_left","equipped":true,"path":"res://resources/mech/parts/arm_left/wanzer_arm_left.tres","slot":"arm_left"}},
		"arm_right": {"frame": {"id":"frame_arm_right_01","equipped":true}, "armor": {"id":"wanzer_arm_right","equipped":true,"path":"res://resources/mech/parts/arm_right/wanzer_arm_right.tres","slot":"arm_right"}},
		"leg_left": {"frame": {"id":"frame_leg_left_01","equipped":true}, "armor": {"id":"wanzer_leg_left","equipped":true,"path":"res://resources/mech/parts/leg_left/wanzer_leg_left.tres","slot":"leg_left"}},
		"leg_right": {"frame": {"id":"frame_leg_right_01","equipped":true}, "armor": {"id":"wanzer_leg_right","equipped":true,"path":"res://resources/mech/parts/leg_right/wanzer_leg_right.tres","slot":"leg_right"}},
	}

	# Also test full GLB as single mesh preview (optional): attach to Body for reference
	# var full = load("res://scenes/mecha/parts/body/wanzer_body.tscn")
	pm.refresh_from_loadout(loadout)
	print("[TestWanzer] Equipped Wanzer 6 parts via refresh_from_loadout")
	for slot in ["head","body","arm_left","arm_right","leg_left","leg_right"]:
		var tres_path = "res://resources/mech/parts/%s/wanzer_%s.tres" % [slot, slot]
		print("  %s -> %s exists: %s" % [slot, tres_path, ResourceLoader.exists(tres_path)])
		var glb_path = "res://scenes/mecha/parts/%s/wanzer_%s.glb" % [slot, slot]
		print("  GLB %s exists: %s" % [glb_path, ResourceLoader.exists(glb_path)])
