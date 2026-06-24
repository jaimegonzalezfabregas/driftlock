## Level 06 — Mega Spin
## Introduces Mega Spin powerups that temporarily boost rotation
## efficiency and force an immediate spin.
extends "res://scenes/levels/level_base.gd"

const _MegaSpinScene := preload("res://scripts/obstacles/mega_spin.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	## Place mega spin pickups along the track.
	var bl := curve.get_baked_length()
	var positions := [bl * 0.25, bl * 0.5, bl * 0.75]

	for pos in positions:
		_spawn_mega_spin(curve, pos)


func _spawn_mega_spin(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 40.0 * side

	var ms := _MegaSpinScene.new()
	ms.global_position = xf.origin + offset
	ms.duration = 5.0
	ms.efficiency_mult = 3.0
	ms.spin_force = 50.0
	add_child(ms)
