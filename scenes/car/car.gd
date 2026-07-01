
class_name Car
extends CharacterBody2D

## Renamed to CarMode to avoid clashing with class_name State from state.gd.
enum CarMode { STOPPED, ACCELERATE, SPINNING }

var spin_direction: float = -1;
var car_state: CarMode = CarMode.STOPPED

var input_locked: bool = false  

var acceleration: float = 2
var max_speed: float = 30

var r_speed: float = 0;
var r_acceleration: float = 0.01
var r_max_speed: float = 0.1


signal wall_hit()

func _ready() -> void:
	add_to_group("car")
	z_index = 1


func _physics_process(delta: float) -> void:

	# Do nothing while countdown runs.
	if input_locked:
		return


	match car_state:
		CarMode.STOPPED:
			if(Input.is_key_pressed(KEY_SPACE)):
				car_state = CarMode.ACCELERATE

		CarMode.ACCELERATE:
			velocity += acceleration * delta * Vector2(0, 1).rotated(rotation);
			velocity = velocity.normalized() * min(velocity.length(), max_speed);

			if(Input.is_key_pressed(KEY_A)):
				spin_direction = -1;
				car_state = CarMode.SPINNING
			if(Input.is_key_pressed(KEY_A)):
				spin_direction = 1;
				car_state = CarMode.SPINNING
		CarMode.SPINNING:
			r_speed += spin_direction * r_acceleration;
			r_speed = min(r_speed, max_speed);
			rotation += r_speed;

			if(Input.is_key_pressed(KEY_SPACE)):
				r_speed = 0;
				car_state = CarMode.ACCELERATE
	
	move_and_slide()

	var col = get_last_slide_collision()
	if col:
		if col.get_collider() is StaticBody2D:
			emit_signal("wall_hit")


func reset(pos: Vector2, rot: float) -> void:
	spin_direction = 0
	velocity = Vector2.ZERO
	global_position = pos
	global_rotation = rot
	car_state = CarMode.ACCELERATE

