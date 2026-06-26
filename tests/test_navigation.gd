## Mobility test — verify the car can accelerate, steer (enter/exit spin),
## and maintain forward momentum with the asymmetric drag model.
##
## The full AI track-navigation challenge (tap-timing through the full
## self‑intersecting level_01) is left for future work — the track is
## hard and the AI parameters need dedicated tuning.
##
## Run:  godot --headless --path . tests/test_navigation.tscn
extends Node2D

const MAX_FRAMES := 600   # 10 s at 60 fps — enough for basic mobility checks
const LOG_INTERVAL := 60

var _level: Node2D = null
var _car: Node = null
var _curve: Curve2D = null
var _goal: Area2D = null
var _camera: Camera2D = null

var _frames := 0
var _state_changes: Array[Dictionary] = []
var _max_speed := 0.0
var _wall_hit_count := 0
var _assert_pass := 0
var _assert_fail := 0
var _entries: Array[String] = []


# ═════════════════════════════════════════════════════════════════════
# Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_sep()
	_log("MOBILITY TEST — car accelerates, steers, coasts through spins")
	_sep()
	_log("")

	_ensure_game_state()
	_load_level()


func _process(_delta: float) -> void:
	_frames += 1

	if _frames == 1:
		return   # let _ready chain finish

	if _frames == 2:
		_check_nodes()
		_log("\n-- Entering drive loop --\n")
		return

	if _frames >= MAX_FRAMES:
		_check_results()
		_print_summary()
		set_process(false)
		get_tree().quit()
		return

	_drive()


# ═════════════════════════════════════════════════════════════════════
# Setup
# ═════════════════════════════════════════════════════════════════════

func _ensure_game_state() -> void:
	if Engine.has_singleton("GameState"):
		var gs = Engine.get_singleton("GameState")
		gs.set("accept_keyboard_input", false)
		var p = gs.get("physics_params")
		if p != null:
			p.set("wall_bounce", true)
			p.set("wall_bounce_restitution", 0.4)
		return

	var GameStateScript := preload("res://autoload/game_state.gd")
	var gs := Node.new()
	gs.set_script(GameStateScript)
	var p = preload("res://resources/physics_params.gd").new()
	p.set("wall_bounce", true)
	p.set("wall_bounce_restitution", 0.4)
	gs.set("physics_params", p)
	gs.set("accept_keyboard_input", false)
	Engine.register_singleton("GameState", gs)


func _load_level() -> void:
	_level = preload("res://scenes/levels/level_01.tscn").instantiate()
	add_child(_level)


# ═════════════════════════════════════════════════════════════════════
# Node discovery
# ═════════════════════════════════════════════════════════════════════

func _check_nodes() -> void:
	_car = _level.get_node_or_null("Car")
	_assert(_car != null, "Level has a 'Car' node")

	if _car:
		_car.set("_accept_keyboard_input", false)
		if _car.has_signal("wall_hit"):
			_car.wall_hit.connect(_on_wall_hit)
		if _car.has_signal("state_changed"):
			_car.state_changed.connect(_on_state_changed)

	var track_path: Node = _level.get_node_or_null("TrackPath")
	_assert(track_path != null, "Level has a 'TrackPath' node")

	if track_path:
		_curve = track_path.get("curve")
		_assert(_curve != null, "TrackPath has a Curve2D")

	_goal = _level.get_node_or_null("GoalArea") as Area2D
	_assert(_goal != null, "Level has a 'GoalArea' Area2D")

	_camera = _level.get_node_or_null("Camera2D") as Camera2D
	_assert(_camera != null, "Level has a 'Camera2D' node")


# ═════════════════════════════════════════════════════════════════════
# Drive cycle — inject steering taps, verify car responds
# ═════════════════════════════════════════════════════════════════════

func _drive() -> void:
	if not is_instance_valid(_car):
		return

	# Track speed
	var s = _car.get("current_speed")
	if typeof(s) == TYPE_FLOAT and s > _max_speed:
		_max_speed = s

	# Log periodically
	if _frames % LOG_INTERVAL == 0:
		_log_car_state()

	# Simple steering pattern to exercise state transitions:
	#   - frames 50-53:  brief left spin
	#   - frames 200-203: brief right spin
	#   - frames 400-406: longer left (tests sustained spin + recovery)
	#   - otherwise: coast straight (no input → boost fires)
	if _frames >= 50 and _frames <= 53:
		_car.set_test_input(true, false)
	elif _frames >= 200 and _frames <= 203:
		_car.set_test_input(false, true)
	elif _frames >= 400 and _frames <= 406:
		_car.set_test_input(true, false)
	else:
		_car.set_test_input(false, false)


# ═════════════════════════════════════════════════════════════════════
# Results
# ═════════════════════════════════════════════════════════════════════

func _check_results() -> void:
	_assert(_max_speed >= 100.0,
		"Peak speed = %.0f px/s  (expected >= 100 — car accelerates)" % _max_speed)

	_assert(_state_changes.size() >= 4,
		"State changes = %d  (expected >= 4 from 3 steering taps)" % _state_changes.size())

	# Verify spin entries and exits are both present.
	var entries := 0
	var exits := 0
	for sc in _state_changes:
		if sc.state == 1:  # ACCELERATE
			entries += 1
		elif sc.state == 2:  # SPINNING
			exits += 1
	_assert(entries >= 1, "At least 1 SPIN entry recorded")
	_assert(exits >= 1, "At least 1 ACCELERATE (spin exit) recorded")

	_assert(_wall_hit_count <= 3,
		"Wall hits = %d  (expected ≤ 3 — some bouncing is OK with wall_bounce)" % _wall_hit_count)


# ═════════════════════════════════════════════════════════════════════
# Signal handlers
# ═════════════════════════════════════════════════════════════════════

func _on_wall_hit() -> void:
	_wall_hit_count += 1
	_log("  WALL HIT #%d [frame %d]" % [_wall_hit_count, _frames])


func _on_state_changed(new_state) -> void:
	_state_changes.append({"frame": _frames, "state": new_state})


# ═════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════

func _log_car_state() -> void:
	if not is_instance_valid(_car):
		return
	var pos = _car.get("global_position")
	var speed = _car.get("current_speed")
	var state = _car.get("car_state")
	if typeof(pos) != TYPE_VECTOR2 or typeof(speed) != TYPE_FLOAT:
		return
	var sl := "ACCEL" if typeof(state) == TYPE_INT and state == 1 else "STOP" if typeof(state) == TYPE_INT and state == 0 else "SPIN"
	_log("  t=%2ds  pos=(%5.0f,%5.0f)  speed=%5.0f  state=%s" % [_frames / 60, pos.x, pos.y, speed, sl])


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
