## Race result overlay — shown when the player completes a level.
## UI layout is defined in race_result.tscn; this script connects buttons.
extends CanvasLayer

signal next_level(level_idx: int)
signal retry_level(level_idx: int)
signal go_to_level_select()


func setup(level_idx: int) -> void:
	%ImproveBtn.pressed.connect(_on_improve.bind(level_idx))
	%NextBtn.pressed.connect(_on_next.bind(level_idx))
	%SelectBtn.pressed.connect(_on_level_select)


func _on_improve(level_idx: int) -> void:
	retry_level.emit(level_idx)
	queue_free()


func _on_next(level_idx: int) -> void:
	next_level.emit(level_idx)
	queue_free()


func _on_level_select() -> void:
	go_to_level_select.emit()
	queue_free()
