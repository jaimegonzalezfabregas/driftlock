## Base class for all track levels.
## Circuit-style lap racing with support for boss levels (time-trial endurance).
extends Node2D

const TRACK_WIDTH: float = 200.0
const GOAL_THICKNESS: float = 10.0

## Number of laps required to win the race.
@export var total_laps: int = 1
## Level index (0-based). Set by the level-select system.
@export var level_index: int = 0

## Emitted when the race is won.
signal race_won(level_idx: int)

var _car: Node = null
var _game_over: bool = false
var _camera: Camera2D = null

# HUD / pause — instances of hud.tscn and pause_overlay.tscn.
var _hud: Node = null
var _pause_overlay: Node = null
var _paused: bool = false

var _lap: int = 1
var _race_started: bool = false

# Test hook: when true, _end_game() skips the scene navigation so the
# test runner survives the win.  Tests set this after instantiating the level.
var _skip_nav_on_end: bool = false

# Camera shake.
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_decay: float = 12.0


func _ready() -> void:
	var path := $TrackPath
	assert(path != null and path.curve != null and path.curve.point_count >= 2, "TrackPath needs a baked curve with at least 2 points")

	if path.has_method("rebuild_collision"):
		path.rebuild_collision()

	var start_pos: Vector2 = path.start_pos
	var start_dir: Vector2 = path.start_dir
	var end_pos: Vector2   = path.end_pos
	var end_dir: Vector2   = path.end_dir

	# Boss mode: set laps from GameState.
	var gs = _get_gamestate()
	if gs:
		if gs.LEVEL_DATA[level_index].get("is_boss", false):
			total_laps = gs.level_laps[level_index] if level_index < gs.level_laps.size() else 3

	_spawn_car(start_pos, start_dir.angle()-3.1415/2)
	_setup_camera()
	_build_finish_line(end_pos, end_dir)
	_setup_hud()

	_race_started = true
	if _car:
		_car.set("_input_locked", false)


func _get_gamestate():
	var gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if gs == null:
		var tree := get_tree()
		if tree:
			gs = tree.root.get_node_or_null("GameState")
	return gs


# ---------------------------------------------------------------------------
# Track construction helpers
# ---------------------------------------------------------------------------

func _build_finish_line(pos: Vector2, dir: Vector2) -> void:
	var goal := Area2D.new()
	goal.name = "GoalArea"
	goal.global_position = pos
	goal.rotation = dir.angle()
	goal.monitoring = true

	var shape := RectangleShape2D.new()
	shape.size = Vector2(GOAL_THICKNESS, TRACK_WIDTH)

	var col := CollisionShape2D.new()
	col.shape = shape
	goal.add_child(col)

	goal.body_entered.connect(_on_finish_line_crossed)
	add_child(goal)


func _spawn_car(pos: Vector2, rot: float) -> void:
	var car_scene := preload("res://scenes/car/car.tscn")
	_car = car_scene.instantiate()
	_car.name = "Car"
	_car.global_position = pos
	_car.global_rotation = rot
	_car.wall_hit.connect(_on_wall_hit)
	_car.set("_track_builder", $TrackPath)
	add_child(_car)


func _setup_camera() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.5, 0.1))
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 10.0
	add_child(_camera)
	_camera.make_current()


func _setup_hud() -> void:
	# Instantiate HUD scene — all node layout lives there.
	_hud = preload("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_hud.setup(level_index, total_laps)

	# Instantiate pause overlay scene.
	_pause_overlay = preload("res://scenes/ui/pause_overlay.tscn").instantiate()
	_pause_overlay.resume_requested.connect(_resume_game)
	_pause_overlay.quit_requested.connect(_quit_to_title)
	add_child(_pause_overlay)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _paused:
			_resume_game()
		else:
			_pause_game()


func _pause_game() -> void:
	if _game_over or _pause_overlay == null:
		return
	_paused = true
	_pause_overlay.visible = true
	get_tree().paused = true


func _resume_game() -> void:
	if _pause_overlay == null:
		return
	_paused = false
	_pause_overlay.visible = false
	get_tree().paused = false


func _quit_to_title() -> void:
	_resume_game()
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")


func _process(delta: float) -> void:
	# Camera follows car with a look-ahead offset.
	var camera_target: Vector2 = _camera.global_position if _camera else Vector2.ZERO
	if _car and is_instance_valid(_car) and _camera:
		var car := _car as Node2D
		var forward := Vector2.RIGHT.rotated(car.global_rotation)
		const LOOK_AHEAD := -30.0
		camera_target = car.global_position + forward * LOOK_AHEAD

	# Camera shake.
	if _shake_duration > 0.0:
		_shake_duration -= delta
		_shake_strength = move_toward(_shake_strength, 0.0, _shake_decay * delta)
		if _shake_strength > 0.0:
			camera_target += Vector2(
				randf_range(-_shake_strength, _shake_strength),
				randf_range(-_shake_strength, _shake_strength),
			)

	if _camera:
		_camera.global_position = camera_target

	# HUD data updates.
	if _hud:
		_hud.update_lap(_lap, total_laps)


# ---------------------------------------------------------------------------
# Win / Lose
# ---------------------------------------------------------------------------

func _on_wall_hit() -> void:
	if _game_over:
		return
	_game_over = true
	print("GAME OVER — wall hit!")
	_show_drift_hint_and_die()


func _show_drift_hint_and_die() -> void:
	if _hud:
		_hud.set_drift_hint_visible(true)

	# Freeze the car.
	if _car and is_instance_valid(_car):
		_car.velocity = Vector2.ZERO
		_car.set("_input_locked", true)

	await get_tree().create_timer(2.0).timeout

	if _hud:
		_hud.set_drift_hint_visible(false)

	_end_game()


func _on_goal_entered(body: Node) -> void:
	_on_finish_line_crossed(body)


func _on_finish_line_crossed(body: Node) -> void:
	if _game_over:
		return
	if body != _car:
		return
	if not _race_started:
		return

	_lap += 1
	if _lap > total_laps:
		_game_over = true
		print("YOU WIN!  Laps: %d" % total_laps)
		race_won.emit(level_index)
		_show_race_result()
	else:
		print("Lap %d / %d" % [_lap, total_laps])
		if _hud:
			_hud.update_lap(_lap, total_laps)


func _end_game(_reason: String = "crashed") -> void:
	if _car and is_instance_valid(_car):
		_car.queue_free()
		_car = null

	if _skip_nav_on_end:
		return

	var popup := preload("res://scenes/screens/game_over_popup.tscn").instantiate()
	popup.setup(level_index)
	popup.retry_level.connect(_on_result_retry)
	popup.go_to_level_select.connect(_on_result_level_select)
	add_child(popup)


func _show_race_result() -> void:
	var gs = _get_gamestate()
	if gs:
		gs.complete_level(level_index)

		if _car and is_instance_valid(_car):
			_car.queue_free()
			_car = null

		var result := preload("res://scenes/screens/race_result.tscn").instantiate()
		result.setup(level_index)

		if _skip_nav_on_end:
			result.queue_free()
			return

		result.next_level.connect(_on_result_next)
		result.retry_level.connect(_on_result_retry)
		result.go_to_level_select.connect(_on_result_level_select)
		add_child(result)


func _on_result_next(level_idx: int) -> void:
	var gs = _get_gamestate()
	var max_levels: int = gs.LEVEL_COUNT if gs else 10
	var next := level_idx + 1
	if next >= max_levels:
		get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")
		return
	if gs:
		get_tree().change_scene_to_file(gs.get_level_scene(next))


func _on_result_retry(level_idx: int) -> void:
	var gs = _get_gamestate()
	if gs:
		get_tree().change_scene_to_file(gs.get_level_scene(level_idx))


func _on_result_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")
