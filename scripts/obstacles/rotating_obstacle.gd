## RotatingObstacle — spinning bar placed at a track path node
## The bar rotates continuously; the player must time their passage
## when the gap aligns with the driving lane.
##
## Uses a single long rectangle (the bar) as both collision shape and visual.
## The bar rotates around the obstacle's origin (the path node position).
class_name RotatingObstacle
extends StaticBody2D

## Length of the rotating bar (pixels). Should be ~track_width to create a challenge.
@export var bar_length: float = 180.0
## Thickness of the bar (pixels).
@export var bar_thickness: float = 10.0
## Rotation speed (radians per second). Positive = CCW.
@export var rotation_speed: float = deg_to_rad(90.0)
## Colour of the bar.
@export var bar_color: Color = Color.DARK_RED


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(bar_length, bar_thickness)
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	col.name = "ObstacleShape"
	queue_redraw()


func _physics_process(delta: float) -> void:
	rotation += rotation_speed * delta


func _draw() -> void:
	draw_rect(Rect2(-Vector2(bar_length, bar_thickness) * 0.5, Vector2(bar_length, bar_thickness)), bar_color)
