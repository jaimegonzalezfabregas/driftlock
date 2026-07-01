## Pause overlay — full-screen dim with PAUSED label and two buttons.
## Layout defined in pause_overlay.tscn; this script wires signals.
## The parent level connects resume/quit callbacks via setup().
extends CanvasLayer

signal resume_requested()
signal quit_requested()


func _ready() -> void:
	%ResumeBtn.pressed.connect(_on_resume)
	%QuitBtn.pressed.connect(_on_quit)
	# Start hidden; the level shows/hides us.
	visible = false


func _on_resume() -> void:
	resume_requested.emit()


func _on_quit() -> void:
	quit_requested.emit()
