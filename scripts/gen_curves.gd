## Run with: godot --path /home/jaime/GodotProjects/driftlock --headless --script scripts/gen_curves.gd
## Outputs Curve2D data for 7 progressive tracks.
extends Node

const TSCN_TEMPLATE := """[gd_scene load_steps=4 format=3 uid="uid://{uid}"]

[ext_resource type="Script" uid="uid://{level_uid}" path="{level_script}" id="1"]
[ext_resource type="Script" uid="uid://bpthnnhd5py3j" path="res://scripts/track_builder.gd" id="2"]

[sub_resource type="Curve2D" id="Curve2D_{curve_id}"]
_data = {{
"points": {points_data}
}}
point_count = {point_count}

[node name="{node_name}" type="Node2D"]
script = ExtResource("1")

[node name="TrackPath" type="Path2D" parent="."]
position = {track_pos}
scale = Vector2(1, 1)
curve = SubResource("Curve2D_{curve_id}")
script = ExtResource("2")
track_width = 220.0
segment_distance = 25.0
{spin_zones}
"""

# Each track: list of [in_x, in_y, out_x, out_y, pos_x, pos_y]
# in/out are relative offsets from the point position.
# Tracks designed to be progressively longer and more complex.

var TRACKS := [
	{  # Level 1 - Simple oval (length ~2000)
		"name": "Level01",
		"script": "res://scenes/levels/level_01.gd",
		"uid": "cud3432fh0vxf",
		"level_uid": "bjt8wj0hef4jc",
		"curve_id": "L1",
		"track_pos": "Vector2(350, 350)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 200, 200],  # bottom-left, going right
			[-30, -30, 30, 30, 400, 200],  # bottom-middle
			[-30, -30, 30, 30, 600, 200],  # bottom-right, curve up
			[-30, 30, 30, -30, 600, 50],   # top-right, curve left
			[-30, -30, 30, 30, 400, 50],   # top-middle, curve left
			[-30, -30, 30, 30, 200, 50],   # top-left, curve down
			[-30, 30, 30, -30, 200, 200],  # back to start
		]
	},
	{  # Level 2 - S-curves (length ~2600)
		"name": "Level002",
		"script": "res://scenes/levels/level_02.gd",
		"uid": "level02uid",
		"level_uid": "level02scr",
		"curve_id": "L2",
		"track_pos": "Vector2(250, 350)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 150, 200],  # start, going right
			[-30, -30, 30, 30, 350, 200],  # straight
			[-30, 30, 30, -30, 550, 200],  # curve up-right
			[-30, -30, 30, 30, 750, 120],  # S-bend peak
			[30, 30, -30, -30, 750, 50],   # curve left
			[-30, -30, 30, 30, 550, 50],   # straight left
			[30, 30, -30, -30, 350, 50],   # curve down-left
			[-30, -30, 30, 30, 200, 120],  # S-bend low
			[-30, 30, 30, -30, 150, 200],  # curve back to start
		]
	},
	{  # Level 3 - Figure-8 (length ~3200, self-intersecting)
		"name": "Level003",
		"script": "res://scenes/levels/level_03.gd",
		"uid": "level03uid",
		"level_uid": "level03scr",
		"curve_id": "L3",
		"track_pos": "Vector2(300, 300)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 200, 200],  # start bottom-left
			[-30, -30, 30, 30, 400, 200],  # go right
			[-30, -30, 30, 30, 600, 200],  # more right
			[-30, 30, 30, -30, 700, 100],  # curve up-right to top
			[-30, -30, 30, 30, 600, 50],   # go left
			[-30, -30, 30, 30, 400, 50],   # more left  
			[-30, -30, 30, 30, 200, 50],   # to top-left
			[30, -30, -30, 30, 100, 100],  # curve down to center (cross)
			[-30, 30, 30, -30, 300, 130],  # cross under
			[-30, -30, 30, 30, 500, 130],  # straight
			[-30, -30, 30, 30, 700, 130],  # straight to right
			[30, 30, -30, -30, 700, 250],  # curve down
			[-30, -30, 30, 30, 500, 250],  # go left
			[-30, -30, 30, 30, 300, 250],  # go left
			[-30, 30, 30, -30, 200, 200],  # curve up to start
		]
	},
	{  # Level 4 - Hairpin (length ~3800) - tight turns
		"name": "Level004",
		"script": "res://scenes/levels/level_04.gd",
		"uid": "level04uid",
		"level_uid": "level04scr",
		"curve_id": "L4",
		"track_pos": "Vector2(250, 300)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 200, 250],  # start, going right
			[-30, -30, 30, 30, 400, 250],  # straight
			[-30, -30, 30, 30, 600, 250],  # straight
			[-50, 0, 50, 0, 750, 200],    # hairpin right
			[50, -30, -50, 30, 750, 50],   # hairpin top
			[-30, -30, 30, 30, 550, 50],   # straight left
			[-30, -30, 30, 30, 350, 50],   # straight left
			[0, 50, 0, -50, 200, 80],      # hairpin left
			[-30, 30, 30, -30, 150, 150],  # down
			[-30, -30, 30, 30, 200, 250],  # back to start
		]
	},
	{  # Level 5 - Wavy (length ~4200) - long sweeping curves
		"name": "Level005",
		"script": "res://scenes/levels/level_05.gd",
		"uid": "level05uid",
		"level_uid": "level05scr",
		"curve_id": "L5",
		"track_pos": "Vector2(150, 250)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 100, 300],  # start bottom-left
			[-30, -30, 30, 30, 300, 300],  # 
			[-30, -30, 30, 30, 500, 300],  # 
			[-30, -30, 30, 30, 700, 300],  # 
			[-30, -30, 30, 30, 850, 250],  # sweep right
			[-30, 30, 30, -30, 900, 150],  # curve up
			[-30, -30, 30, 30, 800, 80],   # 
			[-30, -30, 30, 30, 600, 80],   # 
			[-30, -30, 30, 30, 400, 80],   # 
			[-30, -30, 30, 30, 200, 80],   # 
			[-30, 30, 30, -30, 80, 130],   # curve left-up
			[-30, -30, 30, 30, 60, 200],   # 
			[-30, -30, 30, 30, 100, 300],  # back to start
		]
	},
	{  # Level 6 - Complex (length ~5000) - mix of everything
		"name": "Level006",
		"script": "res://scenes/levels/level_06.gd",
		"uid": "level06uid",
		"level_uid": "level06scr",
		"curve_id": "L6",
		"track_pos": "Vector2(150, 200)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 150, 350],  # start bottom
			[-30, -30, 30, 30, 350, 350],  # go right
			[-30, -30, 30, 30, 550, 350],  # 
			[-30, -30, 30, 30, 750, 350],  # 
			[-30, -30, 30, 30, 900, 300],  # sweep up-right
			[-30, 30, 30, -30, 950, 200],  # curve up
			[-30, -30, 30, 30, 850, 120),  # 
			[-30, -30, 30, 30, 650, 120],  # go left
			[-30, -30, 30, 30, 450, 120],  # 
			[0, 60, 0, -60, 350, 150],     # hairpin down
			[-30, -30, 30, 30, 250, 200],  # s-bend
			[30, 30, -30, -30, 200, 250],  # 
			[-30, -30, 30, 30, 150, 300],  # 
			[-30, -30, 30, 30, 150, 350],  # back
		]
	},
	{  # Level 7 - The Gauntlet (length ~5500) - hardest
		"name": "Level007",
		"script": "res://scenes/levels/level_07.gd",
		"uid": "level07uid",
		"level_uid": "level07scr",
		"curve_id": "L7",
		"track_pos": "Vector2(100, 150)",
		"spin_zones": "",
		"points": [
			[-30, -30, 30, 30, 150, 450],  # start bottom
			[-30, -30, 30, 30, 350, 450],  # right
			[-30, -30, 30, 30, 550, 450],  # 
			[-30, -30, 30, 30, 750, 450],  # 
			[-30, -30, 30, 30, 900, 400],  # sweep to right
			[-30, 30, 30, -30, 950, 280],  # hairpin up-left
			[-30, -30, 30, 30, 800, 220],  # 
			[-30, -30, 30, 30, 600, 220],  # 
			[-30, -30, 30, 30, 450, 200],  # cross center
			[-30, -30, 30, 30, 300, 180],  # 
			[-30, -30, 30, 30, 150, 150],  # 
			[-30, -30, 30, 30, 80, 100],   # top-left
			[30, 30, -30, -30, 150, 70],   # tight turn right
			[-30, -30, 30, 30, 300, 70],   # 
			[-30, -30, 30, 30, 500, 70],   # 
			[-30, 30, 30, -30, 550, 120),  # S-curve
			[30, -30, -30, 30, 450, 130],  # 
			[-30, 30, 30, -30, 550, 180],  # 
			[-30, -30, 30, 30, 700, 180],  # 
			[-30, -30, 30, 30, 850, 200],  # 
			[30, 30, -30, -30, 850, 300),  # sweep down
			[-30, -30, 30, 30, 700, 320],  # 
			[-30, -30, 30, 30, 500, 350],  # 
			[-30, -30, 30, 30, 300, 380],  # 
			[-30, -30, 30, 30, 150, 450],  # back to start
		]
	},
]

func _ready() -> void:
	for t in TRACKS:
		var pts := PackedVector2Array()
		for p in t.points:
			pts.append(p[0])
			pts.append(p[1])
			pts.append(p[2])
			pts.append(p[3])
			pts.append(p[4])
			pts.append(p[5])
		
		var pts_str := pts_to_str(pts)
		var ts := TSCN_TEMPLATE
		ts = ts.replace("{uid}", t.uid)
		ts = ts.replace("{level_uid}", t.level_uid)
		ts = ts.replace("{level_script}", t.script)
		ts = ts.replace("{curve_id}", t.curve_id)
		ts = ts.replace("{points_data}", pts_str)
		ts = ts.replace("{point_count}", str(t.points.size()))
		ts = ts.replace("{node_name}", t.name)
		ts = ts.replace("{track_pos}", t.track_pos)
		ts = ts.replace("{spin_zones}", t.spin_zones)
		
		print("=== %s ===" % t.name)
		print(pts_str)
		print("")
		
		# Verify
		var curve := Curve2D.new()
		var ppts := pts_str.replace("PackedVector2Array(", "").rstrip(")")
		# Can't easily load from string in GDScript, skip verification.
		
	print("=== DONE ===")
	get_tree().quit()


# Format PackedVector2Array as a readable string matching Godot's export format
func pts_to_str(pts: PackedVector2Array) -> String:
	var parts: Array[String] = []
	for i in range(0, pts.size(), 6):
		var s := ""
		for j in range(6):
			s += "%g" % pts[i + j]
			if j < 5:
				s += ", "
			elif i + 6 < pts.size():
				s += ", "
		parts.append(s)
	var out := "PackedVector2Array(" + ", ".join(parts) + ")"
	return out
