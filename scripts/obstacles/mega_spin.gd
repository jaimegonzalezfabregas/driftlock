## Mega Spin powerup — temporary super spin efficiency.
##
## While active, rotation_efficiency is multiplied by `efficiency_mult`
## and spin_min_rotations is reduced, making spins more powerful and
## shorter.  The effect lasts `duration` seconds.
extends Area2D

## How long the mega spin effect lasts (seconds).
@export var duration: float = 5.0

## Multiplier applied to rotation_efficiency while active.
@export var efficiency_mult: float = 3.0

## Angular velocity applied when mega spin triggers.
@export var spin_force: float = 60.0

## Visual rotation speed (floating).
@export var float_speed: float = 3.0


func _ready() -> void:
	# Collision shape.
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	# Visual: golden star-like indicator.
	var vis := ColorRect.new()
	vis.name = "MegaSpinVisual"
	vis.size = Vector2(24, 24)
	vis.color = Color(1.0, 0.8, 0.0, 0.9)
	vis.position = -vis.size * 0.5
	add_child(vis)

	add_to_group("powerup")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	var vis := get_node_or_null("MegaSpinVisual") as ColorRect
	if vis:
		vis.rotation += float_speed * delta


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		if body.has_method("activate_mega_spin"):
			body.activate_mega_spin(duration, efficiency_mult, spin_force)
			queue_free()
