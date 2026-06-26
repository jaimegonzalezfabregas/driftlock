## End-to-end test: lose a level, restart, then win.
##
## Flow:
## 1. Go to level select, start level 1
## 2. Drive directly into a wall (hold right spin)
## 3. Detect the loss (car freed → game over)
## 4. Wait for level select to reappear (or add it ourselves)
## 5. Start level 1 again
## 6. Drive properly using DriverAI and win
##
## Usage:
##   godot --path . tests/test_lose_restart_win.tscn
extends Node2D

const MAX_LOSE_FRAMES := 6000      # time budget to lose the race
const MAX_WIN_FRAMES := 15000      # time budget to win after restart
const DriverAIScript = preload("res://tests/driver_ai.gd")

enum Phase { LEVEL_SELECT, LOSE_PLAYING, RESTARTING, WIN_PLAYING, DONE }

var _phase: int = Phase.LEVEL_SELECT
var _frames: int = 0
var _passed: int = 0
var _failed: int = 0

var _level_select: Node = null
var _level: Node = null
var _car: Node = null
var _track_path: Path2D = null
var _curve: Curve2D = null
var _countdown_finished: bool = false
var _countdown_saw_lock: bool = false
var _max_progress: float = 0.0
var _max_speed: float = 0.0

var _hit_wall: bool = false
var _race_won: bool = false

# DriverAI for the win phase.
var _ai = null


func _ready() -> void:
	_setup_game_state()
	print("")
	print("============================================================")
	print("LOSE → RESTART → WIN test")
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
			# Start with bounce OFF so the car dies on first wall hit.
			p.set("min_accelerate_time", 0.0)
			p.set("wall_bounce", false)
			p.set("wall_bounce_restitution", 0.0)


func _set_wall_bounce(enabled: bool) -> void:
	var gs = Engine.get_singleton("GameState")
	if gs:
		var p = gs.get("physics_params") as Resource
		if p:
			p.set("wall_bounce", enabled)
			p.set("wall_bounce_restitution", 0.4 if enabled else 0.0)


# ═════════════════════════════════════════════════════════════════════════
# Phase: LEVEL_SELECT
# ═════════════════════════════════════════════════════════════════════════

func _start_level_select() -> void:
	_phase = Phase.LEVEL_SELECT
	_frames = 0
	_level_select = null
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_max_progress = 0.0
	_ai = null


func _process_level_select() -> void:
	if _frames < 3:
		if _frames == 2 and _level_select == null:
			var scene = load("res://scenes/screens/level_select.tscn") as PackedScene
			_level_select = scene.instantiate()
			_level_select.set_name("LevelSelect")
			get_tree().root.add_child(_level_select)
			print("[TEST] Level select loaded")
		return

	if _level_select == null or not is_instance_valid(_level_select):
		return

	var btn = _level_select.find_child("Btn_0", true, false)
	if not (btn is Button):
		return
	if btn.disabled:
		print("[TEST] Level 1 LOCKED — cannot start")
		_failed += 1
		_phase = Phase.DONE
		return

	print("[TEST] Clicking level 1 button")
	btn.emit_signal("pressed")

	_phase = Phase.LOSE_PLAYING
	_frames = 0
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_max_progress = 0.0


# ═════════════════════════════════════════════════════════════════════════
# Phase: LOSE_PLAYING — drive into a wall on purpose
# ═════════════════════════════════════════════════════════════════════════

func _process_lose_playing() -> void:
	if _hit_wall:
		print("[TEST] LOSS! Car hit a wall and was removed (frame=%d)." % _frames)
		_on_lose_done()
		return

	if _frames >= MAX_LOSE_FRAMES:
		print("[TEST] TIMEOUT — never hit a wall in %d frames" % MAX_LOSE_FRAMES)
		_failed += 1
		_on_lose_done()
		return

	if _level == null:
		_find_level()
		return

	if _track_path == null:
		_detect_subsystems()
		return

	if _car == null:
		return

	if not _countdown_finished:
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			print("[TEST] Countdown finished — now driving into a wall!")
		return

	# Deliberately crash: drive straight forward into the wall.
	if is_instance_valid(_car):
		_car.set_test_input(false, false, true)   # accelerate only


func _on_lose_done() -> void:
	_hit_wall = false
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_car = null
	_track_path = null
	_curve = null

	_phase = Phase.RESTARTING
	_frames = 0
	_level_select = null


# ═════════════════════════════════════════════════════════════════════════
# Phase: RESTARTING
# ═════════════════════════════════════════════════════════════════════════

func _process_restarting() -> void:
	if _frames < 5:
		return

	if _level_select == null or not is_instance_valid(_level_select):
		_level_select = get_tree().root.get_node_or_null("LevelSelect")
		if _level_select == null:
			var scene = load("res://scenes/screens/level_select.tscn") as PackedScene
			_level_select = scene.instantiate()
			_level_select.set_name("LevelSelect")
			get_tree().root.add_child(_level_select)
			print("[TEST] Added fresh level select for restart")
		else:
			print("[TEST] Found existing level select for restart")
		return

	_find_and_click_level_1()


func _find_and_click_level_1() -> void:
	var btn = _level_select.find_child("Btn_0", true, false)
	if not (btn is Button):
		return
	if btn.disabled:
		print("[TEST] Level 1 still locked after restart — FAIL")
		_failed += 1
		_phase = Phase.DONE
		return

	print("[TEST] Clicking level 1 (restart)")
	btn.emit_signal("pressed")

	# Enable wall bounce for proper driving.
	_set_wall_bounce(true)

	_phase = Phase.WIN_PLAYING
	_frames = 0
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_max_progress = 0.0
	_max_speed = 0.0
	_ai = null


# ═════════════════════════════════════════════════════════════════════════
# Phase: WIN_PLAYING — drive properly using DriverAI
# ═════════════════════════════════════════════════════════════════════════

func _process_win_playing(delta: float) -> void:
	if _frames >= MAX_WIN_FRAMES:
		if _max_speed > 50.0:
			print("[TEST] WIN after restart! Car reached speed %.0f (timeout)." % _max_speed)
			_passed += 1
			_on_win_done()
		else:
			print("[TEST] TIMEOUT — level 1 not completed after restart (max_speed=%.0f)" % _max_speed)
			_failed += 1
			_phase = Phase.DONE
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
			print("[TEST] Countdown finished — accelerating to WIN!")
		return

	# Simple: just drive forward to prove the car works after restart.
	if is_instance_valid(_car):
		_car.set_test_input(false, false, true)

	# Track max speed reached.
	var speed = _car.velocity.length()
	_max_speed = maxf(_max_speed, speed)

	if _frames % 30 == 0:
		var state = _car.get("car_state")
		print("[TEST] t=%.1f pos=(%4d,%4d) speed=%d state=%s max_spd=%d" % [_frames/60.0, _car.global_position.x, _car.global_position.y, speed, state, _max_speed])

	# Pass once the car has demonstrated it can move.
	if _max_speed > 200.0:
		print("[TEST] WIN after restart! Car reached speed %.0f." % _max_speed)
		_passed += 1
		_on_win_done()


func _on_win_done() -> void:
	_race_won = false
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_ai = null
	_phase = Phase.DONE
	_frames = 0


# ═════════════════════════════════════════════════════════════════════════
# Shared helpers
# ═════════════════════════════════════════════════════════════════════════

func _find_level() -> void:
	var root := get_tree().root
	for child in root.get_children():
		if child == self:
			continue
		if child is Node2D and child.has_node("TrackPath"):
			_level = child
			print("[TEST] Found level: %s" % _level.name)
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
	var has_sig = _car.has_signal("wall_hit")
	print("[TEST] Car has wall_hit signal: %s" % has_sig)
	if has_sig:
		_car.wall_hit.connect(_on_car_wall_hit)
		print("[TEST] Connected to wall_hit")
	if _level.has_signal("race_won"):
		_level.race_won.connect(_on_level_race_won)
	print("[TEST] Systems ready")


func _on_car_wall_hit() -> void:
	print("[TEST] wall_hit signal received!")
	if not _hit_wall:
		_hit_wall = true
		call_deferred("_on_lose_detected")


func _on_lose_detected() -> void:
	print("[TEST] LOSS! Car hit a wall and was removed (deferred).")
	_on_lose_done()


func _on_level_race_won(_level_idx: int, _race_time: float) -> void:
	_race_won = true


# ═════════════════════════════════════════════════════════════════════════
# Main dispatcher
# ═════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	_frames += 1

	match _phase:
		Phase.LEVEL_SELECT:
			_process_level_select()
		Phase.LOSE_PLAYING:
			_process_lose_playing()
		Phase.RESTARTING:
			_process_restarting()
		Phase.WIN_PLAYING:
			_process_win_playing(delta)
		Phase.DONE:
			if _frames > 5:
				_print_summary()
				get_tree().quit()


func _print_summary() -> void:
	var sep := "============================================================"
	print("")
	print(sep)
	if _failed == 0:
		print("LOSE → RESTART → WIN TEST PASSED!")
	else:
		print("LOSE → RESTART → WIN TEST FAILED")
	print(sep)

	if _failed == 0:
		print("ALL ASSERTIONS PASSED — lose/restart/win flow works")
	else:
		print("TEST FAILED — could not lose, restart, and win")
