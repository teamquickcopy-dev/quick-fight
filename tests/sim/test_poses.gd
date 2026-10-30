## Pose pictures: every picture a fighter's pose map names exists, every move has pictures, and a
## whole CPU match (both sides) always has a picture to draw, so the cutout rig fallback never shows.
extends RefCounted
var t

const PoseRig := preload("res://fighters/_poses/pose_rig.gd")
const Cpu := preload("res://engine/cpu.gd")


func test_pose_map_names_exist() -> void:
	var rig = PoseRig.for_fighter(t.fighter("arghya"))
	t.check(rig != null, "arghya has pose pictures")
	if rig == null:
		return
	for key in rig.map:
		var v = rig.map[key]
		if key == "moves" or key == "_doc":
			continue
		for name in (v if v is Array else [v]):
			t.check(rig.poses.has(name), "map '%s' -> '%s' exists" % [key, name])
	for move in rig.map.moves:
		for part in ["wind", "strike", "recover"]:
			var v = rig.map.moves[move].get(part, [])
			for name in (v if v is Array else [v]):
				t.check(rig.poses.has(name), "%s %s -> '%s' exists" % [move, part, name])
	for m in t.fighter("arghya").moves:
		t.check(rig.map.moves.has(m.name), "move %s has pictures" % m.name)


func test_cpu_match_always_has_a_picture() -> void:
	var sim = t.MatchSim.new(t.fighter("arghya"), t.fighter("arghya"))
	var rig = PoseRig.for_fighter(sim.fighters[0].data)
	var c0 := Cpu.new(0, Cpu.Level.ART_DIRECTOR, 7)
	var c1 := Cpu.new(1, Cpu.Level.SENIOR, 8)
	var missing := {}
	var seen := {}
	var frames := 0
	while sim.phase != t.MatchSim.Phase.OVER and frames < 60 * 400:
		sim.step(c0.next_input(sim), c1.next_input(sim))
		frames += 1
		for f in sim.fighters:
			var look: Dictionary = rig.pick(f)
			seen[look.pose] = true
			if not rig.poses.has(look.pose):
				missing["%s/%s" % [f.STATE_NAMES[f.state], f.cur_move().get("name", "") if f.move >= 0 else ""]] = true
	print("        %d different pictures shown in %d s" % [seen.size(), frames / 60])
	t.eq(missing.keys(), [], "states without a picture")
