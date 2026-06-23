## Driftlock — Car Physics Tests
class_name GdUnitCarPhysicsTest
extends GdUnitTestSuite

const ACCELERATE := 0
const SPINNING := 1

var _car: Node = null
var _runner = null


func before_test() -> void:
	if Engine.has_singleton("GameState"):
		GameState.physics_params = preload("res://resources/physics_params.gd").new()
	_runner = scene_runner("res://scenes/car.tscn")
	_car = _runner.scene()
	_car.set("_accept_keyboard_input", false)


func after_test() -> void:
	_car = null
	_runner = null


# ── Helpers ──────────────────────────────────────────────────────────────────

func _st() -> int:
	return _car.get("car_state") if _car else -1

func _sp() -> float:
	return _car.get("current_speed") if _car else -1.0

func _rot() -> float:
	return _car.global_rotation if _car else 0.0

func _pos() -> Vector2:
	return _car.global_position if _car else Vector2.ZERO

func _p(name: String, default = null):
	return _car.P().get(name) if _car and _car.has_method("P") and _car.P() else default

func _setp(name: String, val) -> void:
	var p = _car.P()
	if p: p.set(name, val)

func _start() -> void:
	if _car and _car.has_method("start_race"):
		_car.start_race()

func _press(j: bool, l: bool) -> void:
	if _car and _car.has_method("set_test_input"):
		_car.set_test_input(j, l)

# ── Tests ────────────────────────────────────────────────────────────────────

func test_starts_in_accelerate() -> void:
	assert_int(_st()).is_equal(ACCELERATE)

func test_start_race_sets_speed() -> void:
	_start()
	await _runner.simulate_frames(2)
	assert_float(_sp()).is_greater(0.0)

func test_j_press_enters_spin() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(SPINNING)

func test_l_press_enters_spin() -> void:
	_start()
	await _runner.simulate_frames(5)
	var rot_before := _rot()
	_press(false, true)
	await _runner.simulate_frames(5)
	assert_bool(_st() == SPINNING or abs(_rot() - rot_before) > 0.01).is_true()

func test_spin_slows_car() -> void:
	_start()
	await _runner.simulate_frames(5)
	var before: float = _sp()
	_press(true, false)
	await _runner.simulate_frames(20)
	assert_float(_sp()).is_less(before)

func test_release_from_spin_returns_to_accelerate() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, false)
	await _runner.simulate_frames(15)
	_press(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)

func test_spin_changes_rotation() -> void:
	_start()
	await _runner.simulate_frames(5)
	var before := _rot()
	_press(true, false)
	await _runner.simulate_frames(20)
	_press(false, false)
	await _runner.simulate_frames(3)
	assert_float(abs(_rot() - before)).is_greater(0.5)

func test_j_and_l_together_is_no_spin() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, true)
	await _runner.simulate_frames(5)
	assert_int(_st()).is_equal(ACCELERATE)

func test_spin_state_flow() -> void:
	_start()
	await _runner.simulate_frames(5)
	assert_int(_st()).is_equal(ACCELERATE)
	_press(true, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(SPINNING)
	await _runner.simulate_frames(15)
	_press(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)
	assert_float(_sp()).is_greater(0.0)

func test_state_transition_on_start() -> void:
	_start()
	assert_int(_st()).is_equal(ACCELERATE)

func test_state_transition_on_spin() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(SPINNING)

func test_state_transition_on_release() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, false)
	await _runner.simulate_frames(10)
	_press(false, false)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)

func test_reset_returns_to_accelerate() -> void:
	_start()
	await _runner.simulate_frames(10)
	if _car and _car.has_method("reset"):
		_car.reset(Vector2.ZERO, 0.0)
	await _runner.simulate_frames(3)
	assert_int(_st()).is_equal(ACCELERATE)
	var sp: float = _sp()
	assert_bool(sp < 10.0).is_true()

func test_long_runtime_no_crash() -> void:
	_start()
	await _runner.simulate_frames(600)
	var v: Vector2 = _car.get("velocity")
	assert_bool(is_nan(v.x) == false).is_true()
	assert_bool(is_nan(v.y) == false).is_true()
