## Driftlock track collision builder & editor corridor visualiser.
##
## **Runtime** — builds `StaticBody2D` with `SegmentShape2D` edges along
## the curve at `segment_distance` intervals, one edge per consecutive
## vertex pair.  Self-intersecting tracks work naturally (each segment is
## an independent collision shape).
##
## **Editor** — draws a smooth corridor fill and edge lines at the exact
## collision vertices so the drawn boundary and collision boundary match
## sub-pixel.
@tool
extends Path2D
class_name TrackBuilder

# =====================================================================
# Export
# =====================================================================

## Track clear corridor width (px).
@export var track_width: float = 300.0

## Spacing between consecutive collision-edge vertices (px along curve).
## Larger values = fewer edges but coarser approximation.
@export var segment_distance: float = 30.0

## Corridor fill colour (asphalt / track surface).
## Changed from near-black (0.08) to dark grey so tire marks are visible.
@export var corridor_color: Color = Color(0.25, 0.25, 0.25)

## Edge line colour — drawn at the collision boundary.
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.4)

## Length of the start grid-slot section along the track (px).
@export var start_section_length: float = 60.0

## Colour of the start section (matches road colour so the grid slot
## sits on a uniform surface).
@export var start_section_color: Color = Color(0.25, 0.25, 0.25)

## Line colour for the grid slot.
@export var grid_slot_color: Color = Color.WHITE

## Line width for the grid slot (px).
@export var grid_slot_line_width: float = 2.5

## Length of the checkerboard finish section along the track (px).
@export var finish_section_length: float = 60.0

## Checkerboard tile size (px).
@export var checker_tile_size: float = 10.0

## Checkerboard colour 1 (lighter).
@export var checker_color_1: Color = Color.WHITE

## Checkerboard colour 2 (darker).
@export var checker_color_2: Color = Color(0.15, 0.15, 0.15, 1.0)

## Spin zones — coloured track sections where the car builds
## spin energy more efficiently.  Each Dictionary should have:
##   start_offset (float)  — baked distance where zone begins
##   end_offset   (float)  — baked distance where zone ends
##   factor       (float)  — multiplier for rotation_efficiency
##   color        (Color)  — highlight colour (alpha works)
@export var spin_zones: Array[Dictionary] = []

## Maximum allowed angle between consecutive edge-segment vertices
## (degrees).  Angles exceeding this indicate a malformed sharp corner
## where the inner offset cusps or the wall turns too abruptly.
const MAX_VERTEX_ANGLE_DEG: float = 60.0
const MAX_VERTEX_ANGLE_RAD: float = deg_to_rad(MAX_VERTEX_ANGLE_DEG)

## When true, draw red highlights on sharp corners (validation mode).
@export var show_validation: bool = false:
	set(v):
		show_validation = v
		queue_redraw()

# Validation results.
var _sharp_corners: Dictionary = { "left": [], "right": [] }  # Array[PackedInt32Array] per side

var start_pos: Vector2
var start_dir: Vector2
var end_pos: Vector2
var end_dir: Vector2

## Returns sharp-corner vertex indices for both edges.
## Keys: "left" / "right" → Array[int].
func get_validation_result() -> Dictionary:
	return _sharp_corners.duplicate()

# =====================================================================
# Lifecycle
# =====================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		return          # editor mode — only draw
	# Collision is now built on demand via rebuild_collision()
	# so that level_base can set a procedural curve first.


## Build (or rebuild) collision walls from the current curve.
## Called by level_base._ready() after setting a procedural curve.
func rebuild_collision() -> void:
	_build_collision()


func _draw() -> void:
	if curve == null or curve.point_count < 2:
		return

	var bl := curve.get_baked_length()
	if bl <= 0.0:
		return

	var half := track_width * 0.5
	var coll_step := maxf(segment_distance, 1.0)
	var fill_step := 12.0

	# -- Fill: per-segment quads (handles self-intersection) --------
	_draw_fill_segments(bl, half, fill_step)

	# -- Start section (dark grey) ----------------------------------
	if start_section_length > 0.0:
		_draw_start_section(bl, half, fill_step)

	# -- Grid slot (F1-style start box) ----------------------------
	_draw_grid_slot(half)

	# -- Finish section (checkerboard) ------------------------------
	if finish_section_length > 0.0:
		_draw_finish_checkerboard(bl, half)

	# -- Spin zones (coloured track overlays) --------------------
	if spin_zones.size() > 0:
		_draw_spin_zones(bl, half, fill_step)

	# -- Edge lines: exact collision-boundary vertices --------------
	# Only draw segments whose midpoint is close to a REMOTE
	# centreline point (different t — i.e., a different branch of the
	# curve at a self-intersection).  Segments that are close to
	# their own centreline are valid and remain visible.
	var center_ref := _build_center_reference(curve, bl)
	var result := sample_curve(curve, half, coll_step)
	var left_edge := result["left"] as PackedVector2Array
	var right_edge := result["right"] as PackedVector2Array

	for i in range(1, left_edge.size()):
		var seg_t := i * coll_step
		if _valid_edge_segment(left_edge[i - 1], left_edge[i], center_ref, half, seg_t, coll_step):
			draw_line(left_edge[i - 1], left_edge[i], edge_color, 1.5)
		if _valid_edge_segment(right_edge[i - 1], right_edge[i], center_ref, half, seg_t, coll_step):
			draw_line(right_edge[i - 1], right_edge[i], edge_color, 1.5)

	# -- Validation overlay: red highlights on sharp corners ------
	if show_validation:
		var red := Color(1.0, 0.0, 0.0, 0.8)
		var thick := 4.0
		for side_idx in range(2):
			var edge := left_edge if side_idx == 0 else right_edge
			var bad: Array = _sharp_corners.get("left" if side_idx == 0 else "right", [])
			if bad.is_empty():
				continue
			for vi in bad:
				if vi > 0 and vi < edge.size():
					# Draw the two segments meeting at this vertex in red.
					draw_line(edge[vi - 1], edge[vi], red, thick)
					draw_line(edge[vi], edge[vi + 1], red, thick)
				# Also draw a small red circle at the vertex.
				if vi < edge.size():
					draw_circle(edge[vi], 4.0, red)


## Draw the track corridor as independent quads between consecutive
## left/right edge points.  Each quad is self-contained, so
## self-intersecting tracks render correctly — crossings just overlap.
func _draw_fill_segments(bl: float, half: float, step: float) -> void:
	var n := maxi(2, int(bl / step))
	var left: PackedVector2Array = []
	var right: PackedVector2Array = []
	left.resize(n)
	right.resize(n)

	for i in range(n):
		var t := bl * i / (n - 1)
		var xf := curve.sample_baked_with_rotation(t)
		var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
		var nrm := fwd.rotated(PI * 0.5)
		left[i] = xf.origin - nrm * half
		right[i] = xf.origin + nrm * half

	for i in range(n - 1):
		var poly := PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]])
		if _valid_draw_quad(poly):
			draw_colored_polygon(poly, corridor_color)


## Black / dark strip at the start of the track.
func _draw_start_section(bl: float, half: float, step: float) -> void:
	var sec_len := minf(start_section_length, bl * 0.5)
	var n := maxi(2, int(sec_len / step))
	var left: PackedVector2Array = []
	var right: PackedVector2Array = []
	left.resize(n)
	right.resize(n)

	for i in range(n):
		var t := sec_len * i / (n - 1)
		var xf := curve.sample_baked_with_rotation(t)
		var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
		var nrm := fwd.rotated(PI * 0.5)
		left[i] = xf.origin - nrm * half
		right[i] = xf.origin + nrm * half

	for i in range(n - 1):
		var poly := PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]])
		if _valid_draw_quad(poly):
			draw_colored_polygon(poly, start_section_color)


## Checkerboard pattern at the finish line.
func _draw_finish_checkerboard(bl: float, half: float) -> void:
	var sec_len := minf(finish_section_length, bl * 0.5)
	var tile := maxf(checker_tile_size, 2.0)
	var tiles_along := maxi(1, int(ceil(sec_len / tile)))
	var tiles_across := maxi(1, int(ceil(track_width / tile)))
	var actual_tile_along := sec_len / tiles_along
	var actual_tile_across := track_width / tiles_across

	# Precompute center + normal at each grid row along the track.
	var centers: Array[Vector2] = []
	var normals: Array[Vector2] = []
	for ai in range(tiles_along + 1):
		var t_param := bl - sec_len + actual_tile_along * ai
		var xf := curve.sample_baked_with_rotation(clampf(t_param, 0.0, bl))
		var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
		centers.append(xf.origin)
		normals.append(fwd.rotated(PI * 0.5))

	for ai in range(tiles_along):
		for wi in range(tiles_across):
			var color := checker_color_1 if ((ai + wi) % 2 == 0) else checker_color_2
			var w0 := -half + actual_tile_across * wi
			var w1 := -half + actual_tile_across * (wi + 1)
			var p00 := centers[ai] + normals[ai] * w0
			var p01 := centers[ai] + normals[ai] * w1
			var p10 := centers[ai + 1] + normals[ai + 1] * w0
			var p11 := centers[ai + 1] + normals[ai + 1] * w1
			var poly := PackedVector2Array([p00, p10, p11, p01])
			if _valid_draw_quad(poly):
				draw_colored_polygon(poly, color)


## Draw the F1-style starting grid slot: a U-shaped outline open at
## the rear, exactly matching the car's visual shape (body rectangle +
## nose cone).  The slot is positioned at the car spawn point (t = 0)
## with no forward shift, so the outline and the car are perfectly
## aligned.
##
## The car's shape dimensions come from `physics_params.gd` (the same
## resource that `car.gd::_draw()` reads), keeping the shape definition
## in one place.
func _draw_grid_slot(half: float) -> void:
	var xf := curve.sample_baked_with_rotation(0.0)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)
	var c := xf.origin

	# Car visual dimensions (match car.gd _draw()).
	var car_len := 50
	var car_wid := 25
	var nose_ofs := 2.0                # nose tip extends beyond body rect

	# Front of the slot = at the car's nose tip.
	var front_dist := car_len * 0.5 + nose_ofs
	# Side lines extend back past the car's rear.
	var back_dist := car_len * 0.5

	var slot_half := minf(car_wid * 0.5, half * 0.9)

	# Front line (perpendicular to track) at the car's nose.
	var fl := c + fwd * front_dist + nrm * slot_half
	var fr := c + fwd * front_dist - nrm * slot_half
	# Side lines run from front to rear.
	var bl := fl - fwd * (front_dist + back_dist)
	var br := fr - fwd * (front_dist + back_dist)

	draw_line(fl, fr, grid_slot_color, grid_slot_line_width)
	draw_line(fl, bl, grid_slot_color, grid_slot_line_width)
	draw_line(fr, br, grid_slot_color, grid_slot_line_width)
	# Back is NOT drawn — open end.


# =====================================================================
# Spin zones
# =====================================================================

## Draw colour overlays for each spin zone along the track.
## Also draws boundary markers (chevron arrows) at zone entry/exit.
func _draw_spin_zones(bl: float, half: float, step: float) -> void:
	for z in spin_zones:
		var start_ofs := z.get("start_offset", 0.0) as float
		var end_ofs := z.get("end_offset", 1000.0) as float
		var color := z.get("color", Color(0.2, 0.5, 1.0, 0.25)) as Color

		if start_ofs >= bl or end_ofs <= 0.0 or end_ofs <= start_ofs:
			continue

		var t := maxf(start_ofs, 0.0)
		var end := minf(end_ofs, bl)
		var prev_left := Vector2.ZERO
		var prev_right := Vector2.ZERO
		var first := true

		while t < end:
			var xf := curve.sample_baked_with_rotation(t)
			var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
			var nrm := fwd.rotated(PI * 0.5)
			var l := xf.origin - nrm * half
			var r := xf.origin + nrm * half

			if not first:
				var poly := PackedVector2Array([prev_left, l, r, prev_right])
				if _valid_draw_quad(poly):
					draw_colored_polygon(poly, color)

			prev_left = l
			prev_right = r
			first = false
			t += step

		# -- Boundary markers: chevron arrows at entry and exit --
		_draw_zone_boundary_marker(start_ofs, half, color)
		_draw_zone_boundary_marker(end_ofs, half, color)


## Draw a chevron arrow marker at a given baked offset to indicate
## a spin zone boundary.  The arrow points in the track direction.
func _draw_zone_boundary_marker(baked_offset: float, half: float, color: Color) -> void:
	if curve == null:
		return
	var bl := curve.get_baked_length()
	if baked_offset < 0.0 or baked_offset > bl:
		return

	var xf := curve.sample_baked_with_rotation(baked_offset)
	var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
	var nrm := fwd.rotated(PI * 0.5)

	var alpha := minf(color.a + 0.3, 1.0)
	var marker_color := Color(color.r, color.g, color.b, alpha)
	var arrow_size := 14.0
	var gap := 6.0  # inset from track edge

	for side in [-1.0, 1.0]:
		var base: Vector2 = xf.origin + nrm * (half - gap) * side
		var tip: Vector2 = base + fwd * arrow_size * sign(-side)
		var wing: Vector2 = base + (fwd - nrm * 0.5 * side) * arrow_size * 0.6 * sign(-side)
		var wing2: Vector2 = base + (fwd + nrm * 0.5 * side) * arrow_size * 0.6 * sign(-side)

		draw_line(base, tip, marker_color, 2.5)
		draw_line(tip, wing, marker_color, 2.0)
		draw_line(tip, wing2, marker_color, 2.0)


## Returns the bonus multiplier for the given world position.
## Returns 1.0 (no bonus) if the position is not inside any spin zone.
## Called by car.gd each physics frame.
func get_spin_zone_factor(global_pos: Vector2) -> float:
	if spin_zones.is_empty() or curve == null:
		return 1.0

	var local_pos := to_local(global_pos)
	var half := track_width * 0.5
	var bl := curve.get_baked_length()
	if bl <= 0.0:
		return 1.0

	# Coarse sweep of centreline points — every 40 px.
	# This avoids needing a closest-point query on the curve.
	var step := 40.0
	var t := 0.0
	while t <= bl:
		var xf := curve.sample_baked_with_rotation(t)
		var d_sq := xf.origin.distance_squared_to(local_pos)
		var threshold_sq := half * half * 0.64   # 80% of corridor width

		if d_sq < threshold_sq:
			# Found a nearby point — check if its baked offset is in any zone.
			for z in spin_zones:
				var zs := z.get("start_offset", 0.0) as float
				var ze := z.get("end_offset", 1000.0) as float
				if t >= zs and t <= ze:
					var factor := z.get("factor", 2.0) as float
					return maxf(factor, 1.0)
		t += step

	return 1.0


# =====================================================================
# Collision building (called from _ready at runtime)
# =====================================================================

func _build_collision() -> void:
	if curve == null or curve.point_count < 2:
		return
	var result := build(self, track_width, segment_distance)
	var walls := result["walls"] as StaticBody2D
	if walls != null:
		add_child(walls)

	# build() returns Path2D-local coordinates.  The walls are already
	# correct (they're children of this Path2D), but start/end metadata
	# must be in global space for the car / goal placement in level_base.
	start_pos = to_global(result["start_pos"] as Vector2)
	start_dir = (result["start_dir"] as Vector2).rotated(global_rotation)
	end_pos = to_global(result["end_pos"] as Vector2)
	end_dir = (result["end_dir"] as Vector2).rotated(global_rotation)

	# Validate edge sharp corners.
	var bl := curve.get_baked_length()
	var half := track_width * 0.5
	var coll_step := maxf(segment_distance, 1.0)
	var edges := sample_curve(curve, half, coll_step)
	var left_edge := edges["left"] as PackedVector2Array
	var right_edge := edges["right"] as PackedVector2Array
	_validate_sharp_corners(left_edge, right_edge)

	# Remove wall segments connected to cusp vertices (inner-offset folds
	# that point into the track corridor).  The opposite wall (200 px away)
	# still contains the car, so removing these fold segments is safe.
	_remove_cusp_segments(walls)


## Walk wall children and remove any segment whose endpoint is a
## sharp-corner vertex.  Those segments form folds pointing into the
## track corridor and are blocked by the opposite wall.
func _remove_cusp_segments(walls: StaticBody2D) -> void:
	# Collect segment indices to skip, per side.
	var skip_left: Dictionary = {}
	var skip_right: Dictionary = {}

	for vi in _sharp_corners.get("left", []):
		if vi > 0:
			skip_left[vi - 1] = true
		skip_left[vi] = true

	for vi in _sharp_corners.get("right", []):
		if vi > 0:
			skip_right[vi - 1] = true
		skip_right[vi] = true

	var to_remove: Array[Node] = []
	for child in walls.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		var seg := col.shape as SegmentShape2D
		if seg == null:
			continue

		var name := str(col.name)
		if not ("LeftEdge_" in name or "RightEdge_" in name):
			continue
		# Parse the trailing index: "LeftEdge_5" → 5
		var parts := name.rsplit("_", true, 1)
		if parts.size() != 2:
			continue
		var idx := int(parts[1])

		var skip_set := skip_left if name.begins_with("Left") else skip_right
		if skip_set.has(idx):
			to_remove.append(col)

	for node in to_remove:
		walls.remove_child(node)
		node.queue_free()


## Check each edge-vertex for a direction change > MAX_VERTEX_ANGLE_DEG.
## Stores malformed vertex indices in `_sharp_corners`.
func _validate_sharp_corners(left_edge: PackedVector2Array, right_edge: PackedVector2Array) -> void:
	_sharp_corners["left"] = []
	_sharp_corners["right"] = []

	for side in ["left", "right"]:
		var edge := left_edge if side == "left" else right_edge
		var bad: Array[int] = []
		for i in range(1, edge.size() - 1):
			var a: Vector2 = edge[i] - edge[i - 1]
			var b: Vector2 = edge[i + 1] - edge[i]
			var a_len := a.length()
			var b_len := b.length()
			if a_len < 0.01 or b_len < 0.01:
				continue
			var dot_val := clampf(a.dot(b) / (a_len * b_len), -1.0, 1.0)
			var seg_angle := acos(dot_val)
			if seg_angle > MAX_VERTEX_ANGLE_RAD:
				bad.append(i)
		_sharp_corners[side] = bad


# =====================================================================
# Public static helpers
# =====================================================================

## Sample both offset curves of `curve` at `step` t-intervals.
##
## Returns `{ "left": PackedVector2Array, "right": PackedVector2Array }`.
## Each array contains the offset-curve vertex positions.
static func sample_curve(curve: Curve2D, half: float, step: float) -> Dictionary:
	var bl := curve.get_baked_length()
	var s := maxf(step, 1.0)
	return {
		"left": _sample(curve, bl, s, half, -1.0),
		"right": _sample(curve, bl, s, half, +1.0),
	}


## Build a `StaticBody2D` with `SegmentShape2D` children along `path`.
##
## Returns a Dictionary:
##   walls      — StaticBody2D (named "TrackWalls")
##   start_pos  — centerline position at t = 0
##   start_dir  — forward direction at t = 0
##   end_pos    — centerline position at t = total
##   end_dir    — forward direction at t = total
static func build(
	path: Path2D,
	track_width: float,
	segment_distance: float,
) -> Dictionary:
	var out := {
		"walls": null,
		"start_pos": Vector2.ZERO,
		"start_dir": Vector2.RIGHT,
		"end_pos": Vector2.ZERO,
		"end_dir": Vector2.RIGHT,
	}

	var curve: Curve2D = path.curve
	if curve == null or curve.point_count < 2:
		return out

	var total := curve.get_baked_length()
	var step := maxf(segment_distance, 1.0)
	var half := track_width * 0.5
	var pts := sample_curve(curve, half, step)
	var left_pts: PackedVector2Array = pts["left"]
	var right_pts: PackedVector2Array = pts["right"]

	# Build centreline reference for edge-segment validation.
	var center_ref := _build_center_reference(curve, total)

	var walls := StaticBody2D.new()
	walls.name = "TrackWalls"
	out["walls"] = walls

	var side_names := ["Left", "Right"]
	for si in range(2):
		var arr = left_pts if si == 0 else right_pts
		for i in range(arr.size() - 1):
			var seg_t := i * step
			if not _valid_edge_segment(arr[i], arr[i + 1], center_ref, half, seg_t, step):
				continue    # segment too close to a REMOTE centreline point
			var seg := SegmentShape2D.new()
			seg.a = arr[i]
			seg.b = arr[i + 1]
			var col := CollisionShape2D.new()
			col.shape = seg
			col.name = "%sEdge_%d" % [side_names[si], i]
			walls.add_child(col)

	# Start / end metadata.
	if left_pts.size() > 0:
		var xf0 := curve.sample_baked_with_rotation(0.0)
		out["start_pos"] = xf0.origin
		out["start_dir"] = Vector2.RIGHT.rotated(xf0.get_rotation())

	var exf := curve.sample_baked_with_rotation(total)
	out["end_pos"] = exf.origin
	out["end_dir"] = Vector2.RIGHT.rotated(exf.get_rotation())

	return out


# =====================================================================
# Private
# =====================================================================

## Sample one offset curve at uniform t-intervals.
static func _sample(curve: Curve2D, total: float, step: float, half: float, sign_: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var t := 0.0
	while t <= total:
		var xf = curve.sample_baked_with_rotation(t)
		var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
		var nrm := fwd.rotated(PI * 0.5)
		pts.append(xf.origin + nrm * half * sign_)
		t += step

	# End cap: if last regular point is more than half-step from total,
	# add one more at total to avoid a large gap at the finish.
	if pts.size() > 0:
		var last_dist := total - (pts.size() - 1) * step
		if last_dist > step * 0.5:
			var xf = curve.sample_baked_with_rotation(total)
			var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
			var nrm := fwd.rotated(PI * 0.5)
			pts.append(xf.origin + nrm * half * sign_)

	return pts


## Build a dense reference array of centreline positions (with
## corresponding baked t-values) for edge-segment validation.
##
## Returns `{ "pos": PackedVector2Array, "t": PackedFloat32Array }`.
## Used by both `build()` and `_draw()` so the visual boundary matches
## the collision boundary.  The t-values enable remote-branch detection
## at self-intersections.
static func _build_center_reference(curve: Curve2D, total: float) -> Dictionary:
	var n := maxi(200, int(total / 2))
	var pos: PackedVector2Array = []
	var t: PackedFloat32Array = []
	pos.resize(n)
	t.resize(n)
	for i in range(n):
		t[i] = total * i / float(n - 1)
		pos[i] = curve.sample_baked_with_rotation(t[i]).origin
	return { "pos": pos, "t": t }


## A wall segment is valid unless its midpoint is both:
##
##   1. inside the track corridor (distance < `half` from the
##      centreline), AND
##   2. the nearest centreline point is **remote** in t-space
##      (|t_diff| > `step × REMOTE_T_FACTOR`), meaning it belongs
##      to a different branch at a self-intersection.
##
## This allows filtering at the full corridor width (`MIN_DIST_FACTOR =
## 1.0`) without accidentally dropping valid segments in tight curves,
## because those segments are always closest to their **own** centreline
## point (small t-difference).
static func _valid_edge_segment(a: Vector2, b: Vector2, center_ref: Dictionary, half: float, seg_t: float, step: float) -> bool:
	# Only filter when the nearest centreline point is far in t-space
	# (a different branch at a self-intersection) AND the segment
	# midpoint is very close to that remote centreline.  The threshold
	# `half × 0.6` removes the innermost crossing segments (which would
	# block the opposing corridor) while keeping outer wall segments
	# that frame the opening so the car doesn't fall off.
	const MIN_DIST_FACTOR := 0.6
	const REMOTE_T_FACTOR := 6.0

	var mid := (a + b) * 0.5
	var center_pos: PackedVector2Array = center_ref["pos"]
	var center_t: PackedFloat32Array = center_ref["t"]
	var threshold_sq := half * half * MIN_DIST_FACTOR * MIN_DIST_FACTOR

	# Find the globally nearest centreline point (full scan — no early
	# exit, because we need the true minimum to decide remoteness).
	var min_d_sq := INF
	var min_t := -INF
	for i in range(center_pos.size()):
		var d_sq := mid.distance_squared_to(center_pos[i])
		if d_sq < min_d_sq:
			min_d_sq = d_sq
			min_t = center_t[i]

	# If the nearest point is remote in t-space AND within threshold,
	# the segment passes through the other branch's corridor — skip it.
	if min_d_sq < threshold_sq and abs(min_t - seg_t) > step * REMOTE_T_FACTOR:
		return false
	return true


## Returns true if a 4-vertex polygon is safe to draw (non-degenerate,
## minimum area, convex).  Prevents "triangulation failed" errors from
## `draw_colored_polygon` on tight curve segments.
static func _valid_draw_quad(poly: PackedVector2Array) -> bool:
	if poly.size() < 4:
		return false
	# Minimum area threshold (px²) — skip zero-area slivers.
	var area := 0.0
	for i in range(4):
		var j := (i + 1) % 4
		area += poly[i].cross(poly[j])
	area = abs(area) * 0.5
	if area < 1.0:
		return false
	# Check convexity: all cross products must have the same sign.
	var sign_ := 0.0
	for i in range(4):
		var a := poly[i]
		var b := poly[(i + 1) % 4]
		var c := poly[(i + 2) % 4]
		var cross := (b - a).cross(c - b)
		if sign_ == 0.0:
			sign_ = sign(cross)
		elif sign_ * cross < 0.0:
			return false  # different sign → concave or self-intersecting
	return true
