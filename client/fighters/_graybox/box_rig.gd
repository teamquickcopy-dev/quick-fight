## Gray-box puppet: a fighter drawn as colored boxes on a simple 2D skeleton (hips, torso, head,
## two-bone arms and legs). Poses blend between wind-up, strike and recovery using the sim's own
## frame data, so the motion timing can be judged before the real cutout rigs exist.
## Presentation only: reads fighter state, never changes it.
extends RefCounted

const Fighter := preload("res://engine/fighter.gd")
const R := preload("res://engine/rules.gd")

const THIGH := 48.0
const SHIN := 46.0
const TORSO := 64.0
const HEAD := 17.0
const UPPER_ARM := 34.0
const FOREARM := 36.0
const LIMB_W := 15.0
const TORSO_W := 36.0

# Angles in degrees. Limbs: 0 = straight down, positive = toward the side the fighter faces.
# Torso lean: 0 = upright, positive = leaning forward. "drop" lowers the hips (px), "spin" rotates the body.
# "to" = held tool (e.g. Arghya's squeegee-hammer) angle relative to the forearm: 100 rests it on the
# shoulder, 0 extends it along the arm for a strike. Only cutout rigs with a tool use it.
const IDLE := {"lean": 6.0, "drop": 6.0, "spin": 0.0, "to": 30.0, "ft": 24.0, "fs": 2.0, "bt": -22.0, "bs": -14.0,
		"fu": 40.0, "fl": 140.0, "bu": 20.0, "bl": 120.0}
const CROUCH := {"lean": 20.0, "drop": 44.0, "spin": 0.0, "to": 30.0, "ft": 80.0, "fs": -8.0, "bt": 30.0, "bs": -60.0,
		"fu": 45.0, "fl": 135.0, "bu": 25.0, "bl": 115.0}
const AIR := {"lean": 4.0, "drop": 0.0, "spin": 0.0, "to": 100.0, "ft": 70.0, "fs": -20.0, "bt": 30.0, "bs": -50.0,
		"fu": 70.0, "fl": 150.0, "bu": 10.0, "bl": 100.0}
const HIT := {"lean": -24.0, "fu": -25.0, "fl": 20.0, "bu": -45.0, "bl": -5.0, "ft": 18.0, "bt": -30.0}
const BLOCK := {"lean": -4.0, "fu": 35.0, "fl": 172.0, "bu": 28.0, "bl": 165.0}
const LYING := {"lean": 0.0, "drop": 80.0, "spin": -92.0, "to": 60.0, "ft": 10.0, "fs": 0.0, "bt": -10.0, "bs": -10.0,
		"fu": 30.0, "fl": 40.0, "bu": -20.0, "bl": -10.0}
const WIN := {"fu": 165.0, "fl": 182.0, "bu": 30.0, "bl": 120.0, "lean": -4.0}
const DASH := {"lean": 22.0, "ft": 50.0, "fs": 20.0, "bt": -40.0, "bs": -20.0}

## Attack key poses by kind: [wind-up, strike].
const KINDS := {
	"punch": [{"fu": -25.0, "fl": 70.0, "lean": -4.0, "to": 120.0}, {"fu": 90.0, "fl": 90.0, "lean": 16.0, "bu": -10.0, "bl": 60.0, "to": 0.0}],
	"kick": [{"ft": 85.0, "fs": -15.0, "lean": -6.0}, {"ft": 88.0, "fs": 92.0, "lean": -20.0, "fu": 10.0, "fl": 60.0}],
	"sweep": [{"ft": 40.0, "fs": -30.0, "drop": 52.0}, {"ft": 84.0, "fs": 90.0, "drop": 58.0, "lean": 30.0, "bt": 20.0, "bs": -70.0}],
	"uppercut": [{"drop": 30.0, "fu": 15.0, "fl": 50.0, "lean": 18.0, "to": 60.0}, {"drop": -4.0, "fu": 165.0, "fl": 175.0, "lean": 6.0, "to": 0.0}],
	"overhead": [{"fu": 190.0, "fl": 215.0, "bu": 175.0, "bl": 205.0, "lean": -14.0, "to": 0.0}, {"fu": 100.0, "fl": 105.0, "bu": 95.0, "bl": 100.0, "lean": 30.0, "to": 0.0}],
	"throw": [{"fu": 60.0, "fl": 80.0, "bu": 50.0, "bl": 80.0}, {"fu": 84.0, "fl": 86.0, "bu": 80.0, "bl": 84.0, "lean": 16.0}],
	"air_punch": [{"fu": 30.0, "fl": 100.0}, {"fu": 70.0, "fl": 60.0, "lean": 15.0}],
	"air_kick": [{"ft": 50.0, "fs": -30.0}, {"ft": 60.0, "fs": 50.0, "bt": 0.0, "bs": -30.0, "lean": -10.0}],
	"roll": [{"drop": 50.0, "lean": 60.0, "spin": 0.0, "ft": 100.0, "fs": -40.0, "bt": 80.0, "bs": -50.0},
			{"drop": 50.0, "lean": 60.0, "spin": 360.0, "ft": 100.0, "fs": -40.0, "bt": 80.0, "bs": -50.0}],
}


static func _blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		out[k] = lerpf(a.get(k, IDLE.get(k, 0.0)), b[k], t)
	return out


static func _over(base: Dictionary, o: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(o, true)
	return out


static func _smooth(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func attack_kind(m: Dictionary, airborne: bool) -> String:
	if m.throw:
		return "throw"
	if m.hits.is_empty():
		return "roll"
	var btn: String = m.name.get_slice("_", 1) if m.name.contains("_") else ""
	var kick := btn == "lk" or btn == "hk"
	if airborne:
		return "air_kick" if kick else "air_punch"
	var box: Array = m.hits[0].box
	var top: int = (box[1] + box[3]) / R.FP
	if top <= 60:
		return "sweep"
	if m.hits[0].level == 2:
		return "overhead"
	if box[1] / R.FP >= 100 and box[3] / R.FP >= 80:
		return "uppercut"
	return "kick" if kick else "punch"


static func pose(f) -> Dictionary:
	var sf: float = f.state_frame
	match f.state:
		Fighter.IDLE, Fighter.JUMP_SQUAT, Fighter.LAND:
			var p := _over(IDLE, {"drop": IDLE.drop + sin(sf * 0.08) * 2.5})
			if f.state == Fighter.JUMP_SQUAT:
				p.drop = 26.0
			elif f.state == Fighter.LAND:
				p.drop = 20.0
			return p
		Fighter.WALK_F, Fighter.WALK_B:
			var ph := sf * (0.22 if f.state == Fighter.WALK_F else -0.18)
			return _over(IDLE, {"ft": 8.0 + sin(ph) * 28.0, "bt": -8.0 - sin(ph) * 28.0,
					"fs": -12.0 + maxf(0.0, cos(ph)) * -20.0, "bs": -12.0 + maxf(0.0, -cos(ph)) * -20.0,
					"drop": 6.0 + absf(sin(ph)) * 3.0})
		Fighter.CROUCH:
			return CROUCH
		Fighter.AIR:
			var rising: bool = f.vy > 0
			return _over(AIR, {"ft": 60.0 if rising else 40.0, "bt": 40.0 if rising else 10.0})
		Fighter.DASH_F:
			return _over(IDLE, DASH)
		Fighter.DASH_B:
			return _over(IDLE, {"lean": -18.0, "ft": 40.0, "bt": -20.0, "bs": -40.0})
		Fighter.ATTACK, Fighter.THROWING:
			return _attack_pose(f)
		Fighter.HITSTUN, Fighter.THROWN:
			var base := CROUCH if f.crouching else IDLE
			var shake := 1.0 - _smooth(sf / 12.0)
			return _blend(base, _over(base, HIT), shake * 0.6 + 0.4)
		Fighter.BLOCKSTUN, Fighter.THROW_TECH:
			return _over(CROUCH if f.crouching else IDLE, BLOCK)
		Fighter.JUGGLE:
			return _over(_over(IDLE, HIT), {"spin": -40.0 - minf(sf * 4.0, 60.0)})
		Fighter.KNOCKDOWN:
			return LYING
		Fighter.KO:
			return LYING if f.airborne == 0 else _over(_over(IDLE, HIT), {"spin": -60.0})
		Fighter.GETUP:
			return _blend(LYING, IDLE, _smooth(sf / float(R.GETUP_FRAMES)))
		Fighter.WIN:
			return _blend(IDLE, _over(IDLE, WIN), _smooth(sf / 20.0))
	return IDLE


static func _attack_pose(f) -> Dictionary:
	if f.move < 0:
		return IDLE
	var m: Dictionary = f.cur_move()
	var base: Dictionary = AIR if f.airborne else (CROUCH if m.crouching else IDLE)
	var kind := attack_kind(m, f.airborne != 0)
	var keys: Array = KINDS[kind]
	var wind := _over(base, keys[0])
	var strike := _over(base, keys[1])
	var mf: float = f.move_frame
	var first: float = m.first_active
	var last_end: float = first + m.active
	for h in m.hits:
		last_end = maxf(last_end, h.end)
	if m.hits.is_empty():
		return _blend(wind, strike, mf / maxf(1.0, m.total))
	if mf < first:
		return _blend(base, wind, _smooth(mf / maxf(1.0, first)))
	if mf < last_end:
		# Multi-hit moves alternate between strike and wind-up for each hit.
		for i in m.hits.size():
			var h: Dictionary = m.hits[i]
			if mf >= h.start and mf < h.end:
				return strike if i % 2 == 0 else _over(strike, {"fu": 40.0, "fl": 40.0, "bu": 95.0, "bl": 92.0})
		return _blend(strike, wind, 0.4)
	return _blend(strike, base, _smooth((mf - last_end) / maxf(1.0, m.total - last_end)))


static func _dir(deg: float, facing: int) -> Vector2:
	var r := deg_to_rad(deg)
	return Vector2(sin(r) * facing, cos(r))


## Draws the fighter with its feet at `feet` (screen px).
static func draw(ci: CanvasItem, f, feet: Vector2, color: Color) -> void:
	var p := pose(f)
	var face: int = f.facing
	var spin: float = p.get("spin", 0.0)
	var dark := color.darkened(0.35)
	var outline := color.darkened(0.6)
	var hip := feet + Vector2(0, -(THIGH + SHIN - p.get("drop", 0.0)))
	var torso_dir := Vector2(sin(deg_to_rad(p.lean + spin)) * face, -cos(deg_to_rad(p.lean + spin)))
	var neck := hip + torso_dir * TORSO
	var shoulder := hip + torso_dir * (TORSO - 8.0)

	_limb(ci, hip, p.bt + spin, p.bs + spin, THIGH, SHIN, face, dark, outline)
	_limb(ci, shoulder, p.bu + spin, p.bl + spin, UPPER_ARM, FOREARM, face, dark, outline)
	_bone(ci, hip, neck, TORSO_W, color, outline)
	var head := neck + torso_dir * (HEAD + 4.0)
	ci.draw_circle(head, HEAD + 2.0, outline)
	ci.draw_circle(head, HEAD, color.lightened(0.15))
	# Facing marker (where the sunglasses / eyes will be).
	ci.draw_rect(Rect2(head + Vector2(4.0 * face - (10.0 if face < 0 else 0.0), -6.0), Vector2(10, 5)), outline)
	_limb(ci, hip, p.ft + spin, p.fs + spin, THIGH, SHIN, face, color, outline)
	_limb(ci, shoulder, p.fu + spin, p.fl + spin, UPPER_ARM, FOREARM, face, color.lightened(0.08), outline)


static func _limb(ci: CanvasItem, root: Vector2, a1: float, a2: float, l1: float, l2: float, face: int,
		c: Color, outline: Color) -> void:
	var mid := root + _dir(a1, face) * l1
	var end := mid + _dir(a2, face) * l2
	_bone(ci, root, mid, LIMB_W, c, outline)
	_bone(ci, mid, end, LIMB_W - 2.0, c, outline)


static func _bone(ci: CanvasItem, a: Vector2, b: Vector2, w: float, c: Color, outline: Color) -> void:
	ci.draw_line(a, b, outline, w + 4.0)
	ci.draw_circle(a, (w + 4.0) / 2.0, outline)
	ci.draw_circle(b, (w + 4.0) / 2.0, outline)
	ci.draw_line(a, b, c, w)
	ci.draw_circle(a, w / 2.0, c)
	ci.draw_circle(b, w / 2.0, c)
