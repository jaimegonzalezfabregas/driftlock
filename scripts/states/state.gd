## Virtual base class for all states (GDQuest FSM pattern).
class_name State extends Node

## Emitted when the state finishes and wants to transition to another state.
## `next_state_path` is the (relative) node name of the target state.
signal finished(next_state_path: String, data: Dictionary)

## Called once when this state becomes active.
func enter(_previous_state_path: String, _data := {}) -> void:
	pass

## Called once when this state is about to be deactivated.
func exit() -> void:
	pass

## Called by the state machine when receiving unhandled input events.
func handle_input(_event: InputEvent) -> void:
	pass

## Called by the state machine on the engine's main loop tick.
func update(_delta: float) -> void:
	pass

## Called by the state machine on the engine's physics update tick.
func physics_update(_delta: float) -> void:
	pass
