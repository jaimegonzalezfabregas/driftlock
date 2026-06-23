## GameState — global singleton
##
## Holds the shared PhysicsParams instance and a keyboard-accept flag.
## Autoloaded in project settings.
extends Node

## The single source of truth for all physics tuning knobs.
var physics_params: Resource = null  # Actually PhysicsParams, typed as Resource to avoid class_name dependence

## Whether the car should respond to real keyboard input.
## (False during automated tests so test-input doesn't fight keyboard.)
var accept_keyboard_input: bool = true

# Preload the PhysicsParams script so we can instantiate it
var _PhysicsParams = preload("res://resources/physics_params.gd")


func _init() -> void:
	# Create the shared params with defaults
	physics_params = _PhysicsParams.new()
