## SPIN state — car rotates, converts linear KE to rotational, exits on input release.
extends CarState


func enter(_previous_state_path: String, data := {}) -> void:
	# Combo: chain if grace timer still running.
	if car._combo_timer > 0.0 and car._combo_count > 0:
		car._combo_count = min(car._combo_count + 1, car.COMBO_MAX)
	else:
		car._combo_count = 1
	car._combo_timer = 0.0
	car.combo_changed.emit(car._combo_count)

	car.spin_direction = data.get("direction", -1)
	car.spin_timer = 0.0
	car._accumulated_spin_rotation = 0.0
	var p = car.P()
	car.spin_angular_velocity = car._g(p, "min_spin_rate", 0.5)
	car._spin_stuck_timer = 0.0


func physics_update(delta: float) -> void:
	var p = car.P()
	car.spin_timer += delta

	# Continuous linear‑to‑rotational energy transfer
	_transfer_linear_to_rotational(delta, p)

	# Drag angular velocity
	var drag = car._g(p, "spin_drag", 0.97)
	car.spin_angular_velocity *= pow(drag, delta * 60.0)

	# Clamp to minimum spin rate
	var min_rate = car._g(p, "min_spin_rate", 0.5)
	if abs(car.spin_angular_velocity) < min_rate:
		car.spin_angular_velocity = sign(car.spin_angular_velocity) * min_rate

	# Apply rotation
	car.global_rotation += car.spin_direction * car.spin_angular_velocity * delta
	car._accumulated_spin_rotation += abs(car.spin_angular_velocity) * delta

	# Uniform velocity drag during spin
	var vel_drag = car._g(p, "spin_velocity_drag", 0.85)
	car.velocity *= pow(vel_drag, delta * 60.0)

	# Stuck safety net
	if car.velocity.length() < car.SPIN_STUCK_SPEED:
		car._spin_stuck_timer += delta
		if car._spin_stuck_timer >= car.SPIN_STUCK_TIMEOUT:
			_force_exit_spin(delta)
			return
	else:
		car._spin_stuck_timer = maxf(0.0, car._spin_stuck_timer - delta * 2.0)

	if car._spin_dust:
		car._spin_dust.emitting = true

	# Check for spin input release
	if _get_spin_released():
		_exit_spin()


func exit() -> void:
	if car._spin_dust:
		car._spin_dust.emitting = false
	car.spin_direction = 0
	car.spin_angular_velocity = 0.0
	car.spin_timer = 0.0
	car._accumulated_spin_rotation = 0.0
	car._spin_stuck_timer = 0.0


func _get_spin_released() -> bool:
	var j: bool
	var l: bool

	if car._accept_keyboard_input:
		j = Input.is_key_pressed(KEY_A)
		l = Input.is_key_pressed(KEY_D)
	else:
		j = car._test_input_left
		l = car._test_input_right

	return not (j or l)


func _transfer_linear_to_rotational(_delta: float, p: Resource) -> void:
	var efficiency = car._g(p, "rotation_efficiency", 0.03)
	if efficiency <= 0.0:
		return

	var mass = car._g(p, "car_mass", 1000.0)
	var I = car._g(p, "angular_mass", 1500.0)

	var v = car.velocity.length()
	if v < 1.0:
		return

	var E_lin = 0.5 * mass * v * v
	var E_transfer = E_lin * efficiency
	if E_transfer <= 0.0:
		return

	var E_lin_new = E_lin - E_transfer
	var v_new = sqrt(maxf(0.0, 2.0 * E_lin_new / mass))
	car.velocity = car.velocity.normalized() * v_new

	var E_rot_current = 0.5 * I * car.spin_angular_velocity * car.spin_angular_velocity
	var E_rot_new = E_rot_current + E_transfer
	car.spin_angular_velocity = sqrt(2.0 * E_rot_new / I)


func _exit_spin() -> void:
	# Sideways grip on exit
	var fwd := Vector2.RIGHT.rotated(car.global_rotation)
	var fwd_speed = fwd.dot(car.velocity)
	car.velocity = fwd * fwd_speed

	# Spin boost
	var p = car.P()
	var boost_mult = car._g(p, "spin_boost_multiplier", 3.0)
	var boost_cap = car._g(p, "spin_boost_cap", 600.0)
	var boost = minf(car.spin_angular_velocity * boost_mult, boost_cap)

	# Combo multiplier
	if boost > 0.0 and car._combo_count > 1:
		var combo_factor := 1.0 + float(car._combo_count - 1) * car.COMBO_BOOST_PER_STEP
		combo_factor = minf(combo_factor, 3.0)
		boost *= combo_factor

	if boost > 0.0:
		car.velocity += fwd * boost
		car._last_boost = boost
		car._boost_flash_timer = 0.2
		car.boost_applied.emit(boost)
		if car._boost_trail:
			car._boost_trail.emitting = true

	finished.emit("AccelerateState")


func _force_exit_spin(delta: float) -> void:
	var fwd := Vector2.RIGHT.rotated(car.global_rotation)
	car.velocity = fwd * 60.0
	car._stuck_recovery_timer = 0.5
	if car._spin_dust:
		car._spin_dust.emitting = false
	finished.emit("AccelerateState")
