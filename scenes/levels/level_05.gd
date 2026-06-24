## Level 05 — Spin Shield Run
## Introduces shield pickups.  The shield absorbs one wall hit and
## converts it into a spin.
extends "res://scenes/levels/level_base.gd"

const _ShieldScene := preload("res://scripts/obstacles/spin_shield.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	## Place shield pickups along the track.
	var bl := curve.get_baked_length()
	var positions := [bl * 0.2, bl * 0.45, bl * 0.7]

	for pos in positions:
		_spawn_shield(curve, pos)


func _spawn_shield(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 30.0 * side

	var shield := _ShieldScene.new()
	shield.global_position = xf.origin + offset
	shield.spin_force = 35.0
	add_child(shield)
