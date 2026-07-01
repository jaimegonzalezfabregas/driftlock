@tool
extends EditorPlugin

var path: String = ProjectSettings.globalize_path("res://")
var dock: Control

func _enter_tree() -> void:
	dock = Control.new()
	dock.name = "Git"
	var dock_content = preload("uid://ivjdq3iu1k6r").instantiate()
	dock.add_child(dock_content)
	add_control_to_dock(DOCK_SLOT_LEFT_UR, dock)


func _exit_tree() -> void:
	if dock != null:
		remove_control_from_dock(dock)
		dock.queue_free()
		dock = null
