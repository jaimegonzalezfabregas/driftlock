#!/usr/bin/env godot -s
## One-time tool: bake hardcoded track waypoints into each level scene's TrackPath curve.
##
## After running this, each .tscn file has its curve data embedded and a correct
## `level_index` on the root node.  Users can then edit waypoints from the editor.
##
## Usage:
##   godot --headless -s tools/bake_track_curves.gd
@tool
extends SceneTree


const LEVEL_BASE_SCRIPT := preload("res://scenes/levels/level_base.gd")
const LEVEL_PATHS: Array[String] = [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_02.tscn",
	"res://scenes/levels/level_03.tscn",
	"res://scenes/levels/level_04.tscn",
	"res://scenes/levels/level_05.tscn",
	"res://scenes/levels/level_06.tscn",
	"res://scenes/levels/level_07.tscn",
	"res://scenes/levels/level_08.tscn",
]


func _initialize() -> void:
	print("Baking track curves into scene files…")
	print("")

	var ok_count := 0
	var fail_count := 0

	for level_index in range(LEVEL_PATHS.size()):
		var path := LEVEL_PATHS[level_index]

		# -- 1. Generate waypoints from hardcoded data --------------
		var temp_base = LEVEL_BASE_SCRIPT.new()
		temp_base.level_index = level_index
		var waypoints: Array[Dictionary] = temp_base._get_track_waypoints()
		temp_base.free()

		if waypoints.is_empty():
			print("  SKIP %s — no waypoints for level_index=%d" % [path.get_file(), level_index])
			fail_count += 1
			continue

		# -- 2. Load the scene --------------------------------------
		var scene := load(path) as PackedScene
		if scene == null:
			print("  ERROR %s — could not load scene" % path.get_file())
			fail_count += 1
			continue

		var instance := scene.instantiate()
		if instance == null:
			print("  ERROR %s — could not instantiate" % path.get_file())
			fail_count += 1
			continue

		# -- 3. Find TrackPath and set curve ------------------------
		var track_path := instance.get_node_or_null("TrackPath") as Path2D
		if track_path == null:
			print("  ERROR %s — no TrackPath node" % path.get_file())
			instance.free()
			fail_count += 1
			continue

		var curve := Curve2D.new()
		for wp in waypoints:
			curve.add_point(wp.pos, wp.inside, wp.out)
		track_path.curve = curve

		# -- 4. Set level_index on root node ------------------------
		instance.set("level_index", level_index)

		# -- 5. Pack and save ---------------------------------------
		var packed := PackedScene.new()
		var pack_result := packed.pack(instance)
		instance.free()

		if pack_result != OK:
			print("  ERROR %s — PackedScene.pack() returned %d" % [path.get_file(), pack_result])
			fail_count += 1
			continue

		var save_result := ResourceSaver.save(packed, path)
		if save_result != OK:
			print("  ERROR %s — ResourceSaver.save() returned %d" % [path.get_file(), save_result])
			fail_count += 1
			continue

		print("  OK   %s — level_index=%d, %d waypoints baked" % [path.get_file(), level_index, waypoints.size()])
		ok_count += 1

	print("")
	print("Done.  %d baked, %d failed." % [ok_count, fail_count])

	# Reload the scenes so the editor picks up changes.
	if ok_count > 0:
		for path in LEVEL_PATHS:
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)

	quit(0 if fail_count == 0 else 1)
