## DriverAI — fair test driving agent
##
## A finite-state machine that drives the car using **only** the same
## three inputs a human player has:
##   set_test_input(left: bool, right: bool, accelerate: bool)
##
## Design for the FSM:
## - Gentle-steering (<14 frames): rotates the car at 2.5 rad/s
## - Sustained steer (>=14 frames): triggers SpinState (drift)
## - Spin detection: if rotation rate > threshold, the car is drifting
##   → release steer to exit spin with a speed boost
##
## Usage:
##   var ai = DriverAIScript.new()
##   ai.setup(car, track_path)
##   ai.process(delta)   # each frame
extends RefCounted

# ── States ─────────────────────────────────────────────────────────────
enum DriverState {
	START,
	COAST,       # Driving forward, checking angle
	TURN_LEFT,   # Gentle-steering left
	TURN_RIGHT,  # Gentle-steering right
	SPIN_OUT,    # Detected spin — releasing steer to exit
	RECOVERY,    # Stuck — coast briefly
}

var state: DriverState = DriverState.START

# ── Dependencies (set via setup()) ────────────────────────────────────
var _car: Node = null
var _track_path: Node = null
var _curve: Curve2D = null

# ── Internal state ────────────────────────────────────────────────────
var _coast_frames: int = 0
var _turn_frames: int = 0
var _stuck_frames: int = 0
var _spin_out_frames: int = 0
var _prev_pos: Vector2 = Vector2.ZERO
var _prev_rot: float = 0.0

# ── Tuning ────────────────────────────────────────────────────────────
## Normal steering — turn until angle is resolved.
## Spin detection is the safety net if turns trigger a drift.
const TURN_ANGLE_THRESHOLD: float = 0.2   # ~11°
const MIN_TURN_FRAMES: int = 2
const MAX_TURN_FRAMES: int = 40           # allow spin to trigger (~14 frames)
const COAST_COOLDOWN: int = 1

## Spin detection — if rotation rate exceeds gentle-steering max (~2.5 rad/s),
## the car is drifting. Release to exit spin.
const SPIN_ROT_THRESHOLD: float = 3.5    # rad/s
const SPIN_OUT_FRAMES: int = 20          # frames to coast after exiting spin

## Stuck detection
const STUCK_SPEED: float = 25.0
const STUCK_TIMEOUT: int = 60            # ~1s
const RECOVERY_FRAMES: int = 20

## Look-ahead
const LOOK_AHEAD: float = 120.0

var current_speed: float = 0.0


func setup(car: Node, track_path: Node) -> void:
	_car = car
	_track_path = track_path
	_curve = track_path.get("curve") if track_path else null
	reset()


func reset() -> void:
	state = DriverState.START
	_coast_frames = 0
	_turn_frames = 0
	_stuck_frames = 0
	_spin_out_frames = 0
	_prev_pos = Vector2.ZERO
	_prev_rot = 0.0
	current_speed = 0.0


func process(delta: float) -> void:
	if _car == null:
		return

	var pos: Vector2 = _car.get("global_position")
	var rot: float = _car.get("global_rotation")
	var speed: float = _car.get("current_speed")
	current_speed = speed if typeof(speed) == TYPE_FLOAT else 0.0

	# ── Stuck detection ────────────────────────────────────────
	var moved := (pos - _prev_pos).length()
	if moved < STUCK_SPEED * delta and current_speed < STUCK_SPEED:
		_stuck_frames += 1
	else:
		_stuck_frames = maxi(0, _stuck_frames - 2)
	_prev_pos = pos

	if _stuck_frames >= STUCK_TIMEOUT:
		state = DriverState.RECOVERY
		_stuck_frames = 0
		_turn_frames = 0
		_spin_out_frames = 0
		_car.set_test_input(false, false, true)
		return

	# ── Spin detection ──────────────────────────────────────────
	# If the car rotates faster than gentle-steering allows, it's drifting.
	var rot_rate: float = abs(rot - _prev_rot) / maxf(delta, 0.001)
	_prev_rot = rot

	if rot_rate > SPIN_ROT_THRESHOLD and current_speed > 50.0:
		state = DriverState.SPIN_OUT
		_spin_out_frames = 0
		_turn_frames = 0
		# Fall through — let SPIN_OUT handle this frame

	# ── Pure-pursuit look-ahead ────────────────────────────────
	var angle_to_target := 0.0
	if _curve != null:
		var local_pos: Vector2 = _track_path.to_local(pos)
		var total_length: float = _curve.get_baked_length()
		var nearest_ofs: float = _curve.get_closest_offset(local_pos)
		var ahead_ofs: float = nearest_ofs + LOOK_AHEAD
		if ahead_ofs > total_length:
			ahead_ofs = fmod(ahead_ofs, total_length)
		var ahead_xf: Transform2D = _curve.sample_baked_with_rotation(ahead_ofs)
		var ahead_global: Vector2 = _track_path.to_global(ahead_xf.origin)
		var forward: Vector2 = Vector2.RIGHT.rotated(rot)
		var to_target: Vector2 = (ahead_global - pos).normalized()
		angle_to_target = forward.angle_to(to_target)

	# ── State machine ─────────────────────────────────────────
	match state:
		DriverState.START:
			_car.set_test_input(false, false, true)
			if current_speed > 0.0:
				state = DriverState.COAST
				_coast_frames = 0

		DriverState.COAST:
			_car.set_test_input(false, false, true)
			_coast_frames += 1

			if _coast_frames >= COAST_COOLDOWN:
				if angle_to_target > TURN_ANGLE_THRESHOLD:
					state = DriverState.TURN_LEFT
					_turn_frames = 0
				elif angle_to_target < -TURN_ANGLE_THRESHOLD:
					state = DriverState.TURN_RIGHT
					_turn_frames = 0

		DriverState.TURN_LEFT:
			_turn_frames += 1
			_car.set_test_input(true, false, true)

			if current_speed < STUCK_SPEED and _turn_frames > MIN_TURN_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
			elif _turn_frames >= MAX_TURN_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
			elif _turn_frames >= MIN_TURN_FRAMES and abs(angle_to_target) < TURN_ANGLE_THRESHOLD:
				state = DriverState.COAST
				_coast_frames = 0

		DriverState.TURN_RIGHT:
			_turn_frames += 1
			_car.set_test_input(false, true, true)

			if current_speed < STUCK_SPEED and _turn_frames > MIN_TURN_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
			elif _turn_frames >= MAX_TURN_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
			elif _turn_frames >= MIN_TURN_FRAMES and abs(angle_to_target) < TURN_ANGLE_THRESHOLD:
				state = DriverState.COAST
				_coast_frames = 0

		DriverState.SPIN_OUT:
			_spin_out_frames += 1
			# Release steer — exit spin naturally, boost forward.
			_car.set_test_input(false, false, true)

			if _spin_out_frames >= SPIN_OUT_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
				_turn_frames = 0
				_spin_out_frames = 0

		DriverState.RECOVERY:
			_turn_frames += 1
			_car.set_test_input(false, false, true)
			if _turn_frames >= RECOVERY_FRAMES:
				state = DriverState.COAST
				_coast_frames = 0
				_turn_frames = 0
				_stuck_frames = 0
