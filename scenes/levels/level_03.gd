## Level 03 — Spinner Enemies
## Introduces enemy cars that patrol the track.  Spin through them to
## get a boost, or get bounced off.
extends "res://scenes/levels/level_base.gd"

const _EnemyScene := preload("res://scripts/obstacles/spinner_enemy.gd")


func _level_specific_setup(curve: Curve2D) -> void:
	## Place spinner enemies on patrol paths.
	_spawn_enemy_patrol(curve, 0.2, 1, 100.0)
	_spawn_enemy_patrol(curve, 0.5, -1, 80.0)
	_spawn_enemy_patrol(curve, 0.75, 1, 90.0)


func _spawn_enemy_patrol(curve: Curve2D, progress_ratio: float, dir: int, speed: float) -> void:
	## Create a Path2D with a short segment for the enemy to patrol.
	## The enemy moves along a small fraction of the track.
	var bl := curve.get_baked_length()
	var start_ofs := bl * progress_ratio
	var seg_length := bl * 0.15  # patrol segment length

	# Create a Path2D with a short curve for the enemy to follow.
	var path := Path2D.new()
	var patrol_curve := Curve2D.new()

	# Sample two points from the main track.
	var xf1 := curve.sample_baked_with_rotation(start_ofs)
	var xf2 := curve.sample_baked_with_rotation(minf(start_ofs + seg_length, bl))

	# Add points to the patrol curve (offset slightly from centreline).
	var nrm := Vector2.RIGHT.rotated(xf1.get_rotation()).rotated(PI * 0.5)
	var offset := nrm * 40.0  # slightly off-centre
	patrol_curve.add_point(xf1.origin + offset, Vector2.ZERO, Vector2.ZERO)
	patrol_curve.add_point(xf2.origin + offset, Vector2.ZERO, Vector2.ZERO)

	path.curve = patrol_curve
	add_child(path)

	# Place the enemy on a PathFollow2D.
	var follow := PathFollow2D.new()
	follow.loop = true
	follow.progress_ratio = 0.0
	path.add_child(follow)

	var enemy := _EnemyScene.new()
	enemy.patrol_speed = speed
	enemy.spin_direction = dir
	enemy.hit_boost = 150.0
	follow.add_child(enemy)
