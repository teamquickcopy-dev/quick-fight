## Rollback netcode over a simulated network: two sessions, each with its own sim, connected by
## a link with chosen latency, jitter and packet loss. Every confirmed frame must match on both.
extends RefCounted
var t

const Rollback := preload("res://net/rollback.gd")
const FRAME_MS := 1000.0 / 60.0


## Runs two peers for `seconds` of virtual time. Peer B starts `offset_ms` after A, like real
## players whose "go" message arrives at different times.
func run_link(rtt_ms: float, jitter_ms: float, loss: float, seconds: float, offset_ms := 37.0, seed := 1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var now := [0.0]
	var clock := func() -> int: return int(now[0])
	var delay := Rollback.delay_for_rtt(rtt_ms)
	var a = Rollback.new(t.MatchSim.new(t.fighter("arghya"), t.fighter("jitu")), 0, delay, clock)
	var b = Rollback.new(t.MatchSim.new(t.fighter("arghya"), t.fighter("jitu")), 1, delay, clock)
	var peers := [a, b]
	var in_flight := []      # [deliver_at_ms, to_index, bytes]
	var next_tick := [0.0, offset_ms]
	var rec := _recording(seed + 100, 4000)
	var end := seconds * 1000.0
	var restarts := 0
	while now[0] < end:
		# Next event: a peer's tick or a packet arrival.
		var p := 0 if next_tick[0] <= next_tick[1] else 1
		now[0] = next_tick[p]
		in_flight.sort_custom(func(x, y): return x[0] < y[0])
		while not in_flight.is_empty() and in_flight[0][0] <= now[0]:
			var pkt = in_flight.pop_front()
			peers[pkt[1]].receive(pkt[2])
		var s = peers[p]
		var input: int = rec[s.frame % rec.size()][p]
		s.advance(input)
		for bytes in s.take_outgoing():
			if rng.randf() < loss:
				continue
			var lat := rtt_ms / 2.0 + rng.randf_range(-jitter_ms, jitter_ms)
			in_flight.append([now[0] + maxf(lat, 1.0), 1 - p, bytes])
		next_tick[p] += FRAME_MS
	# Compare every frame both sides confirmed.
	var common := 0
	var mismatched := 0
	for f in a._local_checksums:
		if b._local_checksums.has(f):
			common += 1
			if a._local_checksums[f] != b._local_checksums[f]:
				mismatched += 1
	return {"a": a, "b": b, "common": common, "mismatched": mismatched, "delay": delay}


## Hold-random inputs per player (same generator idea as the determinism test).
func _recording(seed: int, frames: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	var held := [0, 0]
	var left := [0, 0]
	for i in frames:
		for p in 2:
			if left[p] <= 0:
				left[p] = rng.randi_range(2, 10)
				held[p] = [0, 1, 2, 4, 8, 6, 10, 4, 8][rng.randi_range(0, 8)]
				if rng.randf() < 0.4:
					held[p] |= [16, 32, 64, 128, 48, 80][rng.randi_range(0, 5)]
			left[p] -= 1
		out.append([held[0], held[1]])
	return out


func _report(name: String, r: Dictionary) -> void:
	var sa: Dictionary = r.a.stats
	var sb: Dictionary = r.b.stats
	print("        %s: delay %d, frames A %d / B %d, checked %d, rollbacks %d/%d (max depth %d/%d, avg %.1f), stalls %d/%d, skips %d/%d, rtt %.0f ms" % [
		name, r.delay, r.a.frame, r.b.frame, r.common, sa.rollbacks, sb.rollbacks, sa.max_rollback, sb.max_rollback,
		float(sa.rollback_frames + sb.rollback_frames) / maxf(1.0, sa.rollbacks + sb.rollbacks),
		sa.stalls, sb.stalls, sa.skips, sb.skips, r.a.rtt_ms])


func test_delay_for_rtt() -> void:
	var D = Rollback
	t.eq([D.delay_for_rtt(0), D.delay_for_rtt(50), D.delay_for_rtt(150), D.delay_for_rtt(300)], [1, 1, 2, 4], "input delay by ping")


func test_lan_no_desync() -> void:
	var r := run_link(4.0, 1.0, 0.0, 30.0)
	_report("LAN", r)
	t.check(r.common > 20, "frames compared: %d" % r.common)
	t.eq(r.mismatched, 0, "desynced checksums")
	t.eq(r.a.desync_frame, -1, "A detected no desync")


func test_150ms_gate_conditions() -> void:
	# Saint Paul <-> Dhaka: 150 ms round trip, +-15 ms jitter, 1% packet loss, 60 s.
	var r := run_link(150.0, 15.0, 0.01, 60.0)
	_report("150 ms", r)
	t.check(r.common > 50, "frames compared: %d" % r.common)
	t.eq(r.mismatched, 0, "desynced checksums")
	t.eq(r.a.desync_frame + r.b.desync_frame, -2, "no desync detected")
	var frames: int = r.a.frame + r.b.frame
	var stalls: int = r.a.stats.stalls + r.b.stats.stalls
	t.check(stalls * 100 < frames, "stalls under 1%% of frames (%d of %d)" % [stalls, frames])
	t.check(r.a.stats.max_rollback <= 6 and r.b.stats.max_rollback <= 6,
			"rollbacks stay shallow (max %d/%d)" % [r.a.stats.max_rollback, r.b.stats.max_rollback])
	t.check(absi(r.a.frame - r.b.frame) <= 6, "both sides stay in step (A %d, B %d)" % [r.a.frame, r.b.frame])
	t.check(absf(r.a.rtt_ms - 150.0) < 30.0, "ping measured ~150 ms (%.0f)" % r.a.rtt_ms)


func test_heavy_loss_still_in_sync() -> void:
	var r := run_link(100.0, 20.0, 0.2, 30.0, 12.0, 7)
	_report("20% loss", r)
	t.eq(r.mismatched, 0, "desynced checksums with 20% loss")
	t.check(r.common > 20, "frames compared: %d" % r.common)


func test_very_high_ping_degrades_but_never_desyncs() -> void:
	var r := run_link(400.0, 30.0, 0.02, 30.0, 90.0, 9)
	_report("400 ms", r)
	t.eq(r.mismatched, 0, "desynced checksums at 400 ms")
	t.check(r.a.stats.max_rollback <= Rollback.MAX_ROLLBACK, "rollback never deeper than the limit")
