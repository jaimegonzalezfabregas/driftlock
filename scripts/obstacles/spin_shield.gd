## Spin Shield powerup — collectible item.
## When the car picks it up, it grants a "shield" that absorbs the next
## wall hit.  Instead of dying/bouncing, the car enters a spin with bonus
## angular velocity.
extends Area2D

## Angular velocity applied when the shield triggers on wall hit.
@export var spin_force: float = 30.0

## Visual rotation speed for the floating effect.
@export var float_speed: float = 2.0

var _floating: bool = true


func _ready() -> void:
	# Collision shape.
	var shape := CircleShape2D.new()
	shape.radius = 10.0
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	# Visual: blue shield icon.
	var vis := ColorRect.new()
	vis.name = "ShieldVisual"
	vis.size = Vector2(20, 20)
	vis.color = Color(0.2, 0.4, 1.0, 0.9)
	vis.position = -vis.size * 0.5
	add_child(vis)

	add_to_group("powerup")
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	if _floating:
		var vis := get_node_or_null("ShieldVisual") as ColorRect
		if vis:
			vis.rotation += float_speed * delta


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		if body.has_method("grant_shield"):
			body.grant_shield(spin_force)
			queue_free()
