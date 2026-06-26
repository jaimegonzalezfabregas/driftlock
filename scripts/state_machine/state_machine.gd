## Finite‑state machine node (GDQuest FSM pattern).
##
## Manages a set of child State nodes and transitions between them.
## Only the active state's update functions are called each frame.
## NOTE: physics_update is NOT handled here — it is called explicitly by
## the owner's _physics_process so that it respects input_lock / countdown.
class_name StateMachine extends Node

## Optional initial state override.  If unset, the first child is used.
@export var initial_state: State = null

## The currently active state.
@onready var state: State = (func get_initial() -> State:
	return initial_state if initial_state != null else get_child(0)
).call()


func _ready() -> void:
	# Connect every child state's finished signal.
	for child in get_children():
		if child is State:
			child.finished.connect(_transition_to_next_state)

	await owner.ready
	state.enter("")


func _unhandled_input(event: InputEvent) -> void:
	state.handle_input(event)


func _process(delta: float) -> void:
	state.update(delta)


## Called explicitly by the owner so it can respect input lock / countdown.
func physics_update(delta: float) -> void:
	state.physics_update(delta)


## Transition to a new state by node name (relative path).
func transition_to(target_path: String, data: Dictionary = {}) -> void:
	_transition_to_next_state(target_path, data)


func _transition_to_next_state(target_path: String, data: Dictionary = {}) -> void:
	if not has_node(target_path):
		push_error(owner.name + ": state not found: " + target_path)
		return

	var target = get_node(target_path)
	if not target is State:
		push_error(owner.name + ": target node is not a State: " + target_path)
		return
	var prev := state.name
	state.exit()
	state = target
	state.enter(prev, data)
