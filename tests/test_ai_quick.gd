## Quick AI debug test — runs level 01 with DriverAI for 600 frames
extends Node2D

const DriverAIScript = preload("res://tests/driver_ai.gd")

var _level: Node = null
var _car: Node = null
var _track_path: Node = null
var _curve: Curve2D = null
var _ai = null
var _frames: int = 0
var _countdown_finished: bool = false
var _countdown_saw_lock: bool = false


func _ready() -> void:
	_setup_game_state()
	var scene := load("res://scenes/levels/level_01.tscn") as PackedScene
	_level = scene.instantiate()
	_level.set("total_laps", 1)
	add_child(_level)


func _setup_game_state() -> void:
	if not Engine.has_singleton("GameState"):
		var gs := Node.new()
		gs.set_script(preload("res://autoload/game_state.gd"))
		var p := preload("res://resources/physics_params.gd").new()
		p.set("wall_bounce", true)
		p.set("wall_bounce_restitution", 0.4)
		p.set("min_accelerate_time", 0.0)
		gs.set("physics_params", p)
		gs.set("accept_keyboard_input", false)
		Engine.register_singleton("GameState", gs)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames > 600:
		print("=== TIMEOUT after 600 frames — AI did not complete ===")
		get_tree().quit()
		return

	if _track_path == null:
		_detect_level()
		return

	if not _countdown_finished:
		if _car == null:
			_detect_level()
			return
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			print("Countdown finished — AI driving...")
		return

	if _ai != null:
		_ai.process(_delta)

	if _car == null or not is_instance_valid(_car):
		print("=== AI COMPLETED THE LEVEL! ===")
		get_tree().quit()
		return

	if _frames % 60 == 0:
		var speed = _car.get("current_speed")
		var pos = _car.get("global_position")
		var car_state = _car.get("car_state")
		var state_name: String
		match int(car_state):
			0: state_name = "STOP"
			1: state_name = "ACCEL"
			2: state_name = "SPIN"
		print("t=%3d pos=(%5.0f,%5.0f) speed=%4.0f ai_state=%s car_state=%s  %s" % [
			_frames, pos.x, pos.y, speed,
			["START","COAST","L","R","RECOV"][_ai.state],
			state_name,
			"" if _frames < 300 else "<<< STILL GOING"
		])


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
	print("Level ready — curve len=%.0f" % _curve.get_baked_length())
	_ai = DriverAIScript.new()
	_ai.setup(_car, _track_path)
