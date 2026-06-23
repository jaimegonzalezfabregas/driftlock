## Test: collision edge alignment and spacing consistency.
##
## Builds curves with TrackVisualiser.build(), extracts the SegmentShape2D
## endpoints, and measures:
##   1. Alignment — max distance from each endpoint to the theoretical
##      offset curve (dense reference).  PASS if max < 15 px on target.
##   2. Spacing — coefficient of variation of edge lengths.
##      PASS if cv ≤ 1.0 and max edge length ≤ 3× step.
##
## Synthetic curves are informational.  Only `level_01_replica` counts
## toward pass/fail.
extends SceneTree

var _half := 100.0  # track_width * 0.5  (no wall_thickness)
var _step := 30.0
var _curve: Curve2D
var _errors := 0
var _test_count := 0

func _init() -> void:
	_test("straight", _make_straight(), false)
	_test("gentle_curve", _make_gentle(), false)
	_test("sharp_bend", _make_sharp(), false)
	_test("level_01_replica", _make_level01(), true)

	print("\n=== Summary ===")
	print("Segments checked: ", _test_count)
	if _errors == 0:
		print("✓ ALL PASS")
	else:
		print("✗ ", _errors, " FAILURES")
	quit()

# ── Curve factories ────────────────────────────────────────────────

static func _build_curve(points: Array) -> Curve2D:
	var c := Curve2D.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]), Vector2(p[2], p[3]), Vector2(p[4], p[5]))
	return c

func _make_straight() -> Curve2D:
	return _build_curve([
		[0, 0,       0, 0,  40, 0],
		[600, 0,   -40, 0,   0, 0],
	])

func _make_gentle() -> Curve2D:
	return _build_curve([
		[0, 0,       0, 0,   50, 0],
		[300, 100, -30, -20, 30, -20],
		[600, 0,   -30, 20,   0, 0],
	])

func _make_sharp() -> Curve2D:
	return _build_curve([
		[0, 0,        0, 0,   50, 0],
		[100, -100, -10, -20, 10, -20],
		[200, 0,    -10, 20,  10, -20],
		[300, -100, -10, -20, 10, -20],
		[400, 0,    -10, 20,   0, 0],
	])

func _make_level01() -> Curve2D:
	var pts := [
		[-213.46048, -280.31622,  213.46048,  280.31622,  -68, 560],
		[-330.09320, -360.18637,  330.09320,  360.18637,  675, 577],
		[-249.68716, -262.65585,  249.68716,  262.65585, 1427, 701],
		[ 489.52960,  430.90527, -489.52960, -430.90527, 1759, 413],
		[ 129.88255,   50.86649, -129.88255,  -50.86649,  -62,  11],
		[   2.59373,  108.93721,   -2.59373, -108.93721, -279,-230],
		[-233.43689,   10.37499,  233.43689,  -10.37499,  -46,-471],
		[   0.0,        0.0,        0.0,        0.0,       154, -82],
		[   0.0,        0.0,        0.0,        0.0,       110, 307],
	]
	var offset := Vector2(488, 219)
	var c := Curve2D.new()
	for p in pts:
		c.add_point(Vector2(p[4], p[5]) + offset, Vector2(p[0], p[1]), Vector2(p[2], p[3]))
	return c

# ── Test runner ────────────────────────────────────────────────────

func _test(label: String, curve: Curve2D, is_target: bool) -> void:
	_curve = curve
	if curve.point_count < 2:
		return

	var path := Path2D.new()
	path.curve = curve
	var bl := curve.get_baked_length()
	var TV = preload("res://scripts/track_builder.gd")
	var out = TV.build(path, 200.0, _step)
	path.queue_free()

	# Extract segment endpoints from the StaticBody2D children.
	# TrackBuilder names them "LeftEdge_N" or "RightEdge_N".
	var left_pts: PackedVector2Array = []
	var right_pts: PackedVector2Array = []
	var walls: StaticBody2D = out["walls"]
	for child in walls.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		var seg := col.shape as SegmentShape2D
		if seg == null:
			continue
		var is_left := col.name.begins_with("Left")
		var pts = left_pts if is_left else right_pts
		pts.append(seg.a)
		pts.append(seg.b)

	# Deduplicate (adjacent segments share endpoints).
	left_pts = _dedup(left_pts)
	right_pts = _dedup(right_pts)

	print("  %-20s bl=%.0f  edges L=%d R=%d" % [label, bl, left_pts.size(), right_pts.size()])
	_test_count += left_pts.size() + right_pts.size()

	# Build reference offset curves.
	var n_ref := maxi(400, int(bl / 2))
	var lref: PackedVector2Array = []
	var rref: PackedVector2Array = []
	lref.resize(n_ref)
	rref.resize(n_ref)
	for i in range(n_ref):
		var t := bl * i / (n_ref - 1)
		var xf := curve.sample_baked_with_rotation(t)
		var fwd := Vector2.RIGHT.rotated(xf.get_rotation())
		var nrm := fwd.rotated(PI * 0.5)
		lref[i] = xf.origin - nrm * _half
		rref[i] = xf.origin + nrm * _half

	if not _check_align(label + " L", left_pts, lref, n_ref, is_target):
		_is_error(is_target)
	if not _check_align(label + " R", right_pts, rref, n_ref, is_target):
		_is_error(is_target)

	# Spacing = distances between consecutive points.
	if not _check_spacing(label + " L", left_pts, is_target):
		_is_error(is_target)
	if not _check_spacing(label + " R", right_pts, is_target):
		_is_error(is_target)

	walls.queue_free()

func _is_error(serious: bool) -> void:
	if serious:
		_errors += 1

func _dedup(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.is_empty():
		return pts
	var out: PackedVector2Array = [pts[0]]
	for i in range(1, pts.size()):
		if pts[i].distance_squared_to(out[out.size() - 1]) > 0.01:
			out.append(pts[i])
	return out

# ── Checks ─────────────────────────────────────────────────────────

func _check_align(label: String, pts: PackedVector2Array, ref_pts: PackedVector2Array, n: int, is_target: bool) -> bool:
	if pts.is_empty():
		return true
	var max_dist := 0.0
	var far := 0
	var m = ref_pts.size()
	for pos in pts:
		var best_d := INF
		for i in range(m):
			var d = pos.distance_squared_to(ref_pts[i])
			if d < best_d: best_d = d
		var d := sqrt(best_d)
		if d > max_dist: max_dist = d
		if d > 15.0: far += 1
	var fail := far > 0 and is_target
	var mark := "✗" if fail else ("✓" if is_target else "·")
	print("  %s %-20s align  max %.1f  (pts=%d)" % [mark, label, max_dist, pts.size()])
	return not fail

func _check_spacing(label: String, pts: PackedVector2Array, is_target: bool) -> bool:
	if pts.size() < 3:
		return true
	var gaps: Array = []
	for i in range(1, pts.size()):
		gaps.append(pts[i].distance_to(pts[i-1]))
	var avg := 0.0
	for g in gaps: avg += g
	avg /= gaps.size()
	var v := 0.0
	for g in gaps: v += (g - avg) * (g - avg)
	v /= gaps.size()
	var std := sqrt(v)
	var min_g := INF; var max_g := -INF
	for g in gaps:
		if g < min_g: min_g = g
		if g > max_g: max_g = g
	var cv := std / maxf(avg, 1.0)
	var bad := (max_g > _step * 3.0 or cv > 1.0) and is_target
	var mark := "✗" if bad else ("✓" if is_target else "·")
	print("  %s %-20s spacing  avg %.0f  std %.0f  [%.0f … %.0f]  cv=%.2f" % [mark, label, avg, std, min_g, max_g, cv])
	return not bad
