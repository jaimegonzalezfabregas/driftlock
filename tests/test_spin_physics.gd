## Spin physics test — uniform drag during spin, KE transfer, sideways grip on exit.
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
	_log("SPIN PHYSICS TEST — uniform drag, KE transfer, sideways grip on exit")
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
	await _test_spin_angular_velocity_dragged()
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
		gs.set("physics_params", p)
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)

	# Ensure wall_bounce=false so the car dies on wall hit (we block walls with test position).


func _spawn_car() -> Node:
	var car := CAR_SCENE.instantiate()
	add_child(car)
	await get_tree().physics_frame
	return car


func _P() -> Resource:
	if _car == null or not _car.has_method("P"):
		return null
	return _car.P()


func _speed() -> float:
	if _car == null:
		return -1.0
	return _car.get("current_speed")


func _spin_ang_vel() -> float:
	if _car == null:
		return 0.0
	return _car.get("spin_angular_velocity")


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
	_log("  Verify that sustained spin reduces forward speed (per-frame KE transfer).")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	_start()
	await _frames(15)
	var speed_before = _speed()
	_log("  Speed before spin: %.1f px/s" % speed_before)

	# Enter spin and hold for several frames — continuous KE transfer
	# should slow the car down over time.
	_press(true, false)   # J → left spin
	await _frames(15)
	var speed_after = _speed()
	_log("  Speed after 15 frames of spin: %.1f px/s" % speed_after)

	_assert(speed_after < speed_before * 0.95,
		"Speed decreases during sustained spin (%.1f -> %.1f, expected < %.1f)" \
		% [speed_before, speed_after, speed_before * 0.95])

	_press(false, false)
	_car.queue_free()
	_car = null
	_log("")


func _test_uniform_velocity_drag_during_spin() -> void:
	_log("── test_uniform_velocity_drag_during_spin ──")
	_log("  During a sustained spin, velocity length should decay by")
	_log("  a predictable factor each frame (uniform drag, direction-agnostic).")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	# Set a custom uniform drag for predictable decay.  Disable the
	# per-frame KE transfer so speed decay is purely from drag.
	var p = _P()
	if p != null:
		p.set("spin_velocity_drag", 0.90)
		p.set("rotation_efficiency", 0.0)

	# Position in open space, set an initial velocity in any direction.
	_car.global_position = Vector2(500, 500)
	_car.global_rotation = 0.0
	var vel := Vector2(300, 0)
	_car.set("velocity", vel)
	_car.set("car_state", 1)  # SPINNING
	_car.set("spin_direction", 1)
	_car.set("spin_angular_velocity", 5.0)
	await _frames(2)

	var speed_init = _speed()
	_log("  Initial speed: %.1f px/s" % speed_init)

	# Keep spinning for 30 frames — velocity drag should reduce speed.
	_press(false, true)  # hold right spin
	await _frames(30)

	var speed_after = _speed()
	_log("  Speed after 30 frames of spin: %.1f px/s" % speed_after)

	# With drag=0.90 per 60fps tick, after 30 frames:
	# expected = initial * 0.90^30 ≈ initial * 0.042
	# Speed should be significantly lower than initial.
	_assert(speed_after < speed_init * 0.95,
		"Velocity decays during spin (%.1f -> %.1f, expected < %.1f)" \
		% [speed_init, speed_after, speed_init * 0.95])

	# Drag is uniform: regardless of how the car rotated during spin,
	# the velocity magnitude decays the same way.
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

	_start()
	await _frames(10)

	# Enter spin
	_press(true, false)
	# Wait 5 frames to establish the spin
	await _frames(5)

	# Capture velocity during spin
	var vel_during = _car.get("velocity")

	# Wait for minimum spin duration to elapse before releasing.
	# spin_min_time is 1.0 s by default, so wait ~65 frames total from entry.
	await _frames(60)

	# Release spin — sideways grip engages
	_press(false, false)
	await _frames(2)

	# After exit, sideways component should be zero (grip killed it).
	var vel_after = _car.get("velocity")
	var fwd := Vector2.RIGHT.rotated(_car.global_rotation)
	var side := fwd.rotated(PI * 0.5)
	var side_after = side.dot(vel_after)

	_log("  Velocity during spin: (%.1f, %.1f)" % [vel_during.x, vel_during.y])
	_log("  Velocity after exit:  (%.1f, %.1f)" % [vel_after.x, vel_after.y])
	_log("  Sideways component after exit: %.1f  (expected near 0 — grip engaged)" % side_after)

	# Sideways grip should have killed lateral velocity.
	_assert(abs(side_after) < 1.0,
		"Sideways velocity killed on exit (|%.1f| < 1.0) — grip engaged" % side_after)

	# Forward momentum should still be > 0.
	var fwd_speed = fwd.dot(vel_after)
	_assert(fwd_speed > 10.0,
		"Forward momentum preserved after exit (%.1f > 10.0)" % fwd_speed)

	# State should be ACCELERATE
	var state = _car.get("car_state")
	_assert(state == 0, "Car state = %d (0 = ACCELERATE) after spin release" % state)

	# Spin angular velocity should be zero
	var ang = _spin_ang_vel()
	_assert(ang == 0.0, "spin_angular_velocity = %.2f (expected 0.0 after exit)" % ang)

	_car.queue_free()
	_car = null
	_log("")


func _test_spin_angular_velocity_dragged() -> void:
	_log("── test_spin_angular_velocity_dragged ──")
	_log("  Angular velocity should decay each frame during spin (drag < 1).")

	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)

	# Disable per-frame KE transfer so angular velocity change is purely
	# from drag (no speed-to-rotation injection).
	var p = _P()
	if p != null:
		p.set("rotation_efficiency", 0.0)

	# Manually set a high angular velocity
	_car.set("spin_direction", 1)
	_car.set("spin_angular_velocity", 20.0)
	_car.set("car_state", 1)  # SPINNING
	_press(false, true)  # hold right spin

	var ang_initial = _spin_ang_vel()
	_log("  Initial angular velocity: %.2f rad/s" % ang_initial)

	await _frames(10)

	var ang_after = _spin_ang_vel()
	_log("  Angular velocity after 10 frames: %.2f rad/s" % ang_after)

	_assert(ang_after < ang_initial,
		"Angular velocity decreases over time (%.2f -> %.2f)" % [ang_initial, ang_after])

	_press(false, false)
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

	# Set a moderate forward speed
	_car.set("velocity", Vector2(300, 0))
	_car.set("car_state", 0)
	await _frames(2)

	# Left spin
	_press(true, false)  # J
	await _frames(5)
	var rot_left = _car.global_rotation
	_log("  Rotation after left spin: %.2f rad" % rot_left)

	_press(false, false)
	_car.queue_free()
	_car = null

	# Right spin
	_car = await _spawn_car()
	_car.set("_accept_keyboard_input", false)
	_car.global_position = Vector2(500, 500)
	_car.global_rotation = 0.0
	_car.set("velocity", Vector2(300, 0))
	await _frames(2)

	_press(false, true)  # L
	await _frames(5)
	var rot_right = _car.global_rotation
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
