## Base class for all track levels.
## Circuit-style lap racing with support for boss levels (time-trial endurance).
extends Node2D

const TRACK_WIDTH: float = 200.0
const SEGMENT_DISTANCE: float = 30.0
const GOAL_THICKNESS: float = 10.0

## Number of laps required to win the race.
@export var total_laps: int = 1
## Level index (0-based). Set by the level-select system.
@export var level_index: int = 0

## Emitted when the race is won.
signal race_won(level_idx: int, time: float)

var _car: Node = null
var _game_over: bool = false
var _camera: Camera2D = null
var _hud_layer: CanvasLayer = null
var _boost_bar_bg: ColorRect = null
var _boost_bar_fill: ColorRect = null
var _lap_label: Label = null
var _timer_label: Label = null
var _level_label: Label = null
var _countdown_label: Label = null
var _time_limit_label: Label = null  # shown for boss levels

# Hint labels (shown to new players).
var _space_hint_label: Label = null
var _drift_hint_label: Label = null
var _no_input_timer: float = 0.0    # seconds since SPACE last pressed after race start
var _has_spun: bool = false         # true if the car ever entered SPINNING state

# Pause state.
var _pause_overlay: CanvasLayer = null
var _paused: bool = false

const COUNTDOWN_TEXT: Array[String] = ["3", "2", "1", "GO!"]

var _lap: int = 1
var _race_time: float = 0.0
var _race_started: bool = false

# Boss-level time limit (seconds), 0 if not a boss level.
var _boss_time_limit: float = 0.0

# Test hook: when true, _end_game() skips the scene navigation so the
# test runner survives the win.  Tests set this after instantiating the level.
var _skip_nav_on_end: bool = false

# Camera shake.
var _shake_strength: float = 0.0
var _shake_duration: float = 0.0
var _shake_decay: float = 12.0


func _ready() -> void:
	var path := $TrackPath
	assert(path != null, "TrackPath needs to be a Path2D")

	# If the curve already has waypoints (baked into scene by
	# tools/bake_track_curves.gd), use it directly so the user can edit
	# waypoints in the editor.  Otherwise generate from hardcoded data.
	if path.curve == null or path.curve.point_count < 2:
		_generate_track_curve(path)
		assert(path.curve != null, "TrackPath needs a curve after generation")

	if path.has_method("rebuild_collision"):
		path.rebuild_collision()

	var start_pos: Vector2 = path.start_pos
	var start_dir: Vector2 = path.start_dir
	var end_pos: Vector2 = path.end_pos
	var end_dir: Vector2 = path.end_dir

	# Boss mode: set laps and time limit.
	var gs = _get_gamestate()
	if gs:
		if gs.LEVEL_DATA[level_index].get("is_boss", false):
			total_laps = gs.level_laps[level_index] if level_index < gs.level_laps.size() else 3
			_boss_time_limit = gs.get_bronze_time(level_index)

	_level_specific_setup(path.curve)
	_spawn_car(start_pos, start_dir.angle())
	_setup_camera()
	_build_finish_line(end_pos, end_dir)
	_setup_hud()

	if _car:
		_car.set("_input_locked", true)
		_start_countdown()


func _get_gamestate():
	var gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if gs == null:
		var tree := get_tree()
		if tree:
			gs = tree.root.get_node_or_null("GameState")
	return gs


## Virtual hook — override in subclasses to add obstacles, etc.
func _level_specific_setup(_curve: Curve2D) -> void:
	pass


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
	var car_scene := preload("res://scenes/car.tscn")
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
	# Explicitly mark as current so it always becomes the active camera,
	# even on scene reload (retry) where auto-detection can be flaky.
	_camera.make_current()


func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var bar_w := 200.0
	var bar_h := 14.0
	var margin := 20.0
	var view := _hud_layer.get_viewport().get_visible_rect().size if _hud_layer.get_viewport() else Vector2(1152, 648)

	# -- Boost bar ----------------------------------------------------
	var bg := ColorRect.new()
	bg.name = "BoostBarBg"
	bg.size = Vector2(bar_w, bar_h)
	bg.position = Vector2(view.x * 0.5 - bar_w * 0.5, view.y - margin - bar_h)
	bg.color = Color(0.2, 0.2, 0.2, 0.7)
	_hud_layer.add_child(bg)
	_boost_bar_bg = bg

	var fill := ColorRect.new()
	fill.name = "BoostBarFill"
	fill.size = Vector2(bar_w, bar_h)
	fill.position = bg.position
	fill.color = Color(1.0, 0.6, 0.0, 0.9)
	_hud_layer.add_child(fill)
	_boost_bar_fill = fill

	if _car:
		if _car.has_signal("boost_applied"):
			_car.boost_applied.connect(_on_boost_applied)

	# -- Lap counter (top center) ------------------------------------
	var ll := Label.new()
	ll.name = "LapLabel"
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ll.add_theme_color_override("font_color", Color.WHITE)
	ll.add_theme_font_size_override("font_size", 32)
	ll.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, margin)
	ll.text = ""
	_hud_layer.add_child(ll)
	_lap_label = ll

	# -- Timer -------------------------------------------------------
	var tl := Label.new()
	tl.name = "TimerLabel"
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	tl.add_theme_font_size_override("font_size", 20)
	tl.position = Vector2(margin, margin + 36)
	tl.size = Vector2(160, 30)
	tl.text = ""
	_hud_layer.add_child(tl)
	_timer_label = tl

	# -- Time limit (boss levels) ------------------------------------
	if _boss_time_limit > 0.0:
		var timelimit_lbl := Label.new()
		timelimit_lbl.name = "TimeLimitLabel"
		timelimit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		timelimit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		timelimit_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
		timelimit_lbl.add_theme_font_size_override("font_size", 18)
		timelimit_lbl.position = Vector2(margin, margin + 68)
		timelimit_lbl.size = Vector2(200, 24)
		timelimit_lbl.text = "TIME LIMIT: %.1f s" % _boss_time_limit
		_hud_layer.add_child(timelimit_lbl)
		_time_limit_label = timelimit_lbl

	# -- Level indicator ---------------------------------------------
	var level_lbl := Label.new()
	level_lbl.name = "LevelLabel"
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	level_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	level_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.6))
	level_lbl.add_theme_font_size_override("font_size", 16)
	level_lbl.position = Vector2(margin, view.y - margin - 20)
	level_lbl.size = Vector2(200, 24)
	level_lbl.text = "Level %d" % (level_index + 1)
	_hud_layer.add_child(level_lbl)
	_level_label = level_lbl

	# -- Countdown label ---------------------------------------------
	var cl2 := Label.new()
	cl2.name = "CountdownLabel"
	cl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cl2.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	cl2.add_theme_font_size_override("font_size", 96)
	cl2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl2.text = ""
	_hud_layer.add_child(cl2)
	_countdown_label = cl2

	# -- Space hint label (centred, semi-transparent) ----------------
	var shl := Label.new()
	shl.name = "SpaceHintLabel"
	shl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.7))
	shl.add_theme_font_size_override("font_size", 28)
	shl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shl.position = Vector2(0, -40)
	shl.text = "Press SPACEBAR to run"
	shl.visible = false
	_hud_layer.add_child(shl)
	_space_hint_label = shl

	# -- Drift hint label (centred, yellow) --------------------------
	var dhl := Label.new()
	dhl.name = "DriftHintLabel"
	dhl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dhl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dhl.add_theme_color_override("font_color", Color(1.0, 1.0, 0.4, 0.9))
	dhl.add_theme_font_size_override("font_size", 28)
	dhl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dhl.position = Vector2(0, -40)
	dhl.text = "Press A and D to drift"
	dhl.visible = false
	_hud_layer.add_child(dhl)
	_drift_hint_label = dhl

	# -- Pause overlay -----------------------------------------------
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.layer = 20
	_pause_overlay.visible = false

	var pause_bg := ColorRect.new()
	pause_bg.color = Color(0.0, 0.0, 0.0, 0.6)
	pause_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(pause_bg)

	var pause_label := Label.new()
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_color_override("font_color", Color.WHITE)
	pause_label.add_theme_font_size_override("font_size", 48)
	pause_label.text = "PAUSED"
	pause_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_label.position = Vector2(0, -40)
	_pause_overlay.add_child(pause_label)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.add_theme_font_size_override("font_size", 24)
	resume_btn.position = view * 0.5 - Vector2(60, 10)
	resume_btn.size = Vector2(120, 40)
	resume_btn.pressed.connect(_resume_game)
	_pause_overlay.add_child(resume_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit to Title"
	quit_btn.add_theme_font_size_override("font_size", 20)
	quit_btn.position = view * 0.5 + Vector2(-60, 40)
	quit_btn.size = Vector2(120, 36)
	quit_btn.pressed.connect(_quit_to_title)
	_pause_overlay.add_child(quit_btn)

	add_child(_pause_overlay)


func _start_countdown() -> void:
	if not _countdown_label or not _car:
		return

	# Track car state changes to detect if the player ever spins.
	if _car.has_signal("state_changed"):
		if not _car.state_changed.is_connected(_on_car_state_changed):
			_car.state_changed.connect(_on_car_state_changed)

	_countdown_label.text = ""
	await get_tree().create_timer(0.5).timeout

	for text in COUNTDOWN_TEXT:
		_countdown_label.text = text
		var delay := 0.8 if text != "GO!" else 0.5
		await get_tree().create_timer(delay).timeout

	_countdown_label.text = ""

	_race_started = true

	if is_instance_valid(_car):
		_car.start_race()
		_car.set("_input_locked", false)


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


func _update_lap_hud() -> void:
	if _lap_label:
		# Only show the lap counter on multi-lap levels (boss).
		if total_laps > 1:
			_lap_label.text = "Lap %d / %d" % [_lap, total_laps]
			_lap_label.visible = true
		else:
			_lap_label.visible = false
			_lap_label.text = ""


func _update_timer_hud() -> void:
	if _timer_label:
		var mins := int(_race_time) / 60
		var secs := int(_race_time) % 60
		var tenths := int(_race_time * 10) % 10
		_timer_label.text = "%d:%02d.%d" % [mins, secs, tenths]


# ---------------------------------------------------------------------------
# Procedural track generation
# ---------------------------------------------------------------------------

func _generate_track_curve(path: Path2D) -> void:
	var curve := Curve2D.new()
	var waypoints: Array[Dictionary] = _get_track_waypoints()
	for wp in waypoints:
		curve.add_point(wp.pos, wp.inside, wp.out)
	path.curve = curve


func _get_track_waypoints() -> Array[Dictionary]:
	match level_index:
		0:   return _track_oval()
		1:   return _track_s_curves()
		2:   return _track_loop()
		3:   return _track_oval()           # Boss 1 — same oval, 3 laps via total_laps
		4:   return _track_hairpin()
		5:   return _track_wavy()
		6:   return _track_figure8()
		7:   return _track_s_curves()       # Boss 2 — same S-curves
		_:   return _track_oval()


func _track_helper(pts: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pts:
		out.append({
			"pos": Vector2(p[0], p[1]),
			"inside": Vector2(p[2], p[3]),
			"out": Vector2(p[4], p[5]),
		})
	return out


## Convert a list of [x, y] positions into smooth waypoints.
## Computes IN/OUT control vectors so the curve is smooth and gentle,
## with control point lengths ~40% of the distance to adjacent points.
## `scale` multiplies all positions (to space them apart).
func _smooth_track(flat_positions: Array, scale := 1.0) -> Array[Dictionary]:
	var pts_count := flat_positions.size()
	if pts_count < 3:
		return []

	# Scale positions.
	var pos: Array[Vector2] = []
	for p in flat_positions:
		pos.append(Vector2(p[0], p[1]) * scale)

	var out: Array[Dictionary] = []
	for i in range(pts_count):
		var cur := pos[i]
		var prev := pos[(i - 1 + pts_count) % pts_count]
		var nxt := pos[(i + 1) % pts_count]

		var to_prev := (prev - cur)
		var to_next := (nxt - cur)
		var dist_prev := to_prev.length()
		var dist_next := to_next.length()

		# Control vectors: point toward adjacent points, ~40% of distance.
		var inside_vec := Vector2.ZERO
		var out_vec := Vector2.ZERO
		if dist_prev > 0.01:
			inside_vec = to_prev.normalized() * dist_prev * 0.4
		if dist_next > 0.01:
			out_vec = to_next.normalized() * dist_next * 0.4

		out.append({"pos": cur, "inside": inside_vec, "out": out_vec})
	return out


## Same as _smooth_track but accepts explicit control point override for
## specific waypoints.  `overrides` is a dict keyed by index:
##   { 2: {"inside": [x,y], "out": [x,y]}, ... }
func _smooth_track_with_overrides(flat_positions: Array, overrides: Dictionary, scale := 1.0) -> Array[Dictionary]:
	var result := _smooth_track(flat_positions, scale)
	for idx in overrides:
		if idx >= 0 and idx < result.size():
			var ov := overrides[idx] as Dictionary
			if ov.has("inside"):
				result[idx]["inside"] = Vector2(ov["inside"][0], ov["inside"][1])
			if ov.has("out"):
				result[idx]["out"] = Vector2(ov["out"][0], ov["out"][1])
	return result


# -- Track definitions (20 tracks, progressively harder) ------------------

func _track_oval() -> Array[Dictionary]:
	## User-smoothed oval with long control points.
	return _track_helper([
		[300, 500, -188, -10,  188,  10],
		[750, 500,  -91,  34,   91, -34],
		[950, 250,    7, 138,   -7, -138],
		[750,   0,  125,  11, -125, -11],
		[300,   0,  108, -45, -108,  45],
		[100, 250,   38,-101,  -38, 101],
	])


func _track_s_curves() -> Array[Dictionary]:
	return _smooth_track([
		[350, 350], [700, 350], [850, 280],
		[850, 170], [650, 130], [400, 130],
		[220, 180], [280, 320],
	])


func _track_loop() -> Array[Dictionary]:
	## Loop with a crossover.
	return _smooth_track([
		[400, 400], [650, 420], [800, 360],
		[780, 260], [600, 240], [400, 240],
		[250, 300], [280, 420], [450, 440],
	])


func _track_hairpin() -> Array[Dictionary]:
	return _smooth_track([
		[300, 450], [650, 470], [900, 420],
		[950, 260], [800, 150], [500, 140],
		[200, 160], [120, 300], [280, 420],
	])


func _track_wavy() -> Array[Dictionary]:
	return _smooth_track([
		[250, 400], [550, 420], [800, 420],
		[950, 360], [900, 220], [700, 180],
		[500, 180], [300, 220], [180, 300],
		[270, 380], [350, 410],
	])


func _track_figure8() -> Array[Dictionary]:
	return _smooth_track([
		[400, 420], [700, 420], [880, 340],
		[850, 200], [650, 200], [400, 200],
		[220, 280], [280, 380], [450, 420],
		[680, 400], [520, 400],
	])


func _track_chicane() -> Array[Dictionary]:
	## Alternating chicanes.
	return _smooth_track([
		[300, 400], [550, 420], [680, 360],
		[620, 260], [740, 220], [850, 300],
		[800, 400], [630, 410], [450, 400],
		[330, 390],
	])


func _track_serpentine() -> Array[Dictionary]:
	## Long winding snake.
	return _smooth_track([
		[250, 400], [500, 420], [620, 360],
		[560, 260], [680, 220], [800, 280],
		[840, 380], [740, 460], [580, 480],
		[420, 460], [320, 410],
	])


func _process(delta: float) -> void:
	# Camera target.
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
			var shake_offset := Vector2(
				randf_range(-_shake_strength, _shake_strength),
				randf_range(-_shake_strength, _shake_strength),
			)
			camera_target += shake_offset

	if _camera:
		_camera.global_position = camera_target

	# Race timer.
	if not _game_over and _race_started:
		_race_time += delta

	# Boss time limit check.
	if _boss_time_limit > 0.0 and not _game_over and _race_started:
		if _race_time >= _boss_time_limit:
			_game_over = true
			print("TIME LIMIT EXCEEDED — boss level lost!")
			_end_game()

	# -- Space hint ----------------------------------------------------
	# Show "Press SPACEBAR to run" when the race has started but the
	# player hasn't pressed accelerate for 2+ consecutive seconds.
	if not _game_over and _race_started and _car and is_instance_valid(_car):
		var accel = _car.get("_test_input_accelerate")
		if accel == false:
			_no_input_timer += delta
			if _space_hint_label:
				_space_hint_label.visible = _no_input_timer >= 2.0
		else:
			_no_input_timer = 0.0
			if _space_hint_label:
				_space_hint_label.visible = false

	# Boost bar.
	if _boost_bar_fill and is_instance_valid(_car):
		var se = _car.get("spin_energy")
		var bw = _boost_bar_bg.size.x
		_boost_bar_fill.size.x = bw * clampf(se if se != null else 0.0, 0.0, 1.0)

	# HUD updates.
	_update_timer_hud()
	_update_lap_hud()


# ---------------------------------------------------------------------------
# Win / Lose
# ---------------------------------------------------------------------------

func _on_wall_hit() -> void:
	if _game_over:
		return
	_game_over = true
	print("GAME OVER — wall hit!")

	if _has_spun:
		_end_game()
	else:
		_show_drift_hint_and_die()


func _show_drift_hint_and_die() -> void:
	## Show "Press A and D to drift" for 2 seconds, then show the
	## normal game-over popup.  Freeze the car during the delay.
	if _drift_hint_label:
		_drift_hint_label.visible = true

	# Freeze the car so it doesn't keep sliding.
	if _car and is_instance_valid(_car):
		_car.velocity = Vector2.ZERO
		_car.set("_input_locked", true)

	await get_tree().create_timer(2.0).timeout

	if _drift_hint_label:
		_drift_hint_label.visible = false

	_end_game()


func _on_goal_entered(body: Node) -> void:
	_on_finish_line_crossed(body)


func _on_finish_line_crossed(body: Node) -> void:
	if _game_over:
		return
	if body != _car:
		return
	if not _race_started:
		return  # ignore initial overlap (car spawns on finish line for closed loops)

	_lap += 1
	if _lap > total_laps:
		_game_over = true
		print("YOU WIN!  Time: %.1f s  Laps: %d" % [_race_time, total_laps])
		race_won.emit(level_index, _race_time)
		_show_race_result()
	else:
		print("Lap %d / %d — %.1f s" % [_lap, total_laps, _race_time])
		_update_lap_hud()


func _on_boost_applied(amount: float) -> void:
	var intensity := clampf(amount / 150.0, 2.0, 12.0)
	_shake_strength = maxf(_shake_strength, intensity)
	_shake_duration = 0.25


func _on_car_state_changed(new_state: int) -> void:
	## Track whether the car ever entered SPINNING state (for the drift hint).
	if new_state == 2:  # Car.CarMode.SPINNING
		_has_spun = true


func _end_game(reason: String = "crashed") -> void:
	## Called on wall hit or time limit loss.
	## Shows a game-over popup with Retry and Level Select buttons.
	if _car and is_instance_valid(_car):
		_car.queue_free()
		_car = null

	# In test mode, skip the popup (test uses its own detection).
	if _skip_nav_on_end:
		return

	var popup := preload("res://scenes/screens/game_over_popup.tscn").instantiate()
	popup.setup(level_index)
	popup.retry_level.connect(_on_result_retry)
	popup.go_to_level_select.connect(_on_result_level_select)
	add_child(popup)


func _show_race_result() -> void:
	## Show the race result overlay with medal times and navigation buttons.
	## Saves the record via GameState, then lets the player choose next action.
	var gs = _get_gamestate()
	if gs:
		gs.complete_level(level_index, _race_time)

		# Free the car.
		if _car and is_instance_valid(_car):
			_car.queue_free()
			_car = null

		# Build the result screen.
		var result := preload("res://scenes/screens/race_result.tscn").instantiate()
		var data: Dictionary = gs.LEVEL_DATA[level_index] if level_index < gs.LEVEL_COUNT else {}
		var bronze: float = data.get("bronze", INF)
		var silver: float = data.get("silver", INF)
		var gold: float = data.get("gold", INF)
		result.setup(level_index, _race_time, bronze, silver, gold)

		if _skip_nav_on_end:
			# Test mode — no result screen needed (test uses race_won signal).
			result.queue_free()
			return

		# Normal flow: connect buttons and add to scene.
		result.next_level.connect(_on_result_next)
		result.retry_level.connect(_on_result_retry)
		result.go_to_level_select.connect(_on_result_level_select)
		add_child(result)


func _on_result_next(level_idx: int) -> void:
	## "Next Level" button: advance to the next level.
	var gs = _get_gamestate()
	var max_levels: int = gs.LEVEL_COUNT if gs else 10
	var next := level_idx + 1
	if next >= max_levels:
		get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")
		return
	if gs:
		var scene_path: String = gs.get_level_scene(next)
		get_tree().change_scene_to_file(scene_path)


func _on_result_retry(level_idx: int) -> void:
	## "Improve Time" button: reload current level.
	var gs = _get_gamestate()
	if gs:
		var scene_path: String = gs.get_level_scene(level_idx)
		get_tree().change_scene_to_file(scene_path)


func _on_result_level_select() -> void:
	## "Level Select" button.
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")
