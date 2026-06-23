## Test: self‑intersecting track (level_01) generates collision segments
## from both track branches at the spatial crossing point.
##
## Approach:
##   1. Load level_01, let the TrackBuilder build collision edges.
##   2. Count total edges — expect ≈ 2 × ceil(bl / step) for a
##      self‑intersecting track (no segments merged).
##   3. Find the crossing: sample the centreline at fine intervals,
##      locate two non‑adjacent samples within 1 track‑width.
##   4. Parse the edge naming ("LeftEdge_N" / "RightEdge_N") to map
##      each segment to its index → approximate t.
##   5. Verify that near the crossing there are edges from both the
##      early part of the curve (low index) and the late part
##      (high index) — proving both branches are solid at the overlap.
##   6. Physics shape query at the crossing — a small circle should
##      intersect collision shapes from both branches.
##
## Run:  godot --headless --path . tests/test_self_intersection.tscn
extends Node2D

const TRACK_WIDTH := 200.0
const HALF := TRACK_WIDTH * 0.5

var _assert_pass := 0
var _assert_fail := 0
var _entries: Array[String] = []


# ═════════════════════════════════════════════════════════════════════
# Lifecycle
# ═════════════════════════════════════════════════════════════════════

func _ready() -> void:
	await _run_test()
	_print_summary()
	get_tree().quit()


# ═════════════════════════════════════════════════════════════════════
# Test
# ═════════════════════════════════════════════════════════════════════

func _run_test() -> void:
	_sep()
	_log("SELF‑INTERSECTION TEST — level_01 collision at crossing")
	_sep()
	_log("")

	# ── 1. Instantiate level ──────────────────────────────────────
	var level := preload("res://scenes/levels/level_01.tscn").instantiate()
	add_child(level)
	await get_tree().process_frame   # _ready() chain fires
	await get_tree().physics_frame   # physics shapes register

	var track := level.get_node("TrackPath") as Path2D
	_assert(track != null, "TrackPath node exists")
	var walls := track.get_node("TrackWalls") as StaticBody2D
	_assert(walls != null, "TrackWalls StaticBody2D was built")
	var curve := track.curve
	_assert(curve != null and curve.point_count >= 2, "Curve has ≥ 2 points")

	var bl := curve.get_baked_length()
	var step = track.segment_distance
	_log("Curve baked length: %.0f px   segment_distance: %.0f px" % [bl, step])

	# ── 2. Edge count ─────────────────────────────────────────────
	# Self‑intersection filtering removes segments too close to the
	# centreline, so the count is less than 2 × ceil(bl/step).  We
	# still expect at least 75 % of the theoretical maximum.
	var edge_count := walls.get_child_count()
	var expected_per_side := int(ceil(bl / step)) + 1
	var expected_total := expected_per_side * 2
	_assert(edge_count >= int(expected_total * 0.75),
		"Total CollisionShape2D edges = %d  (expected ~ %d = %d/side × 2, "
		+ "min %d with filtering)" \
		% [edge_count, expected_total, expected_per_side, int(expected_total * 0.75)])
	_log("")

	# ── 3. Collect segment data from edge names ───────────────────
	# Names are "LeftEdge_N" or "RightEdge_N" where N is the segment
	# index along the curve.  We can derive approximate t from index.
	var segments: Array[Dictionary] = []
	for child in walls.get_children():
		var col := child as CollisionShape2D
		if col == null or col.shape == null:
			continue
		var seg := col.shape as SegmentShape2D
		if seg == null:
			continue
		var is_left := col.name.begins_with("Left")
		var idx := _parse_index(col.name)
		var mid := (seg.a + seg.b) * 0.5
		segments.append({
			"idx": idx,
			"mid": mid,
			"a": seg.a,
			"b": seg.b,
			"is_left": is_left,
			"name": col.name,
		})

	_assert(segments.size() == edge_count,
		"All %d children parsed as SegmentShape2D with index" % edge_count)

	# ── 4. Find the spatial crossing ──────────────────────────────
	var n_samples := maxi(2, int(bl / 5.0))
	var samples: Array[Vector2] = []
	samples.resize(n_samples)
	for i in range(n_samples):
		var t := bl * i / (n_samples - 1)
		samples[i] = curve.sample_baked_with_rotation(t).origin

	var crossing_local := Vector2.ZERO
	var sample_a := -1
	var sample_b := -1
	var found := false
	for i in range(n_samples):
		for j in range(i + 40, n_samples):
			if samples[i].distance_squared_to(samples[j]) < HALF * HALF:
				crossing_local = (samples[i] + samples[j]) * 0.5
				sample_a = i
				sample_b = j
				_log("Crossing found:")
				_log("  sample %d (t≈%.0f) at local (%.0f, %.0f)" \
					% [i, bl*i/(n_samples-1), samples[i].x, samples[i].y])
				_log("  sample %d (t≈%.0f) at local (%.0f, %.0f)" \
					% [j, bl*j/(n_samples-1), samples[j].x, samples[j].y])
				_log("  crossing centre local: (%.0f, %.0f)" \
					% [crossing_local.x, crossing_local.y])
				found = true
				break
		if found:
			break

	_assert(found,
		"Curve has a spatial self‑intersection (two non‑adjacent centre points within 1 track‑width)")
	_assert(sample_a >= 0 and sample_b >= 0,
		"Both crossing branches have valid indices")
	_log("")

	# ── 5. Find segments from both branches near the crossing ────
	# Convert sample indices to t-values, then to edge indices.
	var t_per_sample := bl / float(n_samples - 1)
	var crossing_t_a := sample_a * t_per_sample
	var crossing_t_b := sample_b * t_per_sample
	var t_mid := (crossing_t_a + crossing_t_b) * 0.5
	var idx_split := int(t_mid / step)  # edge index that splits early/late

	var search_radius_sq := (HALF * 1.2) * (HALF * 1.2)
	var branch_early: Array[Dictionary] = []
	var branch_late: Array[Dictionary] = []

	for seg in segments:
		var d_sq = seg.mid.distance_squared_to(crossing_local)
		if d_sq > search_radius_sq:
			continue
		# Approximate t from edge index: segment i starts at t≈i×step.
		var seg_t = seg.idx * step
		if seg_t < t_mid:
			branch_early.append(seg)
		else:
			branch_late.append(seg)

	_log("Edges within %.0f px of crossing (split at idx %d, t=%.0f):" \
		% [HALF * 1.2, idx_split, t_mid])
	_log("  Early branch (t < %.0f): %d edge(s)" % [t_mid, branch_early.size()])
	for s in branch_early:
		_log("    %-16s idx=%3d  t≈%4.0f  mid=(%.0f, %.0f)" \
			% [s.name, s.idx, s.idx * step, s.mid.x, s.mid.y])
	_log("  Late branch (t ≥ %.0f): %d edge(s)" % [t_mid, branch_late.size()])
	for s in branch_late:
		_log("    %-16s idx=%3d  t≈%4.0f  mid=(%.0f, %.0f)" \
			% [s.name, s.idx, s.idx * step, s.mid.x, s.mid.y])

	# Each branch must have at least one edge near the crossing.
	_assert(branch_early.size() >= 1,
		"Early branch has %d edge(s) near crossing" % branch_early.size())
	_assert(branch_late.size() >= 1,
		"Late branch has %d edge(s) near crossing" % branch_late.size())
	_log("")

	# ── 6. Physics shape query at crossing ───────────────────────
	var space := get_world_2d().direct_space_state
	var crossing_global := track.to_global(crossing_local)
	var params := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = HALF         # 100 px — reaches the edges at ±100 from centre
	params.shape = circle
	params.transform = Transform2D(0.0, crossing_global)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var hits := space.intersect_shape(params)
	_log("Physics shape query at crossing (circle r=%.0f): %d hit(s)" \
		% [circle.radius, hits.size()])

	# Count unique shapes (one per overlapping CollisionShape2D).
	var unique_shape_ids: Array[int] = []
	var unique_bodies: Array[RID] = []
	for h in hits:
		var sid: int = h.get("shape", -1)
		var rid: RID = h.get("rid", RID())
		if sid >= 0 and not sid in unique_shape_ids:
			unique_shape_ids.append(sid)
		if rid.is_valid() and not rid in unique_bodies:
			unique_bodies.append(rid)
		var collider_info = str(h.get("collider", "?"))
		_log("    hit: collider=%s  shape=%d  rid=%s" % [collider_info, sid, str(rid)])

	_assert(unique_shape_ids.size() >= 2,
		"Physics query: %d unique shape IDs at crossing (≥ 2 confirms both branches)" \
		% unique_shape_ids.size())

	# ── 7. Side balance (informational) ────────────────────────────
	# With self‑intersection filtering the left/right counts can differ
	# because geometry is asymmetric at the crossing — this is expected.
	var left_count := 0
	var right_count := 0
	for seg in segments:
		if seg.is_left:
			left_count += 1
		else:
			right_count += 1
	_log("Left edges: %d   Right edges: %d  (difference expected with filtering)" \
		% [left_count, right_count])

	_log("")
	_log("── ALL CHECKS DONE ──")


# ═════════════════════════════════════════════════════════════════════
# Helpers
# ═════════════════════════════════════════════════════════════════════

## Parse the numeric index from an edge name like "LeftEdge_42".
static func _parse_index(name: String) -> int:
	# Find the last underscore and parse the trailing digits.
	var us := name.rfind("_")
	if us < 0:
		return -1
	return int(name.substr(us + 1))


func _assert(cond: bool, msg: String) -> void:
	if cond:
		_assert_pass += 1
	else:
		_assert_fail += 1
		_log("  FAIL: %s" % msg)


func _log(text: String) -> void:
	_entries.append(text)
	print(text)


func _sep() -> void:
	_log("=".repeat(60))


func _print_summary() -> void:
	_log("")
	_sep()
	_log("RESULTS")
	_sep()
	_log("Assertions: %d / %d passed" % [_assert_pass, _assert_pass + _assert_fail])
	if _assert_fail > 0:
		_log("%d ASSERTION(S) FAILED — review messages above" % _assert_fail)
	else:
		_log("ALL ASSERTIONS PASSED")
	_sep()
