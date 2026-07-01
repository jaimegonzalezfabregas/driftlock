## Level Select Screen — 4-column grid with boss levels and tier-based badge colors.
##
##   * 4 columns, 2 rows (8 levels)
##   * Every 4th level is a boss (gold border, endurance label)
##   * Badge color reflects best record tier:
##       Gray  = no record
##       Bronze
##       Silver
##       Gold
##   * Locked levels show a lock icon and are non-interactive
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
	RenderingServer.set_default_clear_color(Color(0.3, 0.3, 0.3))
	_gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if _gs == null:
		var tree := get_tree()
		if tree:
			_gs = tree.root.get_node_or_null("GameState")

	if _gs == null:
		push_error("LevelSelect: GameState singleton not found")
		return

	$BackButton.pressed.connect(_on_back_pressed)
	_build_grid()


func _build_grid() -> void:
	## Populate the 2×4 grid of level badges (defined in .tscn).
	var grid: GridContainer = %Grid as GridContainer
	# Clear any previously-populated badges (e.g. after returning from level).
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()

	for i in range(_gs.LEVEL_COUNT):
		var badge := _create_badge(i)
		grid.add_child(badge)


func _create_badge(level_idx: int) -> Control:
	## Build one level badge (~100×100 px, centered in grid cell).
	var data: Dictionary = _gs.LEVEL_DATA[level_idx] if level_idx < _gs.LEVEL_COUNT else {}
	var is_boss: bool = data.get("is_boss", false)
	var is_unlocked: bool = _gs.unlocked_levels[level_idx]
	var tier: int = _gs.level_tiers[level_idx]
	var has_record: bool = _gs.level_times[level_idx] < INF

	# Main vertical column: button + label.
	var vbox := VBoxContainer.new()
	vbox.alignment = 1  # BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	vbox.custom_minimum_size = Vector2(100, 100)

	var btn := Button.new()
	btn.name = "Btn_%d" % level_idx
	btn.flat = true
	btn.disabled = not is_unlocked
	btn.custom_minimum_size = Vector2(80, 80)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	if not is_unlocked:
		# Locked: dark with lock symbol.
		btn.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
		btn.text = "🔒"
		btn.add_theme_font_size_override("font_size", 28)
	elif has_record:
		var c: Color = TIER_COLORS[tier] if tier >= 0 and tier < TIER_COLORS.size() else TIER_COLORS[0]
		btn.add_theme_color_override("font_color", c)
		btn.text = "%d" % (level_idx + 1)
		btn.add_theme_font_size_override("font_size", 32)
	else:
		btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		btn.text = "%d" % (level_idx + 1)
		btn.add_theme_font_size_override("font_size", 32)

	# Boss styling: gold border.
	if is_boss:
		var border_color := Color(1.0, 0.8, 0.1, 0.7) if is_unlocked else Color(0.4, 0.35, 0.1, 0.5)
		btn.add_theme_stylebox_override("normal", _make_border_style(border_color))
		btn.add_theme_stylebox_override("disabled", _make_border_style(Color(0.2, 0.2, 0.2, 0.5)))

	vbox.add_child(btn)

	# Label below the number.
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	label.add_theme_font_size_override("font_size", 14)
	label.text = "Level %d" % (level_idx + 1)
	vbox.add_child(label)

	if is_boss:
		var boss_label := Label.new()
		boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		boss_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.1))
		boss_label.add_theme_font_size_override("font_size", 10)
		boss_label.text = "BOSS"
		vbox.add_child(boss_label)

	var idx := level_idx
	btn.pressed.connect(_on_level_pressed.bind(idx))

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
