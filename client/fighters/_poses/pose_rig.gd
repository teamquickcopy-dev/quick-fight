## Pose-picture rig: draws a fighter as one finished picture per pose (fighters/<id>/art/pose_*.webp,
## cut from the pose sheets by tools/art/build_poses.py), the way hand-drawn fighting games do.
## poses.json "map" says which picture shows for each state and move; a move shows its wind-up
## pose during startup, its strike pose on the active frames (one per hit for multi-hit moves) and
## its recovery pose, all timed by the sim's frame data.
## Smooth motion between the pictures:
##  - a quick blend from one picture to the next (strikes cut in hard instead, with a speed trail)
##  - squash and stretch: crouch before a jump, stretch on take-off, squash on landing
##  - leaning: into walks and dashes, back during a wind-up, recoil when hit
##  - breathing and a slight sway in the stance, a bounce when knocked down, a hop on winning
## The blend and trail use wall-clock time per fighter, so rollback resimulation never affects them.
## Presentation only: reads fighter state, never changes it. Returns false from draw() when a
## picture is missing, so rigs.gd can fall back to the cutout rig.
extends RefCounted

const Fighter := preload("res://engine/fighter.gd")
const Art := preload("res://fighters/_cutout/art.gd")

const WALK_FRAMES := 9       # ticks per walk-cycle picture
const SNAP_FRAMES := 3       # first strike frames drawn stretched forward
const SHAKE_FRAMES := 8      # hit shake length
const RECOVER_HOLD := 0.5    # share of recovery that keeps the strike pose (no recover pose)
const BLEND_MS := 75.0       # picture-to-picture blend
const TRAIL_MS := 110.0      # speed trail after a strike cuts in

static var _cache := {}

var draw_scale := 0.8
var poses := {}      # name -> {tex, anchor: Vector2}
var map := {}
var _shown := {}     # fighter instance id -> {pose, look, prev, prev_look, since, strike}


## The pose rig for a fighter, or null when it has no pose pictures.
static func for_fighter(data) -> Variant:
	if _cache.has(data.id):
		return _cache[data.id]
	var rig = null
	var path := "res://fighters/%s/art/poses.json" % data.id
	if FileAccess.file_exists(path):
		rig = load("res://fighters/_poses/pose_rig.gd").new()
		if not rig._load(path):
			rig = null
	_cache[data.id] = rig
	return rig


func _load(path: String) -> bool:
	var cfg = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cfg is Dictionary:
		push_error("bad pose file %s" % path)
		return false
	draw_scale = cfg.draw_scale
	map = cfg.map
	var dir := path.get_base_dir()
	for name in cfg.poses:
		var p: Dictionary = cfg.poses[name]
		var tex := Art.texture(dir.path_join(p.texture))
		if tex == null:
			return false
		poses[name] = {"tex": tex, "anchor": Vector2(p.anchor[0], p.anchor[1])}
	return true


## Draws the fighter with its feet at `feet`. False if this state has no picture.
func draw(ci: CanvasItem, f, feet: Vector2, tint := Color.WHITE) -> bool:
	var look := pick(f)
	var name: String = look.get("pose", "")
	if not poses.has(name):
		return false
	var now := float(Time.get_ticks_msec())
	var id: int = f.get_instance_id()
	var s: Dictionary = _shown.get(id, {})
	if s.get("pose", "") != name:
		s = {"pose": name, "prev": s.get("pose", ""), "prev_look": s.get("look", {}), "since": now,
				"strike": look.get("strike", false)}
		_shown[id] = s
	s.look = look
	var age := now - float(s.since)
	if s.strike and age < TRAIL_MS:
		# Speed trail: fading copies of the strike behind it, as if it moved too fast to see.
		var k := 1.0 - age / TRAIL_MS
		for i in [2, 1]:
			var ghost := look.duplicate()
			ghost.dx = look.get("dx", 0.0) - 16.0 * i * k
			_draw_pose(ci, f, feet, name, ghost, tint * Color(1, 1, 1, 0.22 * k / i))
	_draw_pose(ci, f, feet, name, look, tint)
	if not s.strike and age < BLEND_MS and poses.has(s.prev):
		# Blend: the old picture fades out over the new one.
		_draw_pose(ci, f, feet, s.prev, s.prev_look, tint * Color(1, 1, 1, 1.0 - age / BLEND_MS))
	return true


func _draw_pose(ci: CanvasItem, f, feet: Vector2, name: String, look: Dictionary, tint: Color) -> void:
	var p: Dictionary = poses[name]
	var sx: float = look.get("sx", 1.0)
	var sy: float = look.get("sy", 1.0)
	var at: Vector2 = feet + Vector2(look.get("dx", 0.0) * f.facing, look.get("dy", 0.0))
	# Tilt turns around the feet; positive leans toward the opponent.
	var xf := Transform2D(deg_to_rad(look.get("tilt", 0.0)) * f.facing,
			Vector2(f.facing * draw_scale * sx, draw_scale * sy), 0.0, at)
	var spin: float = look.get("spin", 0.0)
	if spin != 0.0:
		# Rolls turn around the middle of the picture.
		var mid: Vector2 = p.tex.get_size() / 2.0 - p.anchor
		xf = xf * Transform2D(spin, mid) * Transform2D(0.0, -mid)
	ci.draw_set_transform_matrix(xf)
	ci.draw_texture(p.tex, -p.anchor, tint)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _m(key: String, i := 0) -> String:
	var v = map.get(key, "")
	if v is Array:
		return v[posmod(i, v.size())] if not v.is_empty() else ""
	return v


## The picture for the fighter's current state and how to draw it:
## {pose, sx, sy (scale), dx, dy (offset px), tilt (degrees, + = toward the opponent), spin, strike}.
func pick(f) -> Dictionary:
	var sf: int = f.state_frame
	match f.state:
		Fighter.IDLE:
			return {"pose": _m("idle"), "sy": 1.0 + sin(sf * 0.08) * 0.014, "tilt": sin(sf * 0.035) * 0.8}
		Fighter.WALK_F, Fighter.WALK_B:
			var fwd: bool = f.state == Fighter.WALK_F
			var step := (sf if fwd else -sf) / WALK_FRAMES
			var ph := sf * PI / WALK_FRAMES
			return {"pose": _m("walk", step), "dy": -absf(sin(ph)) * 3.5, "tilt": 2.5 if fwd else -2.0}
		Fighter.CROUCH:
			var down := 1.0 - _ease(sf / 5.0)
			return {"pose": _m("crouch"), "sy": 1.0 - 0.05 * down, "sx": 1.0 + 0.03 * down}
		Fighter.JUMP_SQUAT:
			return {"pose": _m("jump_squat"), "sy": 0.88, "sx": 1.06}
		Fighter.LAND:
			var k := 1.0 - _ease(sf / 6.0)
			return {"pose": _m("land"), "sy": 1.0 - 0.1 * k, "sx": 1.0 + 0.07 * k}
		Fighter.AIR:
			if f.vy > 0:
				var k := 1.0 - _ease(sf / 8.0)
				return {"pose": _m("jump_up"), "sy": 1.0 + 0.09 * k, "sx": 1.0 - 0.05 * k, "tilt": f.jump_dx * f.facing * 4.0}
			return {"pose": _m("jump_down"), "sy": 1.03, "tilt": f.jump_dx * f.facing * 2.0}
		Fighter.DASH_F:
			return {"pose": _m("dash_f"), "tilt": 7.0, "sx": 1.05}
		Fighter.DASH_B:
			return {"pose": _m("dash_b"), "tilt": -8.0, "dy": -sin(minf(sf / 14.0, 1.0) * PI) * 10.0}
		Fighter.ATTACK:
			return _attack(f)
		Fighter.THROWING:
			return {"pose": _m("throwing"), "strike": true, "tilt": 4.0}
		Fighter.HITSTUN:
			var k := 1.0 - _ease(sf / 12.0)
			var shake := maxf(0.0, 1.0 - sf / float(SHAKE_FRAMES)) * (4.0 if sf % 2 == 0 else -4.0)
			var pose := _m("hit_crouch") if f.crouching else _m("hit", f.combo_hits)
			return {"pose": pose, "dx": shake - 6.0 * k, "tilt": -9.0 * k, "sx": 1.0 - 0.04 * k}
		Fighter.BLOCKSTUN:
			var k := 1.0 - _ease(sf / 8.0)
			var push := maxf(0.0, 1.0 - sf / 6.0) * (2.0 if sf % 2 == 0 else -2.0)
			return {"pose": _m("block_low" if f.crouching else "block"), "dx": push - 3.0 * k, "tilt": -3.0 * k}
		Fighter.THROW_TECH:
			return {"pose": _m("throw_tech"), "tilt": -4.0}
		Fighter.JUGGLE:
			return {"pose": _m("juggle"), "tilt": -minf(sf * 1.5, 25.0)}
		Fighter.THROWN:
			return {"pose": _m("thrown"), "tilt": -minf(sf * 2.0, 30.0)}
		Fighter.KNOCKDOWN, Fighter.KO:
			var pose := _m("ko_air") if f.state == Fighter.KO and f.airborne else _m("knockdown" if f.state == Fighter.KNOCKDOWN else "ko")
			# Two small bounces off the floor, then still.
			var bounce := absf(sin(sf * 0.35)) * 9.0 * maxf(0.0, 1.0 - sf / 18.0) if not f.airborne else 0.0
			return {"pose": pose, "dy": -bounce, "sy": 1.0 - 0.05 * maxf(0.0, 1.0 - sf / 5.0)}
		Fighter.GETUP:
			return {"pose": _m("getup"), "sy": 0.97 + 0.03 * _ease(sf / 10.0)}
		Fighter.WIN:
			if sf < 10:
				return {"pose": _m("idle")}
			var hop := sin(minf((sf - 10) / 18.0, 1.0) * PI) * 16.0
			return {"pose": _m("win"), "dy": -hop, "sy": 1.0 + 0.04 * sin(sf * 0.08)}
	return {"pose": _m("idle")}


func _attack(f) -> Dictionary:
	if f.move < 0:
		return {"pose": _m("idle")}
	var m: Dictionary = f.cur_move()
	var keys: Dictionary = map.get("moves", {}).get(m.name, {})
	var base := _m("crouch") if m.crouching else (_m("jump_down") if f.airborne else _m("idle"))
	if keys.is_empty():
		return {"pose": ""}   # no pictures for this move: let the cutout rig draw it
	var mf: int = f.move_frame
	var strike = keys.get("strike", base)
	if m.hits.is_empty():
		# No hitbox (a roll or dash move): wind-up briefly, then the strike pose for the rest.
		if mf < 4:
			return {"pose": keys.get("wind", base)}
		var out := {"pose": strike[0] if strike is Array else strike}
		if keys.get("spin", false):
			out.spin = (mf - 4) * 0.45
		return out
	if mf < m.first_active:
		# Anticipation: lean back and draw in while winding up.
		var k := _ease(mf / maxf(1.0, m.first_active))
		return {"pose": keys.get("wind", base), "tilt": -4.0 * k, "dx": -5.0 * k, "sy": 1.0 - 0.02 * k}
	var last_end: int = m.first_active
	for i in m.hits.size():
		var h: Dictionary = m.hits[i]
		last_end = maxi(last_end, h.end)
		if mf >= h.start and mf < h.end:
			var pose: String = strike[mini(i, strike.size() - 1)] if strike is Array else strike
			var t: int = mf - h.start
			if t < SNAP_FRAMES:
				# Snap: the first strike frames are stretched forward a little.
				var k := 1.0 - t / float(SNAP_FRAMES)
				return {"pose": pose, "sx": 1.0 + 0.07 * k, "sy": 1.0 - 0.03 * k, "dx": 4.0 * k, "tilt": 3.0 * k, "strike": true}
			return {"pose": pose, "strike": true}
	if mf < last_end:
		# Between hits of a multi-hit move: hold the last strike.
		var i := 0
		for j in m.hits.size():
			if mf >= m.hits[j].end:
				i = j
		return {"pose": strike[mini(i, strike.size() - 1)] if strike is Array else strike, "strike": true}
	var last: String = strike[strike.size() - 1] if strike is Array else strike
	if keys.has("recover"):
		return {"pose": keys.recover}
	var hold := last_end + int((m.total - last_end) * RECOVER_HOLD)
	# Recovery: settle back from the follow-through.
	var settle := 1.0 - _ease(float(mf - last_end) / maxf(1.0, m.total - last_end))
	return {"pose": last if mf < hold else base, "tilt": 2.0 * settle, "strike": mf < hold}
