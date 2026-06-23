## Driftlock — Parameter Change Tests
class_name GdUnitParamsTest
extends GdUnitTestSuite

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

func _p(name: String, default = null):
	return _car.P().get(name) if _car and _car.has_method("P") and _car.P() else default

func _setp(name: String, val) -> void:
	var p = _car.P()
	if p: p.set(name, val)

func _sp() -> float:
	return _car.get("current_speed") if _car else -1.0

func _st() -> int:
	return _car.get("car_state") if _car else -1

func _press(j: bool, l: bool) -> void:
	if _car and _car.has_method("set_test_input"):
		_car.set_test_input(j, l)

func _start() -> void:
	if _car and _car.has_method("start_race"):
		_car.start_race()

func _check_speed_after_spin() -> float:
	"""Helper: start car, trigger spin, release, return speed."""
	_start()
	await _runner.simulate_frames(10)
	_press(true, false)
	await _runner.simulate_frames(15)
	_press(false, false)
	await _runner.simulate_frames(3)
	return _sp()


# ── Tests ────────────────────────────────────────────────────────────────────

func test_engine_power_affects_speed() -> void:
	var p = _car.P()
	assert_object(p).is_not_null()
	if not p:
		return

	p.set("engine_power", 5_000_000.0)
	_start()
	await _runner.simulate_frames(10)
	var speed_slow: float = _sp()

	_car.reset(Vector2.ZERO, 0.0)
	await _runner.simulate_frames(2)
	p.set("engine_power", 50_000_000.0)
	_start()
	await _runner.simulate_frames(10)
	var speed_fast: float = _sp()

	assert_float(speed_fast).is_greater(speed_slow)


func test_car_mass_affects_speed() -> void:
	var p = _car.P()
	assert_object(p).is_not_null()
	if not p:
		return

	p.set("car_mass", 2000.0)
	_start()
	await _runner.simulate_frames(10)
	var speed_heavy: float = _sp()

	_car.reset(Vector2.ZERO, 0.0)
	await _runner.simulate_frames(2)
	p.set("car_mass", 500.0)
	_start()
	await _runner.simulate_frames(10)
	var speed_light: float = _sp()

	assert_float(speed_light).is_greater(speed_heavy)


# ── NOTE: `spin_drag` no longer affects linear speed — it drags the
# angular velocity only.  A future test should verify that higher
# spin_drag produces lower accumulated rotation over the same interval.


# ── NOTE: `spin_speed_multiplier` removed — spin is now driven by
# kinetic‑energy transfer (linear KE → rotational KE) with the transfer
# controlled by rotation_efficiency in _transfer_linear_to_rotational().
# A future test should verify that higher engine_power / lighter mass
# produces faster spins (more KE available for conversion).


func test_collision_shape_in_scene() -> void:
	await _runner.simulate_frames(1)

	var found := false
	for child in _car.get_children():
		if child is CollisionShape2D:
			found = true
			var shape: RectangleShape2D = child.shape
			assert_object(shape).is_not_null()
			if shape:
				assert_float(shape.size.x).is_greater(0.0)
				assert_float(shape.size.y).is_greater(0.0)
			break
	assert_bool(found).is_true()


func test_wall_bounce_param_access() -> void:
	var p = _car.P()
	assert_object(p).is_not_null()
	if not p:
		return

	p.set("wall_bounce", true)
	p.set("wall_bounce_restitution", 0.5)
	assert_bool(p.get("wall_bounce")).is_true()
	assert_float(p.get("wall_bounce_restitution")).is_equal_approx(0.5, 0.001)


func test_initial_speed_starts_car() -> void:
	_start()
	await _runner.simulate_frames(3)
	assert_float(_sp()).is_greater(0.0)
