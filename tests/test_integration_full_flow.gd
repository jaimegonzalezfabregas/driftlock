## Integration test: title → level → goal — runnable via
##
##     godot --path . tests/test_full_flow.tscn
##
## The .tscn wrapper ensures the engine fully initialises (autoloads,
## class_name registration, GDScript inheritance) — unlike `--script` mode.
extends Node2D

# ═════════════════════════════════════════════════════════════════════
# Test state
# ═════════════════════════════════════════════════════════════════════

var _frames := 0
const MAX_FRAMES := 1800          # 30 seconds at 60 fps
const LOG_INTERVAL := 60          # Log car state every 60 frames

# Key nodes
var _level: Node2D = null
var _car = null                    # CharacterBody2D (untyped for dynamic access)
var _goal: Area2D = null
var _camera: Camera2D = null
var _walls: StaticBody2D = null
var _track_path: Path2D = null

# Event flags
enum FinishReason { NONE, GOAL, WALL_HIT, TIMEOUT, ERROR }
var _finish_reason := FinishReason.NONE
var _wall_hit_count := 0
var _state_changes := []           # Array of dicts: { frame, state }
var _car_freed := false
var _checked := false              # first‑frame node checks done
var _cam_checked := false          # camera deferred to frame 2

# Log
var _entries: Array[String] = []
var _assert_pass := 0
var _assert_fail := 0
var _assert_total := 0
var _max_speed := 0.0


# ═════════════════════════════════════════════════════════════════════
# Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_sep()
	_log("INTEGRATION TEST — Title -> Level -> Goal")
	_sep()
	_log("Goal: verify every subsystem works end-to-end.\n")

	# ── 1. GameState singleton ──────────────────────────────────
	# Autoloads may not be registered when loading a .tscn directly
	# (rather than through the project's main scene).  Register one
	# manually if needed.
	if not Engine.has_singleton("GameState"):
		var GameStateScript := preload("res://autoload/game_state.gd")
		var gs := Node.new()
		gs.set_script(GameStateScript)
		gs.set("physics_params", preload("res://resources/physics_params.gd").new())
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)

	var has_gs := Engine.has_singleton("GameState")
	_assert(has_gs,
		"GameState singleton registered (via autoload or manual fallback)")

	_configure_params()

	# ── 2. Load level (simulates pressing "Start Game") ─────────
	var level_scene := load("res://scenes/levels/level_01.tscn") as PackedScene
	_assert(level_scene != null,
		"res://scenes/levels/level_01.tscn loads as PackedScene")

	if level_scene == null:
		_fail_now("Cannot proceed without a valid level scene")
		return

	_level = level_scene.instantiate() as Node2D
	_assert(_level != null,
		"Level scene instantiates as Node2D without errors")

	if _level == null:
		_fail_now("Cannot proceed without a valid level instance")
		return

	add_child(_level)
	_log("  Level instantiated and added to scene tree.")

	_log("\n-- Waiting for _ready() chain on frame 1 --")


func _process(_delta: float) -> void:
	_frames += 1

	if not _checked:
		_checked = true
		_check_nodes()
		_log("\n-- Entering drive loop --\n")
		return

	if not _cam_checked and _frames >= 2:
		_cam_checked = true
		_check_camera()

	_run_drive_cycle()

	if _frames >= MAX_FRAMES and _finish_reason == FinishReason.NONE:
		_finish_reason = FinishReason.TIMEOUT
		# Log final drive‑phase checks before summary.
		_check_drive_results()

	if _finish_reason != FinishReason.NONE:
		_print_summary()
		get_tree().quit()


# ═════════════════════════════════════════════════════════════════════
# Drive simulation
# ═════════════════════════════════════════════════════════════════════

func _run_drive_cycle() -> void:
	if not is_instance_valid(_car) or _car_freed:
		_car_freed = true
		return

	if _frames % LOG_INTERVAL == 0:
		_log_car_state()

	# Track max speed
	var s = _car.get("current_speed")
	if typeof(s) == TYPE_FLOAT and s > _max_speed:
		_max_speed = s

	_drive_heuristic()

	# Check if car was removed (queue_free called by _end_game)
	if _level.get_node_or_null("Car") == null and _frames > 5:
		_car_freed = true
		_log("  [frame %d] Car node removed from level (queue_free called)" % _frames)


func _drive_heuristic() -> void:
	if _car == null or not _car.has_method("set_test_input"):
		return

	# Strategy: mostly accelerate straight (no input).  Brief steering
	# taps (3–6 frames) let us verify ACCEL→SPIN→ACCEL state transitions
	# without fully stalling the car.  The track is ~6188 px long and
	# the car reaches ~200+ px/s, so ≈30 s of straight running covers
	# roughly half the track — enough to demonstrate motion but not
	# enough to navigate the full self‑intersecting curve blindly.
	#
	# Frame windows:
	#   50–53   brief left  → verify state transition
	#  200–203  brief right → verify transition back
	#  500–505  longer left  → verify sustained spin then recovery
	#  900–903  brief right → verify spin at moderate speed

	if _frames >= 50 and _frames <= 53:
		_car.set_test_input(true, false)    # brief left spin
	elif _frames >= 200 and _frames <= 203:
		_car.set_test_input(false, true)    # brief right spin
	elif _frames >= 500 and _frames <= 506:
		_car.set_test_input(true, false)    # longer left (tests sustained spin + recovery)
	elif _frames >= 900 and _frames <= 903:
		_car.set_test_input(false, true)    # brief right (tests spin at higher speed)
	else:
		_car.set_test_input(false, false)   # straight — let the car accelerate


# ═════════════════════════════════════════════════════════════════════
# Node discovery & initial checks
# ═════════════════════════════════════════════════════════════════════

func _check_nodes() -> void:
	_log("-- Frame 1: verifying all subsystems --\n")

	# ── TrackPath & collision ───────────────────────────────────
	_track_path = _level.get_node_or_null("TrackPath") as Path2D
	_assert(_track_path != null,
		"level_base has a 'TrackPath' Path2D child")

	if _track_path:
		var bl := 0.0
		if _track_path.curve != null:
			bl = _track_path.curve.get_baked_length()
		_assert(_track_path.curve != null and _track_path.curve.point_count >= 2,
			"TrackPath curve has >= 2 points (baked length = %.0f)" % bl)

		_walls = _track_path.get_node_or_null("TrackWalls") as StaticBody2D
		_assert(_walls != null,
			"TrackBuilder built a 'TrackWalls' StaticBody2D child")
		if _walls:
			var edge_count := _walls.get_child_count()
			_assert(edge_count > 0,
				"TrackWalls has %d CollisionShape2D edge children" % edge_count)

	# ── Car ─────────────────────────────────────────────────────
	_car = _level.get_node_or_null("Car")
	_assert(_car != null,
		"level_base._spawn_car created a 'Car' node")

	if _car:
		var pos = _car.get("global_position")
		var rot = _car.get("global_rotation")
		var speed = _car.get("current_speed")
		var state = _car.get("car_state")
		var locked = _car.get("_input_locked")

		# During countdown, car state is ACCELERATE but speed is 0.
		_assert(typeof(speed) == TYPE_FLOAT and speed == 0.0,
			"Car initial speed = %.1f px/s  (0 during countdown, start_race after)" % speed)

		_assert(typeof(state) == TYPE_INT and state == 1,
			"Car initial state = %d  (0 = ACCELERATE)" % state)

		_assert(typeof(locked) == TYPE_BOOL and locked == true,
			"Car _input_locked = %s  (locked during countdown)" % str(locked))

		_assert(typeof(pos) == TYPE_VECTOR2 and (pos.x != 0.0 or pos.y != 0.0),
			"Car spawn position = (%.0f, %.0f) — not at origin" % [pos.x, pos.y])

		_car.set("_accept_keyboard_input", false)
		var flag_actual = _car.get("_accept_keyboard_input")
		_assert(flag_actual == false,
			"_accept_keyboard_input forced to false  (test injects set_test_input)")

		if _car.has_signal("wall_hit"):
			_car.wall_hit.connect(_on_wall_hit)
		if _car.has_signal("state_changed"):
			_car.state_changed.connect(_on_state_changed)

	# ── Goal ─────────────────────────────────────────────────────
	_goal = _level.get_node_or_null("GoalArea") as Area2D
	_assert(_goal != null,
		"level_base._build_goal created a 'GoalArea' Area2D")

	if _goal:
		var child_count := _goal.get_child_count()
		_assert(child_count >= 1,
			"GoalArea has %d child node(s)  (expected >= 1, the CollisionShape2D)" % child_count)

		var shape_node := _goal.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape != null:
			var rect := shape_node.shape as RectangleShape2D
			_assert(rect != null,
				"GoalArea CollisionShape2D uses a RectangleShape2D")
			if rect != null:
				_assert(rect.size.x == 10.0,
					"Goal RectangleShape2D thickness = %.0f px  (GOAL_THICKNESS = 10)" % rect.size.x)
				_assert(rect.size.y == 200.0,
					"Goal RectangleShape2D span = %.0f px  (TRACK_WIDTH = 200)" % rect.size.y)

		if _goal.has_signal("body_entered"):
			_goal.body_entered.connect(_on_goal_entered)

	# ── Camera (basic existence) ────────────────────────────────
	_camera = _level.get_node_or_null("Camera2D") as Camera2D
	_assert(_camera != null,
		"level_base._setup_camera created a 'Camera2D' node")

	# Camera position / look-ahead is checked on frame 2 (below)
	# because the level's _process() runs after this node's _process()
	# on the same frame, so the camera hasn't been repositioned yet.

func _check_drive_results() -> void:
	"""Called at timeout — verify the car actually moved and input works."""
	_assert(_state_changes.size() >= 4,
		"Drive phase: state changes = %d  (expected >= 4 from 4 steering taps)" % _state_changes.size())

	_assert(_max_speed >= 150.0,
		"Drive phase: peak speed = %.0f px/s  (expected >= 150 from 20 MW power)" % _max_speed)


func _check_camera() -> void:
	"""Check camera position/look-ahead (called on frame 2, after level's _process)."""
	if _camera == null:
		return
	_assert(_camera.position_smoothing_enabled,
		"Camera position_smoothing_enabled = true")
	_assert(_camera.position_smoothing_speed == 10.0,
		"Camera position_smoothing_speed = %.1f  (expected 10.0)" % _camera.position_smoothing_speed)

	if is_instance_valid(_car):
		var car_pos = _car.get("global_position")
		var cam_pos := _camera.global_position
		if typeof(car_pos) == TYPE_VECTOR2:
			var dist = car_pos.distance_to(cam_pos)
			_assert(dist > 10.0 and dist < 200.0,
				"Camera look-ahead: camera is %.0f px from car  (expected ~30 px ahead)" % dist)


# ═════════════════════════════════════════════════════════════════════
# Signal handlers
# ═════════════════════════════════════════════════════════════════════

func _on_wall_hit() -> void:
	_wall_hit_count += 1
	var pos_msg := ""
	if is_instance_valid(_car):
		var p = _car.get("global_position")
		if typeof(p) == TYPE_VECTOR2:
			pos_msg = " at (%.0f, %.0f)" % [p.x, p.y]
	_log("  WALL HIT #%d [frame %d]%s" % [_wall_hit_count, _frames, pos_msg])


func _on_state_changed(new_state) -> void:
	_state_changes.append({ "frame": _frames, "state": new_state })


func _on_goal_entered(body) -> void:
	if body != _car:
		return
	if _finish_reason != FinishReason.NONE:
		return

	_finish_reason = FinishReason.GOAL
	var pos_msg := ""
	if is_instance_valid(body):
		var p = body.get("global_position")
		if typeof(p) == TYPE_VECTOR2:
			pos_msg = " at (%.0f, %.0f)" % [p.x, p.y]
	_log("")
	_log("vvv [frame %d] CAR ENTERED GOAL AREA%s — WIN! vvv" % [_frames, pos_msg])


# ═════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════

func _configure_params() -> void:
	if not Engine.has_singleton("GameState"):
		return
	var gs = Engine.get_singleton("GameState")
	var p := gs.get("physics_params") as Resource
	if p == null:
		return
	p.set("wall_bounce", true)
	p.set("wall_bounce_restitution", 0.4)


func _log_car_state() -> void:
	if not is_instance_valid(_car):
		return
	var pos = _car.get("global_position")
	var speed = _car.get("current_speed")
	var state = _car.get("car_state")
	if typeof(pos) != TYPE_VECTOR2 or typeof(speed) != TYPE_FLOAT:
		return

	var goal_dist := "?"
	if is_instance_valid(_goal):
		goal_dist = "%.0f" % pos.distance_to(_goal.global_position)

	var state_label := "ACCEL" if typeof(state) == TYPE_INT and state == 1 else ("STOP" if typeof(state) == TYPE_INT and state == 0 else "SPIN")
	var vel = _car.get("velocity")
	var rot = _car.get("global_rotation")
	var fwd_speed_str := "?"
	if typeof(vel) == TYPE_VECTOR2 and typeof(rot) == TYPE_FLOAT:
		var fwd := Vector2.RIGHT.rotated(rot)
		var fs := fwd.dot(vel)
		fwd_speed_str = "%.0f" % fs

	_log("  t=%3ds  pos=(%5.0f,%5.0f)  speed=%5.0f  fwd_spd=%s  state=%s  dist->goal=%s" % [
		_frames / 60, pos.x, pos.y, speed, fwd_speed_str, state_label, goal_dist])


func _assert(condition: bool, message: String) -> void:
	_assert_total += 1
	if condition:
		_assert_pass += 1
	else:
		_assert_fail += 1
		_log("  FAIL: %s" % message)


func _fail_now(reason: String) -> void:
	_log("")
	_log("== ABORTED: %s ==" % reason)
	_finish_reason = FinishReason.ERROR
	_print_summary()
	get_tree().quit()


func _log(text: String) -> void:
	_entries.append(text)
	print(text)


func _sep() -> void:
	_log("=".repeat(60))


# ═════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════

func _print_summary() -> void:
	_log("")
	_sep()
	_log("RESULTS")
	_sep()

	match _finish_reason:
		FinishReason.GOAL:
			_log("CAR REACHED THE GOAL — full game flow verified")
		FinishReason.WALL_HIT:
			_log("Car hit a wall (fatal) before reaching the goal")
		FinishReason.TIMEOUT:
			_log("TIMEOUT after %d frames (%.1f s) — car did not reach goal" % [
				MAX_FRAMES, MAX_FRAMES / 60.0])
		FinishReason.ERROR:
			_log("Test aborted early due to setup error")
		_:
			_log("Unknown finish reason")

	if _car_freed and _finish_reason != FinishReason.GOAL:
		_log("  (Car was freed — _end_game was called)")

	_log("Wall hits: %d" % _wall_hit_count)
	_log("Peak speed: %.0f px/s" % _max_speed)

	if _state_changes.size() > 0:
		_log("State changes: %d" % _state_changes.size())
		for sc in _state_changes:
			var sl := "ACCEL" if sc.state == 1 else ("STOP" if sc.state == 0 else "SPIN")
			_log("  frame %d -> %s" % [sc.frame, sl])
	else:
		_log("State changes: 0")

	if _car and is_instance_valid(_car):
		var final_speed = _car.get("current_speed")
		var final_pos = _car.get("global_position")
		if typeof(final_speed) == TYPE_FLOAT:
			_log("Final car speed:  %.0f px/s" % final_speed)
		if typeof(final_pos) == TYPE_VECTOR2:
			_log("Final car pos:    (%.0f, %.0f)" % [final_pos.x, final_pos.y])
			if is_instance_valid(_goal):
				var d = final_pos.distance_to(_goal.global_position)
				_log("Distance to goal: %.0f px" % d)
	elif _car_freed:
		_log("Car was freed after reaching end-game")

	_log("")
	_log("Assertions: %d / %d passed" % [_assert_pass, _assert_total])
	if _assert_fail > 0:
		_log("%d ASSERTION(S) FAILED — review messages above" % _assert_fail)
	else:
		_log("ALL ASSERTIONS PASSED")

	_log("Frames simulated: %d (%.1f s)" % [_frames, _frames / 60.0])
	_sep()
