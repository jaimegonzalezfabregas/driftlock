## Driftlock — Car Input Tests
class_name GdUnitKeyboardInputTest
extends GdUnitTestSuite

const ACCELERATE := 0
const SPINNING := 1

var _car: Node = null
var _runner = null


func before_test() -> void:
	_runner = scene_runner("res://scenes/car.tscn")
	_car = _runner.scene()
	_car.set("_accept_keyboard_input", false)


func after_test() -> void:
	_car = null
	_runner = null


# ── Helpers ──────────────────────────────────────────────────────────────────

func _st() -> int:
	return _car.get("car_state") if _car else -1

func _direction() -> int:
	return _car.get("spin_direction") if _car else 0

func _speed() -> float:
	return _car.get("current_speed") if _car else -1.0

func _start() -> void:
	if _car and _car.has_method("start_race"):
		_car.start_race()


# ── Tests ────────────────────────────────────────────────────────────────────

func test_j_press_triggers_spin_left() -> void:
	_start()
	await _runner.simulate_frames(10)
	assert_int(_st()).is_equal(ACCELERATE)

	_car.set_test_input(true, false)
	await _runner.simulate_frames(3)

	assert_int(_st()).is_equal(SPINNING)
	assert_int(_direction()).is_equal(-1)

	_car.set_test_input(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)


func test_l_press_triggers_spin_right() -> void:
	_start()
	await _runner.simulate_frames(10)
	assert_int(_st()).is_equal(ACCELERATE)

	_car.set_test_input(false, true)
	await _runner.simulate_frames(3)

	assert_int(_st()).is_equal(SPINNING)
	assert_int(_direction()).is_equal(1)

	_car.set_test_input(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)


func test_j_held_maintains_spin() -> void:
	_start()
	await _runner.simulate_frames(10)

	_car.set_test_input(true, false)
	await _runner.simulate_frames(15)

	assert_int(_st()).is_equal(SPINNING)

	_car.set_test_input(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)


func test_both_keys_ignored() -> void:
	_start()
	await _runner.simulate_frames(10)

	_car.set_test_input(true, true)
	await _runner.simulate_frames(5)

	# Both held = no spin
	assert_int(_st()).is_equal(ACCELERATE)

	_car.set_test_input(false, false)
	await _runner.simulate_frames(3)


func test_always_accelerate_by_default() -> void:
	# Before start_race the car is already ACCELERATE
	assert_int(_st()).is_equal(ACCELERATE)

	_car.set_test_input(true, false)
	await _runner.simulate_frames(5)
	assert_int(_st()).is_equal(SPINNING)

	_car.set_test_input(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)


func test_no_steer_when_keyboard_disabled_and_no_test_flags() -> void:
	_start()
	await _runner.simulate_frames(10)
	assert_int(_st()).is_equal(ACCELERATE)

	await _runner.simulate_frames(5)
	assert_int(_st()).is_equal(ACCELERATE)
