## Level 04 — Spin Mines
## Introduces mines scattered around the track.  Driving through them
## while spinning gives a big boost.  Hitting them while not spinning
## forces a spin.
extends "res://scenes/levels/level_base.gd"

const _MineScene := preload("res://scripts/obstacles/spin_mine.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	## Place mines at various points along the track.
	var bl := curve.get_baked_length()
	var mine_positions := [bl * 0.15, bl * 0.35, bl * 0.55, bl * 0.7, bl * 0.85]

	for pos in mine_positions:
		_spawn_mine(curve, pos)


func _spawn_mine(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)
	# Offset slightly left or right of centerline.
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 50.0 * side

	var mine := _MineScene.new()
	mine.global_position = xf.origin + offset
	mine.spin_force = 30.0
	mine.hit_boost = 300.0
	add_child(mine)
