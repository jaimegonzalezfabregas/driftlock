extends CharacterBody2D

enum State { ACCELERATE, SPINNING }

var car_state: State = State.ACCELERATE
var spin_direction: int = 0
var spin_angular_velocity: float = 0.0   # rad/s
var spin_timer: float = 0.0              # seconds spent in current spin
var current_speed: float = 0.0

var _test_input_left: bool = false
var _test_input_right: bool = false
var _accept_keyboard_input: bool = true
var _PP = preload("res://resources/physics_params.gd")
var _local_params: Resource = null

signal state_changed(new_state: State)
signal wall_hit()


func _g(p: Resource, key: String, default = null):
	if p == null:
		return default
	var v = p.get(key)
	return v if v != null else default


func _ready() -> void:
	_ensure_params()
	_sync_keyboard_flag()


func _ensure_params() -> void:
	var gs = _singleton()
	if gs != null:
		if gs.get("physics_params") == null:
			gs.set("physics_params", _PP.new())
	else:
		if _local_params == null:
			_local_params = _PP.new()


func _sync_keyboard_flag() -> void:
	var gs = _singleton()
	if gs != null:
		_accept_keyboard_input = gs.get("accept_keyboard_input")


## Safe GameState singleton accessor — returns null if not registered.
## Not declared with a concrete type to avoid compile-time resolution
## of the GameState autoload in test environments.
static func _singleton():
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	return null


func P() -> Resource:
	var gs = _singleton()
	if gs != null:
		if gs.get("physics_params") == null:
			gs.set("physics_params", _PP.new())
		return gs.get("physics_params")
	if _local_params == null:
		_local_params = _PP.new()
	return _local_params


func _physics_process(delta: float) -> void:
	var p = P()
	if p == null:
		return

	_handle_input()

	match car_state:
		State.ACCELERATE:
			_accelerate(delta, p)
		State.SPINNING:
			_spin(delta, p)

	move_and_slide()
	current_speed = velocity.length()

	if get_last_slide_collision():
		var col := get_last_slide_collision()
		if col.get_collider() is StaticBody2D:
			if _g(p, "wall_bounce", false):
				var rest = _g(p, "wall_bounce_restitution", 0.3)
				velocity = velocity.bounce(col.get_normal()) * rest
			else:
				emit_signal("wall_hit")

	queue_redraw()


func _handle_input() -> void:
	var j: bool
	var l: bool

	if _accept_keyboard_input:
		j = Input.is_key_pressed(KEY_A)
		l = Input.is_key_pressed(KEY_D)
	else:
		j = _test_input_left
		l = _test_input_right

	var wants_spin = (j or l) and not (j and l)

	if car_state == State.ACCELERATE:
		if wants_spin:
			spin_direction = -1 if j else 1
			spin_timer = 0.0
			spin_angular_velocity = _g(P(), "min_spin_rate", 0.5)
			car_state = State.SPINNING
			emit_signal("state_changed", State.SPINNING)
	elif car_state == State.SPINNING:
		var min_time = _g(P(), "spin_min_time", 1.0)
		if not wants_spin and spin_timer >= min_time:
			# Sideways grip on exit — kill lateral velocity, keep forward momentum.
			var fwd := Vector2.RIGHT.rotated(global_rotation)
			var fwd_speed = fwd.dot(velocity)
			velocity = fwd * fwd_speed
			car_state = State.ACCELERATE
			spin_direction = 0
			spin_angular_velocity = 0.0
			spin_timer = 0.0
			emit_signal("state_changed", State.ACCELERATE)


func _accelerate(delta: float, p: Resource) -> void:
	var forward := Vector2.RIGHT.rotated(global_rotation)
	var power = _g(p, "engine_power", 20_000_000.0)
	var mass = _g(p, "car_mass", 1000.0)

	# Power‑based acceleration: F = P / v,  a = F / m.
	# At speed v the forward acceleration is a = P / (m · v).
	# This naturally decreases as speed rises — doubling the speed halves
	# the acceleration.  Capped at `_max_fwd_accel` near standstill to
	# avoid P/0 and give a snappy launch.
	var _max_fwd_accel := 600.0
	var fwd_speed = forward.dot(velocity)
	var speed = abs(fwd_speed)
	var accel = power / (mass * maxf(speed, 1.0))
	accel = minf(accel, _max_fwd_accel)

	# Engine force always pushes forward — even if the car is rolling
	# backward, the engine fights it.
	var fwd_impulse = forward * accel * delta
	velocity += fwd_impulse

	# Floor: never drop below min forward speed while accelerating.
	# Recalculate forward speed after impulse.
	fwd_speed = forward.dot(velocity)
	var min_speed = _g(p, "min_linear_speed", 50.0)
	if fwd_speed < min_speed:
		velocity += forward * (min_speed - fwd_speed)


func _spin(delta: float, p: Resource) -> void:
	spin_timer += delta

	# Continuous linear‑to‑rotational energy transfer.
	_transfer_linear_to_rotational(delta, p)

	# Drag angular velocity (tire friction during spin).
	var drag = _g(p, "spin_drag", 0.97)
	spin_angular_velocity *= pow(drag, delta * 60.0)

	# Clamp to minimum spin rate (car keeps rotating even when nearly stopped).
	var min_rate = _g(p, "min_spin_rate", 0.5)
	if abs(spin_angular_velocity) < min_rate:
		spin_angular_velocity = sign(spin_angular_velocity) * min_rate

	# Apply rotation.
	global_rotation += spin_direction * spin_angular_velocity * delta

	# Uniform velocity drag during spin — equal in all directions.
	# The car drifts/slides equally in all directions while spinning so it
	# maintains a straight-line drift.  Sideways grip only engages on spin
	# exit (when the turn key is released) — see _handle_input().
	var vel_drag = _g(p, "spin_velocity_drag", 0.85)
	velocity *= pow(vel_drag, delta * 60.0)


## Each frame during a spin, convert a fraction of the car's linear
## kinetic energy into rotational kinetic energy.  `rotation_efficiency`
## is the fraction transferred each frame — linear energy gets depleted
## by that amount, so the car slows down.
func _transfer_linear_to_rotational(_delta: float, p: Resource) -> void:
	var efficiency = _g(p, "rotation_efficiency", 0.03)
	if efficiency <= 0.0:
		return

	var mass = _g(p, "car_mass", 1000.0)
	var I = _g(p, "angular_mass", 1500.0)    # moment of inertia

	var v = velocity.length()
	if v < 1.0:
		return   # too slow for meaningful transfer

	# Transfer a fraction of current linear KE to rotational KE.
	var E_lin = 0.5 * mass * v * v
	var E_transfer = E_lin * efficiency
	if E_transfer <= 0.0:
		return

	# Linear speed drops by the transferred energy.
	var E_lin_new = E_lin - E_transfer
	var v_new = sqrt(maxf(0.0, 2.0 * E_lin_new / mass))
	velocity = velocity.normalized() * v_new

	# Rotational speed increases by the transferred energy.
	var E_rot_current = 0.5 * I * spin_angular_velocity * spin_angular_velocity
	var E_rot_new = E_rot_current + E_transfer
	spin_angular_velocity = sqrt(2.0 * E_rot_new / I)


func start_race() -> void:
	car_state = State.ACCELERATE
	var p = P()
	var initial: float = _g(p, "initial_speed", 100.0)
	velocity = Vector2.RIGHT.rotated(global_rotation) * initial
	current_speed = initial
	emit_signal("state_changed", State.ACCELERATE)


func reset(pos: Vector2, rot: float) -> void:
	car_state = State.ACCELERATE
	spin_direction = 0
	spin_angular_velocity = 0.0
	spin_timer = 0.0
	velocity = Vector2.ZERO
	_test_input_left = false
	_test_input_right = false
	global_position = pos
	global_rotation = rot
	emit_signal("state_changed", State.ACCELERATE)


func set_test_input(left: bool, right: bool) -> void:
	_test_input_left = left
	_test_input_right = right


func _draw() -> void:
	var p = P()
	var dw = _g(p, "car_draw_width", 40.0) if p else 40.0
	var dh = _g(p, "car_draw_height", 24.0) if p else 24.0

	var rect := Rect2(-dw/2, -dh/2, dw, dh)
	draw_rect(rect, Color.WHITE)

	var tip = Vector2(dw/2 + 2, 0)
	var l = Vector2(dw/2 - 6, -dh/4)
	var r = Vector2(dw/2 - 6, dh/4)
	draw_colored_polygon(PackedVector2Array([tip, l, r]), Color(0.85, 0.85, 0.85))

	if car_state == State.SPINNING:
		draw_rect(rect, Color.RED, false, 2.0)
