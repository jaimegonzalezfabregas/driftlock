## Spinner Enemy — moves along a path at constant speed, continuously
## spinning.  If the player collides with it while both are spinning,
## the player gets a boost.  If the player hits it while NOT spinning,
## the player bounces off.
extends Area2D

## Speed the enemy drifts along its path (px/s).
@export var patrol_speed: float = 120.0

## Angular velocity of the enemy's spin (rad/s).
@export var spin_speed: float = 8.0

## Boost amount awarded to the player on a successful spin-through.
@export var hit_boost: float = 200.0

## Direction of spin: 1 = clockwise, -1 = counter-clockwise.
@export var spin_direction: int = 1

var _path_follow: PathFollow2D = null
var _car_ref: Node = null


func _ready() -> void:
	# Collision shape.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(28, 20)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	add_child(collision)

	# Visual: a coloured rectangle.
	var rect := ColorRect.new()
	rect.name = "EnemyVisual"
	rect.size = Vector2(28, 20)
	rect.color = Color(1.0, 0.2, 0.2, 0.8)
	rect.position = -rect.size * 0.5
	add_child(rect)

	# Nose cone.
	var nose := ColorRect.new()
	nose.name = "EnemyNose"
	nose.size = Vector2(8, 6)
	nose.color = Color(0.8, 0.1, 0.1)
	nose.position = Vector2(14, -3)
	add_child(nose)

	# Find the parent PathFollow2D.
	_path_follow = get_parent()
	if _path_follow is PathFollow2D:
		_path_follow.loop = true

	add_to_group("enemy")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _path_follow is PathFollow2D:
		_path_follow.progress += patrol_speed * delta

	# Rotate visual (spinning effect).
	var vis := get_node_or_null("EnemyVisual") as ColorRect
	if vis:
		vis.rotation += spin_direction * spin_speed * delta
	var nose := get_node_or_null("EnemyNose") as ColorRect
	if nose:
		nose.rotation = vis.rotation if vis else 0.0


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("car"):
		_car_ref = body
		var car_state = body.get("car_state")
		if car_state == 1:  # SPINNING
			# Spin-through! Apply boost to the player.
			if body.has_method("apply_boost"):
				body.apply_boost(hit_boost)
		else:
			# Bounce the player off.
			var push_dir = (body.global_position - global_position).normalized()
			var car_vel = body.get("velocity")
			if car_vel != null:
				body.set("velocity", car_vel.bounce(-push_dir).normalized() * car_vel.length() * 0.5)


func _on_body_exited(body: Node) -> void:
	if body == _car_ref:
		_car_ref = null
