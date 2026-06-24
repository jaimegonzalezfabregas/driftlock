## Spin Boost Pad — drives over it while ACCELERATING to force-enter a spin.
##
## Emits `spin_triggered(amount)` when the car is forced into a spin.
extends Area2D

signal spin_triggered(amount: float)

@export var spin_force: float = 40.0  # initial angular velocity when pad triggers

var _car_ref: Node = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Visual: a coloured rectangle that fades in/out.
	var rect := ColorRect.new()
	rect.name = "PadVisual"
	rect.size = Vector2(80, 24)
	rect.color = Color(0.0, 0.8, 1.0, 0.4)
	rect.position = -rect.size * 0.5
	rect.material = null
	add_child(rect)

	# Outline for visibility.
	var outline := ColorRect.new()
	outline.name = "PadOutline"
	outline.size = Vector2(80, 24)
	outline.color = Color(0.0, 0.0, 0.0, 0.0)
	outline.position = -outline.size * 0.5
	outline.material = null
	add_child(outline)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(80, 24)
	collision.shape = shape
	add_child(collision)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		_car_ref = body
		_activate(body)


func _on_body_exited(body: Node) -> void:
	if body == _car_ref:
		_car_ref = null


func _activate(body: Node) -> void:
	## Force the car into spin state if it's ACCELERATING.
	if body.get("car_state") == 0:  # ACCELERATE
		if body.has_method("force_spin"):
			var dir = -1 if randf() > 0.5 else 1
			body.force_spin(dir, spin_force)
		# Signal for particle FX / audio.
		spin_triggered.emit(spin_force)
		# Brief visual pulse.
		var rect := get_node_or_null("PadVisual") as ColorRect
		if rect:
			rect.color = Color(1.0, 1.0, 1.0, 0.8)
			await get_tree().create_timer(0.15).timeout
			if is_instance_valid(rect):
				rect.color = Color(0.0, 0.8, 1.0, 0.4)
