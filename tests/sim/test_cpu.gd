## CPU tests: the three levels play real matches, stronger levels win more, and a CPU fight
## replays identically from the same seed.
extends RefCounted
var t

const Cpu := preload("res://engine/cpu.gd")


func cpu_match(lvl0: int, lvl1: int, seed: int, a := "arghya", b := "jitu") -> Dictionary:
	var sim = t.MatchSim.new(t.fighter(a), t.fighter(b))
	var c0 := Cpu.new(0, lvl0, seed)
	var c1 := Cpu.new(1, lvl1, seed + 1)
	var sums := []
	var frames := 0
	while sim.phase != t.MatchSim.Phase.OVER and frames < 60 * 400:
		sim.step(c0.next_input(sim), c1.next_input(sim))
		frames += 1
		if frames % 60 == 0:
			sums.append(sim.checksum())
	return {"winner": sim.match_winner, "frames": frames, "sums": sums}


func test_art_director_beats_intern() -> void:
	var wins := 0
	var games := 0
	for seed in range(1, 7):
		# Alternate sides and fighters so it isn't one matchup.
		var flip := seed % 2 == 0
		var r := cpu_match(Cpu.Level.INTERN if flip else Cpu.Level.ART_DIRECTOR,
				Cpu.Level.ART_DIRECTOR if flip else Cpu.Level.INTERN, seed * 101,
				"jitu" if seed % 3 == 0 else "arghya", "arghya" if seed % 3 == 0 else "jitu")
		t.check(r.winner >= 0, "match %d finished (%d frames)" % [seed, r.frames])
		games += 1
		if r.winner == (1 if flip else 0):
			wins += 1
	print("        Art Director won %d of %d vs Intern" % [wins, games])
	t.check(wins >= 5, "Art Director should win at least 5 of 6 (won %d)" % wins)


func test_cpu_fight_replays_from_seed() -> void:
	var a := cpu_match(Cpu.Level.SENIOR, Cpu.Level.SENIOR, 42)
	var b := cpu_match(Cpu.Level.SENIOR, Cpu.Level.SENIOR, 42)
	t.eq(a.sums, b.sums, "same seed, same fight")
	t.check(a.frames < 60 * 400, "CPU match ends (took %d s)" % (a.frames / 60))
