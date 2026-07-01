## Race result overlay — shows medal times, player time, and navigation buttons.
## UI layout is defined in race_result.tscn; this script fills in dynamic data.
extends CanvasLayer

signal next_level(level_idx: int)
signal retry_level(level_idx: int)
signal go_to_level_select()


## Set up the result display.
##   level_idx  — 0-based level index
##   race_time  — player's finishing time in seconds
##   bronze     — bronze medal threshold (seconds)
##   silver     — silver medal threshold
##   gold       — gold medal threshold
func setup(level_idx: int, race_time: float, bronze: float, silver: float, gold: float) -> void:
	# Player time.
	var time_lbl: Label = %TimeLabel
	time_lbl.text = "Your Time:  %.1f s" % race_time

	# Determine medal.
	var medal_name: String
	var medal_color: Color
	if race_time <= gold:
		medal_name = "GOLD!"
		medal_color = Color(1.0, 0.8, 0.1)
	elif race_time <= silver:
		medal_name = "SILVER!"
		medal_color = Color(0.75, 0.75, 0.8)
	elif race_time <= bronze:
		medal_name = "BRONZE!"
		medal_color = Color(0.8, 0.5, 0.2)
	else:
		medal_name = "FINISHED"
		medal_color = Color(0.6, 0.6, 0.6)

	var medal_lbl: Label = %MedalLabel
	medal_lbl.text = medal_name
	medal_lbl.add_theme_color_override("font_color", medal_color)

	# Medal thresholds.
	%BronzeLabel.text = "Bronze:  %.1f s" % bronze
	%SilverLabel.text = "Silver:  %.1f s" % silver
	%GoldLabel.text = "Gold:  %.1f s" % gold

	# Buttons.
	%ImproveBtn.pressed.connect(_on_improve.bind(level_idx))
	%NextBtn.pressed.connect(_on_next.bind(level_idx))
	%SelectBtn.pressed.connect(_on_level_select)


func _on_improve(level_idx: int) -> void:
	retry_level.emit(level_idx)
	queue_free()


func _on_next(level_idx: int) -> void:
	next_level.emit(level_idx)
	queue_free()


func _on_level_select() -> void:
	go_to_level_select.emit()
	queue_free()
