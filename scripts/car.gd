## Drift-lock car controller — CharacterBody2D with a node‑based
## finite‑state machine (StoppedState / AccelerateState / SpinState).
class_name Car
extends CharacterBody2D

## Renamed to CarMode to avoid clashing with class_name State from state.gd.
enum CarMode { STOPPED, ACCELERATE, SPINNING }

## Backward‑compatible numeric state — derived from the FSM state name.
var car_state: CarMode = CarMode.STOPPED:
	set(v):
		car_state = v
		state_changed.emit(v)
var spin_direction: int = 0
var spin_angular_velocity: float = 0.0   # rad/s
var spin_timer: float = 0.0              # seconds spent in current spin
var _accumulated_spin_rotation: float = 0.0  # total rad rotated this spin
var accelerate_timer: float = 0.0        # seconds spent in current accelerate
var current_speed: float = 0.0
var spin_energy: float = 0.0            # normalised 0–1 for UI

# ── Spin stuck timeout ──────────────────────────────────────────────
## If the car is SPINNING at very low speed for this many consecutive
## seconds, force-exit to prevent getting permanently stuck against a wall.
const SPIN_STUCK_TIMEOUT: float = 3.0
const SPIN_STUCK_SPEED: float = 25.0
var _spin_stuck_timer: float = 0.0
## Brief grace after force-exit to prevent AI from instantly re-entering spin.
var _stuck_recovery_timer: float = 0.0

var _last_boost: float = 0.0            # most recent boost amount (for FX)
var _boost_flash_timer: float = 0.0     # seconds remaining of boost flash

# ── Combo system ─────────────────────────────────────────────────────────
## Consecutive spins within the grace window increase the combo counter,
## which multiplies the exit boost.  Grace timer counts down during
## ACCELERATE state; if it reaches 0 the combo resets.
var _combo_count: int = 0
var _combo_timer: float = 0.0

const COMBO_GRACE_PERIOD: float = 2.0   # seconds
const COMBO_BOOST_PER_STEP: float = 0.5 # boost × per extra combo level
const COMBO_MAX: int = 5                # cap combo at 5 → 3.0× boost

var _test_input_left: bool = false
var _test_input_right: bool = false
var _test_input_accelerate: bool = false
var _accept_keyboard_input: bool = true
var _input_locked: bool = false  # blocks keyboard input (used by countdown)
var _PP = preload("res://resources/physics_params.gd")
var _local_params: Resource = null
var _track_builder: Node = null  # set by level_base after spawn
var _state_machine: Node = null  # set in _ready()

# Particle FX nodes.
var _spin_dust: GPUParticles2D = null
var _boost_trail: GPUParticles2D = null

# Audio.
var _engine_player: AudioStreamPlayer2D = null

signal state_changed(new_state: CarMode)
signal wall_hit()
signal boost_applied(amount: float)
signal combo_changed(count: int)


func _g(p: Resource, key: String, default = null):
	if p == null:
		return default
	var v = p.get(key)
	return v if v != null else default


func _ready() -> void:
	_ensure_params()
	_sync_keyboard_flag()
	_setup_particles()
	_setup_audio()
	add_to_group("car")

	# Initialise the node‑based FSM (child node in car.tscn).
	_state_machine = get_node_or_null("StateMachine")
	if not _state_machine:
		push_warning("car.gd: no StateMachine child node — FSM disabled")


func _ensure_params() -> void:
	var gs = _singleton()
	if gs != null:
		if gs.get("physics_params") == null:
			gs.set("physics_params", _PP.new())
	else:
		if _local_params == null:
			_local_params = _PP.new()


func _sync_keyboard_flag() -> void:
	var gs = _singleton()
	if gs != null:
		_accept_keyboard_input = gs.get("accept_keyboard_input")


func _setup_particles() -> void:
	## Create spin‑dust and boost‑trail GPU particle emitters as children.
	# ── Spin dust: emitted from rear while spinning ────────────────
	var dust := GPUParticles2D.new()
	dust.name = "SpinDust"
	dust.amount = 24
	dust.lifetime = 0.4
	dust.preprocess = 0.0
	dust.one_shot = false
	dust.emitting = false
	dust.local_coords = true

	var dust_mat := ParticleProcessMaterial.new()
	dust_mat.direction = Vector3(0.0, 1.0, 0.0)   # backward in car-local
	dust_mat.spread = 60.0
	dust_mat.initial_velocity = Vector2(20.0, 60.0)
	dust_mat.angular_velocity = Vector2(0.0, 120.0)
	dust_mat.scale_min = 2.0
	dust_mat.scale_max = 5.0
	dust_mat.color = Color(0.55, 0.45, 0.35, 0.5)  # brownish dust
	dust_mat.gravity = Vector3.ZERO
	dust.process_material = dust_mat

	dust.position = Vector2(-18.0, 0.0)  # rear of car
	add_child(dust)
	_spin_dust = dust

	# ── Boost trail: burst of flame on boost application ───────────
	var trail := GPUParticles2D.new()
	trail.name = "BoostTrail"
	trail.amount = 16
	trail.lifetime = 0.25
	trail.preprocess = 0.0
	trail.one_shot = true   # burst on each boost
	trail.emitting = false
	trail.local_coords = true

	var trail_mat := ParticleProcessMaterial.new()
	trail_mat.direction = Vector3(0.0, 1.0, 0.0)
	trail_mat.spread = 30.0
	trail_mat.initial_velocity = Vector2(80.0, 160.0)
	trail_mat.scale_min = 3.0
	trail_mat.scale_max = 8.0
	trail_mat.color = Color(1.0, 0.5, 0.0, 0.7)  # orange flame
	trail_mat.gravity = Vector3.ZERO
	trail.process_material = trail_mat

	trail.position = Vector2(-18.0, 0.0)  # rear of car
	add_child(trail)
	_boost_trail = trail


func _setup_audio() -> void:
	## Set up the continuous engine‑hum AudioStreamPlayer2D.
	if not Engine.has_singleton("SoundManager"):
		return
	var sm = Engine.get_singleton("SoundManager")
	if not sm or not sm.has_method("get_sfx_stream"):
		return
	var stream: AudioStreamWAV = sm.get_sfx_stream("engine_loop") as AudioStreamWAV
	if stream == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.name = "EngineSound"
	p.stream = stream
	p.bus = "Master"
	p.max_distance = 600.0
	p.volume_db = -12.0  # comfortable background level
	p.play()
	add_child(p)
	_engine_player = p


## Safe GameState singleton accessor — returns null if not registered.
## Returns the GameState singleton or null.
## Tries Engine singleton first (for test environments), then falls back
## to tree lookup (for Godot 4.5.2 where the autoload * prefix may not
## register the Engine singleton properly).
func _singleton():
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	var tree := get_tree()
	if tree:
		return tree.root.get_node_or_null("GameState")
	return null


func P() -> Resource:
	var gs = _singleton()
	if gs != null:
		if gs.get("physics_params") == null:
			gs.set("physics_params", _PP.new())
		return gs.get("physics_params")
	if _local_params == null:
		_local_params = _PP.new()
	return _local_params


func _physics_process(delta: float) -> void:
	var p = P()
	if p == null:
		return

	# Do nothing while countdown runs.
	if _input_locked:
		queue_redraw()
		return

	# Delegate to the state machine (drives the active state).
	if _state_machine:
		_state_machine.physics_update(delta)

	move_and_slide()

	# Air drag: F_drag = air_drag × v² opposes motion every frame.
	var speed = velocity.length()
	if speed > 0.0:
		var drag_force: float = _g(p, "air_drag", 0.4) * speed * speed
		var drag_accel: float = drag_force / _g(p, "car_mass", 1000.0)
		velocity -= velocity.normalized() * drag_accel * delta

	current_speed = velocity.length()

	# Normalised spin energy (0–1) for UI / visual feedback.
	spin_energy = clampf(spin_angular_velocity / 80.0, 0.0, 1.0)

	# Combo grace timer — ticks down during ACCELERATE, resets combo on expiry.
	# (CarState states manage combo start/chain; this handles expiry.)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo_timer = 0.0
			_combo_count = 0
			combo_changed.emit(0)

	if _boost_flash_timer > 0.0:
		_boost_flash_timer -= delta

	# Stuck-recovery grace timer.
	if _stuck_recovery_timer > 0.0:
		_stuck_recovery_timer -= delta

	# Sync backward‑compat car_state from the active state name.
	if _state_machine and _state_machine.state:
		var sn: String = _state_machine.state.name
		var new_state: CarMode
		match sn:
			"StoppedState":   new_state = CarMode.STOPPED
			"AccelerateState": new_state = CarMode.ACCELERATE
			"SpinState":       new_state = CarMode.SPINNING
			_:                 new_state = CarMode.STOPPED
		if car_state != new_state:
			car_state = new_state  # setter emits state_changed

	if get_last_slide_collision():
		var col := get_last_slide_collision()
		if col.get_collider() is StaticBody2D:
			if _g(p, "wall_bounce", false):
				var rest = _g(p, "wall_bounce_restitution", 0.3)
				velocity = velocity.bounce(col.get_normal()) * rest
			else:
				emit_signal("wall_hit")

	queue_redraw()


func start_race() -> void:
	## Called after countdown.  Car enters STOPPED state — waits for
	## Space / test_input_accelerate before moving.
	if _state_machine and _state_machine.has_method("transition_to"):
		_state_machine.transition_to("StoppedState")
	velocity = Vector2.ZERO
	current_speed = 0.0
	_test_input_accelerate = false
	car_state = CarMode.STOPPED


## Apply a direct boost to forward velocity (used by enemies, powerups).
func apply_boost(amount: float) -> void:
	var fwd := Vector2.RIGHT.rotated(global_rotation)
	velocity += fwd * amount
	_last_boost = amount
	_boost_flash_timer = 0.2
	boost_applied.emit(amount)
	if _boost_trail:
		_boost_trail.emitting = true


func reset(pos: Vector2, rot: float) -> void:
	if _state_machine and _state_machine.has_method("transition_to"):
		_state_machine.transition_to("AccelerateState")
	spin_direction = 0
	spin_angular_velocity = 0.0
	spin_timer = 0.0
	velocity = Vector2.ZERO
	_test_input_left = false
	_test_input_right = false
	global_position = pos
	global_rotation = rot
	car_state = CarMode.ACCELERATE


func set_test_input(left: bool, right: bool, accelerate: bool = true) -> void:
	_test_input_left = left
	_test_input_right = right
	_test_input_accelerate = accelerate


## Force the car into spin state (used by test / external triggers).
func force_spin(direction: int, angular_velocity: float) -> void:
	if _state_machine and _state_machine.has_method("transition_to"):
		_state_machine.transition_to("SpinState", {
			"direction": direction,
			"angular_velocity": angular_velocity
		})
	spin_direction = direction
	spin_angular_velocity = angular_velocity


func _draw() -> void:
	var p = P()
	var dw = _g(p, "car_draw_width", 40.0) if p else 40.0
	var dh = _g(p, "car_draw_height", 24.0) if p else 24.0

	var rect := Rect2(-dw/2, -dh/2, dw, dh)

	# Shadow below the car (dark ellipse, slightly offset).
	var shadow_offset := Vector2(0.0, 3.0)
	var shadow_radius := Vector2(dw * 0.45, dh * 0.35)
	# Approximate ellipse with a 16‑vertex polygon.
	var shadow_poly := PackedVector2Array()
	var segs := 16
	for k in range(segs):
		var ang := TAU * k / segs
		shadow_poly.append(shadow_offset + Vector2(cos(ang) * shadow_radius.x, sin(ang) * shadow_radius.y))
	draw_colored_polygon(shadow_poly, Color(0.0, 0.0, 0.0, 0.25))

	# Body colour: white at rest, yellow→orange→red as spin energy builds.
	var body_color := Color.WHITE
	if spin_energy > 0.0:
		var e := spin_energy
		body_color = Color(1.0, 1.0 - e * 0.6, 1.0 - e * 0.8)  # white → red

	# Boost flash overrides everything.
	if _boost_flash_timer > 0.0:
		body_color = Color(1.0, 1.0, 0.6)  # bright yellow flash

	draw_rect(rect, body_color)

	var tip = Vector2(dw/2 + 2, 0)
	var l = Vector2(dw/2 - 6, -dh/4)
	var r = Vector2(dw/2 - 6, dh/4)
	draw_colored_polygon(PackedVector2Array([tip, l, r]), Color(0.85, 0.85, 0.85))

	# Spin border: red outline while spinning, intensity matches energy.
	if car_state == CarMode.SPINNING:
		var border := Color(1.0, 1.0 - spin_energy, 1.0 - spin_energy)
		draw_rect(rect, border, false, 2.0)


# ═════════════════════════════════════════════════════════════════════════
# Powerup methods (called from pickups)
# ═════════════════════════════════════════════════════════════════════════

# (no powerups in the current build)
