## STOPPED state — car waits for Space / test_input_accelerate.
extends CarState

func physics_update(delta: float) -> void:
	if car._input_locked:
		return

	# Check for Space or test accelerate signal.
	var wants_go := false
	if car._accept_keyboard_input:
		wants_go = Input.is_key_pressed(KEY_SPACE) and not car._input_locked
	else:
		wants_go = car._test_input_accelerate and not car._input_locked

	if wants_go:
		var p = car.P()
		var initial: float = car._g(p, "initial_speed", 100.0)
		car.velocity = Vector2.RIGHT.rotated(car.global_rotation) * initial
		finished.emit("AccelerateState", {})
