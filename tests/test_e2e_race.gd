## End‑to‑end race test — human‑like driving.
##
## Loads a level directly, waits for the countdown, then drives the car
## around the track using **short steering bursts** — holds the turn key
## long enough to face the target, then releases.  This simulates how a
## player flicks the stick through a corner and lets go.
##
## The test monitors total rotation per key press and **fails** if the car
## spins more than 2 full rotations (4π rad) during a single press,
## signalling that the physics still need tuning.
##
## Handles any level that uses a TrackBuilder with a valid Curve2D.
##
## Usage:
##   godot --headless --path . tests/test_e2e_race.tscn
##   or set a custom level:
##   godot --headless --path . tests/test_e2e_race.tscn -- level_path="res://scenes/levels/level_01.tscn"
extends Node2D

const MAX_FRAMES := 7200          # 2 minutes at 60 fps
const LOG_INTERVAL := 60          # log car state every 60 frames (1 s)
const LOOK_AHEAD := 100.0         # look‑ahead distance for pure pursuit (px)
const DEFAULT_LEVEL := "res://scenes/levels/level_01.tscn"

# ── Driving parameters ─────────────────────────────────────────────────
## When angle between car forward and the look‑ahead target (rad) drops
## below this, release the steer key — the car is facing the target.
const PARALLEL_THRESHOLD := 0.25   # ~14°

# ── Rotation limit ─────────────────────────────────────────────────────
const MAX_ROTATION_PER_PRESS := TAU * 2  # 2 full turns (4π rad)

const SEPARATOR := "============================================================"

enum FinishReason { NONE, WIN, TIMEOUT, SPIN_FAIL }

var _finish_reason: int = FinishReason.NONE
var _frames := 0
var _level: Node = null
var _car: Node = null
var _track_path: Path2D = null
var _curve: Curve2D = null
var _peek_speed := 0.0
var _countdown_finished := false
var _countdown_saw_lock := false  # true after first seeing _input_locked == true

# ── Steering state ─────────────────────────────────────────────────────
var _steering_left: bool = false     # currently holding which direction
var _steering_active: bool = false   # currently in a steer hold
var _coast_timer: int = 0           # frames to coast after releasing steer

# ── Spin rotation monitoring ───────────────────────────────────────────
var _in_spin: bool = false
var _spin_accumulated_rotation: float = 0.0

# ── Track progress ────────────────────────────────────────────────────
var _max_progress: float = 0.0         # furthest offset fraction [0, 1)
var _track_length: float = 0.0         # baked curve length (px)


func _ready() -> void:
	_log(SEPARATOR)
	_log("E2E RACE TEST — Human‑like drive (hold turn, release, cooldown)")
	_log(SEPARATOR)

	# ── 1. Ensure GameState singleton exists ─────────────────────
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

	# ── 2. Pick which level to test ──────────────────────────────
	var level_path := DEFAULT_LEVEL
	for arg in OS.get_cmdline_args():
		if arg.begins_with("level_path="):
			level_path = arg.trim_prefix("level_path=")
			break

	_log("Loading level: %s" % level_path)

	# ── 3. Load and instantiate the level ────────────────────────
	var level_scene := load(level_path) as PackedScene
	assert(level_scene != null, "Level scene loads as PackedScene")

	_level = level_scene.instantiate()
	_level.set("total_laps", 1)

	add_child(_level)
	_log("Level instantiated and added to scene tree (total_laps = 1).")


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

	# ── Detect subsystems (level ready) ─────────────────────────
	if _track_path == null:
		_detect_level()
		return

	# ── Wait for countdown to finish ───────────────────────────
	if not _countdown_finished:
		var locked = _car.get("_input_locked")
		if locked == true:
			_countdown_saw_lock = true
		elif locked == false and _countdown_saw_lock:
			_countdown_finished = true
			_log("Countdown finished — race started.\n")
		return

	# ── Track spin rotation (fail if > 2 turns per press) ──────
	_track_spin_rotation(delta)

	# ── Drive the car (steering bursts) ─────────────────────────
	_drive()

	# ── Check for win ──────────────────────────────────────────
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
# Pure‑pursuit driving — aim for a point ahead on the centerline.  This
# naturally follows track curves and corrects offset without needing
# separate offset/curvature triggers.
# ═════════════════════════════════════════════════════════════════════════

func _drive() -> void:
	if _car == null or _curve == null:
		return

	var car_pos: Vector2 = _car.get("global_position")
	var car_rot: float = _car.get("global_rotation")
	var forward: Vector2 = Vector2.RIGHT.rotated(car_rot)
	var local_pos: Vector2 = _track_path.to_local(car_pos)
	var speed: float = _car.get("current_speed") as float

	# ── Nearest track centreline point ────────────────────────────
	var nearest_ofs: float = _curve.get_closest_offset(local_pos)
	var total_length: float = _curve.get_baked_length()

	# ── Look‑ahead point on the centreline ────────────────────────
	var look_dist: float = maxf(200.0, speed * 2.0)  # 2 s ahead, at least 200 px
	var ahead_ofs: float = nearest_ofs + look_dist
	if ahead_ofs > total_length:
		ahead_ofs -= total_length  # wrap for closed circuit

	var ahead_xf: Transform2D = _curve.sample_baked_with_rotation(ahead_ofs) as Transform2D
	var ahead_global: Vector2 = _track_path.to_global(ahead_xf.origin)
	var to_target: Vector2 = (ahead_global - car_pos).normalized()
	var angle_to_target: float = forward.angle_to(to_target)

	# ── Read car spin state ───────────────────────────────────────
	# NOTE: _accumulated_spin_rotation is 0 when not spinning, grows
	# while SPINNING.  spin_min_rotations is not a car property — it
	# lives in PhysicsParams — so we use the same constant here.
	var acc_rot_v = _car.get("_accumulated_spin_rotation")
	var acc_rot: float = acc_rot_v if typeof(acc_rot_v) == TYPE_FLOAT else 0.0
	var min_rot: float = TAU  # must match spin_min_rotations default

	# ── Decrement coast timer ────────────────────────────────────
	if _coast_timer > 0:
		_coast_timer -= 1

	# ── Steering state machine ────────────────────────────────────
	if _steering_active:
		# Holding spin — check if we can release.
		var can_release: bool = acc_rot >= min_rot
		var facing_target: bool = abs(angle_to_target) < PARALLEL_THRESHOLD
		if can_release and facing_target:
			_steering_active = false
			_car.set_test_input(false, false)
			_coast_timer = 8  # ~0.13 s cooldown
	else:
		# Not steering — coast timer must be 0, and angle must be significant.
		if _coast_timer == 0 and abs(angle_to_target) > PARALLEL_THRESHOLD:
			_steering_active = true
			_steering_left = (angle_to_target > 0)

	# ── Apply input for current frame ────────────────────────────
	if _steering_active:
		_car.set_test_input(_steering_left, not _steering_left)
	else:
		_car.set_test_input(false, false)

	# ── Track progress ──────────────────────────────────────────
	# Normalised progress around the closed circuit [0, 1).
	var prog: float = nearest_ofs / total_length
	if prog > _max_progress:
		_max_progress = prog

	# ── Track peak speed ───────────────────────────────────────
	var s = _car.get("current_speed")
	if typeof(s) == TYPE_FLOAT and s > _peek_speed:
		_peek_speed = s


# ═════════════════════════════════════════════════════════════════════════
# Spin rotation monitoring — fail if > 2 full turns per key press
# ═════════════════════════════════════════════════════════════════════════

func _track_spin_rotation(delta: float) -> void:
	if _car == null:
		return

	var state = _car.get("car_state")
	var ang_vel = _car.get("spin_angular_velocity")

	if state == 1:  # SPINNING
		if not _in_spin:
			# Entering a spin — reset accumulator.
			_in_spin = true
			_spin_accumulated_rotation = 0.0

		# Accumulate rotation this frame: |ω| × Δt
		_spin_accumulated_rotation += abs(ang_vel) * delta

	else:  # ACCELERATE
		if _in_spin:
			# Exiting a spin — check limit.
			if _spin_accumulated_rotation > MAX_ROTATION_PER_PRESS:
				_log("SPIN FAIL: %.1f rad (%.0f°) in one press — exceeds 2-turn limit (%.1f rad)" %
					[_spin_accumulated_rotation, rad_to_deg(_spin_accumulated_rotation),
					 MAX_ROTATION_PER_PRESS])
				_finish_reason = FinishReason.SPIN_FAIL
				_print_summary()
				print("TEST FAILED — Car spun more than 2 rotations per key press (%.1f rad)" %
					_spin_accumulated_rotation)
				get_tree().quit()
			_in_spin = false


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

	_track_length = _curve.get_baked_length()

	_car = _level.get_node_or_null("Car")
	if _car == null:
		return

	_car.set("_accept_keyboard_input", false)
	_log("Level '%s' ready — car found." % _level.name)
	_log("Curve baked length: %.0f px" % _curve.get_baked_length())
	# Reset countdown tracking — wait for _input_locked true → false.
	_countdown_finished = false
	_countdown_saw_lock = false


func _log_car_state() -> void:
	if _car == null:
		return
	var pos = _car.get("global_position")
	var speed = _car.get("current_speed")
	var state = _car.get("car_state")
	var state_name = "ACCEL" if state == 0 else "SPIN"
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
			var prog_pct := _max_progress * 100.0
			_log("RESULT: TIMEOUT after %d frames (%.1f s) — progress %.1f%%" %
				[MAX_FRAMES, MAX_FRAMES / 60.0, prog_pct])
		FinishReason.SPIN_FAIL:
			_log("RESULT: SPIN FAIL — Car rotated > 2 turns per key press")
		_:
			_log("RESULT: UNKNOWN")
	_log("Peak speed: %.0f px/s" % _peek_speed)
	_log(SEPARATOR)

	if _finish_reason == FinishReason.WIN:
		print("ALL ASSERTIONS PASSED — E2E RACE WIN")
	else:
		print("TEST FAILED — Car did not reach goal")


func _log(msg: String) -> void:
	print(msg)
