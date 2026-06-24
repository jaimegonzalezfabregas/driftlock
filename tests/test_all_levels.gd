## All-Levels Playthrough Test
##
## Loads each level scene individually, sets the car's physics to
## test-friendly values, and drives the car to complete the race.
## Reports PASS/FAIL for each level.
extends Node2D

const LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_02.tscn",
	"res://scenes/levels/level_03.tscn",
	"res://scenes/levels/level_04.tscn",
	"res://scenes/levels/level_05.tscn",
	"res://scenes/levels/level_06.tscn",
	"res://scenes/levels/level_07.tscn",
]

const MAX_FRAMES_PER_LEVEL := 9000  # 2.5 min per level
const LOG_INTERVAL := 120

var _current_level_idx: int = 0
var _level: Node = null
var _car: Node = null
var _track_path: Path2D = null
var _curve: Curve2D = null
var _frames: int = 0
var _countdown_finished: bool = false
var _countdown_saw_lock: bool = false
var _won: bool = false
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Ensure GameState exists.
	if not Engine.has_singleton("GameState"):
		var gs := Node.new()
		gs.set_script(preload("res://autoload/game_state.gd"))
		gs.set("physics_params", preload("res://resources/physics_params.gd").new())
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)
	_setup_physics()
	_load_next_level()


func _setup_physics() -> void:
	var gs = Engine.get_singleton("GameState")
	if gs:
		var p = gs.get("physics_params") as Resource
		if p:
			p.set("min_accelerate_time", 0.0)
			p.set("wall_bounce", true)
			p.set("wall_bounce_restitution", 0.4)


func _load_next_level() -> void:
	if _current_level_idx >= LEVEL_PATHS.size():
		# All done.
		_print_summary()
		get_tree().quit()
		return

	var path := LEVEL_PATHS[_current_level_idx]
	print("\n=== Level %d / %d: %s ===" % [_current_level_idx + 1, LEVEL_PATHS.size(), path])

	# Clean up previous.
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_frames = 0
	_countdown_finished = false
	_countdown_saw_lock = false
	_won = false

	var scene := load(path) as PackedScene
	if scene == null:
		print("  FAIL — Could not load scene: %s" % path)
		_failed += 1
		_current_level_idx += 1
		_load_next_level()
		return

	_level = scene.instantiate()
	_level.set("total_laps", 1)
	add_child(_level)
	print("  Level instantiated (total_laps = 1)")


func _process(delta: float) -> void:
	if _level == null:
		return

	_frames += 1

	if _won:
		return

	if _frames >= MAX_FRAMES_PER_LEVEL:
		print("  TIMEOUT after %d frames — level %d" % [MAX_FRAMES_PER_LEVEL, _current_level_idx + 1])
		_failed += 1
		_current_level_idx += 1
		_load_next_level()
		return

	# Detect subsystems.
	if _track_path == null:
		_detect_level()
		return

	# Wait for countdown.
	if not _countdown_finished:
		if _car == null:
			_detect_level()
			return
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			print("  Countdown finished — driving...")
		return

	# Drive the car.
	_drive()

	# Check for win (car removed = race won).
	if _car == null or not is_instance_valid(_car):
		_won = true
		_passed += 1
		print("  PASS — Level %d completed!" % (_current_level_idx + 1))
		_current_level_idx += 1
		# Wait 1 frame then load next.
		_load_next_level()
		return


func _detect_level() -> void:
	if _level == null:
		return
	_track_path = _level.get_node_or_null("TrackPath") as Path2D
	if _track_path == null:
		return
	var c = _track_path.get("curve")
	_curve = c as Curve2D
	if _curve == null:
		return
	_car = _level.get_node_or_null("Car")
	if _car == null:
		return
	_car.set("_accept_keyboard_input", false)
	_countdown_finished = false
	_countdown_saw_lock = false


# ── Driving logic (same as test_e2e_race) ─────────────────────────────

const PARALLEL_THRESHOLD := 0.25

var _steering_left: bool = false
var _steering_active: bool = false
var _coast_timer: int = 0
var _in_spin: bool = false
var _spin_accumulated_rotation: float = 0.0
var _max_progress: float = 0.0
var _track_length: float = 0.0


func _drive() -> void:
	if _car == null or _curve == null:
		return

	var car_pos: Vector2 = _car.get("global_position")
	var car_rot: float = _car.get("global_rotation")
	var forward: Vector2 = Vector2.RIGHT.rotated(car_rot)
	var local_pos: Vector2 = _track_path.to_local(car_pos)
	var speed: float = _car.get("current_speed") as float

	var nearest_ofs: float = _curve.get_closest_offset(local_pos)
	var total_length: float = _curve.get_baked_length()

	var look_dist: float = maxf(200.0, speed * 2.0)
	var ahead_ofs: float = nearest_ofs + look_dist
	if ahead_ofs > total_length:
		ahead_ofs -= total_length

	var ahead_xf: Transform2D = _curve.sample_baked_with_rotation(ahead_ofs) as Transform2D
	var ahead_global: Vector2 = _track_path.to_global(ahead_xf.origin)
	var to_target: Vector2 = (ahead_global - car_pos).normalized()
	var angle_to_target: float = forward.angle_to(to_target)

	var acc_rot_v = _car.get("_accumulated_spin_rotation")
	var acc_rot: float = acc_rot_v if typeof(acc_rot_v) == TYPE_FLOAT else 0.0
	var min_rot: float = TAU

	if _coast_timer > 0:
		_coast_timer -= 1

	if _steering_active:
		var can_release: bool = acc_rot >= min_rot
		var facing_target: bool = abs(angle_to_target) < PARALLEL_THRESHOLD
		if can_release and facing_target:
			_steering_active = false
			_car.set_test_input(false, false)
			_coast_timer = 8
	else:
		if _coast_timer == 0 and abs(angle_to_target) > PARALLEL_THRESHOLD:
			_steering_active = true
			_steering_left = (angle_to_target > 0)

	if _steering_active:
		_car.set_test_input(_steering_left, not _steering_left)
	else:
		_car.set_test_input(false, false)

	var prog: float = nearest_ofs / total_length
	if prog > _max_progress:
		_max_progress = prog


func _print_summary() -> void:
	var sep := "============================================================"
	print("")
	print(sep)
	print("ALL LEVELS TEST — %d passed, %d failed out of %d" % [_passed, _failed, LEVEL_PATHS.size()])
	print(sep)
	if _failed == 0:
		print("ALL ASSERTIONS PASSED — All levels beatable!")
	else:
		print("TEST FAILED — %d level(s) not beatable" % _failed)
