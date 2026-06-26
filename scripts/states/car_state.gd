## Intermediate base for all Car states.  Provides a typed `car` reference.
class_name CarState extends State

## Set when the node enters the scene tree — safe to use in _process / _physics_process.
@onready var car: Car = owner
