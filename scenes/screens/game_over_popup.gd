## Game over overlay — shown on wall hit or time limit loss.
## UI layout is defined in game_over_popup.tscn; this script connects signals.
extends CanvasLayer

signal retry_level(level_idx: int)
signal go_to_level_select()


func setup(level_idx: int) -> void:
	%RetryBtn.pressed.connect(_on_retry.bind(level_idx))
	%SelectBtn.pressed.connect(_on_level_select)


func _on_retry(level_idx: int) -> void:
	retry_level.emit(level_idx)
	queue_free()


func _on_level_select() -> void:
	go_to_level_select.emit()
	queue_free()
