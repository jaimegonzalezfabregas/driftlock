## Base class for all track levels.
##
## The TrackPath Path2D node (with the TrackBuilder script) builds
## collision edges in its own `_ready()`, which fires before this one
## (bottom‑up node lifecycle).  We read the start/end metadata from it,
## spawn the car, and place the goal.
class_name LevelBase
extends Node2D

const TRACK_WIDTH: float = 200.0
const SEGMENT_DISTANCE: float = 30.0
const GOAL_THICKNESS: float = 10.0

var _car: Node = null
var _game_over: bool = false
var _camera: Camera2D = null
var _hud_layer: CanvasLayer = null
var _boost_bar_bg: ColorRect = null
var _boost_bar_fill: ColorRect = null


func _ready() -> void:
	var path := $TrackPath as TrackBuilder
	assert(path != null, "TrackPath needs the TrackBuilder script")
	assert(path.curve != null, "TrackPath needs a curve defined in the editor")

	# TrackBuilder._ready() already built the collision and set these.
	var start_pos := path.start_pos
	var start_dir := path.start_dir
	var end_pos := path.end_pos
	var end_dir := path.end_dir

	_level_specific_setup(path.curve)
	_spawn_car(start_pos, start_dir.angle())
	_setup_camera()
	_build_goal(end_pos, end_dir)
	_setup_hud()
	# Defer goal activation so body_entered doesn't fire on car overlap
	# when start and finish are on the same straight section.
	call_deferred("_activate_goal")

	if _car:
		_car.start_race()


## Virtual hook — override in subclasses to add obstacles, etc.
func _level_specific_setup(_curve: Curve2D) -> void:
	pass


# ---------------------------------------------------------------------------
# Track construction helpers
# ---------------------------------------------------------------------------

func _build_goal(pos: Vector2, dir: Vector2) -> void:
	var goal := Area2D.new()
	goal.name = "GoalArea"
	goal.global_position = pos
	goal.rotation = dir.angle()
	# monitoring starts false — _activate_goal enables it one frame later
	# to prevent false "YOU WIN" if the car spawns overlapping the goal area.
	goal.monitoring = false

	var shape := RectangleShape2D.new()
	shape.size = Vector2(GOAL_THICKNESS, TRACK_WIDTH)

	var col := CollisionShape2D.new()
	col.shape = shape
	goal.add_child(col)

	add_child(goal)


func _activate_goal() -> void:
	var goal := $GoalArea as Area2D
	if not goal:
		return
	goal.monitoring = true
	goal.body_entered.connect(_on_goal_entered)


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


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _car and _camera:
		# Camera sits ahead of the car in the direction the car FACES
		# (global_rotation = sprite direction), not the velocity direction.
		# This lets the player see the road ahead during slides / spins.
		var car := _car as Node2D
		var forward := Vector2.RIGHT.rotated(car.global_rotation)

		const LOOK_AHEAD := -30.0
		_camera.global_position = car.global_position + forward * LOOK_AHEAD

	# Boost bar — read spin_energy from the car (0–1).
	if _boost_bar_fill and is_instance_valid(_car):
		var se: float = _car.get("spin_energy") if _car.has_method("get") else 0.0
		var bw = _boost_bar_bg.size.x
		_boost_bar_fill.size.x = bw * clampf(se, 0.0, 1.0)


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
	if _game_over:
		return
	if body == _car:
		_game_over = true
		print("YOU WIN!")
		_end_game()


func _end_game() -> void:
	if _car and is_instance_valid(_car):
		_car.queue_free()
		_car = null
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/screens/title_screen.tscn")
