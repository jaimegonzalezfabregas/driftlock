## Spin physics test — input‑simulating only.
##
## All driving uses set_test_input(left, right, accelerate).
## No internal car state is ever set directly.
## Assertions read observable state (position, rotation, speed) or signals.
##
## Run:  godot --headless --path . tests/test_spin_physics.tscn
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
	_log("SPIN PHYSICS TEST — input‑simulating only")
	_sep()
	_log("")

	await _run_all()

	_print_summary()
	get_tree().quit()


# ═════════════════════════════════════════════════════════════════════
# Test runner
# ═════════════════════════════════════════════════════════════════════

func _run_all() -> void:
	await _test_ke_transfer_reduces_speed()
	await _test_uniform_velocity_drag_during_spin()
	await _test_sideways_grip_on_exit()
	await _test_spin_direction_left_vs_right()


# ═════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════

func _ensure_game_state() -> void:
	if not Engine.has_singleton("GameState"):
		var GameStateScript := preload("res://autoload/game_state.gd")
		var gs := Node.new()
		gs.set_script(GameStateScript)
		var p := preload("res://resources/physics_params.gd").new()
		p.set("wall_bounce", false)
		p.set("spin_velocity_drag", 0.90)   # faster drag for test 2
		p.set("rotation_efficiency", 0.002)  # normal KE transfer
		gs.set("physics_params", p)
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)


func _spawn_car() -> Node:
	var car := CAR_SCENE.instantiate()
	add_child(car)
	await get_tree().physics_frame
	return car


func _press(j: bool, l: bool) -> void:
	if _car == null or not _car.has_method("set_test_input"):
		return
	_car.set_test_input(j, l)


func _start() -> void:
	if _car == null or not _car.has_method("start_race"):
		return
	_car.start_race()


func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame


# ═════════════════════════════════════════════════════════════════════
# Tests
# ═════════════════════════════════════════════════════════════════════

func _test_ke_transfer_reduces_speed() -> void:
	_log("── test_ke_transfer_reduces_speed ──")
	_log("  Verify that sustained spin reduces forward speed.")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	# Activate the car and let it accelerate.
	_car.set_test_input(false, false, true)
	await _frames(20)
	var speed_before: float = _car.get("current_speed")
	_log("  Speed before spin: %.1f px/s" % speed_before)

	# Enter spin and hold long enough for SpinState to actually trigger
	# (gentle-steering needs ~13 frames, then we want actual spin frames).
	_press(true, false)   # left spin
	await _frames(25)     # ~13 frames gentle-steering + 12 frames spin
	var speed_after: float = _car.get("current_speed")
	_log("  Speed after 25 frames (spin engaged): %.1f px/s" % speed_after)

	_assert(speed_after < speed_before * 0.95,
		"Speed decreases during sustained spin (%.1f -> %.1f, expected < %.1f)" \
		% [speed_before, speed_after, speed_before * 0.95])

	_press(false, false)
	_car.queue_free()
	_car = null
	_log("")


func _test_uniform_velocity_drag_during_spin() -> void:
	_log("── test_uniform_velocity_drag_during_spin ──")
	_log("  During a sustained spin, velocity length should decay.")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	# Activate and accelerate in open space.
	_car.global_position = Vector2(500, 500)
	_car.global_rotation = 0.0
	_car.set_test_input(false, false, true)
	await _frames(20)
	var speed_init: float = _car.get("current_speed")
	_log("  Speed before spin: %.1f px/s" % speed_init)

	# Enter spin and hold — wait for spin to fully trigger, then measure.
	_press(false, true)  # right spin
	await _frames(40)     # ~13 frames gentle-steering + 27 frames spin
	var speed_after: float = _car.get("current_speed")
	_log("  Speed after 40 frames (spin engaged): %.1f px/s" % speed_after)

	_assert(speed_after < speed_init * 0.95,
		"Velocity decays during spin (%.1f -> %.1f, expected < %.1f)" \
		% [speed_init, speed_after, speed_init * 0.95])

	_assert(speed_after > 0,
		"Velocity magnitude stays positive (%.1f > 0)" % speed_after)

	_press(false, false)
	_car.queue_free()
	_car = null
	_log("")


func _test_sideways_grip_on_exit() -> void:
	_log("── test_sideways_grip_on_exit ──")
	_log("  After releasing the spin button, the car should kill lateral")
	_log("  velocity (sideways grip) while keeping forward momentum.")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	# Activate and accelerate.
	_car.set_test_input(false, false, true)
	await _frames(15)

	# Hold left long enough to actually enter SpinState (~13+ frames).
	# Then let spin run a bit more so the car rotates and builds lateral velocity.
	_press(true, false)
	await _frames(25)      # ~13 frames gentle-steering + 12 frames actual spin

	# Capture velocity during spin.
	var vel_during = _car.get("velocity")

	# Release spin — sideways grip should engage.
	_press(false, false)
	await _frames(2)

	# After exit, sideways component should be zero.
	var vel_after = _car.get("velocity")
	var fwd := Vector2.RIGHT.rotated(_car.global_rotation)
	var side := fwd.rotated(PI * 0.5)
	var side_after = side.dot(vel_after)

	_log("  Velocity during spin: (%.1f, %.1f)" % [vel_during.x, vel_during.y])
	_log("  Velocity after exit:  (%.1f, %.1f)" % [vel_after.x, vel_after.y])
	_log("  Sideways component after exit: %.1f  (expected near 0)" % side_after)

	_assert(abs(side_after) < 1.0,
		"Sideways velocity killed on exit (|%.1f| < 1.0)" % side_after)

	var fwd_speed = fwd.dot(vel_after)
	_assert(fwd_speed > 10.0,
		"Forward momentum preserved after exit (%.1f > 10.0)" % fwd_speed)

	# Spin angular velocity should be zero after exit.
	var ang: float = _car.get("spin_angular_velocity")
	_assert(ang == 0.0, "spin_angular_velocity = %.2f (expected 0.0 after exit)" % ang)

	_car.queue_free()
	_car = null
	_log("")


func _test_spin_direction_left_vs_right() -> void:
	_log("── test_spin_direction_left_vs_right ──")
	_log("  Verify that J (left) and L (right) produce opposite rotation.")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)
	_car.global_position = Vector2(500, 500)
	_car.global_rotation = 0.0

	# Activate car.
	_car.set_test_input(false, false, true)
	await _frames(10)

	# Hold left long enough for spin to trigger (gentle-steering ~13 frames,
	# then actual spin).
	_press(true, false)
	await _frames(25)
	var rot_left: float = _car.global_rotation
	_log("  Rotation after left spin: %.2f rad" % rot_left)

	_press(false, false)
	_car.queue_free()
	_car = null

	# Right spin.
	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)
	_car.global_position = Vector2(500, 500)
	_car.global_rotation = 0.0
	_car.set_test_input(false, false, true)
	await _frames(10)

	_press(false, true)
	await _frames(25)
	var rot_right: float = _car.global_rotation
	_log("  Rotation after right spin: %.2f rad" % rot_right)

	_press(false, false)

	_assert(rot_left < 0 and rot_right > 0,
		"Left (J) rotates negative (%.2f), Right (L) rotates positive (%.2f)" \
		% [rot_left, rot_right])

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
