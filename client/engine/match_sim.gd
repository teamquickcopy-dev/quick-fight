## The whole fight: two fighters, rounds, timer, hit-stop, hits, blocks, throws.
## step() takes one frame of input per player. Nothing here reads the keyboard, the clock or
## any randomness, so the same inputs always produce the same fight (required for rollback).
extends RefCounted

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")
const FD := preload("res://engine/fighter_data.gd")
const Fighter := preload("res://engine/fighter.gd")

enum Phase { INTRO, FIGHT, ROUND_END, FINISHER_WINDOW, FINISHER, OVER }

var fighters: Array = []
var frame := 0
var phase := Phase.INTRO
var phase_frame := 0
var round_num := 1
var wins := PackedInt32Array([0, 0])
var timer := 0
var freeze := 0
var round_winner := -1      # -1 undecided, 0/1, 2 = draw
var match_winner := -1

# Training options (offline only, but kept in the sim so behaviour stays deterministic).
var training := false
var infinite_meter := false

## Presentation events for this frame only (sparks, shake, announcer). Not part of the state.
var events: Array = []


func _init(a: FD, b: FD, is_training := false) -> void:
	fighters = [Fighter.new(a), Fighter.new(b)]
	training = is_training
	_start_round()


## Rematch with the same fighters.
func restart() -> void:
	wins = PackedInt32Array([0, 0])
	round_num = 1
	match_winner = -1
	for f in fighters:
		f.meter = 0
	_start_round()


func _start_round() -> void:
	var c := R.STAGE_WIDTH / 2
	fighters[0].reset_round(c - R.START_GAP / 2, 1)
	fighters[1].reset_round(c + R.START_GAP / 2, -1)
	timer = R.ROUND_SECONDS * R.TICKS_PER_SECOND
	freeze = 0
	round_winner = -1
	phase = Phase.FIGHT if training else Phase.INTRO
	phase_frame = 0


func emit(e: Dictionary) -> void:
	if e.has("who"):
		e.p = fighters.find(e.who)
		e.erase("who")
	events.append(e)


func flash(who, frames: int) -> void:
	freeze = maxi(freeze, frames)
	emit({"t": "super_flash", "who": who, "frames": frames})


func is_round_winner(f) -> bool:
	var i := fighters.find(f)
	return round_winner == i or match_winner == i


func seconds_left() -> int:
	return (timer + R.TICKS_PER_SECOND - 1) / R.TICKS_PER_SECOND


## Advance one frame. Inputs are bitmasks from input_bits.gd in screen directions.
func step(in0: int, in1: int) -> void:
	frame += 1
	events.clear()
	var frozen := freeze > 0
	fighters[0].buf.push(in0, frozen)
	fighters[1].buf.push(in1, frozen)
	phase_frame += 1
	match phase:
		Phase.INTRO:
			if phase_frame == 1:
				emit({"t": "round_start", "round": round_num})
			for f in fighters:
				f.state_frame += 1
			if phase_frame >= R.INTRO_FRAMES:
				_set_phase(Phase.FIGHT)
				emit({"t": "fight"})
		Phase.FIGHT, Phase.ROUND_END:
			_fight_tick()
			if phase == Phase.ROUND_END and phase_frame >= R.ROUND_END_FRAMES:
				_after_round()
		Phase.FINISHER_WINDOW:
			_fight_tick()
			if fighters[match_winner].buf.chord(B.HP, B.HK):
				_set_phase(Phase.FINISHER)
				emit({"t": "finisher", "p": match_winner})
			elif phase_frame >= R.FINISHER_WINDOW:
				_set_phase(Phase.OVER)
		Phase.FINISHER:
			_fight_tick()
			if phase_frame >= R.FINISHER_FRAMES:
				_set_phase(Phase.OVER)
		Phase.OVER:
			pass


func _set_phase(p: int) -> void:
	phase = p
	phase_frame = 0


func _fight_tick() -> void:
	if freeze > 0:
		freeze -= 1
		return
	var a = fighters[0]
	var b = fighters[1]
	var locked := phase != Phase.FIGHT
	_throw_tick()
	a.think(self, b, locked)
	b.think(self, a, locked)
	var prev := [a.x, b.x]
	a.physics(self)
	b.physics(self)
	_push(a, b, prev)
	a.face(b)
	b.face(a)
	if not locked:
		_hits()
	if training:
		_training_tick()
	if phase == Phase.FIGHT:
		_check_round()


# --- hits --------------------------------------------------------------------------------------

static func overlap(r1: Array, r2: Array) -> bool:
	return r1[0] < r2[0] + r2[2] and r2[0] < r1[0] + r1[2] and r1[1] < r2[1] + r2[3] and r2[1] < r1[1] + r1[3]


func _hits() -> void:
	# Collect first, then apply, so both fighters hitting on the same frame trade.
	var strikes := []
	var grabs := []
	for i in 2:
		var att = fighters[i]
		var def = fighters[1 - i]
		for ah in att.active_hits():
			var m: Dictionary = att.cur_move()
			if m.throw:
				if def.throwable() and overlap(ah[1], def.push_box()):
					grabs.append([att, def])
				break
			if def.strike_invuln():
				break
			if def.state == Fighter.JUGGLE and def.juggle_hits >= R.JUGGLE_LIMIT:
				break  # fell out of the juggle
			var touched := false
			for hb in def.hurtboxes():
				if overlap(ah[1], hb):
					touched = true
					break
			if touched:
				strikes.append([att, def, m, ah[0], def.in_startup(), ah[1]])
				break
	for s in strikes:
		_apply_strike(s[0], s[1], s[2], s[3], s[4], s[5])
	if grabs.size() == 2:
		_throw_tech(grabs[0][0], grabs[0][1])
	elif grabs.size() == 1:
		var att = grabs[0][0]
		var def = grabs[0][1]
		# A strike landing on the same frame beats the grab.
		if att.state == Fighter.ATTACK and def.throwable():
			_start_throw(att, def)


func _blocks(def, att, h: Dictionary) -> bool:
	if not def.can_block() or not def.holding_back():
		return false
	var crouch: bool = def.buf.current & B.DOWN != 0
	if h.level == FD.LEVEL_LOW and not crouch:
		return false
	if (h.level == FD.LEVEL_OVERHEAD or att.airborne) and crouch:
		return false
	return true


func _away(att, def) -> int:
	if def.x != att.x:
		return 1 if def.x > att.x else -1
	return att.facing


func _at_wall(f, dir: int) -> bool:
	var half: int = f.data.push_w / 2
	if dir > 0:
		return f.x >= R.STAGE_WIDTH - R.STAGE_MARGIN - half
	return f.x <= R.STAGE_MARGIN + half


## Pushback goes to the defender, or back onto the attacker when the defender is in the corner.
func _push_apart(att, def, dist: int) -> void:
	var away := _away(att, def)
	if _at_wall(def, away):
		att.slide(-away * dist)
	else:
		def.slide(away * dist)


func _gain(f, amount: int) -> void:
	f.meter = clampi(f.meter + amount, 0, R.METER_MAX)


static func scaling_pct(combo_hit: int) -> int:
	if combo_hit <= R.SCALING_FREE_HITS:
		return 100
	return maxi(100 - R.SCALING_STEP_PCT * (combo_hit - R.SCALING_FREE_HITS), R.SCALING_FLOOR_PCT)


## `m` is captured when hits are collected: in a trade the attacker may already have been hit.
func _apply_strike(att, def, m: Dictionary, idx: int, counter: bool, box: Array) -> void:
	var h: Dictionary = m.hits[idx]
	att.hit_mask |= 1 << idx
	var builds_meter: bool = m.meter_cost == 0
	var spark := [box[0] + box[2] / 2, box[1] + box[3] / 2]
	freeze = maxi(freeze, h.hitstop)

	if _blocks(def, att, h):
		def.crouching = 1 if def.buf.current & B.DOWN else 0
		def.move = -1
		def.vx = 0
		def._set_state(Fighter.BLOCKSTUN)
		def.state_frame = 0
		def.stun = h.blockstun
		def.health = maxi(def.health - h.chip, 1 if training else 0)
		_push_apart(att, def, h.pushback)
		_gain(def, h.damage * R.METER_ON_BLOCK_PCT / 100)
		if att.connected == 0:
			att.connected = 2
		emit({"t": "block", "who": def, "x": spark[0], "y": spark[1], "heavy": h.heavy,
				"adv": def.stun - (m.total - att.move_frame)})
		return

	if def.has_armor():
		def.armor_used += 1
		var adm: int = maxi(h.damage * att.bonus_pct / 100, 1)
		def.health = maxi(def.health - adm, 1 if training else 0)
		att.connected = 1
		emit({"t": "armor", "who": def, "x": spark[0], "y": spark[1], "dmg": adm})
		return

	var juggling: bool = def.state == Fighter.JUGGLE
	if def.state == Fighter.HITSTUN or juggling:
		def.combo_hits += 1
	else:
		def.combo_hits = 1
		def.combo_damage = 0
		def.juggle_hits = 0
	var dmg: int = h.damage * scaling_pct(def.combo_hits) * att.bonus_pct \
			* (R.COUNTER_HIT_PCT if counter else 100) / 1000000
	dmg = maxi(dmg, 1)
	def.health = maxi(def.health - dmg, 1 if training else 0)
	def.combo_damage += dmg
	if builds_meter:
		_gain(att, h.damage * R.METER_ON_HIT_PCT / 100)
	_gain(def, dmg * R.METER_ON_DAMAGE_TAKEN_PCT / 100)
	att.connected = 1
	def.move = -1
	var away := _away(att, def)
	var adv := 0
	if def.airborne or h.launch:
		if juggling:
			def.juggle_hits += 1
		def._set_state(Fighter.JUGGLE)
		def.airborne = 1
		def.crouching = 0
		def.vy = h.launch_vy if h.launch else R.AIR_HIT_VY
		def.vx = away * (h.launch_vx if h.launch else R.AIR_HIT_VX)
	elif h.knockdown:
		def._set_state(Fighter.KNOCKDOWN)
		def.crouching = 0
		def.vx = 0
		def.slide(away * h.pushback)
		emit({"t": "knockdown", "who": def})
	else:
		def._set_state(Fighter.HITSTUN)
		def.state_frame = 0
		def.vx = 0
		def.stun = h.hitstun
		_push_apart(att, def, h.pushback)
		adv = def.stun - (m.total - att.move_frame)
	emit({"t": "hit", "who": def, "x": spark[0], "y": spark[1], "heavy": h.heavy, "counter": counter,
			"dmg": dmg, "combo": def.combo_hits, "adv": adv, "move": m.name})
	if h.heavy or h.knockdown or h.launch:
		emit({"t": "shake", "amount": 8 if h.heavy else 4})


# --- throws ------------------------------------------------------------------------------------

func _start_throw(att, def) -> void:
	att._set_state(Fighter.THROWING)
	att.throw_timer = R.THROW_BREAK_WINDOW
	att.vx = 0
	att.hit_mask = 1
	att.connected = 1
	def.move = -1
	def.vx = 0
	def.crouching = 0
	def._set_state(Fighter.THROWN)
	def.throw_timer = R.THROW_BREAK_WINDOW
	emit({"t": "grab", "who": att})


func _throw_tech(a, b) -> void:
	for f in [a, b]:
		f.move = -1
		f.vx = 0
		f.throw_timer = 0
		f._set_state(Fighter.THROW_TECH)
	_push_apart(a, b, R.THROW_TECH_PUSH / 2)
	_push_apart(b, a, R.THROW_TECH_PUSH / 2)
	emit({"t": "tech", "x": (a.x + b.x) / 2, "y": 120 * R.FP})


## Runs at the start of each tick: the break window, then the throw damage.
func _throw_tick() -> void:
	for i in 2:
		var att = fighters[i]
		var def = fighters[1 - i]
		if att.state != Fighter.THROWING or att.throw_timer <= 0 or def.state != Fighter.THROWN:
			continue
		var m: Dictionary = att.cur_move()
		var elapsed: int = R.THROW_BREAK_WINDOW - att.throw_timer
		var lp: int = def.buf.age(B.LP)
		var lk: int = def.buf.age(B.LK)
		if m.breakable and def.buf.chord(B.LP, B.LK) and mini(lp, lk) <= elapsed:
			def.buf.consume(B.LP | B.LK)
			_throw_tech(att, def)
			continue
		att.throw_timer -= 1
		def.throw_timer = att.throw_timer
		if att.throw_timer > 0:
			continue
		var h: Dictionary = m.hits[0]
		var dmg: int = maxi(h.damage * att.bonus_pct / 100, 1)
		def.combo_hits = 1
		def.combo_damage = dmg
		def.health = maxi(def.health - dmg, 1 if training else 0)
		_gain(att, h.damage * R.METER_ON_HIT_PCT / 100)
		_gain(def, dmg * R.METER_ON_DAMAGE_TAKEN_PCT / 100)
		def._set_state(Fighter.KNOCKDOWN)
		def.slide(_away(att, def) * 80 * R.FP)
		emit({"t": "hit", "who": def, "x": def.x, "y": 100 * R.FP, "heavy": true, "counter": false,
				"dmg": dmg, "combo": 1, "adv": 0, "move": m.name})
		emit({"t": "shake", "amount": 8})


# --- movement limits ---------------------------------------------------------------------------

func _clamp_stage(f) -> void:
	var half: int = f.data.push_w / 2
	f.x = clampi(f.x, R.STAGE_MARGIN + half, R.STAGE_WIDTH - R.STAGE_MARGIN - half)


func _push(a, b, prev: Array) -> void:
	_clamp_stage(a)
	_clamp_stage(b)
	var pa: Array = a.push_box()
	var pb: Array = b.push_box()
	if pa[1] < pb[1] + pb[3] and pb[1] < pa[1] + pa[3]:
		var ov: int = (pa[2] + pb[2]) / 2 - absi(a.x - b.x)
		if ov > 0:
			var dir: int = (1 if a.x > b.x else -1) if a.x != b.x else -a.facing
			var half := ov / 2
			a.x += dir * half
			b.x -= dir * (ov - half)
			_clamp_stage(a)
			_clamp_stage(b)
			ov = (pa[2] + pb[2]) / 2 - absi(a.x - b.x)
			if ov > 0:  # one of them is in the corner: the other takes the full push
				if _at_wall(a, dir):
					b.x -= dir * ov
				else:
					a.x += dir * ov
				_clamp_stage(a)
				_clamp_stage(b)
	# Camera limit: whoever moved away this frame is held back.
	var excess: int = absi(a.x - b.x) - R.MAX_SEPARATION
	if excess > 0:
		var dir_a: int = 1 if a.x > b.x else -1
		var a_away: bool = (a.x - prev[0]) * dir_a > 0
		var b_away: bool = (b.x - prev[1]) * -dir_a > 0
		if a_away and not b_away:
			a.x -= dir_a * excess
		elif b_away and not a_away:
			b.x += dir_a * excess
		else:
			a.x -= dir_a * (excess / 2)
			b.x += dir_a * (excess - excess / 2)


# --- rounds ------------------------------------------------------------------------------------

func _check_round() -> void:
	var dead := [fighters[0].health <= 0, fighters[1].health <= 0]
	if dead[0] or dead[1]:
		for i in 2:
			if dead[i]:
				var f = fighters[i]
				f.move = -1
				f._set_state(Fighter.KO)
				f.airborne = 1
				f.vy = R.KO_POP_VY
				f.vx = -f.facing * R.KO_POP_VX
		round_winner = 2 if dead[0] and dead[1] else (1 if dead[0] else 0)
		freeze = maxi(freeze, R.KO_FREEZE)
		_end_round("ko")
		return
	if training:
		return
	timer -= 1
	if timer <= 0:
		var h0: int = fighters[0].health
		var h1: int = fighters[1].health
		round_winner = 0 if h0 > h1 else (1 if h1 > h0 else 2)
		_end_round("time")


func _end_round(reason: String) -> void:
	_set_phase(Phase.ROUND_END)
	if round_winner == 2:
		wins[0] += 1
		wins[1] += 1
	else:
		wins[round_winner] += 1
	var perfect: bool = round_winner < 2 and fighters[round_winner].health == fighters[round_winner].data.health
	emit({"t": reason, "winner": round_winner, "perfect": perfect})


func _after_round() -> void:
	if wins[0] >= R.ROUNDS_TO_WIN or wins[1] >= R.ROUNDS_TO_WIN:
		if wins[0] >= R.ROUNDS_TO_WIN and wins[1] >= R.ROUNDS_TO_WIN:
			match_winner = 2
			_set_phase(Phase.OVER)
		else:
			match_winner = 0 if wins[0] >= R.ROUNDS_TO_WIN else 1
			_set_phase(Phase.FINISHER_WINDOW)
		emit({"t": "match_over", "winner": match_winner})
		return
	round_num += 1
	_start_round()


func _training_tick() -> void:
	for f in fighters:
		if infinite_meter:
			f.meter = R.METER_MAX
		if f.state in Fighter.NEUTRAL and f.state_frame > 45:
			f.health = f.data.health


# --- rollback support --------------------------------------------------------------------------

func save_state() -> Array:
	return [frame, phase, phase_frame, round_num, wins.duplicate(), timer, freeze, round_winner,
			match_winner, infinite_meter, fighters[0].save(), fighters[1].save()]


func load_state(s: Array) -> void:
	frame = s[0]
	phase = s[1]
	phase_frame = s[2]
	round_num = s[3]
	wins = s[4].duplicate()
	timer = s[5]
	freeze = s[6]
	round_winner = s[7]
	match_winner = s[8]
	infinite_meter = s[9]
	fighters[0].restore(s[10])
	fighters[1].restore(s[11])


## Fingerprint of the full game state; two clients with the same inputs must always match.
func checksum() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	ctx.update(var_to_bytes(save_state()))
	return ctx.finish().hex_encode()
