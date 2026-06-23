## Unified Physics Parameters Resource
extends Resource

# ── Power / Energy ───────────────────────────────────────────────────────
## Engine power (W).  Kinetic energy increases by P·Δt each frame.
## Acceleration naturally decreases with speed: v = sqrt(2·E/m).
## Higher values = faster acceleration at all speeds.
@export var engine_power: float = 200_000_000.0

## Car mass (arbitrary units).  Higher mass = slower acceleration from same power.
@export var car_mass: float = 1000.0

## Air drag coefficient.  Drag force = air_drag × v² opposes motion every
## frame, creating a natural top speed: v_top = (engine_power / air_drag)^⅓.
## Higher values = lower top speed and more noticeable deceleration when
## coasting.
@export var air_drag: float = 0.4

# ── Spin ──────────────────────────────────────────────────────────────────
## Angular mass (moment of inertia, arbitrary units).  Higher values make
## the car harder to spin (more rotational KE needed for the same angular
## velocity).  Roughly analogous to `car_mass` but for rotation.
@export var angular_mass: float = 5000000.0

## Angular‑velocity multiplier per 60‑FPS physics tick while spinning
## (0.0 – 1.0).  The spin speed is set once on entry via kinetic‑energy
## transfer (linear KE → rotational KE), then dragged each frame.
@export var spin_drag: float = 0.97

## Minimum spin duration (seconds).  The car spins for at least this long
## after entering a spin, even if the turn key is released early.
@export var spin_min_time: float = 0.2

## Uniform velocity multiplier per 60‑FPS physics tick during spin
## (0.0 – 1.0).  Drag is equal in all directions so the car slides
## in a straight line while spinning.  Sideways grip only engages
## when the turn key is released (spin exit).
@export var spin_velocity_drag: float = 0.97

## Fraction of current linear kinetic energy converted to rotational
## kinetic energy each physics frame during a spin.  0.03 = 3 % per frame.
## Linear energy is depleted by this amount, so the car slows down.
@export var rotation_efficiency: float = 0.08

# ── Speed floors ──────────────────────────────────────────────────────────

@export var min_linear_speed: float = 10

@export var min_spin_rate: float = 0.5

# ── Car shape ─────────────────────────────────────────────────────────────
## Collision shape width (px).
@export var car_width: float = 36.0

## Collision shape height (px).
@export var car_height: float = 20.0

## Visual draw width (px) — can differ from collision for prototyping feel.
@export var car_draw_width: float = 40.0

## Visual draw height (px).
@export var car_draw_height: float = 24.0

# ── Wall collision ────────────────────────────────────────────────────────
## If true, car bounces off walls instead of dying (test-friendly).
@export var wall_bounce: bool = true

## Bounce restitution when wall_bounce is true (0.0 = stop, 1.0 = full bounce).
@export var wall_bounce_restitution: float = 0.3
