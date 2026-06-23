## SimpleObstacle — static block placed at a track path node
## The car dies on contact (same as wall_hit signal).
class_name SimpleObstacle
extends StaticBody2D

## Collision / visual size (width, height) in pixels.
@export var obstacle_size: Vector2 = Vector2(30, 30)
## Fill colour drawn in _draw.
@export var obstacle_color: Color = Color.DARK_ORANGE


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = obstacle_size
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	# Name it so the car's wall_hit detector sees a recognisable collider
	col.name = "ObstacleShape"
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(-obstacle_size * 0.5, obstacle_size), obstacle_color)
