## Shared helpers for sim tests.
extends RefCounted

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")
const FD := preload("res://engine/fighter_data.gd")
const Fighter := preload("res://engine/fighter.gd")
const MatchSim := preload("res://engine/match_sim.gd")

var failures: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(got, want, msg: String) -> void:
	if got != want:
		failures.append("%s: got %s, want %s" % [msg, got, want])


func fighter(id: String) -> FD:
	var d: FD = FD.load_file("res://fighters/%s/fighter.json" % id)
	check(d.ok(), "%s loads: %s" % [id, d.errors])
	return d


## A sim past the round intro, fighters `gap_px` apart in the middle of the stage.
func fight(a := "arghya", b := "jitu", gap_px := 120) -> MatchSim:
	var sim := MatchSim.new(fighter(a), fighter(b))
	while sim.phase == MatchSim.Phase.INTRO:
		sim.step(0, 0)
	place(sim, gap_px)
	return sim


func place(sim: MatchSim, gap_px: int) -> void:
	var c := R.STAGE_WIDTH / 2
	sim.fighters[0].x = c - gap_px * R.FP / 2
	sim.fighters[1].x = c + gap_px * R.FP / 2
	sim.fighters[0].facing = 1
	sim.fighters[1].facing = -1


## Step with per-frame inputs for p0 and p1 (arrays of masks, or a single mask repeated `frames` times).
func run(sim: MatchSim, p0, p1 = 0, frames := -1) -> Array:
	var all_events := []
	var n: int = frames if frames >= 0 else maxi(p0.size() if p0 is Array else 1, p1.size() if p1 is Array else 1)
	for i in n:
		var a: int = (p0[i] if i < p0.size() else 0) if p0 is Array else p0
		var b: int = (p1[i] if i < p1.size() else 0) if p1 is Array else p1
		sim.step(a, b)
		all_events.append_array(sim.events)
	return all_events


func events_of(events: Array, type: String) -> Array:
	return events.filter(func(e): return e.t == type)


## Press `mask` for one frame then release, padded to `frames`.
func tap(mask: int, frames := 1) -> Array:
	var out := [mask]
	for i in frames - 1:
		out.append(0)
	return out
