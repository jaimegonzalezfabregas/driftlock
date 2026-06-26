## Level Select Screen — 4×5 grid with boss levels and tier‑based badge colors.
##
##   * 4 columns, 5 rows (20 levels)
##   * Every 4th level is a boss (gold border, endurance label)
##   * Badge color reflects best record tier:
##       Gray  = no record
##       Bronze
##       Silver
##       Gold
##   * Locked levels show a lock icon and are non‑interactive
extends Control

const COLS := 4

# Tier colors for badges.
const TIER_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.5, 1.0),   # 0 none — gray
	Color(0.8, 0.5, 0.2, 1.0),   # 1 bronze
	Color(0.75, 0.75, 0.8, 1.0), # 2 silver
	Color(1.0, 0.8, 0.1, 1.0),   # 3 gold
]

var _gs = null  # GameState singleton


func _ready() -> void:
	_gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if _gs == null:
		var tree := get_tree()
		if tree:
			_gs = tree.root.get_node_or_null("GameState")

	if _gs == null:
		push_error("LevelSelect: GameState singleton not found")
		return

	_build_grid()


func _build_grid() -> void:
	## Create the 4×5 grid of level badges.
	var grid: GridContainer = get_node_or_null("GridContainer") as GridContainer
	if grid == null:
		grid = GridContainer.new()
		grid.name = "GridContainer"
		grid.columns = COLS
		add_child(grid)
	else:
		# Clear existing children.
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()

	# Center the grid on screen.
	grid.anchor_left = 0.0
	grid.anchor_right = 1.0
	grid.anchor_top = 0.0
	grid.anchor_bottom = 1.0

	for i in range(_gs.LEVEL_COUNT):
		var badge := _create_badge(i)
		grid.add_child(badge)

	# Add title and back button (placed outside grid for layout).
	_setup_ui()


func _create_badge(level_idx: int) -> Control:
	## Build one level badge (100×100 px).
	var data: Dictionary = _gs.LEVEL_DATA[level_idx] if level_idx < _gs.LEVEL_COUNT else {}
	var is_boss: bool = data.get("is_boss", false)
	var is_unlocked: bool = _gs.unlocked_levels[level_idx]
	var tier: int = _gs.level_tiers[level_idx]
	var has_record: bool = _gs.level_times[level_idx] < INF

	var container := AspectRatioContainer.new()
	container.ratio = 1.0
	container.custom_minimum_size = Vector2(100, 100)
	container.size_flags_horizontal = Control.SIZE_EXPAND
	container.size_flags_vertical = Control.SIZE_EXPAND

	var btn := Button.new()
	btn.name = "Btn_%d" % level_idx
	btn.text = ""
	btn.flat = true
	btn.disabled = not is_unlocked
	btn.custom_minimum_size = Vector2(80, 80)

	if not is_unlocked:
		# Locked: dark with lock symbol.
		btn.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
		btn.text = "🔒"
		btn.add_theme_font_size_override("font_size", 28)
	elif has_record:
		# Has record: show level number and tier color.
		var c: Color = TIER_COLORS[tier] if tier >= 0 and tier < TIER_COLORS.size() else TIER_COLORS[0]
		btn.add_theme_color_override("font_color", c)
		btn.text = "%d" % (level_idx + 1)
		btn.add_theme_font_size_override("font_size", 32)
	else:
		# Playable but no record: white text.
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		btn.text = "%d" % (level_idx + 1)
		btn.add_theme_font_size_override("font_size", 32)

	# Boss styling: gold border.
	if is_boss:
		var border_color := Color(1.0, 0.8, 0.1, 0.7) if is_unlocked else Color(0.4, 0.35, 0.1, 0.5)
		btn.add_theme_stylebox_override("normal", _make_border_style(border_color))
		btn.add_theme_stylebox_override("disabled", _make_border_style(Color(0.2, 0.2, 0.2, 0.5)))

	# Label below the number.
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	if is_unlocked:
		label.text = data.get("label", "")
	else:
		label.text = "???"
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Pack into a vertical container so label sits below the button.
	var vbox := VBoxContainer.new()
	vbox.add_child(container)
	vbox.add_child(label)

	# If boss level and unlocked, add a small "B" indicator.
	if is_boss and is_unlocked:
		var boss_label := Label.new()
		boss_label.text = "B"
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_label.add_theme_font_size_override("font_size", 9)
		boss_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		vbox.add_child(boss_label)

	# Button press.
	var idx := level_idx
	btn.pressed.connect(_on_level_pressed.bind(idx))

	container.add_child(btn)
	return vbox


func _make_border_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	sb.border_color = color
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	return sb


func _setup_ui() -> void:
	## Title and back button.
	var title := Label.new()
	title.text = "LEVEL SELECT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	title.position = Vector2(0, -40)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(title)

	var back_btn := Button.new()
	back_btn.text = "Back to Title"
	back_btn.position = Vector2(20, 20)
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)


func _on_level_pressed(idx: int) -> void:
	if not _gs.unlocked_levels[idx]:
		return
	var scene_path: String = _gs.get_level_scene(idx)
	var laps: int = _gs.get_level_laps(idx)
	var scene := load(scene_path) as PackedScene
	if scene:
		var level := scene.instantiate()
		level.set("level_index", idx)
		level.set("total_laps", laps)
		get_tree().root.add_child(level)
		queue_free()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/title_screen.tscn")
