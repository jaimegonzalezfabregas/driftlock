## End‑to‑end race test — uses DriverAI (fair 3‑key state machine).
##
## Loads a level, starts the AI driver, waits for win or timeout.
##
## Usage:
##   godot --headless --path . tests/test_e2e_race.tscn
##   godot --headless --path . tests/test_e2e_race.tscn -- level_path="res://scenes/levels/level_01.tscn"
extends Node2D

const MAX_FRAMES := 7200          # 2 minutes at 60 fps
const LOG_INTERVAL := 60
const DEFAULT_LEVEL := "res://scenes/levels/level_01.tscn"

const SEPARATOR := "============================================================"
const DriverAIScript = preload("res://tests/driver_ai.gd")

enum FinishReason { NONE, WIN, TIMEOUT }

var _finish_reason: int = FinishReason.NONE
var _frames := 0
var _level: Node = null
var _car: Node = null
var _track_path: Path2D = null
var _curve: Curve2D = null
var _countdown_finished := false
var _countdown_saw_lock := false

# DriverAI — pure FSM using only set_test_input(left, right, accelerate).
var _ai = null


func _ready() -> void:
	_log(SEPARATOR)
	_log("E2E RACE TEST — DriverAI (fair 3‑key FSM)")
	_log(SEPARATOR)

	# ── 1. Ensure GameState singleton ──────────────────────────
	if not Engine.has_singleton("GameState"):
		var gs := Node.new()
		gs.set_script(preload("res://autoload/game_state.gd"))
		gs.set("physics_params", preload("res://resources/physics_params.gd").new())
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)

	var gs = Engine.get_singleton("GameState")
	if gs:
		var p = gs.get("physics_params") as Resource
		if p:
			p.set("min_accelerate_time", 0.0)
			p.set("wall_bounce", true)
			p.set("wall_bounce_restitution", 0.4)

	# ── 2. Pick level ──────────────────────────────────────────
	var level_path := DEFAULT_LEVEL
	for arg in OS.get_cmdline_args():
		if arg.begins_with("level_path="):
			level_path = arg.trim_prefix("level_path=")
			break

	_log("Loading level: %s" % level_path)

	# ── 3. Load and instantiate level ──────────────────────────
	var level_scene := load(level_path) as PackedScene
	assert(level_scene != null, "Level scene loads as PackedScene")

	_level = level_scene.instantiate()
	_level.set("total_laps", 1)
	add_child(_level)
	_log("Level instantiated (total_laps = 1).")


func _process(delta: float) -> void:
	_frames += 1

	if _finish_reason != FinishReason.NONE:
		if _frames > MAX_FRAMES + 1:
			_print_summary()
			get_tree().quit()
		return

	if _frames >= MAX_FRAMES:
		_finish_reason = FinishReason.TIMEOUT
		return

	# Detect level subsystems.
	if _track_path == null:
		_detect_level()
		return

	# Wait for countdown.
	if not _countdown_finished:
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			_log("Countdown finished — race started.\n")
		return

	# Drive using the AI state machine.
	if _ai != null:
		_ai.process(delta)

	# Check for win.
	if _car == null or not is_instance_valid(_car):
		if _finish_reason == FinishReason.NONE:
			_finish_reason = FinishReason.WIN
			_log("[frame %d] Car removed — race won!" % _frames)
			_print_summary()
			get_tree().quit()
		return

	if _frames % LOG_INTERVAL == 0:
		_log_car_state()


# ═════════════════════════════════════════════════════════════════════════
# Detection and logging
# ═════════════════════════════════════════════════════════════════════════

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
	_log("Level '%s' ready — car found." % _level.name)
	_log("Curve baked length: %.0f px" % _curve.get_baked_length())
	_countdown_finished = false
	_countdown_saw_lock = false

	# Create DriverAI.
	_ai = DriverAIScript.new()
	_ai.setup(_car, _track_path)


func _log_car_state() -> void:
	if _car == null:
		return
	var pos = _car.get("global_position")
	var speed = _car.get("current_speed")
	var state = _car.get("car_state")
	var state_name: String
	match int(state):
		0: state_name = "STOP"
		1: state_name = "ACCEL"
		_: state_name = "SPIN"
	var t = _frames / 60.0
	_log("  t=%5.1fs  pos=(%5.0f,%5.0f)  speed=%5.0f  state=%s" %
		[t, pos.x, pos.y, speed, state_name])


func _print_summary() -> void:
	_log(SEPARATOR)
	match _finish_reason:
		FinishReason.WIN:
			_log("RESULT: WIN — Car completed the race!  (%d frames, %.1f s)" %
				[_frames, _frames / 60.0])
		FinishReason.TIMEOUT:
			_log("RESULT: TIMEOUT after %d frames (%.1f s)" %
				[MAX_FRAMES, MAX_FRAMES / 60.0])
		_:
			_log("RESULT: UNKNOWN")
	_log("Peak speed: %.0f px/s" % _ai.current_speed if _ai else 0.0)
	_log(SEPARATOR)

	if _finish_reason == FinishReason.WIN:
		print("ALL ASSERTIONS PASSED — E2E RACE WIN")
	else:
		print("TEST FAILED — Car did not reach goal")


func _log(msg: String) -> void:
	print(msg)
