extends Node2D

func _ready() -> void:
	var scene = load("res://scenes/screens/level_select.tscn")
	var ls = scene.instantiate()
	add_child(ls)
	await get_tree().create_timer(0.1).timeout
	
	# Try clicking level 1
	var container = ls.get_node("ScrollContainer/VBoxContainer")
	var btn = container.get_child(0) as Button
	print("Button text: ", btn.text, " disabled: ", btn.disabled)
	btn.pressed.emit()
	
	await get_tree().create_timer(0.2).timeout
	
	# Check if level appeared
	var found_level = false
	for child in get_tree().root.get_children():
		print("  Root child: ", child.name, " (", child.get_class(), ")")
		if child.name.begins_with("Level0"):
			found_level = true
			print("  -> LEVEL FOUND! Scene was loaded successfully.")
	
	if not found_level:
		print("  -> NO LEVEL FOUND - level select still broken!")
	
	print("Level select valid: ", is_instance_valid(ls))
	get_tree().quit()
