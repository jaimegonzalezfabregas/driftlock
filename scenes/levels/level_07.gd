## Level 07 — The Gauntlet
## All features combined: boost pads, enemies, mines, shields, mega spin.
## Harder track with more obstacles.
extends "res://scenes/levels/level_base.gd"

const _PadScene := preload("res://scripts/obstacles/spin_boost_pad.gd")
const _EnemyScene := preload("res://scripts/obstacles/spinner_enemy.gd")
const _MineScene := preload("res://scripts/obstacles/spin_mine.gd")
const _ShieldScene := preload("res://scripts/obstacles/spin_shield.gd")
const _MegaSpinScene := preload("res://scripts/obstacles/mega_spin.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	var bl := curve.get_baked_length()

	# Boost pads.
	var pad_positions := [bl * 0.1, bl * 0.6]
	for pos in pad_positions:
		_spawn_pad(curve, pos)

	# Enemies.
	_spawn_enemy(curve, 0.3, 1, 100.0)
	_spawn_enemy(curve, 0.7, -1, 80.0)

	# Mines.
	var mine_positions := [bl * 0.15, bl * 0.4, bl * 0.65, bl * 0.85]
	for pos in mine_positions:
		_spawn_mine(curve, pos)

	# Shields.
	var shield_positions := [bl * 0.2, bl * 0.55]
	for pos in shield_positions:
		_spawn_shield(curve, pos)

	# Mega spin.
	var mega_positions := [bl * 0.35, bl * 0.8]
	for pos in mega_positions:
		_spawn_mega_spin(curve, pos)


func _spawn_pad(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var nrm := Vector2.RIGHT.rotated(xf.get_rotation()).rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs * 10) % 2 == 0) else -1.0
	var offset := nrm * 30.0 * side
	var pad := _PadScene.new()
	pad.global_position = xf.origin + offset
	pad.rotation = xf.get_rotation()
	pad.spin_force = 40.0
	add_child(pad)


func _spawn_enemy(curve: Curve2D, progress_ratio: float, dir: int, speed: float) -> void:
	var bl := curve.get_baked_length()
	var start_ofs := bl * progress_ratio
	var seg_length := bl * 0.15

	var path := Path2D.new()
	var patrol_curve := Curve2D.new()
	var xf1 := curve.sample_baked_with_rotation(start_ofs)
	var xf2 := curve.sample_baked_with_rotation(minf(start_ofs + seg_length, bl))
	var nrm := Vector2.RIGHT.rotated(xf1.get_rotation()).rotated(PI * 0.5)
	var offset := nrm * 40.0
	patrol_curve.add_point(xf1.origin + offset, Vector2.ZERO, Vector2.ZERO)
	patrol_curve.add_point(xf2.origin + offset, Vector2.ZERO, Vector2.ZERO)
	path.curve = patrol_curve
	add_child(path)

	var follow := PathFollow2D.new()
	follow.loop = true
	path.add_child(follow)

	var enemy := _EnemyScene.new()
	enemy.patrol_speed = speed
	enemy.spin_direction = dir
	enemy.hit_boost = 150.0
	follow.add_child(enemy)


func _spawn_mine(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var nrm := Vector2.RIGHT.rotated(xf.get_rotation()).rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 50.0 * side
	var mine := _MineScene.new()
	mine.global_position = xf.origin + offset
	mine.spin_force = 30.0
	mine.hit_boost = 300.0
	add_child(mine)


func _spawn_shield(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var nrm := Vector2.RIGHT.rotated(xf.get_rotation()).rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 30.0 * side
	var shield := _ShieldScene.new()
	shield.global_position = xf.origin + offset
	shield.spin_force = 35.0
	add_child(shield)


func _spawn_mega_spin(curve: Curve2D, baked_ofs: float) -> void:
	var xf := curve.sample_baked_with_rotation(baked_ofs)
	var nrm := Vector2.RIGHT.rotated(xf.get_rotation()).rotated(PI * 0.5)
	var side := 1.0 if (int(baked_ofs) % 2 == 0) else -1.0
	var offset := nrm * 40.0 * side
	var ms := _MegaSpinScene.new()
	ms.global_position = xf.origin + offset
	ms.duration = 5.0
	ms.efficiency_mult = 3.0
	ms.spin_force = 50.0
	add_child(ms)
