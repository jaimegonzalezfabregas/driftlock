## Driftlock — Track Navigation Test
##
## Uses a simple AI seek-steering controller to navigate the car through
## the Path2D track in level_01.  Verifies the car can reach the goal area
## by pressing J/L at the right moments — the same input path a human player
## would use.
##
## AI strategy: compute angle error between car heading and direction to a
## look-ahead point on the curve.  When the error exceeds a threshold, apply
## a short timed spin-tap (3 frames ≈ 36° rotation) in the correct direction,
## then coast to let the boost carry the car forward.  This matches the human
## play pattern: tap, release (boost), coast, re-evaluate.
class_name GdUnitTrackNavigationTest
extends GdUnitTestSuite

var _level_runner = null
var _level = null
var _car = null
var _curve = null
var _won := false
var _lost := false


func before_test() -> void:
	_level_runner = scene_runner("res://scenes/levels/level_01.tscn")
	_level = _level_runner.scene()


func after_test() -> void:
	_car = null
	_curve = null
	_level = null
	_level_runner = null
	_won = false
	_lost = false


func test_drive_through_track_and_win() -> void:
	await _level_runner.simulate_frames(5)

	_car = _level.get_node("Car")
	_car.set("_accept_keyboard_input", false)

	var path_node: Node = _level.get_node("TrackPath")
	_curve = path_node.get("curve")
	var goal: Area2D = _level.get_node("GoalArea")

	assert_object(_car).is_not_null()
	assert_object(_curve).is_not_null()
	assert_object(goal).is_not_null()

	# Detect win / loss
	goal.body_entered.connect(func(_b: Node) -> void: _won = true, CONNECT_ONE_SHOT)
	_car.connect("wall_hit", func() -> void: _lost = true, CONNECT_ONE_SHOT)

	# Tap-timing AI: short fixed-duration spin taps followed by coast.
	# Each tap rotates the car by ~36° at 720°/s spin rate.
	const TAP_FRAMES: int = 1
	const COAST_FRAMES: int = 8
	const LOOK_AHEAD: float = 200.0
	const ANGLE_THRESHOLD: float = deg_to_rad(8.0)

	var tap_remaining := 0
	var coast_remaining := 0
	var prev_pos := Vector2.ZERO
	var stuck_frames := 0
	var last_frame: int = 0

	for _i in range(2000):
		last_frame = _i

		if _won or _lost:
			break

		if not is_instance_valid(_car):
			_lost = true
			break

		var car_pos: Vector2 = _car.global_position
		var car_rot: float = _car.global_rotation

		# Stuck detection
		if _i > 10 and car_pos.distance_to(prev_pos) < 1.0:
			stuck_frames += 1
		else:
			stuck_frames = 0
		prev_pos = car_pos

		if stuck_frames > 120:
			prints("NAV DEBUG — car stuck for 120+ frames at", car_pos)
			_lost = true
			break

		# Tap/coast state machine
		if coast_remaining > 0:
			coast_remaining -= 1
			_car.set_test_input(false, false)
		elif tap_remaining > 0:
			tap_remaining -= 1
			# Keep same steering direction (set when tap started)
		else:
			# Evaluate steering
			var offset: float = _curve.get_closest_offset(car_pos)
			var la: float = minf(offset + LOOK_AHEAD, _curve.get_baked_length())
			var target: Vector2 = _curve.sample_baked(la)

			var desired_angle: float = (target - car_pos).angle()
			var angle_err: float = wrapf(desired_angle - car_rot, -PI, PI)

			if angle_err > ANGLE_THRESHOLD:
				# Target is to the right (CW) → press L
				tap_remaining = TAP_FRAMES
				_car.set_test_input(false, true)
			elif angle_err < -ANGLE_THRESHOLD:
				# Target is to the left (CCW) → press J
				tap_remaining = TAP_FRAMES
				_car.set_test_input(true, false)
			else:
				# On course — release/coast (no input → boost forward)
				_car.set_test_input(false, false)
				coast_remaining = COAST_FRAMES

		await _level_runner.simulate_frames(1)

		# Off-track safety check
		if is_instance_valid(_car):
			var off_centre: Vector2 = _curve.sample_baked(_curve.get_closest_offset(car_pos))
			if car_pos.distance_to(off_centre) > 300.0:
				prints("NAV DEBUG — off track at frame", _i, "dist", car_pos.distance_to(off_centre))
				_lost = true
				break

	if _lost:
		var final_pos: Vector2 = _car.global_position if is_instance_valid(_car) else Vector2.ZERO
		prints("NAV FAILED — at frame", last_frame, "pos", final_pos)
		assert_bool(false).is_true()
	elif _won:
		pass  # success
	else:
		var diag_pos: Vector2 = _car.global_position if is_instance_valid(_car) else Vector2.ZERO
		var diag_off: float = _curve.get_closest_offset(diag_pos) if is_instance_valid(_car) else -1.0
		prints("NAV TIMEOUT — frame", 2000, "pos", diag_pos, "offset", diag_off, "baked_len", _curve.get_baked_length())
		assert_bool(false).is_true()
