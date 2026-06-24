## Title Screen — centred Start Game button and Level Select button
##
## The buttons are in a VBoxContainer centred via CenterContainer.
extends Control


func _ready() -> void:
	var start_btn: Button = $CenterContainer/VBoxContainer/StartGameButton
	start_btn.pressed.connect(_on_start_game)
	var level_btn: Button = $CenterContainer/VBoxContainer/LevelSelectButton
	level_btn.pressed.connect(_on_level_select)


func _on_start_game() -> void:
	# Quick start — goes directly to level 1.
	get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn")


func _on_level_select() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/level_select.tscn")
