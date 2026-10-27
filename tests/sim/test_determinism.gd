## Determinism tests (required for rollback netcode):
## the same 10,000-frame input recording played twice must give identical game state every frame,
## and saving, simulating ahead and restoring must give the same result as never rolling back.
extends RefCounted
var t

const FRAMES := 10000


## A seeded "button masher" recording: each player holds a random input for 1-8 frames.
## Biased toward fighting moves so the run covers attacks, blocks, throws, supers and KOs.
func recording(seed: int, frames: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := []
	var held := [0, 0]
	var left := [0, 0]
	for i in frames:
		for p in 2:
			if left[p] <= 0:
				left[p] = rng.randi_range(1, 8)
				var m := 0
				var dir := rng.randi_range(0, 9)
				m |= [0, 1, 2, 4, 8, 6, 10, 5, 9, 4 if p == 0 else 8][dir]
				if rng.randf() < 0.45:
					m |= [16, 32, 64, 128, 48, 160, 80][rng.randi_range(0, 6)]
				held[p] = m
			left[p] -= 1
		out.append([held[0], held[1]])
	return out


func play(rec: Array, sim) -> Array:
	var sums := []
	for i in rec.size():
		sim.step(rec[i][0], rec[i][1])
		if sim.phase == t.MatchSim.Phase.OVER:
			sim.restart()
		sums.append(sim.checksum())
	return sums


func new_sim():
	return t.MatchSim.new(t.fighter("arghya"), t.fighter("jitu"))


func test_same_inputs_same_state_every_frame() -> void:
	var rec := recording(20261028, FRAMES)
	var t0 := Time.get_ticks_usec()
	var a := play(rec, new_sim())
	var per_frame_us := (Time.get_ticks_usec() - t0) / FRAMES
	var b := play(rec, new_sim())
	var first_diff := -1
	for i in FRAMES:
		if a[i] != b[i]:
			first_diff = i
			break
	t.eq(first_diff, -1, "first frame where the two runs differ")
	print("        sim + checksum: %d us/frame" % per_frame_us)


func test_recording_actually_fights() -> void:
	var rec := recording(20261028, FRAMES)
	var sim = new_sim()
	var counts := {}
	for i in rec.size():
		sim.step(rec[i][0], rec[i][1])
		if sim.phase == t.MatchSim.Phase.OVER:
			sim.restart()
		for e in sim.events:
			counts[e.t] = counts.get(e.t, 0) + 1
	print("        events: %s" % [counts])
	for k in ["hit", "block", "ko", "knockdown", "grab", "round_start"]:
		t.check(counts.get(k, 0) > 0, "recording produced '%s' events" % k)


func test_rollback_save_restore_resimulate() -> void:
	var rec := recording(7, 3000)
	var sim = new_sim()
	var reference := play(rec, new_sim())
	var mismatches := 0
	var i := 0
	while i < rec.size():
		# Every 25 frames: save, run 8 frames ahead with wrong (empty) inputs, roll back, replay correctly.
		if i % 25 == 0 and i + 8 < rec.size():
			var saved: Array = sim.save_state()
			for k in 8:
				sim.step(0, 0)
			sim.load_state(saved)
		sim.step(rec[i][0], rec[i][1])
		if sim.phase == t.MatchSim.Phase.OVER:
			sim.restart()
		if sim.checksum() != reference[i]:
			mismatches += 1
		i += 1
	t.eq(mismatches, 0, "frames that differ after rollbacks")


func test_restored_state_into_new_sim_continues_identically() -> void:
	var rec := recording(99, 1200)
	var a = new_sim()
	for i in 600:
		a.step(rec[i][0], rec[i][1])
	var b = new_sim()
	b.load_state(a.save_state())
	var same := true
	for i in range(600, 1200):
		a.step(rec[i][0], rec[i][1])
		b.step(rec[i][0], rec[i][1])
		if a.checksum() != b.checksum():
			same = false
			break
	t.check(same, "a second client restored from a snapshot stays in sync")


func test_resimulation_is_fast_enough_for_rollback() -> void:
	# Rollback may replay ~8 frames inside one 16.6 ms display frame; keep the sim well under 1 ms/frame.
	var rec := recording(3, 2000)
	var sim = new_sim()
	var t0 := Time.get_ticks_usec()
	for i in rec.size():
		sim.step(rec[i][0], rec[i][1])
		if sim.phase == t.MatchSim.Phase.OVER:
			sim.restart()
	var us := (Time.get_ticks_usec() - t0) / rec.size()
	print("        sim step: %d us/frame" % us)
	t.check(us < 1000, "sim step under 1 ms (got %d us)" % us)
