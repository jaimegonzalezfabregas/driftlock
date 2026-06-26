## Generic level instance.
## Track shape and boss mode are determined at runtime by level_index.
extends "res://scenes/levels/level_base.gd"


func _level_specific_setup(_curve: Curve2D) -> void:
	## No obstacles in the new system — all challenge comes from track shape.
	pass
