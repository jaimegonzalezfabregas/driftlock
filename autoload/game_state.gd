## GameState — global singleton
##
## Holds the shared PhysicsParams instance, a keyboard-accept flag,
## and level progression state.
## Autoloaded in project settings.
extends Node

## The single source of truth for all physics tuning knobs.
var physics_params: Resource = null  # Actually PhysicsParams, typed as Resource to avoid class_name dependence

## Whether the car should respond to real keyboard input.
## (False during automated tests so test-input doesn't fight keyboard.)
var accept_keyboard_input: bool = true

## Number of levels in the game.  Each level has a scene at:
##   res://scenes/levels/level_{nn}.tscn  (1-indexed, zero-padded)
const LEVEL_COUNT: int = 7

## Level metadata — defines the scene path and label for each level.
## Index 0 is Level 1, etc.
const LEVEL_DATA: Array[Dictionary] = [
	{
		"scene": "res://scenes/levels/level_01.tscn",
		"label": "Spin Basics",
		"description": "Learn the spin mechanic",
	},
	{
		"scene": "res://scenes/levels/level_02.tscn",
		"label": "Boost Pads",
		"description": "Spin on the pads to fly",
	},
	{
		"scene": "res://scenes/levels/level_03.tscn",
		"label": "Spinners",
		"description": "Dodge or spin through enemies",
	},
	{
		"scene": "res://scenes/levels/level_04.tscn",
		"label": "Minefield",
		"description": "Spin through mines for speed",
	},
	{
		"scene": "res://scenes/levels/level_05.tscn",
		"label": "Shield Run",
		"description": "Collect shields, stay spinning",
	},
	{
		"scene": "res://scenes/levels/level_06.tscn",
		"label": "Mega Spin",
		"description": "Super spin powerups!",
	},
	{
		"scene": "res://scenes/levels/level_07.tscn",
		"label": "The Gauntlet",
		"description": "Everything at once",
	},
]

## Which levels are unlocked (index 0 = Level 1).
## Level 1 is always unlocked.
var unlocked_levels: Array[bool] = []

## The number of laps required to win each level (1-indexed).
## Default 3 laps but we set per-level values in _init.
var level_laps: Array[int] = []

# Preload the PhysicsParams script so we can instantiate it
var _PhysicsParams = preload("res://resources/physics_params.gd")


func _init() -> void:
	# Create the shared params with defaults
	physics_params = _PhysicsParams.new()

	# Initialise level unlocks: only Level 1 available
	unlocked_levels.resize(LEVEL_COUNT)
	unlocked_levels.fill(false)
	unlocked_levels[0] = true

	# Set laps per level (shorter for early levels)
	level_laps.resize(LEVEL_COUNT)
	level_laps[0] = 1
	level_laps[1] = 1
	level_laps[2] = 1
	level_laps[3] = 1
	level_laps[4] = 1
	level_laps[5] = 1
	level_laps[6] = 2


## Mark a level as completed and unlock the next one.
## Returns true if there is a next level to play.
func complete_level(level_index: int) -> bool:
	if level_index < 0 or level_index >= LEVEL_COUNT:
		return false
	var next_idx := level_index + 1
	if next_idx < LEVEL_COUNT:
		unlocked_levels[next_idx] = true
		return true
	return false


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
