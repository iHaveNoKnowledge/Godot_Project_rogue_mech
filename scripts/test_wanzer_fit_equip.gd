extends Node3D
# Fit-check scene for wanzer_local_001 (v3 chunky symmetric) on the GAME's
# procedural inner frame. Armor is placed by PartMeshManager at true game
# joints - no hand transforms, so any visible misalignment is a real part
# defect, not scene scatter.

func _ready() -> void:
	var mecha = $MechaBase
	if not mecha:
		push_error("MechaBase not found")
		return
	var pm = mecha.get_node_or_null("PartMeshManager")
	if not pm:
		push_error("PartMeshManager not found")
		return

	var loadout := {
		"head": {"frame": {"id":"frame_head_01","equipped":true}, "armor": {"id":"wanzer_local_head_001","equipped":true,"path":"res://resources/mech/parts/head/wanzer_local_001.tres","slot":"head"}},
		"body": {"frame": {"id":"frame_body_01","equipped":true}, "armor": {"id":"wanzer_local_body_001","equipped":true,"path":"res://resources/mech/parts/body/wanzer_local_001.tres","slot":"body"}},
		"arm_left": {"frame": {"id":"frame_arm_left_01","equipped":true}, "armor": {"id":"wanzer_local_arm_left_001","equipped":true,"path":"res://resources/mech/parts/arm_left/wanzer_local_001.tres","slot":"arm_left"}},
		"arm_right": {"frame": {"id":"frame_arm_right_01","equipped":true}, "armor": {"id":"wanzer_local_arm_right_001","equipped":true,"path":"res://resources/mech/parts/arm_right/wanzer_local_001.tres","slot":"arm_right"}},
		"leg_left": {"frame": {"id":"frame_leg_left_01","equipped":true}, "armor": {"id":"wanzer_local_leg_left_001","equipped":true,"path":"res://resources/mech/parts/leg_left/wanzer_local_001.tres","slot":"leg_left"}},
		"leg_right": {"frame": {"id":"frame_leg_right_01","equipped":true}, "armor": {"id":"wanzer_local_leg_right_001","equipped":true,"path":"res://resources/mech/parts/leg_right/wanzer_local_001.tres","slot":"leg_right"}},
	}

	pm.refresh_from_loadout(loadout)
	print("[TestWanzerFit] Equipped wanzer_local_001 v3 via refresh_from_loadout")
