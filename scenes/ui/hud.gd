## HUD — in-game overlay for lap counter, level label,
## and player hint labels.
## All layout is defined in hud.tscn; this script only manages dynamic state.
extends CanvasLayer

@onready var _lap_label: Label        = %LapLabel
@onready var _level_label: Label      = %LevelLabel
@onready var _drift_hint_label: Label = %DriftHintLabel


## Configure the HUD for a specific level.
##   level_index  — 0-based index, used for the "Level N" label
##   total_laps   — >1 shows lap counter; 1 hides it
func setup(level_index: int, total_laps: int) -> void:
	_level_label.text = "Level %d" % (level_index + 1)
	_lap_label.visible = false
	_lap_label.text = ""


## Update the lap counter label.
func update_lap(current_lap: int, total_laps: int) -> void:
	if total_laps > 1:
		_lap_label.text = "Lap %d / %d" % [current_lap, total_laps]
		_lap_label.visible = true
	else:
		_lap_label.visible = false
		_lap_label.text = ""


## Show or hide the "Press A and D to drift" hint.
func set_drift_hint_visible(visible_flag: bool) -> void:
	_drift_hint_label.visible = visible_flag
