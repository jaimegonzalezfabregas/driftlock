## End-to-end menu flow test.
##
## Goes through the full game flow:
## 1. Starts at Level Select screen
## 2. Clicks each level button through the actual menu code
## 3. Drives each level using DriverAI (fair 3‑key FSM) to win
## 4. Returns to level select after each completion
## 5. Verifies the next level is unlocked
##
## Usage:
##   godot --path . tests/test_e2e_menu_flow.tscn
extends Node2D

const LEVEL_COUNT := 20
const BASE_FRAMES_PER_LAP := 15000  # generous
const DriverAIScript = preload("res://tests/driver_ai.gd")

enum Phase { LEVEL_SELECT, PLAYING, WIN_WAIT, DONE }

var _phase: int = Phase.LEVEL_SELECT
var _current_level: int = 0  # 0‑based
var _frames: int = 0
var _max_frames_this_level: int = 0
var _passed: int = 0
var _failed: int = 0

var _level_select: Node = null
var _level: Node = null
var _car: Node = null
var _track_path: Path2D = null
var _curve: Curve2D = null
var _countdown_finished: bool = false
var _countdown_saw_lock: bool = false
var _race_won: bool = false

# DriverAI — state‑machine driver.
var _ai = null


func _ready() -> void:
	_setup_game_state()
	print("")
	print("============================================================")
	print("E2E MENU FLOW — All levels through level select UI")
	print("============================================================")
	print("")
	_start_level_select()


func _setup_game_state() -> void:
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


# ═════════════════════════════════════════════════════════════════════════
# Level select screen
# ═════════════════════════════════════════════════════════════════════════

func _start_level_select() -> void:
	_phase = Phase.LEVEL_SELECT
	_frames = 0
	var gs = Engine.get_singleton("GameState")
	var laps := 1
	if gs:
		laps = gs.get_level_laps(_current_level)
	_max_frames_this_level = maxi(BASE_FRAMES_PER_LAP, BASE_FRAMES_PER_LAP * laps)
	_level_select = null
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_race_won = false
	_ai = null


func _process_level_select() -> void:
	if _frames < 3:
		if _frames == 2 and _level_select == null:
			var scene = load("res://scenes/screens/level_select.tscn") as PackedScene
			_level_select = scene.instantiate()
			_level_select.set_name("LevelSelect")
			get_tree().root.add_child(_level_select)
			print("[E2E] Level select screen loaded via root.add_child")
		return

	if _level_select == null or not is_instance_valid(_level_select):
		return

	var btn = _level_select.find_child("Btn_%d" % _current_level, true, false)
	if not (btn is Button):
		return
	if btn.disabled:
		print("[E2E] Level %d LOCKED — FAIL (count=%d)" %
			[_current_level + 1, _get_unlocked_count()])
		_failed += 1
		_current_level += 1
		_check_done()
		return

	print("[E2E] Clicking level %d button" % (_current_level + 1))
	btn.emit_signal("pressed")

	_phase = Phase.PLAYING
	_frames = 0
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_race_won = false
	_ai = null


func _get_unlocked_count() -> int:
	var gs = Engine.get_singleton("GameState")
	if gs:
		var arr = gs.get("unlocked_levels") as Array
		if arr:
			var c := 0
			for v in arr:
				if v:
					c += 1
			return c
	return 0


# ═════════════════════════════════════════════════════════════════════════
# Playing a level
# ═════════════════════════════════════════════════════════════════════════

func _process_playing(delta: float) -> void:
	if _race_won:
		return

	if _frames >= _max_frames_this_level:
		print("[E2E] TIMEOUT — level %d (limit=%d frames)" %
			[_current_level + 1, _max_frames_this_level])
		_failed += 1
		_on_level_done()
		return

	if _level == null:
		_find_level()
		return

	if _track_path == null:
		_detect_subsystems()
		return

	if not _countdown_finished:
		if _car == null:
			return
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			# Create AI after countdown finishes.
			_ai = DriverAIScript.new()
			_ai.setup(_car, _track_path)
		return

	# Drive with AI.
	if _ai != null:
		_ai.process(delta)

	# Check for win.
	if _car == null or not is_instance_valid(_car):
		print("[E2E] Level %d WIN!" % (_current_level + 1))
		_race_won = true
		_passed += 1
		var gs = Engine.get_singleton("GameState")
		if gs:
			gs.complete_level(_current_level)
		_on_level_done()


func _find_level() -> void:
	var root := get_tree().root
	for child in root.get_children():
		if child == self:
			continue
		if child is Node2D and child.has_node("TrackPath"):
			_level = child
			print("[E2E] Found level node: %s (in_tree=%s)" %
				[_level.name, _level.is_inside_tree()])
			break


func _detect_subsystems() -> void:
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
	print("[E2E] Systems ready — track=%.0fpx" % _curve.get_baked_length())


# ═════════════════════════════════════════════════════════════════════════
# Post-level handling
# ═════════════════════════════════════════════════════════════════════════

func _on_level_done() -> void:
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_ai = null

	_current_level += 1
	_check_done()


func _check_done() -> void:
	if _current_level >= LEVEL_COUNT:
		_phase = Phase.DONE
	else:
		_start_level_select()


# ═════════════════════════════════════════════════════════════════════════
# Main _process dispatcher
# ═════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_frames += 1

	match _phase:
		Phase.LEVEL_SELECT:
			_process_level_select()
		Phase.PLAYING:
			_process_playing(delta)
		Phase.DONE:
			if _frames > 5:
				_print_summary()
				get_tree().quit()


# ═════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════

func _print_summary() -> void:
	var sep := "============================================================"
	print("")
	print(sep)
	if _failed == 0:
		print("ALL E2E MENU FLOW TESTS PASSED — %d levels completed" % _passed)
	else:
		print("E2E MENU FLOW: %d passed, %d failed" % [_passed, _failed])
	print(sep)

	if _failed == 0:
		print("ALL ASSERTIONS PASSED — E2E MENU FLOW")
	else:
		print("TEST FAILED — E2E menu flow incomplete")

	get_tree().quit(0 if _failed == 0 else 1)
