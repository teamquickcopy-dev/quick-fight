## Desktop online test: two separate Godot processes play each other through the signaling
## server and real WebRTC (the webrtc_native plugin), each mashing random inputs.
## Run tests/online_desktop.sh (starts the server, the host and the guest).
##   godot --headless --path client -s ../tests/online_desktop.gd -- host <code_file> <seconds>
##   godot --headless --path client -s ../tests/online_desktop.gd -- guest <code_file> <seconds>
## Prints "ONLINE DESKTOP OK" when the fight ran with no desync.
extends SceneTree

var role := ""
var code_file := ""
var seconds := 20.0
var main
var started_ms := 0
var fight_started_ms := 0
var rng := RandomNumberGenerator.new()
var held := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	code_file = args[1]
	seconds = float(args[2]) if args.size() > 2 else 20.0
	rng.seed = 1 if role == "host" else 2
	main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec()
	if now - started_ms > (seconds + 40.0) * 1000.0:
		print("TIMEOUT (%s): online status '%s'" % [role, main.online_status])
		quit(1)
		return true
	if main.screen == main.Screen.TITLE and now - started_ms > 300:
		# Pick online mode and the first fighter, then host or join.
		main.mode = "online"
		main.cursor = [0, 1]
		main._go(main.Screen.ONLINE)
		if role == "host":
			main.online.create_room()
	if role == "guest" and main.screen == main.Screen.ONLINE and main.online.state == main.Online.State.IDLE \
			and FileAccess.file_exists(code_file):
		var code := FileAccess.get_file_as_string(code_file).strip_edges()
		if code.length() == 4:
			main.online.join_room(code)
	if role == "host" and main.room_code != "" and not FileAccess.file_exists(code_file):
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(main.room_code)
		f.close()
		print("host: room %s" % main.room_code)
	if main.screen == main.Screen.FIGHT and main.fight != null:
		if fight_started_ms == 0:
			fight_started_ms = now
			print("%s: fight started (delay %d)" % [role, main.fight.session.input_delay])
			main.fight.local_input = func() -> int:
				if rng.randf() < 0.1:
					held = [0, 1, 2, 4, 8, 6, 10][rng.randi_range(0, 6)] | [0, 0, 16, 32, 64, 128][rng.randi_range(0, 5)]
				return held
		if now - fight_started_ms > seconds * 1000.0:
			var s = main.fight.session
			print("%s: frame %d rtt %d rollbacks %d max %d stalls %d checked %d desync %d" % [role, s.frame,
				s.rtt_ms, s.stats.rollbacks, s.stats.max_rollback, s.stats.stalls, s._local_checksums.size(), s.desync_frame])
			var ok: bool = s.desync_frame < 0 and s._local_checksums.size() > 5
			print("ONLINE DESKTOP OK" if ok else "ONLINE DESKTOP FAIL")
			quit(0 if ok else 1)
	return false
