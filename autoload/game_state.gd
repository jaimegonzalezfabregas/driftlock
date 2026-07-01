## GameState — global singleton
##
## Holds the shared PhysicsParams instance, a keyboard-accept flag,
## and level progression state (8 levels, 4-column grid with boss levels).
## Autoloaded in project settings.
extends Node

## The single source of truth for all physics tuning knobs.
var physics_params: Resource = null  # Actually PhysicsParams


## Number of levels in the game.
const LEVEL_COUNT: int = 8

## Each level's metadata.
const LEVEL_DATA: Array[Dictionary] = [
	# Row 1 — Basics (levels 1-4)
	{
		"scene": "res://scenes/levels/level_01.tscn",
		"label": "First Curve",
		"description": "Gentle oval — learn the spin",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_02.tscn",
		"label": "S Turns",
		"description": "Weave through gentle S-curves",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_03.tscn",
		"label": "Loop Around",
		"description": "A tighter loop with a crossover",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_04.tscn",
		"label": "Boss: Endurance Oval",
		"description": "3 laps of the oval — finish them all!",
		"is_boss": true,
	},
	# Row 2 — Intermediate (levels 5-8)
	{
		"scene": "res://scenes/levels/level_05.tscn",
		"label": "Hairpin",
		"description": "Tight 180° turns",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_06.tscn",
		"label": "Wavy Road",
		"description": "Long sweeping curves",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_07.tscn",
		"label": "Figure 8",
		"description": "Self-intersecting track",
		"is_boss": false,
	},
	{
		"scene": "res://scenes/levels/level_08.tscn",
		"label": "Boss: Endurance S",
		"description": "3 laps of S-curves",
		"is_boss": true,
	},
]

## Which levels are unlocked (index 0 = Level 1).
var unlocked_levels: Array[bool] = []

## Number of laps per level.
var level_laps: Array[int] = []


func _init() -> void:
	# Unlock first 4 levels (indices 0-3).
	unlocked_levels.resize(LEVEL_COUNT)
	unlocked_levels.fill(false)
	for i in range(4):
		unlocked_levels[i] = true

	# Set laps: 1 for regular, 3 for boss.
	level_laps.resize(LEVEL_COUNT)
	for i in range(LEVEL_COUNT):
		level_laps[i] = 3 if LEVEL_DATA[i].get("is_boss", false) else 1

	# Load save data if available.
	_load_records()


## Mark a level as completed and unlock the next group of 4.
## Returns true if there are more levels to play.
func complete_level(level_index: int) -> bool:
	if level_index < 0 or level_index >= LEVEL_COUNT:
		return false

	# Boss levels (indices 3, 7) unlock the next group of 4.
	if LEVEL_DATA[level_index].get("is_boss", false):
		var next_group_start := level_index + 1
		var next_group_end := mini(next_group_start + 4, LEVEL_COUNT)
		for i in range(next_group_start, next_group_end):
			unlocked_levels[i] = true
		_save_records()
		return next_group_start < LEVEL_COUNT

	# Regular levels don't unlock anything special.
	_save_records()
	return level_index + 1 < LEVEL_COUNT


## Get the scene path for a level index (0-based).
func get_level_scene(idx: int) -> String:
	if idx < 0 or idx >= LEVEL_COUNT:
		return LEVEL_DATA[0]["scene"]
	return LEVEL_DATA[idx]["scene"]


## Get laps for a level (0-based index).
func get_level_laps(idx: int) -> int:
	if idx < 0 or idx >= LEVEL_COUNT:
		return 1
	return level_laps[idx]


## —-- Save / Load ---------------------------------------------------------
const SAVE_PATH: String = "user://driftlock_records.cfg"


func _save_records() -> void:
	var cfg := ConfigFile.new()
	for i in range(LEVEL_COUNT):
		cfg.set_value("unlocks", "unlocked_%d" % i, unlocked_levels[i])
	cfg.save(SAVE_PATH)


func _load_records() -> void:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return  # no save file yet

	for i in range(LEVEL_COUNT):
		var unlocked: bool = cfg.get_value("unlocks", "unlocked_%d" % i, false)
		if unlocked:
			unlocked_levels[i] = true
