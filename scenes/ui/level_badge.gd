## Level badge — a single cell in the level-select grid.
## Layout defined in level_badge.tscn; this script applies data-driven styling.
extends VBoxContainer

## Emitted when the player taps/clicks an unlocked badge.
signal badge_pressed(level_idx: int)

@onready var _btn: Button       = %Btn
@onready var _name_label: Label = %NameLabel
@onready var _boss_label: Label = %BossLabel


## Populate and style the badge.
##   level_idx   — 0-based level index
##   is_unlocked — whether the player can enter this level
##   is_boss     — adds gold border and BOSS sub-label
func setup(level_idx: int, is_unlocked: bool, is_boss: bool) -> void:
	_name_label.text = "Level %d" % (level_idx + 1)
	_boss_label.visible = is_boss
	_btn.disabled = not is_unlocked

	if not is_unlocked:
		_btn.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3))
		_btn.text = "🔒"
		_btn.add_theme_font_size_override("font_size", 28)
	else:
		_btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		_btn.text = "%d" % (level_idx + 1)
		_btn.add_theme_font_size_override("font_size", 32)

	if is_boss:
		var border_color := Color(1.0, 0.8, 0.1, 0.7) if is_unlocked else Color(0.4, 0.35, 0.1, 0.5)
		_btn.add_theme_stylebox_override("normal",   _make_border_style(border_color))
		_btn.add_theme_stylebox_override("disabled", _make_border_style(Color(0.2, 0.2, 0.2, 0.5)))

	_btn.pressed.connect(_on_btn_pressed.bind(level_idx))


func _on_btn_pressed(level_idx: int) -> void:
	badge_pressed.emit(level_idx)


func _make_border_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	sb.border_color = color
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left     = 8
	sb.corner_radius_top_right    = 8
	sb.corner_radius_bottom_left  = 8
	sb.corner_radius_bottom_right = 8
	return sb
