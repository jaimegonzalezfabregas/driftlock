## Driftlock — Gameplay Smoke Tests
class_name GdUnitGameplayTest
extends GdUnitTestSuite

const ACCELERATE := 1
const SPINNING := 2

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

func _pos() -> Vector2:
	return _car.global_position if _car else Vector2.ZERO

func _rot() -> float:
	return _car.global_rotation if _car else 0.0

func _press(j: bool, l: bool) -> void:
	if _car and _car.has_method("set_test_input"):
		_car.set_test_input(j, l)

func _start() -> void:
	if _car and _car.has_method("start_race"):
		_car.start_race()


# ── Tests ────────────────────────────────────────────────────────────────────

func test_full_drive_forward() -> void:
	_start()
	await _runner.simulate_frames(60)
	assert_float(_pos().x).is_greater(50.0)


func test_spin_left_then_right() -> void:
	_start()
	await _runner.simulate_frames(5)
	_press(true, false)
	await _runner.simulate_frames(30)
	_press(false, false)
	await _runner.simulate_frames(3)
	var rot_left := _rot()

	_car.reset(Vector2.ZERO, 0.0)
	_start()
	await _runner.simulate_frames(5)
	_press(false, true)
	await _runner.simulate_frames(30)
	_press(false, false)
	await _runner.simulate_frames(3)
	var rot_right := _rot()

	assert_float(rot_left).is_less(-0.5)
	assert_bool(rot_right > 0.0).is_true()


func test_rapid_tapping_no_crash() -> void:
	_start()
	await _runner.simulate_frames(5)
	for _i in 10:
		_press(true, false)
		await _runner.simulate_frames(3)
		_press(false, false)
		await _runner.simulate_frames(3)
	assert_float(_sp()).is_greater(0.0)


func test_long_runtime_stable() -> void:
	_start()
	await _runner.simulate_frames(300)
	var v: Vector2 = _car.get("velocity")
	assert_bool(is_nan(v.x) == false).is_true()
	assert_bool(is_nan(v.y) == false).is_true()
	assert_bool(v.length() < 10000.0).is_true()


func test_multiple_spin_cycles() -> void:
	_start()
	await _runner.simulate_frames(5)
	for _i in 5:
		_press(true, false)
		await _runner.simulate_frames(15)
		_press(false, false)
		await _runner.simulate_frames(10)
	assert_float(_sp()).is_greater(0.0)
	assert_bool(_st() == ACCELERATE or _st() == SPINNING).is_true()
