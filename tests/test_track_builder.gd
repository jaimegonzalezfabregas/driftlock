## TrackBuilder test — verify build() returns correct structure.
##
## Run:  godot --headless --path . -s tests/test_track_builder.gd
extends SceneTree

var _errors := 0
var _test_count := 0

func _init() -> void:
	_sep()
	_log("TRACKBUILDER TEST — build() output structure")
	_sep()
	_log("")

	_test_straight()
	_test_gentle()

	print("\n=== Summary ===")
	print("Tests: ", _test_count)
	if _errors == 0:
		print("✓ ALL PASS")
	else:
		print("✗ ", _errors, " FAILURES")
	quit()


func _test(label: String, curve: Curve2D) -> void:
	_test_count += 1
	var path := Path2D.new()
	path.curve = curve
	var TV = preload("res://scripts/track_builder.gd")
	var out = TV.build(path, 200.0, 30.0)
	path.queue_free()

	# Check output keys
	if typeof(out) != TYPE_DICTIONARY:
		_log("  ✗ %s: output is not a Dictionary" % label)
		_errors += 1
		return

	var has_walls = out.has("walls")
	var has_start_pos = out.has("start_pos")
	var has_start_dir = out.has("start_dir")

	if not has_walls or not has_start_pos or not has_start_dir:
		_log("  ✗ %s: missing key(s)  walls=%s  start_pos=%s  start_dir=%s" \
			% [label, has_walls, has_start_pos, has_start_dir])
		_errors += 1
		return

	var walls = out["walls"]
	if walls == null or not (walls is StaticBody2D):
		_log("  ✗ %s: 'walls' is not a StaticBody2D" % label)
		_errors += 1
		return

	if walls.get_child_count() == 0:
		_log("  ✗ %s: walls has no children" % label)
		_errors += 1
		return

	var seg_count := 0
	for child in walls.get_children():
		var col := child as CollisionShape2D
		if col != null and col.shape is SegmentShape2D:
			seg_count += 1

	if seg_count == 0:
		_log("  ✗ %s: no SegmentShape2D children found" % label)
		_errors += 1
		return

	var sp = out["start_pos"]
	var sd = out["start_dir"]
	if typeof(sp) != TYPE_VECTOR2:
		_log("  ✗ %s: start_pos is not Vector2" % label)
		_errors += 1
		return
	if typeof(sd) != TYPE_VECTOR2:
		_log("  ✗ %s: start_dir is not Vector2" % label)
		_errors += 1
		return

	_log("  ✓ %s: walls=%d children, %d SegmentShape2D, start_pos=(%.0f,%.0f) start_dir=(%.2f,%.2f)" \
		% [label, walls.get_child_count(), seg_count, sp.x, sp.y, sd.x, sd.y])

	walls.queue_free()


func _test_straight() -> void:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(40, 0))
	c.add_point(Vector2(400, 0), Vector2(-40, 0), Vector2.ZERO)
	_test("straight", c)


func _test_gentle() -> void:
	var c := Curve2D.new()
	c.add_point(Vector2(0, 0), Vector2.ZERO, Vector2(50, 0))
	c.add_point(Vector2(200, 80), Vector2(-30, -20), Vector2(30, -20))
	c.add_point(Vector2(400, 0), Vector2(-30, 20), Vector2.ZERO)
	_test("gentle", c)


func _log(text: String) -> void:
	print(text)


func _sep() -> void:
	print("=".repeat(60))
