## Headless test runner: godot --headless --path client -s ../tests/sim/run_tests.gd
## Exits with code 1 if any test fails. Each suite gets the shared helper `t` (test_base.gd);
## suites can't `extends` it because Godot can't resolve classes outside the project folder.
extends SceneTree

const SUITES := [
	"res://../tests/sim/test_data.gd",
	"res://../tests/sim/test_rules.gd",
	"res://../tests/sim/test_determinism.gd",
]


func _init() -> void:
	var failed := 0
	var passed := 0
	var only := OS.get_environment("TEST_FILTER")
	var base: GDScript = load(_resolve("res://../tests/sim/test_base.gd"))
	if base == null or not base.can_instantiate():
		print("FAIL  could not load test_base.gd")
		quit(1)
		return
	var t = base.new()
	for path in SUITES:
		var script: GDScript = load(_resolve(path))
		if script == null or not script.can_instantiate():
			print("  FAIL  could not load %s" % path)
			failed += 1
			continue
		var suite = script.new()
		suite.t = t
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_") or (only != "" and not only in name):
				continue
			t.failures = []
			var t0 := Time.get_ticks_msec()
			suite.call(name)
			var ms := Time.get_ticks_msec() - t0
			if t.failures.is_empty():
				passed += 1
				print("  ok    %s (%d ms)" % [name, ms])
			else:
				failed += 1
				print("  FAIL  %s" % name)
				for f in t.failures:
					print("        - %s" % f)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


## Test files live outside the Godot project (tests/ at the repo root), so load them by absolute path.
func _resolve(p: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join(p.trim_prefix("res://")).simplify_path()
