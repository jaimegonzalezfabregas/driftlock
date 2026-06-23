extends SceneTree

var _frames := 0

func _init() -> void:
	print("_init called")

func _process(delta: float) -> bool:
	_frames += 1
	print("Frame ", _frames)
	if _frames >= 5:
		print("=== Done ===")
		quit()
	return true
