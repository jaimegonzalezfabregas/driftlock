## ACCELERATE state — engine pushes forward with gentle steering.
## Tapping A/D applies gentle steering (nudge). Holding A/D enters SpinState
## for a full drift.
extends CarState

const STEER_RATE := 2.5          # rad/s for gentle steering taps
const SPIN_HOLD_TIME := 0.12     # seconds of held steer before spin triggers
const SPIN_HOLD_FRAME_GUARD := 6 # frames of hold before counting (avoids
                                 # immediate spin from held key on entry)

var _steer_hold_time: float = 0.0
var _steer_hold_frames: int = 0


func enter(_previous_state_path: String, _data := {}) -> void:
	car.accelerate_timer = 0.0
	car._combo_timer = car.COMBO_GRACE_PERIOD
	if car._spin_dust:
		car._spin_dust.emitting = false
	_steer_hold_time = 0.0
	_steer_hold_frames = 0


func physics_update(delta: float) -> void:
	var p = car.P()
	var forward := Vector2.RIGHT.rotated(car.global_rotation)

	# Only apply engine power when accelerate is pressed.
	var wants_accel := false
	if car._accept_keyboard_input:
		wants_accel = Input.is_key_pressed(KEY_SPACE) and not car._input_locked
	else:
		wants_accel = car._test_input_accelerate and not car._input_locked

	if wants_accel:
		var power = car._g(p, "engine_power", 20_000_000.0)
		var mass = car._g(p, "car_mass", 1000.0)
		var max_fwd_accel := 600.0

		var fwd_speed = forward.dot(car.velocity)
		var speed = abs(fwd_speed)
		var accel = power / (mass * maxf(speed, 1.0))
		accel = minf(accel, max_fwd_accel)
		car.velocity += forward * accel * delta

	# Floor: never drop below min forward speed
	var fwd_speed = forward.dot(car.velocity)
	var min_speed = car._g(p, "min_linear_speed", 10.0)
	if fwd_speed < min_speed:
		car.velocity += forward * (min_speed - fwd_speed)

	car.accelerate_timer += delta

	# Handle steering: taps → gentle nudge, sustained → spin
	_handle_steering(delta)


func _handle_steering(delta: float) -> void:
	var steer_dir := _get_steer_input()
	if steer_dir != 0 and car._stuck_recovery_timer <= 0.0:
		_steer_hold_frames += 1
		if _steer_hold_frames > SPIN_HOLD_FRAME_GUARD:
			_steer_hold_time += delta
		# Gentle steering: small rotation per frame
		car.global_rotation += steer_dir * STEER_RATE * delta
		# If held long enough, enter full spin
		if _steer_hold_time >= SPIN_HOLD_TIME:
			finished.emit("SpinState", {"direction": steer_dir})
	else:
		_steer_hold_time = 0.0
		_steer_hold_frames = 0


func _get_steer_input() -> int:
	var j: bool
	var l: bool

	if car._accept_keyboard_input:
		j = Input.is_key_pressed(KEY_A) and not car._input_locked
		l = Input.is_key_pressed(KEY_D) and not car._input_locked
	else:
		j = car._test_input_left and not car._input_locked
		l = car._test_input_right and not car._input_locked

	if j and not l:
		return -1
	elif l and not j:
		return 1
	return 0
