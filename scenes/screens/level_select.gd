## Level Select Screen — 4-column grid with boss levels and tier-based badge colors.
##
##   * 4 columns, 2 rows (8 levels)
##   * Every 4th level is a boss (gold border, endurance label)
##   * Badge color reflects best record tier:
##       Gray  = no record
##       Bronze / Silver / Gold
##   * Locked levels show a lock icon and are non-interactive
##
## UI structure is defined in level_select.tscn.
## Each grid cell is an instance of scenes/ui/level_badge.tscn.
extends Control

const COLS := 4

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
	var grid: GridContainer = %Grid as GridContainer

	# Clear any previously-populated badges (e.g. after returning from a level).
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()

	var badge_scene := preload("res://scenes/ui/level_badge.tscn")

	for i in range(_gs.LEVEL_COUNT):
		var data: Dictionary = _gs.LEVEL_DATA[i] if i < _gs.LEVEL_COUNT else {}
		var badge = badge_scene.instantiate()
		badge.setup(
			i,
			_gs.unlocked_levels[i],
			data.get("is_boss", false),
		)
		badge.badge_pressed.connect(_on_level_pressed)
		grid.add_child(badge)


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
