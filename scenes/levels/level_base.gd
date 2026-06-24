## Base class for all track levels.
## Circuit‑style lap racing: the car completes N laps around the track
## by crossing the finish line.  On the final lap the race ends.
extends Node2D

const TRACK_WIDTH: float = 200.0
const SEGMENT_DISTANCE: float = 30.0
const GOAL_THICKNESS: float = 10.0
## Number of laps required to win the race.
@export var total_laps: int = 3
## Level index (0‑based).  Set per level in the scene or overridden by
## the level‑select system.
@export var level_index: int = 0

## Emitted when the race is won.  The level select screen listens for this
## to advance to the next level.
signal race_won(level_idx: int, time: float)

var _car: Node = null
var _game_over: bool = false
var _camera: Camera2D = null
var _hud_layer: CanvasLayer = null
var _boost_bar_bg: ColorRect = null
var _boost_bar_fill: ColorRect = null
var _combo_label: Label = null
var _lap_label: Label = null
var _timer_label: Label = null
var _level_label: Label = null
var _minimap: Control = null

var _countdown_label: Label = null

# Pause state.
var _pause_overlay: CanvasLayer = null
var _paused: bool = false

const MINIMAP_SIZE: float = 120.0
const COUNTDOWN_TEXT: Array[String] = ["3", "2", "1", "GO!"]

var _lap: int = 1               # current lap (1‑based)
var _race_time: float = 0.0     # elapsed seconds since start

# Camera shake state.
var _shake_strength: float = 0.0   # current shake amplitude (decays)
var _shake_duration: float = 0.0   # remaining shake time
var _shake_decay: float = 12.0     # decay rate (units/s)


func _ready() -> void:
	var path := $TrackPath
	assert(path != null, "TrackPath needs to be a Path2D")
	assert(path.curve != null, "TrackPath needs a curve defined in the editor")

	# TrackBuilder._ready() already built the collision and set these.
	var start_pos: Vector2 = path.start_pos
	var start_dir: Vector2 = path.start_dir
	var end_pos: Vector2 = path.end_pos
	var end_dir: Vector2 = path.end_dir

	_level_specific_setup(path.curve)
	_spawn_car(start_pos, start_dir.angle())
	_setup_camera()
	_build_finish_line(end_pos, end_dir)
	_setup_hud()

	if _car:
		_car.set("_input_locked", true)
		_start_countdown()
		# start_race() is called AFTER the countdown finishes.


## Virtual hook — override in subclasses to add obstacles, etc.
func _level_specific_setup(_curve: Curve2D) -> void:
	pass


# ---------------------------------------------------------------------------
# Track construction helpers
# ---------------------------------------------------------------------------

func _build_finish_line(pos: Vector2, dir: Vector2) -> void:
	## Place the finish‑line Area2D on the track.  Always active — no
	## deferred activation needed because the car spawns BEFORE the line
	## and drives AWAY from it initially, so body_entered only fires
	## after a full lap.
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
	# Give the car a reference to the TrackBuilder for spin‑zone queries.
	_car.set("_track_builder", $TrackPath)
	add_child(_car)


func _setup_camera() -> void:
	# Grass‑green background.
	RenderingServer.set_default_clear_color(Color(0.2, 0.5, 0.1))

	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 10.0
	add_child(_camera)


func _setup_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)

	var bar_w := 200.0
	var bar_h := 14.0
	var margin := 20.0
	var view := _hud_layer.get_viewport().get_visible_rect().size if _hud_layer.get_viewport() else Vector2(1152, 648)

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
	fill.color = Color(1.0, 0.6, 0.0, 0.9)  # orange
	_hud_layer.add_child(fill)
	_boost_bar_fill = fill

	# Combo label (top‑right).
	var cl := Label.new()
	cl.name = "ComboLabel"
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	cl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.0))
	cl.add_theme_font_size_override("font_size", 36)
	cl.position = Vector2(view.x - margin - 120, margin)
	cl.size = Vector2(120, 50)
	cl.text = ""
	_hud_layer.add_child(cl)
	_combo_label = cl

	# Connect car signals.
	if _car:
		if _car.has_signal("combo_changed"):
			_car.combo_changed.connect(_on_combo_changed)
		if _car.has_signal("boost_applied"):
			_car.boost_applied.connect(_on_boost_applied)

	# Lap counter (top‑left).
	var ll := Label.new()
	ll.name = "LapLabel"
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ll.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ll.add_theme_color_override("font_color", Color.WHITE)
	ll.add_theme_font_size_override("font_size", 28)
	ll.position = Vector2(margin, margin)
	ll.size = Vector2(160, 40)
	ll.text = ""
	_hud_layer.add_child(ll)
	_lap_label = ll

	# Timer (below lap counter).
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

	# Level indicator (bottom-left).
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

	# ── Minimap (bottom‑right) ──────────────────────────────────
	var mm_script := load("res://scripts/minimap.gd")
	var mm := mm_script.new() as Control
	mm.name = "Minimap"
	mm.size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	mm.position = Vector2(view.x - margin - MINIMAP_SIZE, view.y - margin - MINIMAP_SIZE)
	_hud_layer.add_child(mm)
	_minimap = mm

	var track_path := $TrackPath
	if track_path and track_path.curve:
		mm.set_track(track_path.curve, track_path.start_pos, track_path.end_pos)
	if _car:
		mm.set_car(_car)

	# ── Countdown label (centred, large) ─────────────────────────
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

	# ── Pause overlay (hidden initially) ─────────────────────────
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
	## Show 3 → 2 → 1 → GO! sequence, then unlock player input.
	if not _countdown_label or not _car:
		return

	_countdown_label.text = ""
	await get_tree().create_timer(0.5).timeout

	for text in COUNTDOWN_TEXT:
		_countdown_label.text = text
		var delay := 0.8 if text != "GO!" else 0.5
		await get_tree().create_timer(delay).timeout

	_countdown_label.text = ""

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
	_resume_game()  # unpause before leaving
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")


func _update_lap_hud() -> void:
	if _lap_label:
		_lap_label.text = "Lap %d / %d" % [_lap, total_laps]


func _update_timer_hud() -> void:
	if _timer_label:
		var mins := int(_race_time) / 60
		var secs := int(_race_time) % 60
		var tenths := int(_race_time * 10) % 10
		_timer_label.text = "%d:%02d.%d" % [mins, secs, tenths]


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Camera position (base look‑ahead).
	var camera_target: Vector2 = _camera.global_position if _camera else Vector2.ZERO
	if _car and is_instance_valid(_car) and _camera:
		var car := _car as Node2D
		var forward := Vector2.RIGHT.rotated(car.global_rotation)
		const LOOK_AHEAD := -30.0
		camera_target = car.global_position + forward * LOOK_AHEAD

	# Apply camera shake.
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
	if not _game_over:
		_race_time += delta

	# Boost bar — read spin_energy from the car (0–1).
	if _boost_bar_fill and is_instance_valid(_car):
		var se = _car.get("spin_energy")
		var bw = _boost_bar_bg.size.x
		_boost_bar_fill.size.x = bw * clampf(se if se != null else 0.0, 0.0, 1.0)

	# Lap / timer HUD.
	_update_timer_hud()
	_update_lap_hud()

	# Minimap — redraw every frame to track car position.
	if _minimap:
		_minimap.queue_redraw()


# ---------------------------------------------------------------------------
# Win / Lose
# ---------------------------------------------------------------------------

func _on_wall_hit() -> void:
	if _game_over:
		return
	_game_over = true
	print("GAME OVER — wall hit!")
	_end_game()


func _on_goal_entered(body: Node) -> void:
	## Legacy hook — kept for compatibility with tests that check the
	## signal exists.  Delegates to the lap‑based handler.
	_on_finish_line_crossed(body)


func _on_finish_line_crossed(body: Node) -> void:
	## Called when the car crosses the finish‑line Area2D.
	## Increments lap counter and either continues or ends the race.
	if _game_over:
		return
	if body != _car:
		return

	_lap += 1
	if _lap > total_laps:
		# Final lap completed — win!
		_game_over = true
		print("YOU WIN!  Time: %.1f s  Laps: %d" % [_race_time, total_laps])
		race_won.emit(level_index, _race_time)
		_end_game()
	else:
		print("Lap %d / %d — %.1f s" % [_lap, total_laps, _race_time])
		_update_lap_hud()


func _on_combo_changed(count: int) -> void:
	if not _combo_label:
		return
	if count > 1:
		_combo_label.text = "COMBO x%d" % count
		# Pulse effect: scale bounce on each increment.
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_BOUNCE)
		tween.tween_property(_combo_label, "scale", Vector2(1.3, 1.3), 0.1)
		tween.tween_property(_combo_label, "scale", Vector2(1.0, 1.0), 0.2)
	else:
		_combo_label.text = ""


func _on_boost_applied(amount: float) -> void:
	## Trigger camera shake proportional to boost strength.
	var intensity := clampf(amount / 150.0, 2.0, 12.0)
	_shake_strength = maxf(_shake_strength, intensity)
	_shake_duration = 0.25  # short burst


func _end_game() -> void:
	# Show win overlay briefly before transitioning.
	if _game_over and _lap > total_laps:
		_show_win_overlay()

	if _car and is_instance_valid(_car):
		_car.queue_free()
		_car = null
	await get_tree().create_timer(1.0).timeout
	if _game_over and _lap > total_laps:
		# Race won — go to level select with completion.
		if Engine.has_singleton("GameState"):
			var gs = Engine.get_singleton("GameState")
			gs.complete_level(level_index)
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")


func _show_win_overlay() -> void:
	if _hud_layer == null:
		return
	var overlay := CanvasLayer.new()
	overlay.layer = 30
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.5)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var label := Label.new()
	label.text = "RACE COMPLETE!"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	label.add_theme_font_size_override("font_size", 56)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(label)

	var time_label := Label.new()
	time_label.text = "Time: %.1f s" % _race_time
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.add_theme_color_override("font_color", Color.WHITE)
	time_label.add_theme_font_size_override("font_size", 28)
	time_label.position = Vector2(0, 60)
	time_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 60)
	overlay.add_child(time_label)

	_hud_layer.add_child(overlay)
