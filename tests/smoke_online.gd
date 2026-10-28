## Online fight-screen smoke test: two FightScreens in online mode, linked by a fake connection
## with ~150 ms round trip, mashing random inputs. Fails on script errors (grep) or a desync.
## Run: godot --headless --path client -s ../tests/smoke_online.gd
extends SceneTree

const FD := preload("res://engine/fighter_data.gd")


class FakeLink extends Node:
	var other: FakeLink
	var handler: Callable
	var added_lag_ms := 0
	var queue: Array = []   # [deliver_at_ms, bytes]

	func set_input_handler(h: Callable) -> void:
		handler = h

	func send_input(bytes: PackedByteArray) -> void:
		other.queue.append([Time.get_ticks_msec() + 75, bytes])

	func _process(_d: float) -> void:
		var now := Time.get_ticks_msec()
		while not queue.is_empty() and queue[0][0] <= now:
			handler.call(queue.pop_front()[1])


var screens: Array = []
var frames := 0
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var a: FD = FD.load_file("res://fighters/arghya/fighter.json")
	var b: FD = FD.load_file("res://fighters/jitu/fighter.json")
	var links := [FakeLink.new(), FakeLink.new()]
	links[0].other = links[1]
	links[1].other = links[0]
	for i in 2:
		root.add_child(links[i])
		# load() at runtime: the Controls autoload doesn't exist yet when this script is compiled.
		var s = load("res://ui/fight_screen.gd").new()
		root.add_child(s)
		s.setup({"mode": "online", "p1": a, "p2": b, "online": links[i], "local": i, "delay": 2})
		s.set_process(false)
		var held := [0, 0]
		s.local_input = func() -> int:
			if rng.randf() < 0.12:
				held[0] = [0, 1, 2, 4, 8, 6, 10][rng.randi_range(0, 6)] | ([0, 0, 16, 32, 64, 128][rng.randi_range(0, 5)])
			return held[0]
		screens.append(s)


func _process(_delta: float) -> bool:
	frames += 1
	if screens.size() < 2:
		quit(1)
		return true
	# Drive both fixed-tick loops directly; random inputs come in through local_input.
	for s in screens:
		s._tick()
	if frames >= 1500:
		for s in screens:
			print("side %d: frame %d rollbacks %d max %d stalls %d desync %d" % [s.cfg.local, s.session.frame,
				s.session.stats.rollbacks, s.session.stats.max_rollback, s.session.stats.stalls, s.session.desync_frame])
		var ok: bool = screens[0].session.desync_frame < 0 and screens[1].session.desync_frame < 0
		print("ONLINE SMOKE OK" if ok else "ONLINE SMOKE DESYNC")
		quit(0 if ok else 1)
	return false
