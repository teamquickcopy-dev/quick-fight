## Frame-data tests: every fighter's data file loads cleanly and follows the rules.
extends RefCounted
var t


func test_all_fighters_load_without_errors() -> void:
	var paths: PackedStringArray = t.FD.discover()
	t.check(paths.size() >= 2, "at least two fighters found, got %s" % [paths])
	for p in paths:
		var d = t.FD.load_file(p)
		t.check(d.ok(), "%s: %s" % [p, "\n          ".join(d.errors)])


func test_every_fighter_has_the_base_move_set() -> void:
	for p in t.FD.discover():
		var d = t.FD.load_file(p)
		t.eq(d.normals.size(), 12, d.id + " normals (4 standing, 4 crouching, 4 jumping)")
		t.check(d.throw_move >= 0, d.id + " has a throw")
		t.check(d.specials.size() >= 2, d.id + " has specials")
		t.check(d.super_move >= 0 and d.ultra_move >= 0, d.id + " has super and ultra")


func test_moves_have_sane_frame_data() -> void:
	for p in t.FD.discover():
		var d = t.FD.load_file(p)
		for m in d.moves:
			t.check(m.total > 0 and m.total < 240, "%s.%s total frames %d" % [d.id, m.name, m.total])
			for h in m.hits:
				t.check(h.damage > 0, "%s.%s damage > 0" % [d.id, m.name])
				t.check(h.start >= 0 and h.end > h.start, "%s.%s hit window" % [d.id, m.name])
				t.check(h.end <= m.total, "%s.%s hit ends before the move does" % [d.id, m.name])
			if m.category == "light":
				t.check("heavy" in m.cancel or m.air, "%s.%s light normals cancel into heavies" % [d.id, m.name])


func test_loader_rejects_fractions_and_missing_fields() -> void:
	var good := FileAccess.get_file_as_string("res://fighters/arghya/fighter.json")
	var bad := good.replace("\"health\": 1000", "\"health\": 999.5").replace("\"st_lp\": {", "\"st_lp\": { \"level\": \"sideways\",")
	var path := "user://bad_fighter.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(bad)
	f.close()
	var d = t.FD.load_file(path)
	t.check(not d.ok(), "bad file is rejected")
	var joined := " ".join(d.errors)
	t.check("whole number" in joined, "fraction reported: " + joined)
	t.check("level must be" in joined, "bad level reported: " + joined)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_multi_hit_repeat_expands() -> void:
	var d = t.fighter("jitu")
	var m: Dictionary = d.moves[d.ultra_move]
	t.eq(m.hits.size(), 12, "Deadline Rush is a 12-hit flurry")


func test_cutout_rigs_load() -> void:
	# Fighters marked "cutout" must have built art that loads (tools/art/build_fighter.py).
	var CutoutRig = load("res://fighters/_cutout/cutout_rig.gd")
	t.check(CutoutRig != null and CutoutRig.can_instantiate(), "cutout rig script compiles")
	if CutoutRig == null:
		return
	for p in t.FD.discover():
		var d = t.FD.load_file(p)
		if d.rig != "cutout":
			continue
		var rig = CutoutRig.for_fighter(d)
		t.check(rig != null, "%s: cutout art loads" % d.id)
		if rig != null:
			for part in ["head", "torso", "pelvis", "arm_upper_F", "arm_lower_F", "leg_upper_F", "leg_lower_F"]:
				t.check(rig.parts.has(part), "%s: has part %s" % [d.id, part])
