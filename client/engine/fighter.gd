## One fighter's mutable fight state and per-fighter state machine.
## Whole-number math only; everything that affects the fight is listed in SAVED for rollback.
## Contains no fighter-specific code: all behaviour comes from the fighter's data file.
extends RefCounted

const B := preload("res://engine/input_bits.gd")
const R := preload("res://engine/rules.gd")
const FD := preload("res://engine/fighter_data.gd")
const InputBuffer := preload("res://engine/input_buffer.gd")

enum {
	IDLE, WALK_F, WALK_B, CROUCH, JUMP_SQUAT, AIR, LAND, DASH_F, DASH_B, ATTACK,
	HITSTUN, BLOCKSTUN, JUGGLE, KNOCKDOWN, GETUP, THROWING, THROWN, THROW_TECH, KO, WIN,
}
const STATE_NAMES := [
	"idle", "walk_f", "walk_b", "crouch", "jump_squat", "air", "land", "dash_f", "dash_b", "attack",
	"hitstun", "blockstun", "juggle", "knockdown", "getup", "throwing", "thrown", "throw_tech", "ko", "win",
]
const NEUTRAL := [IDLE, WALK_F, WALK_B, CROUCH]

const SAVED := [
	"x", "y", "vx", "vy", "facing", "state", "state_frame", "crouching", "airborne", "jump_dx",
	"air_used", "move", "move_frame", "hit_mask", "connected", "stun", "health", "meter",
	"combo_hits", "combo_damage", "juggle_hits", "armor_used", "bonus_pct", "slide_v",
	"slide_ticks", "throw_timer", "land_frames",
]

var data: FD
var buf := InputBuffer.new()

var x := 0
var y := 0
var vx := 0
var vy := 0
var facing := 1
var state := IDLE
var state_frame := 0
var crouching := 0
var airborne := 0
var jump_dx := 0          # -1/0/1 screen direction of the current jump
var air_used := 0         # one air attack per jump
var move := -1
var move_frame := 0
var hit_mask := 0         # hits of the current move that already connected
var connected := 0        # 0 none, 1 hit, 2 blocked: allows cancels
var stun := 0
var health := 0
var meter := 0
var combo_hits := 0       # hits taken in the current combo (as the defender)
var combo_damage := 0
var juggle_hits := 0
var armor_used := 0
var bonus_pct := 100      # 110 when the move was done with a classic motion
var slide_v := 0
var slide_ticks := 0
var throw_timer := 0
var land_frames := 0


func _init(fighter_data: FD) -> void:
	data = fighter_data


func reset_round(start_x: int, face: int) -> void:
	x = start_x
	y = 0
	vx = 0
	vy = 0
	facing = face
	_set_state(IDLE)
	crouching = 0
	airborne = 0
	air_used = 0
	move = -1
	stun = 0
	health = data.health
	combo_hits = 0
	combo_damage = 0
	juggle_hits = 0
	slide_ticks = 0
	throw_timer = 0
	buf.reset()


func save() -> Array:
	var out := []
	for f in SAVED:
		out.append(get(f))
	out.append(buf.save())
	return out


func restore(s: Array) -> void:
	for i in SAVED.size():
		set(SAVED[i], s[i])
	buf.restore(s[SAVED.size()])


# --- queries -----------------------------------------------------------------------------------

func fwd_bit() -> int:
	return B.RIGHT if facing > 0 else B.LEFT


func back_bit() -> int:
	return B.LEFT if facing > 0 else B.RIGHT


func cur_move() -> Dictionary:
	return data.moves[move] if move >= 0 else {}


func state_name() -> String:
	return STATE_NAMES[state]


## Startup frames of the current move: getting hit now is a counter-hit.
func in_startup() -> bool:
	return state == ATTACK and move_frame < data.moves[move].first_active


func can_block() -> bool:
	return airborne == 0 and (state in NEUTRAL or state == BLOCKSTUN or state == LAND)


func holding_back() -> bool:
	return buf.current & back_bit() != 0


func _move_flag(flag: String) -> bool:
	if state != ATTACK:
		return false
	var m: Dictionary = data.moves[move]
	return m[flag] and move_frame >= m.inv_from and move_frame <= m.inv_to


func strike_invuln() -> bool:
	return state in [KNOCKDOWN, GETUP, KO, THROWING, THROWN, THROW_TECH, WIN] or _move_flag("inv_strike")


func projectile_invuln() -> bool:
	return strike_invuln() or _move_flag("inv_projectile")


func throwable() -> bool:
	if airborne or state in [HITSTUN, BLOCKSTUN, JUGGLE, KNOCKDOWN, GETUP, THROWING, THROWN, THROW_TECH, KO, WIN]:
		return false
	return not _move_flag("inv_throw")


func has_armor() -> bool:
	if state != ATTACK:
		return false
	var m: Dictionary = data.moves[move]
	return m.armor_hits > armor_used and move_frame >= m.armor_from and move_frame <= m.armor_to


## Converts a box defined facing right, relative to the feet, into world [x, y, w, h].
func world_box(b: Array) -> Array:
	if facing > 0:
		return [x + b[0], y + b[1], b[2], b[3]]
	return [x - b[0] - b[2], y + b[1], b[2], b[3]]


func push_box() -> Array:
	return [x - data.push_w / 2, y, data.push_w, data.push_h]


func hurtboxes() -> Array:
	if state in [KNOCKDOWN, GETUP, KO]:
		return []
	var src: Array
	if airborne:
		src = data.hurt_air
	elif crouching:
		src = data.hurt_crouch
	else:
		src = data.hurt_stand
	var out := []
	for b in src:
		out.append(world_box(b))
	if state == ATTACK:
		var m: Dictionary = data.moves[move]
		if move_frame >= m.first_active:
			for b in m.hurt_extend:
				out.append(world_box(b))
	return out


## Hits of the current move that are active this frame and haven't connected yet: [[index, world_box], ...]
func active_hits() -> Array:
	var out := []
	if state != ATTACK:
		return out
	var m: Dictionary = data.moves[move]
	for i in m.hits.size():
		var h: Dictionary = m.hits[i]
		if move_frame >= h.start and move_frame < h.end and not hit_mask & (1 << i):
			out.append([i, world_box(h.box)])
	return out


# --- state machine -----------------------------------------------------------------------------

func _set_state(s: int) -> void:
	if state != s:
		state = s
		state_frame = 0


func start_move(sim, idx: int, bonus: int) -> void:
	var m: Dictionary = data.moves[idx]
	_set_state(ATTACK)
	state_frame = 0
	move = idx
	move_frame = 0
	hit_mask = 0
	connected = 0
	armor_used = 0
	bonus_pct = bonus
	crouching = 1 if m.crouching else 0
	if m.air:
		air_used = 1
	else:
		vx = 0
	if m.meter_cost > 0:
		meter -= m.meter_cost
	if m.flash > 0:
		sim.flash(self, m.flash)
	sim.emit({"t": "move", "who": self, "move": m.name, "category": m.category})


## Per-tick update before physics. `locked` = the round is over, inputs are ignored.
func think(sim, opp, locked: bool) -> void:
	state_frame += 1
	match state:
		IDLE, WALK_F, WALK_B, CROUCH:
			_neutral(sim, locked)
		JUMP_SQUAT:
			if state_frame >= data.jump_squat:
				_set_state(AIR)
				airborne = 1
				vy = data.jump_velocity
				vx = jump_dx * data.jump_forward
		AIR:
			if not locked and air_used == 0:
				_try_attack(sim, null)
		LAND:
			if state_frame >= land_frames:
				_set_state(IDLE)
				_neutral(sim, locked)
		DASH_F, DASH_B:
			var fwd := state == DASH_F
			var frames := data.dash_forward_frames if fwd else data.dash_back_frames
			var speed := data.dash_forward_speed if fwd else -data.dash_back_speed
			vx = speed * facing
			if state_frame >= frames:
				vx = 0
				_set_state(IDLE)
		ATTACK:
			move_frame += 1
			var m: Dictionary = data.moves[move]
			if connected and not locked and _try_attack(sim, m.cancel):
				return
			if move_frame >= m.total:
				_end_move(sim, locked)
		HITSTUN, BLOCKSTUN:
			stun -= 1
			if stun <= 0:
				_recover()
				_neutral(sim, locked)
		KNOCKDOWN:
			if state_frame >= R.KNOCKDOWN_FRAMES:
				_set_state(GETUP)
		GETUP:
			if state_frame >= R.GETUP_FRAMES:
				_recover()
		THROW_TECH:
			if state_frame >= R.THROW_TECH_FRAMES:
				_set_state(IDLE)
		THROWING:
			if throw_timer <= 0 and state_frame >= R.THROW_RECOVERY + R.THROW_BREAK_WINDOW:
				move = -1
				_set_state(IDLE)


func _recover() -> void:
	_set_state(IDLE)
	combo_hits = 0
	combo_damage = 0
	juggle_hits = 0
	stun = 0


func _end_move(sim, locked: bool) -> void:
	var m: Dictionary = data.moves[move]
	move = -1
	if airborne:
		_set_state(AIR)
		return
	vx = 0
	_set_state(IDLE)
	crouching = 0
	_neutral(sim, locked)


func _neutral(sim, locked: bool) -> void:
	if locked:
		vx = 0
		crouching = 0
		_set_state(WIN if sim.is_round_winner(self) else IDLE)
		return
	if _try_attack(sim, null):
		return
	var cur := buf.current
	if buf.dashed(facing) and cur & B.DOWN == 0:
		buf.consume_dash()
		_set_state(DASH_F)
		crouching = 0
		return
	if buf.dashed(-facing) and cur & B.DOWN == 0:
		buf.consume_dash()
		_set_state(DASH_B)
		crouching = 0
		return
	if cur & B.UP:
		_set_state(JUMP_SQUAT)
		crouching = 0
		vx = 0
		jump_dx = (1 if cur & B.RIGHT else 0) - (1 if cur & B.LEFT else 0)
		air_used = 0
	elif cur & B.DOWN:
		_set_state(CROUCH)
		crouching = 1
		vx = 0
	elif cur & fwd_bit():
		_set_state(WALK_F)
		crouching = 0
		vx = data.walk_forward * facing
	elif cur & back_bit():
		_set_state(WALK_B)
		crouching = 0
		vx = -data.walk_back * facing
	else:
		_set_state(IDLE)
		crouching = 0
		vx = 0


## Looks for a move to start from the buffered inputs. `allowed` = null for neutral (anything),
## or a cancel list of categories / move names.
func _try_attack(sim, allowed) -> bool:
	var in_air := airborne != 0
	# Ultra: down + HP + HK, Super: HP + HK
	if not in_air and buf.chord(B.HP, B.HK):
		if data.ultra_move >= 0 and buf.current & B.DOWN and meter >= data.moves[data.ultra_move].meter_cost \
				and _allowed(data.ultra_move, allowed):
			buf.consume(B.HP | B.HK)
			start_move(sim, data.ultra_move, 100)
			return true
		if data.super_move >= 0 and meter >= data.moves[data.super_move].meter_cost \
				and _allowed(data.super_move, allowed):
			buf.consume(B.HP | B.HK)
			start_move(sim, data.super_move, 100)
			return true
	# Specials: classic motion first (+10% damage), then the simple direction + button.
	if not in_air:
		for pass_motion in [true, false]:
			for s in data.specials:
				if not buf.pressed(s.button) or not _allowed(s.move, allowed):
					continue
				if pass_motion:
					if not buf.motion(s.motion, facing):
						continue
				elif not _fresh_dir(s.dir):
					continue
				buf.consume(s.button)
				start_move(sim, s.move, R.MOTION_BONUS_PCT if pass_motion else 100)
				return true
	# Throw: LP + LK, only from neutral on the ground.
	if not in_air and allowed == null and data.throw_move >= 0 and buf.chord(B.LP, B.LK):
		buf.consume(B.LP | B.LK)
		start_move(sim, data.throw_move, 100)
		return true
	# Normals: the most recently pressed button wins; heavy wins a tie.
	var prefix := "j_" if in_air else ("cr_" if buf.current & B.DOWN else "st_")
	var best := -1
	var best_age := 1 << 20
	for btn in ["hk", "hp", "lk", "lp"]:
		var bit: int = FD.BUTTONS[btn]
		var a := buf.age(bit)
		if a <= R.INPUT_BUFFER and a < best_age:
			var idx: int = data.normals.get(prefix + btn, -1)
			if idx >= 0 and _allowed(idx, allowed):
				best = idx
				best_age = a
	if best >= 0:
		buf.consume(FD.BUTTONS[data.moves[best].name.get_slice("_", 1)])
		start_move(sim, best, 100)
		return true
	return false


func _allowed(idx: int, allowed) -> bool:
	if allowed == null:
		return true
	var m: Dictionary = data.moves[idx]
	return m.category in allowed or m.name in allowed


## Simple specials: the direction must have been pressed within SIMPLE_SPECIAL_WINDOW frames
## (it may already be released, e.g. tapped during hit-stop). Walking or crouching for longer
## and then pressing a button still gives the normal move.
func _fresh_dir(dir: String) -> bool:
	var bit: int
	match dir:
		"forward": bit = fwd_bit()
		"back": bit = back_bit()
		_: bit = B.DOWN
	return buf.age(bit) <= R.SIMPLE_SPECIAL_WINDOW


# --- physics -----------------------------------------------------------------------------------

func physics(sim) -> void:
	if slide_ticks > 0:
		x += slide_v
		slide_ticks -= 1
	if state == ATTACK and not airborne:
		var m: Dictionary = data.moves[move]
		vx = 0
		for seg in m.motion:
			if move_frame >= seg[0] and move_frame < seg[1]:
				vx = seg[2] * facing
	if state in [THROWING, THROWN, KNOCKDOWN, GETUP]:
		vx = 0
	x += vx
	if airborne:
		y += vy
		vy -= data.gravity
		if y <= 0:
			_land(sim)


func _land(sim) -> void:
	y = 0
	vy = 0
	airborne = 0
	match state:
		AIR, ATTACK:
			move = -1
			vx = 0
			land_frames = R.LAND_FRAMES
			_set_state(LAND)
			sim.emit({"t": "land", "who": self})
		JUGGLE:
			vx = 0
			_set_state(KNOCKDOWN)
			sim.emit({"t": "knockdown", "who": self})
		KO:
			vx = 0
			sim.emit({"t": "knockdown", "who": self})
		_:
			vx = 0


func face(opp) -> void:
	if state in [IDLE, WALK_F, WALK_B, CROUCH, LAND, JUMP_SQUAT, GETUP] and opp.x != x:
		var f := 1 if opp.x > x else -1
		if f != facing:
			facing = f
			if state == WALK_F or state == WALK_B:
				state = WALK_B if state == WALK_F else WALK_F


func slide(dist: int) -> void:
	slide_v = dist / R.PUSHBACK_TICKS
	slide_ticks = R.PUSHBACK_TICKS
