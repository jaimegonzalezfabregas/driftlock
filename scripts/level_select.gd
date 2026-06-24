## Level Select Screen — shows unlocked levels as buttons.
## Player clicks a level to play it.  Completing a level unlocks the next.
extends Control


func _ready() -> void:
	_build_level_buttons()


func _build_level_buttons() -> void:
	var container := $ScrollContainer/VBoxContainer
	if container == null:
		return

	# Clear existing children (except title / instructions).
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

	var gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null

	for i in range(GameState.LEVEL_COUNT if gs == null else gs.LEVEL_COUNT):
		var unlocked: bool = gs.unlocked_levels[i] if gs else i == 0

		var data: Dictionary = gs.LEVEL_DATA[i] if gs else {"label": "Level %d" % (i + 1), "description": ""}

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(360, 64)
		btn.size = Vector2(360, 64)
		btn.text = "Level %d: %s" % [i + 1, data["label"]]
		if not unlocked:
			btn.text = "🔒 " + btn.text
			btn.disabled = true
		btn.theme_override_font_sizes["font_size"] = 20
		btn.pressed.connect(_on_level_pressed.bind(i, unlocked))
		container.add_child(btn)

		# Subtitle description.
		var desc := Label.new()
		desc.text = data["description"]
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc.add_theme_font_size_override("font_size", 14)
		container.add_child(desc)

	# Back button.
	var back_btn := Button.new()
	back_btn.custom_minimum_size = Vector2(200, 40)
	back_btn.text = "Back to Title"
	back_btn.pressed.connect(_on_back_pressed)
	container.add_child(back_btn)


func _on_level_pressed(idx: int, unlocked: bool) -> void:
	if not unlocked:
		return
	var gs = Engine.get_singleton("GameState")
	var scene_path = gs.get_level_scene(idx)
	var laps = gs.get_level_laps(idx)
	# Set the level's total_laps when loading.
	var scene = load(scene_path) as PackedScene
	if scene:
		var level = scene.instantiate()
		level.set("level_index", idx)
		level.set("total_laps", laps)
		get_tree().root.add_child(level)
		# Remove the level select screen.
		queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/title_screen.tscn")
