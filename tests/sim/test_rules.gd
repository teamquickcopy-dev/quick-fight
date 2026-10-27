## Rule tests: each core rule from the design doc's "Controls and combat" section.
## P0 = Arghya facing right, P1 = Jitu facing left (back = RIGHT for P1).
extends RefCounted
var t

const LP := 16
const HP := 32
const LK := 64
const HK := 128
const UP := 1
const DOWN := 2
const LEFT := 4
const RIGHT := 8


## Steps until an event of `type` appears; returns it (or {} after `max_frames`).
func until(sim, p0: Array, p1, type: String, max_frames := 60) -> Dictionary:
	for i in max_frames:
		var a: int = p0[i] if i < p0.size() else 0
		var b: int = (p1[i] if i < p1.size() else 0) if p1 is Array else p1
		sim.step(a, b)
		for e in sim.events:
			if e.t == type:
				return e
	return {}


func pad(seq: Array, n: int) -> Array:
	var out := seq.duplicate()
	while out.size() < n:
		out.append(0)
	return out


## Data file variant: loads Arghya's json, lets `edit` change the dictionary, loads the result.
func variant(edit: Callable):
	var j := JSON.new()
	j.parse(FileAccess.get_file_as_string("res://fighters/arghya/fighter.json"))
	edit.call(j.data)
	var path := "user://variant_fighter.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(j.data))
	f.close()
	var d = t.FD.load_file(path)
	t.check(d.ok(), "variant loads: %s" % [d.errors])
	return d


# --- hit-stop, damage, counter-hit -------------------------------------------------------------

func test_hitstop_4_frames_light_8_heavy() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var e := until(sim, [LP], 0, "hit")
	t.check(not e.is_empty(), "light punch hits")
	t.eq(sim.freeze, t.R.HITSTOP_LIGHT, "light hit-stop")
	var f0: int = sim.fighters[0].state_frame
	t.run(sim, 0, 0, 4)
	t.eq(sim.fighters[0].state_frame, f0, "attacker frozen during hit-stop")
	sim = t.fight("arghya", "jitu", 100)
	until(sim, [HP], 0, "hit")
	t.eq(sim.freeze, t.R.HITSTOP_HEAVY, "heavy hit-stop")


func test_heavy_hits_shake_the_camera() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var events: Array = []
	for i in 20:
		sim.step(HP if i == 0 else 0, 0)
		events.append_array(sim.events)
	t.check(not t.events_of(events, "shake").is_empty(), "camera shake on heavy hit")


func test_damage_scaling_after_third_hit_floor_40() -> void:
	var S = t.MatchSim
	t.eq([S.scaling_pct(1), S.scaling_pct(3), S.scaling_pct(4), S.scaling_pct(5), S.scaling_pct(9), S.scaling_pct(20)],
			[100, 100, 90, 80, 40, 40], "scaling per hit")


func test_counter_hit_does_20_percent_more() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	# Jitu starts a slow heavy kick; Arghya's jab lands during its startup.
	var e := until(sim, [0, LP], [HK], "hit")
	t.eq(e.get("p"), 1, "Jitu is hit")
	t.eq(e.get("counter"), true, "counter-hit flag")
	t.eq(e.get("dmg"), 36, "30 damage +20%")


# --- combos & cancels ----------------------------------------------------------------------------

func test_light_cancels_into_heavy_into_special() -> void:
	var sim = t.fight("arghya", "jitu", 70)
	var p0 := pad([LP], 5) + [HP] + pad([], 11) + [DOWN, DOWN | HP] + [DOWN].duplicate()
	p0 = p0 + pad([], 30)
	var hits: Array = t.events_of(t.run(sim, p0, 0), "hit")
	t.eq(hits.size(), 3, "three hits")
	if hits.size() == 3:
		t.eq([hits[0].move, hits[1].move, hits[2].move], ["st_lp", "st_hp", "heat_press_palm"], "chain")
		t.eq(hits[2].combo, 3, "combo counter")


func test_jitu_rush_order_cancels_into_ruler_slash() -> void:
	var sim = t.fight("jitu", "arghya", 160)
	# P0 is Jitu facing right. Rush Order (forward + HP), then Ruler Slash (down + HK) on hit.
	var p0 := [RIGHT | HP] + pad([], 13) + [DOWN, DOWN | HK] + pad([], 30)
	var hits: Array = t.events_of(t.run(sim, p0, 0), "hit")
	t.eq(hits.map(func(h): return h.move), ["rush_order", "ruler_slash"], "special-to-special cancel")


func test_no_cancel_on_whiff() -> void:
	var sim = t.fight("arghya", "jitu", 400)
	var moves: Array = t.events_of(t.run(sim, [LP, 0, 0, HP] + pad([], 20), 0), "move")
	t.eq(moves.size(), 1, "whiffed jab can't be cancelled (heavy press is dropped)")


# --- blocking ----------------------------------------------------------------------------------

func test_low_must_be_crouch_blocked() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var e := until(sim, [DOWN | LK], RIGHT, "hit")
	t.check(not e.is_empty(), "standing block loses to a low")
	sim = t.fight("arghya", "jitu", 100)
	var ev: Array = t.run(sim, [DOWN | LK] + pad([], 15), DOWN | RIGHT)
	t.eq(t.events_of(ev, "block").size(), 1, "crouch block stops a low")
	t.eq(sim.fighters[1].health, 950, "no chip on normals")


func test_overhead_must_be_stand_blocked() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var ev: Array = t.run(sim, [RIGHT | HP] + pad([], 25), DOWN | RIGHT)
	t.eq(t.events_of(ev, "hit").size(), 1, "crouch block loses to Squeegee Swing (overhead)")
	sim = t.fight("arghya", "jitu", 100)
	ev = t.run(sim, [RIGHT | HP] + pad([], 25), RIGHT)
	t.eq(t.events_of(ev, "block").size(), 1, "stand block stops the overhead")
	t.eq(sim.fighters[1].health, 940, "special chip damage")


# --- specials input ----------------------------------------------------------------------------

func test_simple_special_and_motion_bonus() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var e := until(sim, [RIGHT | HP], 0, "hit")
	t.eq(e.get("move"), "squeegee_swing", "forward + HP = Squeegee Swing")
	t.eq(e.get("dmg"), 110, "simple input damage")
	sim = t.fight("arghya", "jitu", 100)
	e = until(sim, [DOWN, DOWN | RIGHT, RIGHT, RIGHT | HP], 0, "hit")
	t.eq(e.get("move"), "squeegee_swing", "quarter-circle forward + HP = Squeegee Swing")
	t.eq(e.get("dmg"), 121, "classic motion +10%")


func test_walking_then_button_is_a_normal() -> void:
	var sim = t.fight("arghya", "jitu", 300)
	var seq := []
	for i in 12:
		seq.append(RIGHT)
	seq.append(RIGHT | HP)
	var moves: Array = t.events_of(t.run(sim, seq + pad([], 5), 0), "move")
	t.eq(moves.map(func(m): return m.move), ["st_hp"], "held direction doesn't trigger the special")


func test_crouching_heavy_still_reachable() -> void:
	var sim = t.fight("arghya", "jitu", 300)
	var seq := []
	for i in 10:
		seq.append(DOWN)
	seq.append(DOWN | HP)
	var moves: Array = t.events_of(t.run(sim, seq + pad([], 5), 0), "move")
	t.eq(moves.map(func(m): return m.move), ["cr_hp"], "held down + HP = crouching heavy punch")


func test_dash_on_double_tap() -> void:
	var sim = t.fight("arghya", "jitu", 400)
	t.run(sim, [RIGHT, 0, RIGHT], 0)
	t.eq(sim.fighters[0].state_name(), "dash_f", "double-tap forward dashes")


# --- meter, super, ultra -----------------------------------------------------------------------

func test_meter_from_hits_damage_and_blocks() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	until(sim, [HP], 0, "hit")
	t.eq(sim.fighters[0].meter, 80, "attacker gains the move's damage")
	t.eq(sim.fighters[1].meter, 40, "defender gains half the damage taken")
	sim = t.fight("arghya", "jitu", 100)
	until(sim, [HP], RIGHT, "block")
	t.eq(sim.fighters[1].meter, 24, "blocker gains 30%")


func test_super_needs_one_bar_ultra_needs_three() -> void:
	var sim = t.fight("arghya", "jitu", 300)
	sim.fighters[0].meter = 400
	var moves: Array = t.events_of(t.run(sim, [HP | HK] + pad([], 3), 0), "move")
	t.check(moves.size() == 1 and moves[0].move != "heat_press", "no super without a bar")
	sim = t.fight("arghya", "jitu", 300)
	sim.fighters[0].meter = 500
	var ev: Array = t.run(sim, [HP | HK] + pad([], 3), 0)
	t.eq(t.events_of(ev, "move").map(func(m): return m.move), ["heat_press"], "super with one bar")
	t.eq(t.events_of(ev, "super_flash").size(), 1, "super flash")
	t.eq(sim.fighters[0].meter, 0, "super costs 1 bar")
	sim = t.fight("arghya", "jitu", 300)
	sim.fighters[0].meter = 1500
	ev = t.run(sim, [DOWN, DOWN | HP | HK] + pad([], 3), 0)
	t.eq(t.events_of(ev, "move").map(func(m): return m.move), ["full_bleed"], "ultra with three bars")
	t.eq(sim.fighters[0].meter, 0, "ultra costs all 3 bars")


# --- juggles, knockdown, armor -----------------------------------------------------------------

func test_juggle_limit_three_hits() -> void:
	for jh in [2, 3]:
		var sim = t.fight("arghya", "jitu", 90)
		var d = sim.fighters[1]
		d._set_state(t.Fighter.JUGGLE)
		d.airborne = 1
		d.y = 40 * t.R.FP
		d.vy = 1200
		d.juggle_hits = jh
		var e := until(sim, [HP], 0, "hit", 12)
		if jh == 2:
			t.check(not e.is_empty(), "third juggle hit connects")
			t.eq(d.juggle_hits, 3, "juggle count")
		else:
			t.check(e.is_empty(), "no fourth juggle hit")


func test_launcher_starts_juggle_and_lands_in_knockdown() -> void:
	var sim = t.fight("arghya", "jitu", 90)
	var e := until(sim, [DOWN, DOWN | HP], 0, "hit")
	t.eq(e.get("move"), "heat_press_palm", "fresh down + HP")
	t.eq(sim.fighters[1].state_name(), "juggle", "launched")
	var kd := until(sim, [], 0, "knockdown", 120)
	t.check(not kd.is_empty(), "lands in knockdown")


func test_getup_is_invincible() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	sim.fighters[1]._set_state(t.Fighter.GETUP)
	t.check(until(sim, [LP], 0, "hit", 10).is_empty(), "can't hit a fighter getting up")
	t.run(sim, 0, 0, t.R.GETUP_FRAMES)
	t.eq(sim.fighters[1].state_name(), "idle", "gets up")


func test_armor_absorbs_one_hit() -> void:
	var d = variant(func(j): j.moves.st_hk.armor = [0, 8, 1])
	var sim = t.MatchSim.new(d, t.fighter("jitu"))
	while sim.phase == t.MatchSim.Phase.INTRO:
		sim.step(0, 0)
	t.place(sim, 100)
	var ev: Array = t.run(sim, [HK] + pad([], 20), [0, LP] + pad([], 20))
	t.eq(t.events_of(ev, "armor").size(), 1, "jab absorbed")
	var hits: Array = t.events_of(ev, "hit")
	t.check(hits.size() >= 1 and hits[0].p == 1, "armored kick still lands")
	t.eq(sim.fighters[0].health, 975, "armor still takes the damage (Jitu jab = 25)")


# --- throws ------------------------------------------------------------------------------------

func test_throw_break_within_7_frames() -> void:
	var sim = t.fight("arghya", "jitu", 70)
	var e := until(sim, [LP | LK], 0, "grab", 10)
	t.check(not e.is_empty(), "throw grabs")
	t.check(not until(sim, [], [0, LP | LK], "tech", 10).is_empty(), "break pressed 2 frames in")
	sim = t.fight("arghya", "jitu", 70)
	until(sim, [LP | LK], 0, "grab", 10)
	var ev: Array = t.run(sim, [], pad([], 9) + [LP | LK] + pad([], 5))
	t.eq(t.events_of(ev, "tech").size(), 0, "too late to break")
	t.eq(sim.fighters[1].health, 830, "throw damage")
	t.eq(sim.fighters[1].state_name(), "knockdown", "throw knocks down")


func test_throw_cannot_grab_blockstun() -> void:
	var sim = t.fight("arghya", "jitu", 70)
	sim.fighters[1]._set_state(t.Fighter.BLOCKSTUN)
	sim.fighters[1].stun = 20
	t.check(until(sim, [LP | LK], 0, "grab", 10).is_empty(), "blockstun is throw-proof")


# --- spacing -----------------------------------------------------------------------------------

func test_corner_pushback_goes_to_attacker() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	var wall: int = t.R.STAGE_WIDTH - t.R.STAGE_MARGIN - sim.fighters[1].data.push_w / 2
	sim.fighters[1].x = wall
	sim.fighters[0].x = wall - 100 * t.R.FP
	var x0: int = sim.fighters[0].x
	until(sim, [LP], 0, "hit")
	t.run(sim, 0, 0, 12)
	t.check(sim.fighters[0].x < x0, "attacker pushed back off the cornered opponent")
	t.eq(sim.fighters[1].x, wall, "defender stays in the corner")


func test_fighters_cannot_overlap() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	t.run(sim, RIGHT, LEFT, 60)
	var gap: int = sim.fighters[1].x - sim.fighters[0].x
	t.check(gap >= (sim.fighters[0].data.push_w + sim.fighters[1].data.push_w) / 2 - 1, "pushboxes keep them apart (%d)" % gap)


# --- rounds ------------------------------------------------------------------------------------

func test_ko_wins_round_and_best_of_three() -> void:
	var sim = t.fight("arghya", "jitu", 100)
	sim.fighters[1].health = 1
	t.check(not until(sim, [LP], 0, "ko").is_empty(), "KO")
	t.eq(sim.wins[0], 1, "P1 has a round")
	until(sim, [], 0, "round_start", t.R.ROUND_END_FRAMES + t.R.KO_FREEZE + 5)
	t.eq(sim.round_num, 2, "round 2 starts")
	t.eq(sim.fighters[1].health, 950, "health refilled")
	until(sim, [], 0, "fight", t.R.INTRO_FRAMES + 2)
	t.place(sim, 100)
	sim.fighters[1].health = 1
	until(sim, [LP], 0, "ko")
	var over := until(sim, [], 0, "match_over", t.R.ROUND_END_FRAMES + t.R.KO_FREEZE + 5)
	t.eq(over.get("winner"), 0, "P1 wins the match 2-0")
	t.eq(sim.phase, t.MatchSim.Phase.FINISHER_WINDOW, "finisher window opens")
	t.check(not until(sim, [HP | HK], 0, "finisher", 5).is_empty(), "Super in the window triggers the finisher")


func test_time_out_goes_to_more_health() -> void:
	var sim = t.fight("arghya", "jitu", 300)
	t.eq(sim.seconds_left(), 99, "99-second timer")
	sim.timer = 3
	sim.fighters[0].health = 400
	var e := until(sim, [], 0, "time", 5)
	t.eq(e.get("winner"), 1, "Jitu has more health")


func test_training_mode_never_kos() -> void:
	var sim = t.MatchSim.new(t.fighter("arghya"), t.fighter("jitu"), true)
	t.place(sim, 100)
	sim.fighters[1].health = 1
	t.check(until(sim, [LP], 0, "ko", 20).is_empty(), "no KO in training")
	t.eq(sim.fighters[1].health, 1, "health floors at 1")
	t.run(sim, 0, 0, 80)
	t.eq(sim.fighters[1].health, 950, "health refills in neutral")
