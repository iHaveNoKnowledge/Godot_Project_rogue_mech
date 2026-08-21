extends Node

## Verifies:
## 1. SphynxMotionBlurToolkit addon presence and loading
## 2. MotionBlurCompositor initialization with PreBlurProcessor and GuertinMotionBlur / SimpleJumpFlood
## 3. Attachment to Camera3D compositor property in Godot 4.6

var _checks := 0
var _fails := 0

func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("MOTION_BLUR_OK: " + label)
	else:
		_fails += 1
		printerr("MOTION_BLUR_FAIL: " + label)

func _ready() -> void:
	print("--- 1. Testing Addon Classes ---")
	var mb_comp_class = preload("res://addons/SphynxMotionBlurToolkit/BaseClasses/mb_compositor.gd")
	_check(mb_comp_class != null, "MotionBlurCompositor script loaded")

	var pre_proc_class = preload("res://addons/SphynxMotionBlurToolkit/PreBlurProcessing/pre_blur_processor.gd")
	_check(pre_proc_class != null, "PreBlurProcessor script loaded")

	var guertin_class = preload("res://addons/SphynxMotionBlurToolkit/Guertin/guertin_motion_blur.gd")
	_check(guertin_class != null, "GuertinMotionBlur script loaded")

	var jf_class = preload("res://addons/SphynxMotionBlurToolkit/JumpFlood/simple_jf_motion_blur.gd")
	_check(jf_class != null, "SimpleJumpFloodMotionBlur script loaded")

	print("--- 2. Testing Compositor Assembly ---")
	var compositor: Compositor = mb_comp_class.new()
	var pre_proc = pre_proc_class.new()
	var guertin = guertin_class.new()

	var effects: Array[CompositorEffect] = [pre_proc, guertin]
	compositor.compositor_effects = effects
	_check(compositor.compositor_effects.size() == 2, "MotionBlurCompositor configured with 2 effect stages")

	print("--- 3. Testing Camera Attachment ---")
	var cam := Camera3D.new()
	cam.compositor = compositor
	add_child(cam)
	_check(cam.compositor == compositor, "Camera3D accepted MotionBlurCompositor")

	print("--- 4. Testing Pre-configured Resource ---")
	var loaded_res = load("res://resources/rendering/motion_blur_compositor.tres")
	_check(loaded_res != null, "motion_blur_compositor.tres loaded successfully")
	_check(loaded_res is Compositor, "loaded resource is a Compositor")
	_check(loaded_res.compositor_effects.size() == 2, "loaded resource has 2 compositor effects")

	await get_tree().process_frame
	await get_tree().physics_frame

	print("==================================================")
	print("MOTION_BLUR_VERIFY COMPLETED:")
	print("Checks: %d | Fails: %d" % [_checks, _fails])
	print("==================================================")

	get_tree().quit(1 if _fails > 0 else 0)
