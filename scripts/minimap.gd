## Minimap Control — draws track outline, spin zones, and car position.
## Attached to a Control node in the HUD.  The level sets references
## via `set_track(curve, start_pos, end_pos)` and `set_car(car_node)`.
extends Control

## World‑space track centreline points (packed for speed).
var _track_points: PackedVector2Array = []
var _start_pos: Vector2 = Vector2.ZERO
var _end_pos: Vector2 = Vector2.ZERO
var _car_ref: Node = null

## World‑space bounds of the track for normalising into minimap coords.
var _world_min: Vector2 = Vector2.ZERO
var _world_max: Vector2 = Vector2(100.0, 100.0)
var _world_span: Vector2 = Vector2(100.0, 100.0)

## Padding inside the minimap rect (px).
const PADDING: float = 6.0


## Call once at setup with the track Curve2D.
func set_track(curve: Curve2D, start: Vector2, end: Vector2) -> void:
	if curve == null or curve.point_count < 2:
		return
	var bl := curve.get_baked_length()
	if bl <= 0.0:
		return

	var step := 30.0
	var pts: PackedVector2Array = []
	var t := 0.0
	while t <= bl:
		var xf := curve.sample_baked_with_rotation(t)
		pts.append(xf.origin)
		t += step

	_track_points = pts
	_start_pos = start
	_end_pos = end

	# Compute world bounds from track points.
	if pts.size() > 0:
		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		for p in pts:
			if p.x < min_x: min_x = p.x
			if p.y < min_y: min_y = p.y
			if p.x > max_x: max_x = p.x
			if p.y > max_y: max_y = p.y
		_world_min = Vector2(min_x, min_y)
		_world_max = Vector2(max_x, max_y)
		_world_span = _world_max - _world_min
		# Ensure minimum span (avoid div-by-zero for degenerate tracks).
		if _world_span.x < 1.0: _world_span.x = 1.0
		if _world_span.y < 1.0: _world_span.y = 1.0

	queue_redraw()


## Set the car node reference for position tracking.
func set_car(car: Node) -> void:
	_car_ref = car


## Convert a world position to minimap-local coordinates.
func _world_to_minimap(world: Vector2) -> Vector2:
	var margin := PADDING
	var draw_size := size - Vector2(margin, margin) * 2.0
	var rel := (world - _world_min) / _world_span
	var mapped := Vector2(rel.x * draw_size.x, rel.y * draw_size.y)
	mapped.y = draw_size.y - mapped.y  # flip Y axis
	return mapped + Vector2(margin, margin)


func _draw() -> void:
	if _track_points.size() < 2:
		return

	# Background circle (dark translucent).
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5
	draw_circle(center, radius, Color(0.0, 0.0, 0.0, 0.55))

	# Track outline (thin grey line).
	var track_color := Color(0.6, 0.6, 0.6, 0.7)
	var prev := _world_to_minimap(_track_points[0])
	for i in range(1, _track_points.size()):
		var curr := _world_to_minimap(_track_points[i])
		draw_line(prev, curr, track_color, 1.5)
		prev = curr

	# Start marker (green dot).
	draw_circle(_world_to_minimap(_start_pos), 3.0, Color(0.0, 0.8, 0.0, 0.9))

	# End / finish marker (checkered dot — white/black).
	var finish_pos := _world_to_minimap(_end_pos)
	draw_circle(finish_pos, 3.0, Color(1.0, 1.0, 1.0, 0.9))
	draw_circle(finish_pos, 1.5, Color(0.0, 0.0, 0.0, 0.9))

	# Car position (bright yellow dot).
	if _car_ref != null and is_instance_valid(_car_ref):
		var car_pos: Variant = _car_ref.get("global_position")
		if typeof(car_pos) == TYPE_VECTOR2:
			var mp := _world_to_minimap(car_pos)
			draw_circle(mp, 4.0, Color(1.0, 0.9, 0.0, 1.0))  # yellow dot
			# Small white inner dot for visibility.
			draw_circle(mp, 2.0, Color(1.0, 1.0, 1.0, 0.8))
