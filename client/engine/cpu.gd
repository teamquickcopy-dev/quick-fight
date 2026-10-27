## CPU opponent with three levels. Each tick it reads the sim (spacing, what the opponent is doing,
## the opponent's meter) and returns an input mask for its fighter, exactly like a player would.
## It sees the opponent `reaction` frames late. It is offline-only and never changes sim state.
## It uses its own seeded RNG, so a fight with the CPU replays identically from the same seed.
extends RefCounted

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")
const Fighter := preload("res://engine/fighter.gd")
const FD := preload("res://engine/fighter_data.gd")

enum Level { INTERN, SENIOR, ART_DIRECTOR }

const LEVEL_NAMES := ["Intern", "Senior Designer", "Art Director"]
const LEVELS := [
	{"reaction": 26, "block": 0.25, "anti_air": 0.15, "punish": 0.15, "confirm": 0.25, "think": 22, "aggro": 0.35, "tech": 0.05},
	{"reaction": 15, "block": 0.60, "anti_air": 0.50, "punish": 0.55, "confirm": 0.65, "think": 12, "aggro": 0.50, "tech": 0.35},
	{"reaction": 8, "block": 0.88, "anti_air": 0.85, "punish": 0.90, "confirm": 0.95, "think": 6, "aggro": 0.60, "tech": 0.70},
]
## Preferred fighting distance in pixels, by archetype.
const RANGES := {"Rushdown": 85, "All-rounder": 130, "Zoner": 260, "Boss / grappler": 75}

var me := 1
var level := Level.SENIOR
var cfg: Dictionary
var rng := 0x2545F491
var plan: Array = []          # queued input masks, one per frame
var hold := 0                 # directions held between decisions
var hold_left := 0
var seen: Array = []          # ring of opponent snapshots for the reaction delay
var confirmed_move := -1      # move already confirmed into a follow-up
var blocking := 0


func _init(player_index: int, lvl: int, seed: int = 12345) -> void:
	me = player_index
	level = lvl
	cfg = LEVELS[lvl]
	rng = (seed * 2654435761) & 0xFFFFFFFF
	if rng == 0:
		rng = 1


func _rand() -> float:
	rng ^= (rng << 13) & 0xFFFFFFFF
	rng ^= rng >> 17
	rng ^= (rng << 5) & 0xFFFFFFFF
	return float(rng) / 4294967296.0


func _roll(p: float) -> bool:
	return _rand() < p


func next_input(sim) -> int:
	var f = sim.fighters[me]
	var op = sim.fighters[1 - me]
	_observe(op)
	if sim.phase != sim.Phase.FIGHT:
		plan.clear()
		hold_left = 0
		return 0
	if not plan.is_empty():
		return plan.pop_front()
	var snap: Dictionary = seen[0]
	var dist: int = absi(op.x - f.x) / R.FP
	var fwd: int = f.fwd_bit()
	var back: int = f.back_bit()
	# The player having meter makes the CPU more careful.
	var caution := 0.1 if op.meter >= R.METER_PER_BAR else 0.0

	# Break throws.
	if f.state == Fighter.THROWN:
		return (B.LP | B.LK) if _roll(cfg.tech / 3.0) else 0

	# Hit-confirm: once a normal connects, cancel into the follow-up.
	if f.state == Fighter.ATTACK and f.connected == 1 and confirmed_move != f.move and f.move >= 0:
		var m: Dictionary = f.cur_move()
		confirmed_move = f.move
		if _roll(cfg.confirm):
			return _follow_up(f, m)

	if f.state != Fighter.ATTACK:
		confirmed_move = -1

	# Defense: block what we saw coming (late by our reaction time).
	if snap.attacking and dist < snap.reach + 60 and f.can_block():
		if blocking > 0 or _roll(cfg.block + caution):
			blocking = 4
			var low: bool = snap.level == FD.LEVEL_LOW
			var over: bool = snap.level == FD.LEVEL_OVERHEAD or snap.airborne
			# Higher levels read the attack's height; lower ones guess.
			var crouch := low if _roll(cfg.block) else _roll(0.5)
			if over:
				crouch = false if _roll(cfg.block) else crouch
			return back | (B.DOWN if crouch else 0)
	if blocking > 0:
		blocking -= 1
		return back

	if not (f.state in Fighter.NEUTRAL):
		return hold & B.DOWN if f.airborne == 0 else 0

	# Anti-air a jump-in.
	if snap.airborne and snap.toward and dist < 230 and _roll(cfg.anti_air):
		var aa := _special(f, "down")
		if aa != 0:
			plan = [B.DOWN | aa]
			return B.DOWN
		plan = [B.DOWN | B.HP]
		return B.DOWN

	# Punish a whiffed move in recovery.
	if snap.recovering and dist < 170 and _roll(cfg.punish):
		return _attack(f, dist, true)

	# Neutral: think every few frames, otherwise keep doing the last thing.
	if hold_left > 0:
		hold_left -= 1
		return hold
	var want: int = RANGES.get(f.data.archetype, 130)
	hold_left = cfg.think + int(_rand() * cfg.think)
	if f.meter >= R.METER_MAX and dist < 150 and _roll(0.5):
		plan = [B.DOWN | B.HP | B.HK]
		hold = 0
		return B.DOWN
	if dist > want + 50:
		var r := _rand()
		if r < 0.15:
			plan = [0, fwd]
			hold = 0
			return fwd            # dash
		if r < 0.25 and _roll(cfg.aggro):
			hold = 0
			hold_left = 0
			plan = [B.UP | fwd, B.UP | fwd, B.UP | fwd]
			for i in 14:
				plan.append(fwd)
			plan.append(fwd | B.HK)
			return B.UP | fwd     # jump in with a kick
		hold = fwd
		return hold
	if dist < want - 50 and _roll(0.5):
		hold = back
		return hold
	if _roll(cfg.aggro - caution):
		hold = 0
		hold_left = 2
		return _attack(f, dist, false)
	hold = back if _roll(0.4) else 0
	return hold


## Snapshot of the opponent with the reaction delay applied.
func _observe(op) -> void:
	var m: Dictionary = op.cur_move() if op.state == Fighter.ATTACK else {}
	var snap := {
		"attacking": op.state == Fighter.ATTACK and not m.is_empty() and not m.hits.is_empty()
				and op.move_frame < m.hits[m.hits.size() - 1].end,
		"recovering": not m.is_empty() and not m.hits.is_empty() and op.connected == 0
				and op.move_frame >= m.hits[m.hits.size() - 1].end,
		"level": m.hits[0].level if not m.is_empty() and not m.hits.is_empty() else FD.LEVEL_MID,
		"reach": (m.hits[0].box[0] + m.hits[0].box[2]) / R.FP if not m.is_empty() and not m.hits.is_empty() else 0,
		"airborne": op.airborne != 0,
		"toward": op.vx * (1 if op.facing > 0 else -1) > 0,
	}
	seen.append(snap)
	while seen.size() > cfg.reaction:
		seen.pop_front()


func _special(f, dir: String) -> int:
	for s in f.data.specials:
		if s.dir == dir and not f.data.moves[s.move].hits.is_empty():
			return s.button
	return 0


func _special_input(f, s: Dictionary) -> Array:
	# Release first so the direction is freshly pressed (the simple direction + button input).
	var d: int = B.DOWN if s.dir == "down" else (f.fwd_bit() if s.dir == "forward" else f.back_bit())
	return [0, d | s.button]


func _follow_up(f, m: Dictionary) -> int:
	if m.category == "light":
		return B.HP
	if m.category == "heavy" or m.category == "special":
		if f.meter >= R.METER_PER_BAR and _roll(0.35) and ("super" in m.cancel):
			return B.HP | B.HK
		var options := []
		for s in f.data.specials:
			var sm: Dictionary = f.data.moves[s.move]
			if not sm.hits.is_empty() and (sm.category in m.cancel or sm.name in m.cancel):
				options.append(s)
		if not options.is_empty():
			var s: Dictionary = options[int(_rand() * options.size())]
			var seq := _special_input(f, s)
			plan = seq.slice(1)
			return seq[0]
	return 0


func _attack(f, dist: int, punish: bool) -> int:
	if dist < 85 and _roll(0.25):
		return B.LP | B.LK   # throw
	if punish or _roll(0.4):
		plan = [0, 0, 0, 0, 0, 0]
		return B.HP if dist < 130 else B.HK
	var r := _rand()
	if r < 0.3:
		return B.LK if dist < 110 else B.HK
	if r < 0.55:
		plan = [B.DOWN | B.LK]
		return B.DOWN
	if r < 0.75:
		return B.LP
	var specials: Array = f.data.specials.filter(func(s): return not f.data.moves[s.move].hits.is_empty())
	if specials.is_empty():
		return B.HP
	var s: Dictionary = specials[int(_rand() * specials.size())]
	var seq := _special_input(f, s)
	plan = seq.slice(1)
	return seq[0]
