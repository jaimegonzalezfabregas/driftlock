## Spin Mine — stationary hazard.  If the car hits it while NOT spinning,
## the car is forced into a spin.  If the car hits it WHILE spinning,
## the car gets a big boost.
extends Area2D

## Initial angular velocity when the mine forces a spin (rad/s).
@export var spin_force: float = 30.0

## Boost awarded when the car hits the mine while already spinning.
@export var hit_boost: float = 300.0

@export var spin_direction: int = 1


func _ready() -> void:
	# Collision shape.
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	# Visual: red circle with a spiral indicator.
	var vis := ColorRect.new()
	vis.name = "MineVisual"
	vis.size = Vector2(28, 28)
	vis.color = Color(1.0, 0.0, 0.0, 0.7)
	vis.position = -vis.size * 0.5
	add_child(vis)

	add_to_group("mine")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	var vis := get_node_or_null("MineVisual") as ColorRect
	if vis:
		vis.rotation += spin_direction * delta  # slow rotation


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		var car_state = body.get("car_state")
		if car_state == 1:  # SPINNING
			# Spin-through: big boost!
			if body.has_method("apply_boost"):
				body.apply_boost(hit_boost)
			# Destroy the mine.
			queue_free()
		else:
			# Force spin.
			if body.has_method("force_spin"):
				body.force_spin(spin_direction, spin_force)
			# Destroy the mine.
			queue_free()
