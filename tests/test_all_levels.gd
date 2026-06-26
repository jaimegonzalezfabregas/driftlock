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
	"res://scenes/levels/level_08.tscn",
	"res://scenes/levels/level_09.tscn",
	"res://scenes/levels/level_10.tscn",
	"res://scenes/levels/level_11.tscn",
	"res://scenes/levels/level_12.tscn",
	"res://scenes/levels/level_13.tscn",
	"res://scenes/levels/level_14.tscn",
	"res://scenes/levels/level_15.tscn",
	"res://scenes/levels/level_16.tscn",
	"res://scenes/levels/level_17.tscn",
	"res://scenes/levels/level_18.tscn",
	"res://scenes/levels/level_19.tscn",
	"res://scenes/levels/level_20.tscn",
]

const MAX_FRAMES_PER_LEVEL := 18000  # 5 min per level
const LOG_INTERVAL := 120
const DriverAIScript = preload("res://tests/driver_ai.gd")

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

# Driver AI — state‑machine driver that only uses public inputs.
var _ai = null


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
	_ai = null
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

	# Drive using the AI state machine.
	if _ai != null:
		_ai.process(delta)

	# Check for win (car removed = race won).
	if _car == null or not is_instance_valid(_car):
		_won = true
		_passed += 1
		print("  PASS — Level %d completed!" % (_current_level_idx + 1))
		_current_level_idx += 1
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

	# Create the DriverAI.
	_ai = DriverAIScript.new()
	_ai.setup(_car, _track_path)


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
