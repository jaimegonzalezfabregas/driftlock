## Level 02 — Spin Boost Pads
## Features a few spin boost pads on the track that force the car into
## a spin when driven over, teaching the player about spin zones.
extends "res://scenes/levels/level_base.gd"

const _PadScene := preload("res://scripts/obstacles/spin_boost_pad.gd")
const _PP := preload("res://resources/physics_params.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	## Place boost pads along the track at strategic intervals.
	var bl := curve.get_baked_length()
	var pad_positions := [bl * 0.25, bl * 0.5, bl * 0.75]

	for pos in pad_positions:
		_spawn_boost_pad(curve, pos)


func _spawn_boost_pad(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs * 10) % 2 == 0) else -1.0
	var offset := nrm * 30.0 * side  # slightly off-centre on the track

	var pad := _PadScene.new()
	pad.global_position = xf.origin + offset
	pad.rotation = xf.get_rotation()
	pad.spin_force = 40.0
	add_child(pad)
