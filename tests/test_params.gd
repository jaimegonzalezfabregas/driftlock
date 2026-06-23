## Parameter tests — car physics parameter validation.
##
## Run:  godot --headless --path . tests/test_params.tscn
extends Node2D

const CAR_SCENE := preload("res://scenes/car.tscn")

var _car: Node = null
var _assert_pass := 0
var _assert_fail := 0
var _entries: Array[String] = []


# ═════════════════════════════════════════════════════════════════════
# Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_ensure_game_state()
	_sep()
	_log("PARAMETER TESTS — car physics parameter validation")
	_sep()
	_log("")

	await _run_all()

	_print_summary()
	get_tree().quit()


# ═════════════════════════════════════════════════════════════════════
# Test runner
# ═════════════════════════════════════════════════════════════════════

func _run_all() -> void:
	await _test_engine_power_affects_speed()
	await _test_car_mass_affects_speed()
	await _test_collision_shape_in_scene()
	await _test_wall_bounce_param_access()
	await _test_initial_speed_starts_car()


# ═════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════

## Ensure GameState singleton exists with a fresh physics_params.
func _ensure_game_state() -> void:
	if not Engine.has_singleton("GameState"):
		var GameStateScript := preload("res://autoload/game_state.gd")
		var gs := Node.new()
		gs.set_script(GameStateScript)
		gs.set("physics_params", preload("res://resources/physics_params.gd").new())
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)

	# Ensure the singleton has a params resource.
	var gs = Engine.get_singleton("GameState")
	if gs.get("physics_params") == null:
		gs.set("physics_params", preload("res://resources/physics_params.gd").new())


## Spawn the car scene, add as child, wait for _ready.
func _spawn_car() -> Node:
	var car := CAR_SCENE.instantiate()
	add_child(car)
	await get_tree().physics_frame
	return car


## Convience: get car's physics params resource.
func _P() -> Resource:
	if _car == null or not _car.has_method("P"):
		return null
	return _car.P()


## Convenience: get current speed.
func _speed() -> float:
	if _car == null:
		return -1.0
	return _car.get("current_speed")


## Convenience: inject test input.
func _press(j: bool, l: bool) -> void:
	if _car == null or not _car.has_method("set_test_input"):
		return
	_car.set_test_input(j, l)


## Start the race (accelerate from standstill).
func _start() -> void:
	if _car == null or not _car.has_method("start_race"):
		return
	_car.start_race()


## Advance N physics frames.
func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


## Simulate entering a spin: start, accelerate, tap left, release.
func _enter_spin() -> void:
	_start()
	await _frames(10)
	_press(true, false)    # J (left)
	await _frames(15)
	_press(false, false)   # release
	await _frames(3)


# ═════════════════════════════════════════════════════════════════════
# Tests
# ═════════════════════════════════════════════════════════════════════

func _test_engine_power_affects_speed() -> void:
	_log("── test_engine_power_affects_speed ──")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	var p = _P()
	_assert(p != null, "physics_params resource accessible")

	# Low power
	if p != null:
		p.set("engine_power", 5_000_000.0)
	_start()
	await _frames(10)
	var speed_slow := _speed()
	_log("  Low power (5 MW): speed after 10 frames = %.1f" % speed_slow)

	# Reset, high power
	_car.reset(Vector2.ZERO, 0.0)
	await _frames(2)
	if p != null:
		p.set("engine_power", 50_000_000.0)
	_start()
	await _frames(10)
	var speed_fast := _speed()
	_log("  High power (50 MW): speed after 10 frames = %.1f" % speed_fast)

	_assert(speed_fast > speed_slow,
		"Higher engine power produces higher forward speed  (%.1f > %.1f)" % [speed_fast, speed_slow])

	_car.queue_free()
	_car = null
	_log("")


func _test_car_mass_affects_speed() -> void:
	_log("── test_car_mass_affects_speed ──")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	var p = _P()
	_assert(p != null, "physics_params resource accessible")

	# Heavy
	if p != null:
		p.set("car_mass", 2000.0)
		p.set("engine_power", 20_000_000.0)
	_start()
	await _frames(10)
	var speed_heavy := _speed()
	_log("  Heavy (2000 kg): speed after 10 frames = %.1f" % speed_heavy)

	# Reset, light
	_car.reset(Vector2.ZERO, 0.0)
	await _frames(2)
	if p != null:
		p.set("car_mass", 500.0)
	_start()
	await _frames(10)
	var speed_light := _speed()
	_log("  Light (500 kg): speed after 10 frames = %.1f" % speed_light)

	_assert(speed_light > speed_heavy,
		"Lighter car produces higher forward speed  (%.1f > %.1f)" % [speed_light, speed_heavy])

	_car.queue_free()
	_car = null
	_log("")


func _test_collision_shape_in_scene() -> void:
	_log("── test_collision_shape_in_scene ──")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	var found := false
	for child in _car.get_children():
		if child is CollisionShape2D:
			found = true
			var shape: RectangleShape2D = child.shape
			if shape != null:
				_assert(shape.size.x > 0.0,
					"CollisionShape2D RectangleShape2D size.x = %.1f > 0" % shape.size.x)
				_assert(shape.size.y > 0.0,
					"CollisionShape2D RectangleShape2D size.y = %.1f > 0" % shape.size.y)
			else:
				_assert(false, "CollisionShape2D has a non-null shape")
			break

	_assert(found, "Car has a CollisionShape2D child node")

	_car.queue_free()
	_car = null
	_log("")


func _test_wall_bounce_param_access() -> void:
	_log("── test_wall_bounce_param_access ──")

	var p := preload("res://resources/physics_params.gd").new()
	_assert(p != null, "Fresh physics_params resource instantiated")

	if p != null:
		p.set("wall_bounce", true)
		p.set("wall_bounce_restitution", 0.5)
		_assert(p.get("wall_bounce") == true,
			"wall_bounce = true  (got %s)" % str(p.get("wall_bounce")))
		_assert(abs(p.get("wall_bounce_restitution") - 0.5) < 0.001,
			"wall_bounce_restitution = 0.5  (got %s)" % str(p.get("wall_bounce_restitution")))

	_log("")


func _test_initial_speed_starts_car() -> void:
	_log("── test_initial_speed_starts_car ──")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	_start()
	await _frames(3)
	var sp := _speed()
	_assert(sp > 0.0,
		"Car speed after start_race + 3 frames = %.1f (expected > 0)" % sp)

	_car.queue_free()
	_car = null
	_log("")


# ═════════════════════════════════════════════════════════════════════
# Assertion helpers
# ═════════════════════════════════════════════════════════════════════

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_assert_pass += 1
	else:
		_assert_fail += 1
		_log("  FAIL: %s" % msg)


func _log(text: String) -> void:
	_entries.append(text)
	print(text)


func _sep() -> void:
	_log("=".repeat(60))


func _print_summary() -> void:
	_log("")
	_sep()
	_log("RESULTS")
	_sep()
	_log("Assertions: %d / %d passed" % [_assert_pass, _assert_pass + _assert_fail])
	if _assert_fail > 0:
		_log("%d ASSERTION(S) FAILED — review messages above" % _assert_fail)
	else:
		_log("ALL ASSERTIONS PASSED")
	_sep()
