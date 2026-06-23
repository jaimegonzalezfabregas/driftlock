## Title Screen — centred Start Game button
##
## The button fills the entire screen via an anchored Control root,
## and a CenterContainer keeps the button centred at any resolution.
extends Control


func _ready() -> void:
	var btn: Button = $CenterContainer/VBoxContainer/StartGameButton
	btn.pressed.connect(_on_start_game)


func _on_start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/levels/level_01.tscn")
