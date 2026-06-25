## End-to-end menu flow test.
##
## Goes through the full game flow:
## 1. Starts at Level Select screen
## 2. Clicks each level button (1→7) through the actual menu code
## 3. Drives each level to win
## 4. Returns to level select after each completion
## 5. Verifies the next level is unlocked
##
## The title screen is skipped because it calls change_scene_to_file
## synchronously, which would destroy our test scene.  The level select
## instead uses queue_free on itself + add_child on the level, which
## lets our test survive as a root sibling.
##
## Usage:
##   godot --path . tests/test_e2e_menu_flow.tscn
extends Node2D

const LEVEL_COUNT := 7
const BASE_FRAMES_PER_LAP := 10000  # ~167s per lap

enum Phase { LEVEL_SELECT, PLAYING, WIN_WAIT, DONE }

var _phase: int = Phase.LEVEL_SELECT
var _current_level: int = 0  # 0-based
var _frames: int = 0
var _max_frames_this_level: int = 0  # set based on lap count
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

# Driving state.
var _steering_left: bool = false
var _steering_active: bool = false
var _coast_timer: int = 0
var _max_progress: float = 0.0
var _track_length: float = 0.0


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
	# Calculate frame limit based on level lap count.
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
	_steering_active = false
	_max_progress = 0.0

	# Wait a frame before loading to let any previous cleanup finish.


func _process_level_select() -> void:
	if _frames < 3:
		# Check frame 3 — load level select if not present.
		if _frames == 2 and _level_select == null:
			var scene = load("res://scenes/screens/level_select.tscn") as PackedScene
			_level_select = scene.instantiate()
			_level_select.set_name("LevelSelect")
			get_tree().root.add_child(_level_select)
			print("[E2E] Level select screen loaded via root.add_child")
		return

	if _level_select == null or not is_instance_valid(_level_select):
		# Try again — maybe it got destroyed by a previous button press
		# that triggered queue_free.  At this point the level should
		# already be in the tree instead.
		return

	var container := _level_select.get_node_or_null("ScrollContainer/VBoxContainer")
	if container == null:
		return

	# Buttons are every 2nd child (button + description label).
	var btn_idx := _current_level * 2
	if btn_idx >= container.get_child_count():
		print("[E2E] No button for level %d — FAIL" % (_current_level + 1))
		_failed += 1
		_current_level += 1
		_check_done()
		return

	var btn := container.get_child(btn_idx)
	if not (btn is Button):
		return
	if btn.disabled:
		print("[E2E] Level %d LOCKED — FAIL (only %d unlocked)" %
			[_current_level + 1, _get_unlocked_count()])
		_failed += 1
		_current_level += 1
		_check_done()
		return

	print("[E2E] Clicking level %d button in level select" % (_current_level + 1))

	# Simulate the button press.  This calls level_select._on_level_pressed()
	# which creates the level, adds it to root, and queue_free's the
	# level select.  Our test is also a root child and survives.
	btn.emit_signal("pressed")

	# Wait for the level to appear.
	_phase = Phase.PLAYING
	_frames = 0
	_level = null
	_car = null
	_track_path = null
	_curve = null
	_countdown_finished = false
	_countdown_saw_lock = false
	_race_won = false
	_steering_active = false
	_max_progress = 0.0


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
		print("[E2E] TIMEOUT — level %d (progress %.0f%%, limit=%d frames)" %
			[_current_level + 1, _max_progress * 100.0, _max_frames_this_level])
		_failed += 1
		_on_level_done()
		return

	# Find the level (it was added to root by level_select).
	if _level == null:
		_find_level()
		return

	# Detect sub-systems.
	if _track_path == null:
		_detect_subsystems()
		return

	# Wait for countdown.
	if not _countdown_finished:
		if _car == null:
			return
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
		return

	# Drive the car.
	_drive()

	# Check for win — the level removes the car when race is won.
	# _end_game() calls _car.queue_free() then awaits 1 second before
	# calling complete_level() and change_scene_to_file.  Since we free
	# the level here (before that await finishes), we must call
	# complete_level() ourselves to update GameState unlocks.
	if _car == null or not is_instance_valid(_car):
		print("[E2E] Level %d WIN!" % (_current_level + 1))
		_race_won = true
		_passed += 1
		# Call complete_level ourselves since _end_game()'s version
		# won't fire (its 1-second await won't resume once we free the level).
		var gs = Engine.get_singleton("GameState")
		if gs:
			gs.complete_level(_current_level)
		_on_level_done()


func _find_level() -> void:
	# The level is added to root by level_select._on_level_pressed().
	# Look for it among root children. Level scenes extend Node2D.
	var root := get_tree().root
	for child in root.get_children():
		if child == self:
			continue
		if child is Node2D and child.has_node("TrackPath"):
			_level = child
			print("[E2E] Found level node: %s (in tree=%s)" %
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
	_track_length = _curve.get_baked_length()
	print("[E2E] Systems ready — track=%.0fpx car=%s" %
		[_track_length, _car.name])


# ═════════════════════════════════════════════════════════════════════════
# Post-level handling
# ═════════════════════════════════════════════════════════════════════════

func _on_level_done() -> void:
	# Clean up the level node.
	if _level and is_instance_valid(_level):
		_level.queue_free()
	_level = null
	_car = null
	_track_path = null
	_curve = null

	_current_level += 1
	_check_done()


func _check_done() -> void:
	if _current_level >= LEVEL_COUNT:
		_phase = Phase.DONE
	else:
		# Go back to level select.
		_start_level_select()


# ═════════════════════════════════════════════════════════════════════════
# Driving logic (pure pursuit, same as test_e2e_race)
# ═════════════════════════════════════════════════════════════════════════

const PARALLEL_THRESHOLD := 0.25


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
